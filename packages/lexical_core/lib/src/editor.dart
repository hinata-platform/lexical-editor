/// The editor: registry, state, updates and the commit lifecycle.
library;

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'commands.dart';
import 'editor_state.dart';
import 'errors.dart';
import 'garbage_collection.dart';
import 'importer.dart';
import 'integrity.dart';
import 'json/import_limits.dart';
import 'keys.dart';
import 'listeners.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/line_break_node.dart';
import 'nodes/paragraph_node.dart';
import 'nodes/root_node.dart';
import 'nodes/tab_node.dart';
import 'nodes/text_node.dart';
import 'registry.dart';
import 'selection.dart';
import 'transforms.dart';
import 'updates.dart';

/// How much of the document changed in the current update.
enum DirtyType {
  /// Nothing changed.
  none,

  /// Specific nodes changed; the dirty sets name them.
  hasDirtyNodes,

  /// Everything must be rebuilt, regardless of the dirty sets.
  fullReconcile,
}

/// What an editor should do with a node type it does not recognize.
enum UnknownNodePolicy {
  /// Throw `UnknownNodeTypeException`, as upstream Lexical does.
  ///
  /// The right default: it makes a version skew loud rather than silent.
  throwError,

  /// Decode into an inert `UnknownNode` that re-emits its JSON verbatim.
  ///
  /// The right choice for a client whose web counterpart ships new node
  /// types first — an older client then round-trips a newer document
  /// without data loss instead of refusing to open it.
  preserve,
}

/// Static configuration of one editor.
final class EditorConfig {
  /// Creates an editor configuration.
  const EditorConfig({
    this.namespace = 'lexical',
    this.unknownNodePolicy = UnknownNodePolicy.throwError,
    this.importLimits = ImportLimits.defaults,
    this.editable = true,
  });

  /// Identifies documents that may be pasted between editors.
  final String namespace;

  /// What to do with unregistered node types on import.
  final UnknownNodePolicy unknownNodePolicy;

  /// Resource bounds applied while decoding untrusted documents.
  final ImportLimits importLimits;

  /// Whether the document accepts edits.
  final bool editable;
}

/// Node specs for the types `lexical_core` implements itself.
///
/// Feature packages contribute their own; nothing here knows about headings,
/// lists or links.
List<NodeSpec<LexicalNode>> get coreNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<RootNode>(type: 'root', create: RootNode.new),
  NodeSpec<ParagraphNode>(type: 'paragraph', create: ParagraphNode.new),
  NodeSpec<TextNode>(type: 'text', create: TextNode.new),
  NodeSpec<LineBreakNode>(type: 'linebreak', create: LineBreakNode.new),
  NodeSpec<TabNode>(type: 'tab', create: TabNode.new),
];

/// Owns a document, its registry, and the update lifecycle.
///
/// The editor holds two states: the committed [editorState] and, during an
/// update, a pending clone. Reads see the committed state; the update closure
/// mutates the pending one; commit swaps and freezes.
final class LexicalEditor {
  /// Creates an editor understanding [nodes] on top of the core types.
  ///
  /// Registration is closed here. Late registration would let the same
  /// document decode differently depending on when a plugin loaded.
  factory LexicalEditor({
    List<NodeSpec<LexicalNode>> nodes = const [],
    List<NodeReplacement> replacements = const [],
    EditorConfig config = const EditorConfig(),
    EditorState? initialEditorState,
  }) {
    final registry = NodeRegistry([
      ...coreNodes,
      ...nodes,
    ], replacements: replacements);
    return LexicalEditor._(
      registry,
      config,
      initialEditorState ?? EditorState.empty(),
    );
  }

  LexicalEditor._(this.registry, this.config, EditorState initial)
    : _editorState = initial,
      _editable = config.editable {
    _editorState.freeze();
  }

  /// The node types this editor understands.
  final NodeRegistry registry;

  /// Static configuration.
  final EditorConfig config;

