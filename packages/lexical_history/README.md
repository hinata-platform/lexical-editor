![lexical_history](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_history.png)

# lexical_history

Undo and redo for [`lexical_core`](https://pub.dev/packages/lexical_core).
Pure Dart, no Flutter dependency.

## Install

```yaml
dependencies:
  lexical_history: ^0.1.0
```

## Use

```dart
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_history/lexical_history.dart';

final editor = LexicalEditor();
final dispose = registerHistory(editor);

editor.dispatchCommand(undoCommand, null);
editor.dispatchCommand(redoCommand, null);
editor.dispatchCommand(clearHistoryCommand, null);

dispose();   // removes every registration
```

Observing availability, for a toolbar:

```dart
editor
  ..registerCommand(canUndoCommand, (canUndo) {
    setState(() => _canUndo = canUndo);
    return false;                    // observe without claiming the command
  }, CommandPriority.editor)
  ..registerCommand(canRedoCommand, (canRedo) {
    setState(() => _canRedo = canRedo);
    return false;
  }, CommandPriority.editor);
```

## How it works

An undo stack is a list of `EditorState` references. That is not a shortcut —
committed states are immutable and share every untouched node with their
predecessor, so retaining one costs a pointer plus the nodes that actually
changed. There is no operation log to replay and therefore no way for undo to
drift from the document it claims to restore. Selection is part of the state,
so it is restored for free.

## Coalescing

The interesting design question is which consecutive edits share one undo
entry. This package decides from **update tags and the dirty-node set, never
from a timer**. Undo granularity then depends on what the user did rather than
on how fast they typed, and the behaviour is deterministic enough to test —
timer-based coalescing produces suites that pass locally and flake in CI.

A run continues only when all of the following hold:

- exactly one text node changed;
- its format, style and mode did not;
- no element was modified in its own right (the root is exempt — the transform
  pass always flags it, so its dirty state carries no information);
- the new text extends or truncates the old one at a single edge;
- the change is the same kind as the previous one, in the same node.

Anything else starts a new entry: a format toggle, a split, a paste, a
structural change, or switching from typing to deleting.

Two tags override the decision:

| Tag | Effect |
|---|---|
| `historyPushTag` (`history-push`) | Force a new undo entry |
| `historyMergeTag` (`history-merge`) | Fold into the current entry |
| `historicTag` (`historic`) | Applied by this package to its own state swaps, so undo does not record itself |

```dart
editor.update(() { /* ... */ }, tags: {historyPushTag});
```

## Bounding

`HistoryState(maxDepth: 500)` caps retained entries; the oldest are dropped
first. Pass your own instance to inspect depth or to share one across
editors.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
