# Changelog

## 1.7.5

**Moving the caret is no longer an undo step.** Every commit that dirtied no
node — a click, an arrow key, selecting a range — pushed an entry onto the undo
stack, so the first undo after clicking around only put the caret back and
appeared to do nothing, and each of those pushes cleared the redo stack, which
meant clicking anywhere after an undo threw the redo away. A caret position is
not a change to the document. It still ends the current typing run, because
text typed, caret moved, text typed again is two edits and undo should take
them one at a time. This is what upstream does.

**A node that is marked dirty but comes out unchanged does not become an entry
either** — a transform that reverted the edit, or a write of the value that was
already there. There is nothing for an undo to step back over.

Released on its own rather than in lockstep with the set: nothing else changed,
and nineteen uploads is a tenth of pub.dev's daily budget.

## 1.7.4

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.3

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.2

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_link` for what changed.

## 1.7.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` and
`lexical_flutter` for what changed.

## 1.6.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.6.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.5.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.4.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_flutter` for what changed.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

## 1.0.0

First stable release; semantic versioning applies from here.
Undo and redo with upstream’s coalescing rules, and collaboration-aware
merging so a peer’s typing never becomes your undo step.

The entries below record how it got here.

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