  /// Command handlers registered on this editor.
  @internal
  final CommandRegistry commands = CommandRegistry();

  /// Node transforms registered on this editor.
  @internal
  final TransformRegistry transforms = TransformRegistry();

  /// Listeners registered on this editor.
  @internal
  final ListenerRegistry listeners = ListenerRegistry();

  EditorState _editorState;
  EditorState? _pendingEditorState;
  bool _updating = false;
  bool _commitScheduled = false;
  bool _editable;
  int _dispatchDepth = 0;
  String _lastTextContent = '';
  EditorState? _replacementDuringUpdate;

  /// How deep command dispatch may recurse before it is called a bug.
  static const int maxDispatchDepth = 64;

  /// Keys of non-element nodes changed in the current update.
  @internal
  Set<NodeKey> dirtyLeaves = <NodeKey>{};

  /// Keys of element nodes changed in the current update.
  ///
  /// The value distinguishes *intentionally* dirty (`true`) from dirty only
  /// because a descendant changed (`false`) — the reconciler needs both.
  @internal
  Map<NodeKey, bool> dirtyElements = <NodeKey, bool>{};

  /// Keys already cloned into the pending state during this update.
  @internal
  Set<NodeKey> cloneNotNeeded = <NodeKey>{};

  /// How much changed in the current update.
  @internal
  DirtyType dirtyType = DirtyType.none;

  /// Metadata attached to the current update, delivered to listeners.
  @internal
  Set<String> updateTags = <String>{};

  /// The committed document state.
  ///
  /// **Divergence from upstream, deliberate:** reading this flushes a pending
  /// update instead of returning the pre-update state. Upstream defers the
  /// commit for DOM-batching reasons that do not apply here, and the deferral
  /// is its most frequently reported surprise. Inside an update the pending
  /// state is returned, since committing mid-update would be incoherent.
  EditorState get editorState {
    if (_updating) return _pendingEditorState ?? _editorState;
    commitPendingUpdates();
    return _editorState;
  }

  /// The uncommitted state, when an update is in flight.
  EditorState? get pendingEditorState => _pendingEditorState;

  /// Whether an update closure is currently running.
  bool get isUpdating => _updating;

  /// Runs [fn] against the document.
  ///
  /// Updates batch: several synchronous calls coalesce into one commit. Pass
  /// [discrete] to commit before returning, which is what persistence code
  /// needs.
  ///
  /// [tags] are delivered to listeners; keep them plain strings so upstream
  /// tag names such as `history-push` and `collaboration` carry over.
  ///
  /// Nested updates throw. Upstream defers them with counter-intuitive
  /// semantics preserved for backwards compatibility; there is no
  /// compatibility to preserve in a new port, and the deferral is a footgun.
  void update(void Function() fn, {bool discrete = false, Set<String>? tags}) {
    if (_updating) {
      throw const LexicalStateError(
        'Nested editor.update() is not allowed. Perform the work in the '
        'enclosing update, or use a transform or command handler.',
      );
    }
    _runUpdate(fn, discrete: discrete, tags: tags);
  }

