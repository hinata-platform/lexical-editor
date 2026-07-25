/// Element nodes: everything that has children.
library;

import 'package:meta/meta.dart';

import '../errors.dart';
import '../keys.dart';
import '../updates.dart';
import 'lexical_node.dart';
import 'text_node.dart';

/// Resolved writing direction of a block.
///
/// `null` — the absence of a value — means *undetermined*, which is not the
/// same as [ltr]. Upstream resolves it from the block's first strongly
/// directional character, and serializes `null` until it has.
enum NodeDirection {
  /// Left-to-right.
  ltr,

  /// Right-to-left.
  rtl;

  /// Parses a wire-format direction, mapping anything unknown to `null`.
  static NodeDirection? fromWire(Object? value) => switch (value) {
    'ltr' => NodeDirection.ltr,
    'rtl' => NodeDirection.rtl,
    _ => null,
  };

  /// The wire-format string for this direction.
  String get wire => name;
}

/// Block alignment, serialized as a string on element nodes.
///
/// Note that element `format` is a **string** while text `format` is an
/// **int bitmask**. Conflating the two is the most common decoder bug in a
/// Lexical port, so they are separate types here.
///
/// [start] and [end] are logical: they resolve against the block's text
/// direction, so they are not synonyms for [left] and [right]. Keep the
/// value symbolic in the model and resolve it at render time.
enum ElementFormat {
  /// No explicit alignment; serialized as the empty string.
  none(''),

  /// Align to the left edge.
  left('left'),

  /// Centre the content.
  center('center'),

  /// Align to the right edge.
  right('right'),

  /// Stretch lines to both edges.
  justify('justify'),

  /// Align to the leading edge, resolved against text direction.
  start('start'),

  /// Align to the trailing edge, resolved against text direction.
  end('end');

  const ElementFormat(this.wire);

  /// The wire-format string for this alignment.
  final String wire;

  /// Parses a wire-format alignment.
  ///
  /// Unknown values map to [none], matching upstream, which looks the value
  /// up in a table and falls back to `0`.
  static ElementFormat fromWire(Object? value) {
    for (final format in ElementFormat.values) {
      if (format.wire == value) return format;
    }
    return ElementFormat.none;
  }
}

/// A node that owns children.
///
/// Children are stored as a doubly linked list of keys — [firstKey],
/// [lastKey] on the element and `prev`/`next` on each child — so inserting
/// a node touches the new node, its two neighbours, and this element's
/// counters, regardless of how many children there are.
abstract class ElementNode extends LexicalNode {
  /// Creates an empty element.
  ElementNode();

  /// Creates an element with a fixed key. Used only by the root.
  ElementNode.withKey(super.key) : super.withKey();

  /// Key of the first child, or `null` when empty.
  @internal
  NodeKey? firstKey;

  /// Key of the last child, or `null` when empty.
  @internal
  NodeKey? lastKey;

  /// Number of children. Kept in sync by the mutators.
  @internal
  int sizeInternal = 0;

  /// Block alignment.
  @internal
  ElementFormat format = ElementFormat.none;

  /// Element-level style string. Not part of the wire format.
  @internal
  String style = '';

  /// Nesting level, 0-based.
  @internal
  int indent = 0;

  /// Resolved writing direction, or `null` when undetermined.
  @internal
  NodeDirection? direction;

  /// Format the caret would apply to text typed at the end of this block.
  @internal
  int textFormat = 0;

  /// Style the caret would apply to text typed at the end of this block.
  @internal
  String textStyle = '';

  @override
  bool get isInline => false;

  @override
  @mustCallSuper
  void afterCloneFrom(covariant ElementNode prev) {
    super.afterCloneFrom(prev);
    if (key == prev.key) {
      firstKey = prev.firstKey;
      lastKey = prev.lastKey;
      sizeInternal = prev.sizeInternal;
    }
    indent = prev.indent;
    format = prev.format;
    style = prev.style;
    direction = prev.direction;
    textFormat = prev.textFormat;
    textStyle = prev.textStyle;
  }

  // ---------------------------------------------------------------------
  // Children
  // ---------------------------------------------------------------------

  /// Number of children.
  int get childrenSize => getLatest<ElementNode>().sizeInternal;

  /// Whether this element has no children.
  bool get isEmpty => childrenSize == 0;

  /// The first child, or `null` when empty.
  LexicalNode? getFirstChild() {
    final key = getLatest<ElementNode>().firstKey;
    return key == null ? null : $getNodeByKey(key);
  }

