# Changelog

## 0.1.0-dev.2

- A commit tagged `collaboration` no longer becomes an undo entry of its own,
  so undo steps over your own work rather than a collaborator's.
- Registering no longer dispatches `canUndo`/`canRedo` immediately, which
  committed an update from `initState`.

## 0.1.0-dev.1

First development release.

### Added

- `registerHistory` wiring `undoCommand`, `redoCommand` and
  `clearHistoryCommand` into an editor at `CommandPriority.editor`, so an
  application can override any of them at `beforeEditor`.
- `HistoryState` holding undo and redo stacks of `EditorState` references,
  bounded by `maxDepth`.
- Deterministic coalescing driven by update tags and the dirty-node set
  rather than by a timer, with `historyPushTag` and `historyMergeTag` as
  explicit overrides.
- `canUndoCommand` / `canRedoCommand` dispatched only when the answer
  changes, so a toolbar can observe without polling.
- `classifyChange`, exposed for testing the coalescing rules directly.