  void _runUpdate(
    void Function() fn, {
    required bool discrete,
    Set<String>? tags,
  }) {
    final pending = _pendingEditorState ??= _editorState.cloneForUpdate();
    if (tags != null) updateTags.addAll(tags);
    _updating = true;
    try {
      runInUpdateContext(this, pending, () {
        fn();
        // A handler may have replaced the document wholesale (undo does).
        // The pending clone is then irrelevant, and running transforms or
        // the integrity walk over it would be work on a state nobody will
        // ever see.
        if (_replacementDuringUpdate != null) return;
        if (dirtyType != DirtyType.none) {
          applyAllTransforms(pending, this);
          garbageCollectDetachedNodes(
            _editorState,
            pending,
            dirtyLeaves,
            dirtyElements,
          );
        }
        _validateSelection(pending);
      });
    } on Object {
      // A half-applied update must never become the document. Upstream
      // reverts to the last committed state on error; so do we, and the
      // error propagates so the caller cannot mistake failure for success.
      _updating = false;
      _pendingEditorState = null;
      _commitScheduled = false;
      _resetDirtyState();
      rethrow;
    }
    _updating = false;

    final replacement = _replacementDuringUpdate;
    if (replacement != null) {
      _replacementDuringUpdate = null;
      _pendingEditorState = null;
      _commitScheduled = false;
      final replacementTags = updateTags;
      _resetDirtyState();
      _installState(replacement, replacementTags);
      return;
    }

    // An update that changed nothing must not become a commit. Beyond the
    // wasted work, committing a no-op wakes every listener, and a listener
    // that dispatches a command — history reporting canUndo, for instance —
    // would open another empty update and never stop.
    if (dirtyType == DirtyType.none && !_hasDirtySelection(pending)) {
      _pendingEditorState = null;
      _resetDirtyState();
      return;
    }

    assert(() {
      readEditorState(
        pending,
        () => assertTreeIntegrity($getRoot()),
        editor: this,
      );
      return true;
    }());
    if (discrete) {
      commitPendingUpdates();
    } else {
      _scheduleCommit();
    }
  }

  /// Runs [fn] inside the current update when one is active.
  ///
  /// This is what command dispatch uses: a handler must be able to mutate
  /// without opening a nested update.
  @internal
  void updateSync(void Function() fn, {Set<String>? tags}) {
    if (_updating) {
      final pending = _pendingEditorState;
      if (pending == null) {
        throw const LexicalStateError('updateSync: no pending state.');
      }
      if (tags != null) updateTags.addAll(tags);
      fn();
      return;
    }
    _runUpdate(fn, discrete: false, tags: tags);
  }

  /// Reads the committed document.
  ///
  /// Any pending update is committed first, so a read never observes a
  /// half-applied edit.
  T read<T>(T Function() fn) {
    if (_updating) {
      final pending = _pendingEditorState;
      if (pending != null) {
        return readEditorState(pending, fn, editor: this);
      }
    }
    commitPendingUpdates();
    return readEditorState(_editorState, fn, editor: this);
  }

  void _scheduleCommit() {
    if (_commitScheduled) return;
    _commitScheduled = true;
    scheduleMicrotask(() {
      _commitScheduled = false;
      commitPendingUpdates();
    });
  }

  // -------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------

  /// Registers [handler] for [command] at [priority].
  ///
  /// Returns an unsubscribe callback. Collect it and call it in `dispose()`;
  /// a leaked registration keeps the whole editor state alive.
  Unsubscribe registerCommand<P>(
    LexicalCommand<P> command,
    CommandHandler<P> handler,
    CommandPriority priority,
  ) => commands.register(command, handler, priority);

  /// Dispatches [command] with [payload].
  ///
  /// Returns `true` if a handler claimed it. Dispatch opens an update if one
  /// is not already active, so handlers may use `$` helpers directly and a
  /// whole dispatch commits as one atomic change.
  bool dispatchCommand<P>(LexicalCommand<P> command, P payload) {
    if (_dispatchDepth >= maxDispatchDepth) {
      throw LexicalStateError(
        'Command dispatch recursed more than $maxDispatchDepth levels while '
        'handling ${command.label}. A handler is very likely re-dispatching '
        'the command it is handling.',
      );
    }
    _dispatchDepth++;
    var handled = false;
    try {
      updateSync(() {
        handled = commands.dispatch(command, payload);
      });
    } finally {
      _dispatchDepth--;
    }
    return handled;
  }

  // -------------------------------------------------------------------
  // Transforms
  // -------------------------------------------------------------------

