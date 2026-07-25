![lexical_mark](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_mark.png)

# lexical_mark

Mark nodes — annotations and comment ranges — for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_mark: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: markNodes);

editor.update(() {
  $getRoot().append(
    $createParagraphNode()
      ..append($createMarkNode(['comment-1'])
        ..append($createTextNode('markiert'))),
  );
}, discrete: true);
```

A mark wraps inline content and carries a set of identifiers. Overlapping
annotations are represented by **nesting** marks rather than by letting one
node belong to two ranges — which is why `ids` is a list: the innermost mark
of an overlap carries every identifier that covers it.

Wire-compatible with `@lexical/mark` 0.48.x.

## Commenting a selection

```dart
registerMark(editor);                             // once
final id = 'comment-42';                          // yours
editor.dispatchCommand(addMarkCommand, id);       // mark the selection
editor.dispatchCommand(removeMarkCommand, id);    // resolve it
```

Only the **id** reaches the document. Author, text, replies and timestamps
belong to the application, keyed by that id — which is what lets a comment be
written, answered and resolved without touching the document, and keeps a
document with fifty threads the same size as one with none.

`$getMarkedText(id)` reads back what the mark covers **now**, so a sidebar's
quote follows the text as it is edited instead of quoting something that no
longer exists. `$getMarkIdsAtSelection()` answers which threads the caret is
inside.

Marking the same range twice adds the second id to the mark already there;
marking an *overlapping* range nests, because a node has one parent. A mark
left with no ids is unwrapped rather than kept — an annotation nobody refers
to is invisible, and leaving it behind would grow the document by one element
per resolved comment forever.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