  /// The last child, or `null` when empty.
  LexicalNode? getLastChild() {
    final key = getLatest<ElementNode>().lastKey;
    return key == null ? null : $getNodeByKey(key);
  }

  /// The children in document order, walked lazily through the pointers.
  Iterable<LexicalNode> get children sync* {
    var child = getFirstChild();
    while (child != null) {
      yield child;
      child = child.getNextSibling();
    }
  }

  /// The child at [index], or `null` when out of range.
  ///
  /// Negative indices count from the end, and the walk starts from whichever
  /// end is closer.
  LexicalNode? getChildAtIndex(int index) {
    final size = childrenSize;
    var target = index;
    if (target < 0) target += size;
    if (target < 0 || target >= size) return null;
    if (target <= size ~/ 2) {
      var node = getFirstChild();
      var i = 0;
      while (node != null) {
        if (i == target) return node;
        node = node.getNextSibling();
        i++;
      }
    } else {
      var node = getLastChild();
      var i = size - 1;
      while (node != null) {
        if (i == target) return node;
        node = node.getPreviousSibling();
        i--;
      }
    }
    return null;
  }

  /// The descendant text and inline nodes of this element, in order.
  List<LexicalNode> getAllTextNodes() {
    final result = <LexicalNode>[];
    for (final child in children) {
      if (child is TextNode) {
        result.add(child);
      } else if (child is ElementNode) {
        result.addAll(child.getAllTextNodes());
      }
    }
    return result;
  }