  /// Registers [transform] for nodes of [type].
  ///
  /// Existing nodes of that type are marked dirty so the transform applies
  /// to content that is already in the document, matching upstream. Because
  /// that runs an update, this cannot be called from inside one.
  ///
  /// Transforms dispatch on the exact type string, not on the class
  /// hierarchy: a transform registered for `text` does not run for a
  /// `hashtag`, even though `HashtagNode` extends `TextNode`.
  Unsubscribe registerNodeTransform(String type, NodeTransform transform) {
    if (!registry.knows(type)) {
      throw LexicalStateError(
        'registerNodeTransform: type "$type" is not registered on this '
        'editor.',
      );
    }
    final unsubscribe = transforms.register(type, transform);
    _markNodesOfTypeDirty(type);
    return unsubscribe;
  }

  void _markNodesOfTypeDirty(String type) {
    var found = false;
    for (final node in _editorState.nodeMap.values) {
      if (node.type == type) {
        found = true;
        break;
      }
    }
    if (!found) return;
    update(() {
      for (final node in $getActiveEditorState().nodeMap.values.toList()) {
        if (node.type == type) node.markDirty();
      }
    }, discrete: true);
  }

  // -------------------------------------------------------------------
  // Listeners
  // -------------------------------------------------------------------

  /// Runs [listener] after every commit.
  ///
  /// Listeners observe. A listener that mutates schedules another whole
  /// update cycle and can oscillate; put that work in a transform or a
  /// command handler instead.
  Unsubscribe registerUpdateListener(UpdateListener listener) =>
      listeners.addUpdate(listener);

  /// Runs [listener] with the mutations affecting nodes of [type].
  ///
  /// The root is never reported: it is dirty on nearly every commit, so
  /// reporting it would make the listener useless. Use a transform
  /// registered for `root` for document-level reactions.
  Unsubscribe registerMutationListener(
    String type,
    MutationListener listener,
  ) => listeners.addMutation(type, listener);

  /// Runs [listener] when the document's plain text changes.
  Unsubscribe registerTextContentListener(TextContentListener listener) =>
      listeners.addTextContent(listener);

  /// Runs [listener] when [isEditable] changes.
  Unsubscribe registerEditableListener(EditableListener listener) =>
      listeners.addEditable(listener);

  /// Whether the document currently accepts edits.
  bool get isEditable => _editable;

  /// Sets whether the document accepts edits, notifying listeners.
  set isEditable(bool value) {
    if (_editable == value) return;
    _editable = value;
    listeners.notifyEditable(editable: value);
  }

  /// Whether [pending]'s selection differs from the committed one.
  bool _hasDirtySelection(EditorState pending) {
    final pendingSelection = pending.selection;
    final currentSelection = _editorState.selection;
    if (pendingSelection != null) {
      return pendingSelection.dirty ||
          !pendingSelection.isSameAs(currentSelection);
    }
    return currentSelection != null;
  }

  /// Rejects a selection that points at nodes this update removed.
  ///
  /// Without the check the failure surfaces at render time, far from the
  /// mutation that caused it; here it names the update that lost the caret.
  void _validateSelection(EditorState pending) {
    final selection = pending.selection;
    if (selection is! RangeSelection) {
      if (selection is NodeSelection && selection.keys.isEmpty) {
        pending.setSelectionInternal(null);
      }
      return;
    }
    final map = pending.nodeMap;
    if (map.containsKey(selection.anchor.key) &&
        map.containsKey(selection.focus.key)) {
      return;
    }
    throw const LexicalStateError(
      'Selection was lost: the selected nodes were removed without moving '
      'the selection. Move the selection when removing or replacing a '
      'selected node.',
    );
  }

