/// Listeners — observers of a committed update.
///
/// Listeners observe; they must not mutate. Work that needs to change the
/// document belongs in a transform or a command handler: mutating from a
/// post-commit listener schedules another whole update cycle and can
/// oscillate between two states forever.
library;

import 'package:meta/meta.dart';

import 'commands.dart';
import 'editor_state.dart';
import 'keys.dart';
import 'nodes/lexical_node.dart';

/// What happened to a node during one commit.
enum NodeMutation {
  /// The node did not exist before this commit.
  created,

  /// The node existed and changed.
  updated,

  /// The node existed and is now gone.
  destroyed,
}

/// Everything a listener needs to know about one commit.
final class EditorUpdate {
  /// Bundles the state of one commit.
  const EditorUpdate({
    required this.editorState,
    required this.previousEditorState,
    required this.tags,
    required this.dirtyLeaves,
    required this.dirtyElements,
    this.isFullReconcile = false,
  });

  /// The newly committed state.
  final EditorState editorState;

  /// The state this commit replaced.
  final EditorState previousEditorState;

  /// Metadata attached by whoever opened the update.
  ///
  /// Plain strings rather than an enum, so upstream tag names such as
  /// `history-push` and `collaboration` carry over unchanged.
  final Set<String> tags;

  /// Keys of non-element nodes that changed.
  final Set<NodeKey> dirtyLeaves;

  /// Keys of element nodes that changed.
  ///
  /// `true` means the element itself was modified; `false` means it is dirty
  /// only because a descendant changed. A renderer needs the distinction to
  /// avoid rebuilding whole subtrees.
  final Map<NodeKey, bool> dirtyElements;

  /// Whether the whole document must be rebuilt.
  ///
  /// Set when the state was replaced wholesale — an undo, a collaborative
  /// resync, loading a document — where the dirty sets carry no information
  /// because nothing was diffed. A renderer must not trust them here.
  final bool isFullReconcile;

  /// Whether this commit carries [tag].
  bool hasTag(String tag) => tags.contains(tag);
}

/// Called after a commit.
typedef UpdateListener = void Function(EditorUpdate update);

/// Called after a commit with the mutations affecting one node type.
typedef MutationListener = void Function(Map<NodeKey, NodeMutation> mutations);

/// Called after a commit in which the document's plain text changed.
typedef TextContentListener = void Function(String textContent);

/// Called when the editor's editable flag changes.
typedef EditableListener = void Function(bool editable);

/// Per-editor listener storage.
@internal
final class ListenerRegistry {
  final List<UpdateListener> _update = <UpdateListener>[];
  final Map<String, List<MutationListener>> _mutation =
      <String, List<MutationListener>>{};
  final List<TextContentListener> _textContent = <TextContentListener>[];
  final List<EditableListener> _editable = <EditableListener>[];

  /// Whether any text-content listener is registered.
  bool get hasTextContentListeners => _textContent.isNotEmpty;

  /// Whether any mutation listener is registered.
  bool get hasMutationListeners => _mutation.isNotEmpty;

  /// Registers an update listener.
  Unsubscribe addUpdate(UpdateListener listener) {
    _update.add(listener);
    return () => _update.remove(listener);
  }

  /// Registers a mutation listener for nodes of [type].
  Unsubscribe addMutation(String type, MutationListener listener) {
    final list = _mutation.putIfAbsent(type, () => <MutationListener>[]);
    list.add(listener);
    return () {
      list.remove(listener);
      if (list.isEmpty) _mutation.remove(type);
    };
  }

  /// Registers a text-content listener.
  Unsubscribe addTextContent(TextContentListener listener) {
    _textContent.add(listener);
    return () => _textContent.remove(listener);
  }

  /// Registers an editable listener.
  Unsubscribe addEditable(EditableListener listener) {
    _editable.add(listener);
    return () => _editable.remove(listener);
  }

  /// Notifies update listeners.
  void notifyUpdate(EditorUpdate update) {
    for (final listener in List<UpdateListener>.of(_update)) {
      listener(update);
    }
  }

  /// Notifies text-content listeners.
  void notifyTextContent(String textContent) {
    for (final listener in List<TextContentListener>.of(_textContent)) {
      listener(textContent);
    }
  }

  /// Notifies editable listeners.
  void notifyEditable({required bool editable}) {
    for (final listener in List<EditableListener>.of(_editable)) {
      listener(editable);
    }
  }

  /// Notifies mutation listeners, grouping mutations by node type.
  void notifyMutations(Map<String, Map<NodeKey, NodeMutation>> byType) {
    for (final entry in byType.entries) {
      final listeners = _mutation[entry.key];
      if (listeners == null || entry.value.isEmpty) continue;
      for (final listener in List<MutationListener>.of(listeners)) {
        listener(entry.value);
      }
    }
  }
}

/// Derives per-type mutations from the dirty sets and the two node maps.
///
/// `RootNode` is excluded, matching upstream: the root is dirty on nearly
/// every commit, so reporting it would make the listener useless. Use a root
/// transform for document-level reactions instead.
@internal
Map<String, Map<NodeKey, NodeMutation>> computeMutations(
  EditorState previous,
  EditorState current,
  Set<NodeKey> dirtyLeaves,
  Map<NodeKey, bool> dirtyElements,
) {
  final byType = <String, Map<NodeKey, NodeMutation>>{};

  void record(NodeKey key) {
    if (key == NodeKey.root) return;
    final before = previous.nodeMap[key];
    final after = current.nodeMap[key];
    final LexicalNode node;
    final NodeMutation mutation;
    if (after == null) {
      if (before == null) return;
      node = before;
      mutation = NodeMutation.destroyed;
    } else if (before == null) {
      node = after;
      mutation = NodeMutation.created;
    } else {
      node = after;
      mutation = NodeMutation.updated;
    }
    (byType[node.type] ??= <NodeKey, NodeMutation>{})[key] = mutation;
  }

  for (final key in dirtyLeaves) {
    record(key);
  }
  for (final key in dirtyElements.keys) {
    record(key);
  }
  return byType;
}
