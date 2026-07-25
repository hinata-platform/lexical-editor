/// Undo and redo over immutable editor-state snapshots.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

/// Update tag that forces a new undo entry.
const String historyPushTag = 'history-push';

/// Update tag that folds the change into the previous undo entry.
const String historyMergeTag = 'history-merge';

/// Update tag marking a change *produced by* history, so it is not recorded.
const String historicTag = 'historic';

/// How one commit relates to the previous undo entry.
enum HistoryMergeAction {
  /// Start a new undo entry.
  push,

  /// Fold into the current entry — a continued typing run.
  merge,

  /// Record nothing; the change came from history itself.
  discard,
}

/// The shape of a change, used to decide whether a run continues.
///
/// Coalescing is driven by this and by update tags, **not by a timer**.
/// Timer-based coalescing produces tests that pass locally and flake in CI,
/// and it makes undo granularity depend on how fast the user types rather
/// than on what they did.
enum HistoryChangeType {
  /// Anything that ends the current run.
  other,

  /// Text appended at the caret inside one text node.
  insertText,

  /// Text removed before the caret inside one text node.
  deleteBackward,

  /// Text removed after the caret inside one text node.
  deleteForward,
}

/// The undo and redo stacks.
///
/// Because committed states are immutable and structurally shared, an undo
/// stack is a list of state references: cheap to keep, and correct by
/// construction rather than by replaying operations.
final class HistoryState {
  /// Creates an empty history.
  HistoryState({this.maxDepth = 500});

  /// How many undo entries to retain. Older entries are dropped.
  final int maxDepth;

  final List<EditorState> _undo = <EditorState>[];
  final List<EditorState> _redo = <EditorState>[];

  EditorState? _current;
  HistoryChangeType _lastChangeType = HistoryChangeType.other;
  NodeKey? _lastChangeKey;

  /// Whether an undo is available.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether a redo is available.
  bool get canRedo => _redo.isNotEmpty;

  /// Number of retained undo entries.
  int get undoDepth => _undo.length;

  /// Number of retained redo entries.
  int get redoDepth => _redo.length;

  /// Forgets everything, keeping the current state as the baseline.
  void clear() {
    _undo.clear();
    _redo.clear();
    _lastChangeType = HistoryChangeType.other;
    _lastChangeKey = null;
  }
}

/// Wires undo and redo into [editor].
///
/// Registers handlers for `undoCommand`, `redoCommand` and
/// `clearHistoryCommand` at [CommandPriority.editor], so an application can
/// override any of them by registering at `beforeEditor`.
///
/// Returns an unsubscribe callback that removes every registration.
Unsubscribe registerHistory(
  LexicalEditor editor, {
  HistoryState? state,
  void Function(HistoryState state)? onChange,
}) {
  final history = state ?? HistoryState();
  history._current = editor.editorState;
  bool? reportedCanUndo;
  bool? reportedCanRedo;

  // Only dispatch on an actual change. A dispatch opens an update, and an
  // update fires this listener again — cheap to make idempotent, expensive
  // to debug once it is not.
  void notify() {
    onChange?.call(history);
    if (reportedCanUndo != history.canUndo) {
      reportedCanUndo = history.canUndo;
      editor.dispatchCommand(canUndoCommand, history.canUndo);
    }
    if (reportedCanRedo != history.canRedo) {
      reportedCanRedo = history.canRedo;
      editor.dispatchCommand(canRedoCommand, history.canRedo);
    }
  }

  final subscriptions = <Unsubscribe>[
    editor.registerUpdateListener((update) {
      final action = _decide(history, update);
      switch (action) {
        case HistoryMergeAction.discard:
          history._current = update.editorState;
        case HistoryMergeAction.merge:
          history._current = update.editorState;
        case HistoryMergeAction.push:
          final current = history._current;
          if (current != null) {
            history._undo.add(current);
            if (history._undo.length > history.maxDepth) {
              history._undo.removeAt(0);
            }
          }
          history._redo.clear();
          history._current = update.editorState;
      }
      if (action != HistoryMergeAction.discard) notify();
    }),
    editor.registerCommand(undoCommand, (_) {
      return _undo(editor, history, notify);
    }, CommandPriority.editor),
    editor.registerCommand(redoCommand, (_) {
      return _redo(editor, history, notify);
    }, CommandPriority.editor),
    editor.registerCommand(clearHistoryCommand, (_) {
      history.clear();
      notify();
      return true;
    }, CommandPriority.editor),
  ];

  notify();

  return () {
    for (final unsubscribe in subscriptions) {
      unsubscribe();
    }
  };
}

