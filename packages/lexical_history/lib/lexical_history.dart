/// Undo and redo for `lexical_core`.
///
/// Because committed editor states are immutable and structurally shared, an
/// undo stack is a list of state references — cheap to keep, and correct by
/// construction rather than by replaying operations in reverse.
///
/// ```dart
/// final editor = LexicalEditor();
/// final dispose = registerHistory(editor);
///
/// editor.update(() { /* ... */ }, discrete: true);
/// editor.dispatchCommand(undoCommand, null);
/// editor.dispatchCommand(redoCommand, null);
///
/// dispose();
/// ```
///
/// Coalescing — which consecutive edits share one undo entry — is driven by
/// update tags and the dirty-node set, never by a timer. Undo granularity
/// therefore depends on what the user did rather than on how fast they typed,
/// and the behaviour is deterministic enough to test.
library;

export 'src/history.dart'
    show
        HistoryChange,
        HistoryChangeType,
        HistoryMergeAction,
        HistoryState,
        classifyChange,
        collaborationTag,
        historicTag,
        historyMergeTag,
        historyPushTag,
        registerHistory;