  /// Commits the pending state, if any. Framework-internal.
  @internal
  void commitPendingUpdates() {
    final pending = _pendingEditorState;
    if (pending == null || _updating) return;
    _pendingEditorState = null;
    final previous = _editorState;
    pending.freeze();
    // The flag has served its purpose; leaving it set would make the next
    // no-op update look like a selection change.
    pending.selection?.dirty = false;
    _editorState = pending;

    final tags = updateTags;
    final leaves = dirtyLeaves;
    final elements = dirtyElements;
    _resetDirtyState();

    if (listeners.hasMutationListeners) {
      listeners.notifyMutations(
        computeMutations(previous, pending, leaves, elements),
      );
    }
    listeners.notifyUpdate(
      EditorUpdate(
        editorState: pending,
        previousEditorState: previous,
        tags: Set.unmodifiable(tags),
        dirtyLeaves: Set.unmodifiable(leaves),
        dirtyElements: Map.unmodifiable(elements),
      ),
    );
    if (listeners.hasTextContentListeners) {
      final text = readEditorState(
        pending,
        () => $getRoot().getTextContent(),
        editor: this,
      );
      if (text != _lastTextContent) {
        _lastTextContent = text;
        listeners.notifyTextContent(text);
      }
    }
  }

  void _resetDirtyState() {
    dirtyLeaves = <NodeKey>{};
    dirtyElements = <NodeKey, bool>{};
    cloneNotNeeded = <NodeKey>{};
    dirtyType = DirtyType.none;
    updateTags = <String>{};
  }

  /// Replaces the document wholesale.
  ///
  /// Any pending update is discarded. Listeners are notified with
  /// `isFullReconcile` set, because nothing was diffed and the dirty sets
  /// therefore carry no information a renderer could act on.
  ///
  /// Calling this from inside a command handler is supported and is how undo
  /// works: the enclosing update is abandoned in favour of [state], since
  /// the two describe different documents and only one can win.
  void setEditorState(EditorState state, {Set<String>? tags}) {
    state.freeze();
    if (_updating) {
      _replacementDuringUpdate = state;
      if (tags != null) updateTags.addAll(tags);
      return;
    }
    _pendingEditorState = null;
    _commitScheduled = false;
    _installState(state, tags ?? const <String>{});
  }

  void _installState(EditorState state, Set<String> tags) {
    final previous = _editorState;
    _editorState = state;
    _resetDirtyState();
    if (identical(previous, state)) return;

    listeners.notifyUpdate(
      EditorUpdate(
        editorState: state,
        previousEditorState: previous,
        tags: Set.unmodifiable(tags),
        dirtyLeaves: const <NodeKey>{},
        dirtyElements: const <NodeKey, bool>{},
        isFullReconcile: true,
      ),
    );
    if (listeners.hasTextContentListeners) {
      final text = readEditorState(
        state,
        () => $getRoot().getTextContent(),
        editor: this,
      );
      if (text != _lastTextContent) {
        _lastTextContent = text;
        listeners.notifyTextContent(text);
      }
    }
  }

  // -------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------

  /// Decodes a serialized document into a frozen state.
  ///
  /// The result is not installed; pass it to [setEditorState] to adopt it.
  /// Import is bounded by [EditorConfig.importLimits] and rejects unknown
  /// node types according to [EditorConfig.unknownNodePolicy].
  EditorState parseEditorState(Map<String, Object?> json) =>
      importEditorState(this, json);

  /// Decodes a serialized document from a JSON string.
  EditorState parseEditorStateFromString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw MalformedDocumentException('invalid JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const MalformedDocumentException(
        'document root must be a JSON object',
      );
    }
    return parseEditorState(decoded);
  }

  /// Serializes the committed document.
  Map<String, Object?> toJson() => editorState.toJson();

  /// Serializes the committed document to a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Appends an empty paragraph when the document has no children.
  ///
  /// The empty-document shape is `"children": []`, so seeding an initial
  /// paragraph is the editor's job rather than the decoder's. Call this
  /// after installing a state if the editor should never be structurally
  /// empty.
  void ensureNonEmpty() {
    update(() {
      final root = $getRoot();
      if (root.isEmpty) {
        root.append($createParagraphNode());
      }
    }, discrete: true);
  }
}

/// Convenience: the root element of [editor]'s committed state.
ElementNode rootOf(LexicalEditor editor) => editor.editorState.root;
