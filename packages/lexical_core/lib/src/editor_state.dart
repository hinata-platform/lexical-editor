/// The immutable document snapshot.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

import 'errors.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/root_node.dart';
import 'selection.dart';
import 'updates.dart';

const int _maxExportDepth = 2000;

/// A committed or pending snapshot of the document.
///
/// An editor state is a node map plus a selection, and nothing else. The tree
/// lives *in the map*: nodes hold keys and resolve them through the active
/// state rather than holding object references. That indirection is what lets
/// a new state share every untouched node with its predecessor, so an edit
/// costs O(changed nodes) and an undo stack is a list of state references.
///
/// A committed state is frozen. Dart has no `Object.freeze`, so the contract
/// is enforced two ways: the public [nodeMap] is an unmodifiable view even in
/// release, and mutating a node outside an update fails an assertion in debug.
final class EditorState {
  EditorState._(this._nodeMap, this._selection);

  /// Creates a state containing only an empty root.
  ///
  /// Note that this is *not* a document containing one empty paragraph.
  /// Seeding an initial paragraph is the editor's job, not the decoder's —
  /// an empty document serializes as `"children": []` and must decode back
  /// to exactly that.
  factory EditorState.empty() =>
      EditorState._(<NodeKey, LexicalNode>{NodeKey.root: RootNode()}, null);

  final Map<NodeKey, LexicalNode> _nodeMap;
  BaseSelection? _selection;
  bool _frozen = false;
  UnmodifiableMapView<NodeKey, LexicalNode>? _view;

  /// The nodes of this state, keyed by identity.
  ///
  /// Unmodifiable once the state is committed.
  Map<NodeKey, LexicalNode> get nodeMap =>
      _frozen ? (_view ??= UnmodifiableMapView(_nodeMap)) : _nodeMap;

  /// The mutable node map. Framework-internal.
  @internal
  Map<NodeKey, LexicalNode> get nodeMapInternal => _nodeMap;

  /// The selection, or `null` when nothing is selected.
  ///
  /// Never serialized: `toJson` emits only `root`.
  BaseSelection? get selection => _selection;

  /// Replaces the selection. Framework-internal; use `$setSelection`.
  @internal
  void setSelectionInternal(BaseSelection? selection) {
    _selection = selection;
  }

  /// Whether this state has been committed and may no longer be mutated.
  bool get isFrozen => _frozen;

  /// Freezes this state. Framework-internal; called at commit.
  @internal
  void freeze() {
    _frozen = true;
  }

  /// Whether this state holds nothing but an empty root.
  bool get isEmpty => _nodeMap.length == 1 && _selection == null;

  /// The document root.
  RootNode get root {
    final node = _nodeMap[NodeKey.root];
    if (node is! RootNode) {
      throw const LexicalStateError('EditorState has no root node.');
    }
    return node;
  }

  /// Copies this state's node map for a new pending state.
  ///
  /// The map is copied; the nodes in it are not. Structural sharing is the
  /// point — an update clones only the nodes it touches.
  @internal
  EditorState cloneForUpdate() {
    final clone = EditorState._(
      Map<NodeKey, LexicalNode>.of(_nodeMap),
      _selection?.clone(),
    );
    return clone;
  }

  /// Returns a frozen copy that shares this state's node map.
  ///
  /// Used to publish a state without allowing further mutation of it.
  EditorState frozenCopy({BaseSelection? selection}) {
    final copy = EditorState._(_nodeMap, selection ?? _selection)
      .._frozen = true;
    return copy;
  }

  /// Runs [fn] with this state active and read-only.
  T read<T>(T Function() fn) => readEditorState(this, fn);

  /// Serializes the document to its wire-format JSON object.
  ///
  /// The result has exactly one top-level key, `root`. Selection is not part
  /// of the wire format; a document that carries one is not a document
  /// Lexical web can consume.
  Map<String, Object?> toJson() =>
      read(() => <String, Object?>{'root': $exportNodeToJson(root, 0)});

  @override
  String toString() =>
      'EditorState(${_nodeMap.length} nodes, frozen: $_frozen)';
}

/// Serializes [node] and, for elements, its children.
///
/// Children are appended to the `children` array that the node's own
/// `exportJson` created, so a node type controls the order of its own keys
/// while the walk stays generic.
@internal
Map<String, Object?> $exportNodeToJson(LexicalNode node, int depth) {
  if (depth > _maxExportDepth) {
    throw const LexicalTreeError(
      'toJson: document nests deeper than $_maxExportDepth levels.',
    );
  }
  final json = node.exportJson();
  final type = json['type'];
  if (type != node.type) {
    throw LexicalStateError(
      '${node.runtimeType}.exportJson() reported type "$type" but the node '
      'type is "${node.type}".',
    );
  }
  if (node is ElementNode) {
    final children = json['children'];
    if (children is! List) {
      throw LexicalStateError(
        '${node.runtimeType}.exportJson() must include a children array.',
      );
    }
    for (final child in node.children) {
      children.add($exportNodeToJson(child, depth + 1));
    }
  }
  return json;
}