  @override
  String getTextContent() {
    final buffer = StringBuffer();
    var child = getFirstChild();
    while (child != null) {
      buffer.write(child.getTextContent());
      final next = child.getNextSibling();
      if (next != null && child is ElementNode && !child.isInline) {
        buffer.write('\n\n');
      }
      child = next;
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------
  // Structural policy
  // ---------------------------------------------------------------------

  /// Whether this element may exist with no children.
  ///
  /// An element that returns `false` is removed when its last child goes.
  bool get canBeEmpty => true;

  /// Whether this element behaves as a root for containment purposes.
  ///
  /// Shadow roots (table cells, for example) stop upward traversal the same
  /// way the document root does.
  bool get isShadowRoot => false;

  /// Whether text may be inserted immediately before this element.
  bool get canInsertTextBefore => true;

  /// Whether text may be inserted immediately after this element.
  bool get canInsertTextAfter => true;

  /// Whether this element accepts indentation.
  bool get canIndent => true;

  // ---------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------

  /// Appends [node] as the last child of this element.
  ElementNode append(LexicalNode node) {
    splice(childrenSize, 0, [node]);
    return this;
  }

  /// Appends several nodes in one operation.
  ElementNode appendAll(Iterable<LexicalNode> nodes) {
    splice(childrenSize, 0, nodes.toList());
    return this;
  }

  /// Inserts [node] before every existing child.
  ElementNode insertChildAtStart(LexicalNode node) {
    splice(0, 0, [node]);
    return this;
  }

  /// Removes every child.
  ElementNode clear() {
    for (final child in children.toList()) {
      child.remove(preserveEmptyParent: true);
    }
    return this;
  }

  /// Replaces `deleteCount` children starting at [start] with [nodesToInsert].
  ///
  /// This is the single place child pointers are rewritten; every other
  /// mutator funnels through it or through [$removeFromParent], which is
  /// what keeps `first`/`last`/`size` consistent with the chain.
  ElementNode splice(
    int start,
    int deleteCount,
    List<LexicalNode> nodesToInsert,
  ) {
    errorOnReadOnly();
    final oldSize = childrenSize;
    if (start < 0 || deleteCount < 0 || start + deleteCount > oldSize) {
      throw LexicalTreeError(
        'splice: start $start + deleteCount $deleteCount exceeds size $oldSize',
      );
    }
    for (final node in nodesToInsert) {
      errorOnInsertTextNodeOnRoot(this, node);
      if (node.key == key) {
        throw const LexicalTreeError('splice: attempting to append self');
      }
      if (node is ElementNode && node.isParentOf(this)) {
        throw const LexicalTreeError('splice: would create a cycle');
      }
    }

    final writableSelf = getWritable<ElementNode>();
    final nodeAfterRange = getChildAtIndex(start + deleteCount);
    LexicalNode? nodeBeforeRange;
    var newSize = oldSize - deleteCount + nodesToInsert.length;

    if (start != 0) {
      if (start == oldSize) {
        nodeBeforeRange = getLastChild();
      } else {
        nodeBeforeRange = getChildAtIndex(start)?.getPreviousSibling();
      }
    }

    if (deleteCount > 0) {
      var nodeToDelete = nodeBeforeRange == null
          ? getFirstChild()
          : nodeBeforeRange.getNextSibling();
      for (var i = 0; i < deleteCount; i++) {
        if (nodeToDelete == null) {
          throw const LexicalTreeError('splice: sibling not found');
        }
        final next = nodeToDelete.getNextSibling();
        $removeFromParent(nodeToDelete.getWritable<LexicalNode>());
        nodeToDelete = next;
      }
    }

    var prevNode = nodeBeforeRange;
    for (final nodeToInsert in nodesToInsert) {
      if (prevNode != null && nodeToInsert.isSameNode(prevNode)) {
        nodeBeforeRange = prevNode = prevNode.getPreviousSibling();
      }
      final writableInsert = nodeToInsert.getWritable<LexicalNode>();
      if (writableInsert.parentKey == writableSelf.key) newSize--;
      $removeFromParent(writableInsert);
      if (prevNode == null) {
        writableSelf.firstKey = writableInsert.key;
        writableInsert.prevKey = null;
      } else {
        final writablePrev = prevNode.getWritable<LexicalNode>();
        writablePrev.nextKey = writableInsert.key;
        writableInsert.prevKey = writablePrev.key;
      }
      writableInsert.parentKey = writableSelf.key;
      prevNode = writableInsert;
    }

    if (start + deleteCount == oldSize) {
      if (prevNode != null) {
        prevNode.getWritable<LexicalNode>().nextKey = null;
        writableSelf.lastKey = prevNode.key;
      }
    } else if (nodeAfterRange != null) {
      final writableAfter = nodeAfterRange.getWritable<LexicalNode>();
      if (prevNode != null) {
        final writablePrev = prevNode.getWritable<LexicalNode>();
        writableAfter.prevKey = writablePrev.key;
        writablePrev.nextKey = writableAfter.key;
      } else {
        writableAfter.prevKey = null;
        writableSelf.firstKey = writableAfter.key;
      }
    }

    writableSelf.sizeInternal = newSize;
    if (newSize == 0) {
      writableSelf
        ..firstKey = null
        ..lastKey = null;
    }
    return writableSelf;
  }

  // ---------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------

  /// Block alignment.
  ElementFormat getFormat() => getLatest<ElementNode>().format;

  /// Sets block alignment.
  ElementNode setFormat(ElementFormat value) =>
      getWritable<ElementNode>()..format = value;

  /// Nesting level.
  int getIndent() => getLatest<ElementNode>().indent;

  /// Sets the nesting level.
  ElementNode setIndent(int value) =>
      getWritable<ElementNode>()..indent = value < 0 ? 0 : value;

  /// Resolved writing direction, or `null` when undetermined.
  NodeDirection? getDirection() => getLatest<ElementNode>().direction;

  /// Sets the writing direction.
  ElementNode setDirection(NodeDirection? value) =>
      getWritable<ElementNode>()..direction = value;

  /// The caret's pending text format for this block.
  int getTextFormat() => getLatest<ElementNode>().textFormat;

  /// Sets the caret's pending text format.
  ElementNode setTextFormat(int value) =>
      getWritable<ElementNode>()..textFormat = value;

  /// The caret's pending text style for this block.
  String getTextStyle() => getLatest<ElementNode>().textStyle;

  /// Sets the caret's pending text style.
  ElementNode setTextStyle(String value) =>
      getWritable<ElementNode>()..textStyle = value;

  // ---------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------

  @override
  @mustCallSuper
  Map<String, Object?> exportJson() {
    final json = <String, Object?>{
      'children': <Object?>[],
      'direction': direction?.wire,
      'format': format.wire,
      'indent': indent,
      ...super.exportJson(),
    };
    // Only persisted when there is no text child to recompute them from —
    // otherwise they are derived on export. See ParagraphNode, which always
    // emits them.
    if ((textFormat != 0 || textStyle != '') &&
        !isShadowRoot &&
        !children.any((child) => child is TextNode)) {
      if (textFormat != 0) json['textFormat'] = textFormat;
      if (textStyle != '') json['textStyle'] = textStyle;
    }
    return json;
  }

  @override
  @mustCallSuper
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    format = ElementFormat.fromWire(json['format']);
    indent = _readInt(json['indent']);
    direction = NodeDirection.fromWire(json['direction']);
    textFormat = _readInt(json['textFormat']);
    textStyle = json['textStyle'] is String ? json['textStyle']! as String : '';
  }

  static int _readInt(Object? value) => value is int ? value : 0;
}