bool _undo(LexicalEditor editor, HistoryState history, void Function() notify) {
  if (history._undo.isEmpty) return false;
  final current = history._current;
  final previous = history._undo.removeLast();
  if (current != null) history._redo.add(current);
  history
    .._current = previous
    .._lastChangeType = HistoryChangeType.other
    .._lastChangeKey = null;
  editor.setEditorState(previous, tags: {historicTag});
  notify();
  return true;
}

bool _redo(LexicalEditor editor, HistoryState history, void Function() notify) {
  if (history._redo.isEmpty) return false;
  final current = history._current;
  final next = history._redo.removeLast();
  if (current != null) history._undo.add(current);
  history
    .._current = next
    .._lastChangeType = HistoryChangeType.other
    .._lastChangeKey = null;
  editor.setEditorState(next, tags: {historicTag});
  notify();
  return true;
}

HistoryMergeAction _decide(HistoryState history, EditorUpdate update) {
  if (update.hasTag(historicTag)) return HistoryMergeAction.discard;
  if (update.hasTag(historyPushTag)) {
    history
      .._lastChangeType = HistoryChangeType.other
      .._lastChangeKey = null;
    return HistoryMergeAction.push;
  }
  if (update.hasTag(historyMergeTag)) return HistoryMergeAction.merge;
  if (history._current == null) return HistoryMergeAction.push;

  final change = classifyChange(update);
  final sameRun =
      change.type != HistoryChangeType.other &&
      change.type == history._lastChangeType &&
      change.key == history._lastChangeKey;

  history
    .._lastChangeType = change.type
    .._lastChangeKey = change.key;

  return sameRun ? HistoryMergeAction.merge : HistoryMergeAction.push;
}

/// The classification of a single commit.
@immutable
final class HistoryChange {
  /// Describes one commit.
  const HistoryChange(this.type, this.key);

  /// What kind of change this was.
  final HistoryChangeType type;

  /// The text node it happened in, when there was exactly one.
  final NodeKey? key;
}

/// Classifies [update] as a continuable run or as something that breaks one.
///
/// A run continues only when exactly one text node changed, its formatting
/// did not, no element was modified in its own right, and the new text
/// extends or truncates the old one at a single edge. Anything else — a
/// format toggle, a split, a paste, a structural change — starts a new undo
/// entry, which is what a user expects when they press undo.
@visibleForTesting
HistoryChange classifyChange(EditorUpdate update) {
  const none = HistoryChange(HistoryChangeType.other, null);
  if (update.isFullReconcile) return none;
  if (update.dirtyLeaves.length != 1) return none;
  // An element dirty with `true` was modified in its own right; `false` means
  // it is dirty only because a descendant changed, which is expected here.
  //
  // The root is exempt: the transform pass always flags it intentionally
  // dirty so its transform can act as the update finalizer, so its value
  // carries no information about what the user did. A genuine structural
  // change at the root still shows up as some *other* element being
  // intentionally dirty — the node that was added or removed.
  final structural = update.dirtyElements.entries.any(
    (entry) => entry.value && entry.key != NodeKey.root,
  );
  if (structural) return none;

  final key = update.dirtyLeaves.single;
  final before = update.previousEditorState.nodeMap[key];
  final after = update.editorState.nodeMap[key];
  if (before is! TextNode || after is! TextNode) return none;

  final oldText = update.previousEditorState.read(before.getTextContent);
  final newText = update.editorState.read(after.getTextContent);
  if (oldText == newText) return none;

  final beforeAttributes = update.previousEditorState.read(
    () => (before.getFormat(), before.getStyle(), before.getMode()),
  );
  final afterAttributes = update.editorState.read(
    () => (after.getFormat(), after.getStyle(), after.getMode()),
  );
  if (beforeAttributes != afterAttributes) return none;

  if (newText.length > oldText.length && newText.startsWith(oldText)) {
    return HistoryChange(HistoryChangeType.insertText, key);
  }
  if (newText.length < oldText.length && oldText.startsWith(newText)) {
    return HistoryChange(HistoryChangeType.deleteBackward, key);
  }
  if (newText.length < oldText.length && oldText.endsWith(newText)) {
    return HistoryChange(HistoryChangeType.deleteForward, key);
  }
  return none;
}
