/// Selection model.
///
/// Selection is part of the editor state — so it survives undo for free —
/// but it is deliberately **not** part of the wire format. `toJson()` emits
/// only `root`; a document that carries a serialized selection is not a
/// document Lexical web can consume.
library;

import 'package:meta/meta.dart';

import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/text_node.dart';
import 'updates.dart';

/// What a [Point]'s offset counts.
enum PointType {
  /// Offset is an index into a text node's content, in UTF-16 code units.
  text,

  /// Offset is a child index within an element node.
  element,
}

/// One end of a [RangeSelection].
final class Point {
  /// Creates a point addressing [key] at [offset].
  Point(this.key, this.offset, this.type);

  /// The node this point addresses.
  NodeKey key;

  /// Position within the node.
  ///
  /// For [PointType.text] this is a UTF-16 code-unit index, matching
  /// JavaScript. It is never a grapheme index — mixing the two produces
  /// carets that land one character off only for some inputs.
  int offset;

  /// How [offset] should be interpreted.
  PointType type;

  RangeSelection? _selection;

  /// Resolves the addressed node against the active editor state.
  LexicalNode? getNode() => $getNodeByKey(key);

  /// Moves this point, marking the owning selection dirty.
  void set(NodeKey key, int offset, PointType type) {
    if (this.key == key && this.offset == offset && this.type == type) {
      return;
    }
    this.key = key;
    this.offset = offset;
    this.type = type;
    if (!isCurrentlyReadOnlyMode()) {
      _selection?.dirty = true;
    }
  }

  /// Whether this point addresses the same position as [other].
  bool isSamePosition(Point other) =>
      key == other.key && offset == other.offset && type == other.type;

  @override
  String toString() => 'Point($key, $offset, ${type.name})';
}

/// Common interface of every selection kind.
sealed class BaseSelection {
  /// Whether the selection changed during the current update.
  bool dirty = false;

  /// Returns an independent copy, used when an update clones the state.
  BaseSelection clone();

  /// Whether the selection covers no content.
  bool get isCollapsed;

  /// The nodes the selection touches, in document order.
  List<LexicalNode> getNodes();

  /// Whether this selection addresses the same positions as [other].
  bool isSameAs(BaseSelection? other);
}

/// A contiguous selection between two points.
///
/// [anchor] and [focus] are ordered: the anchor is where the selection
/// started and the focus is where it ends, so a backwards drag has
/// `focus` before `anchor`. Do not normalize them to start/end — the order
/// is the selection's direction and the platform text APIs preserve it.
final class RangeSelection extends BaseSelection {
  /// Creates a range selection between [anchor] and [focus].
  RangeSelection(this.anchor, this.focus, {this.format = 0, this.style = ''}) {
    anchor._selection = this;
    focus._selection = this;
  }

  /// Creates a collapsed selection at a text offset inside [key].
  factory RangeSelection.collapsedText(NodeKey key, int offset) =>
      RangeSelection(
        Point(key, offset, PointType.text),
        Point(key, offset, PointType.text),
      );

  /// Where the selection started.
  final Point anchor;

  /// Where the selection ends; the caret sits here.
  final Point focus;

  /// Pending text format bitmask applied to text typed next.
  int format;

  /// Pending CSS style string applied to text typed next.
  String style;

  @override
  bool get isCollapsed => anchor.isSamePosition(focus);

  @override
  RangeSelection clone() => RangeSelection(
    Point(anchor.key, anchor.offset, anchor.type),
    Point(focus.key, focus.offset, focus.type),
    format: format,
    style: style,
  );

  @override
  bool isSameAs(BaseSelection? other) =>
      other is RangeSelection &&
      anchor.isSamePosition(other.anchor) &&
      focus.isSamePosition(other.focus) &&
      format == other.format &&
      style == other.style;

  @override
  List<LexicalNode> getNodes() {
    final first = anchor.getNode();
    final last = focus.getNode();
    if (first == null || last == null) return const [];
    if (identical(first, last) || first.key == last.key) {
      return first is ElementNode && first.childrenSize == 0
          ? [first]
          : [first];
    }
    return first.isBefore(last)
        ? first.getNodesBetween(last)
        : last.getNodesBetween(first);
  }

  /// Whether both ends address the same text node.
  bool get isWithinSingleTextNode =>
      anchor.type == PointType.text &&
      focus.type == PointType.text &&
      anchor.key == focus.key;

  /// The text node the anchor addresses, when it addresses one.
  TextNode? get anchorTextNode {
    final node = anchor.getNode();
    return node is TextNode ? node : null;
  }

  @override
  String toString() => 'RangeSelection($anchor -> $focus)';
}

/// A set of whole nodes selected as units, typically decorators.
///
/// It has no platform text-selection analogue: report a collapsed or empty
/// selection to the IME and render this one yourself.
final class NodeSelection extends BaseSelection {
  /// Creates a selection over [keys].
  NodeSelection(Set<NodeKey> keys) : _nodes = {...keys};

  final Set<NodeKey> _nodes;

  /// The selected node keys.
  Set<NodeKey> get keys => Set.unmodifiable(_nodes);

  /// Adds a node to the selection.
  void add(NodeKey key) {
    if (_nodes.add(key)) dirty = true;
  }

  /// Removes a node from the selection.
  void remove(NodeKey key) {
    if (_nodes.remove(key)) dirty = true;
  }

  /// Whether [key] is part of the selection.
  bool has(NodeKey key) => _nodes.contains(key);

  @override
  bool get isCollapsed => _nodes.isEmpty;

  @override
  NodeSelection clone() => NodeSelection(_nodes);

  @override
  bool isSameAs(BaseSelection? other) =>
      other is NodeSelection &&
      other._nodes.length == _nodes.length &&
      other._nodes.containsAll(_nodes);

  @override
  List<LexicalNode> getNodes() {
    final result = <LexicalNode>[];
    for (final key in _nodes) {
      final node = $getNodeByKey(key);
      if (node != null) result.add(node);
    }
    return result;
  }

  @override
  String toString() => 'NodeSelection($_nodes)';
}

/// Returns the selection of the active editor state, if any.
///
/// `null` is a normal, common state — an editor that has never been focused
/// has no selection.
BaseSelection? $getSelection() => $getActiveEditorState().selection;

/// Replaces the selection of the pending editor state.
///
/// Only valid inside an update.
void $setSelection(BaseSelection? selection) {
  errorOnReadOnly();
  final state = $getActiveEditorState();
  selection?.dirty = true;
  state.setSelectionInternal(selection);
}

/// Marks the current selection dirty so it is reconciled on commit.
@internal
void markSelectionDirty() {
  $getActiveEditorState().selection?.dirty = true;
}
