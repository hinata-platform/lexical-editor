# lexical_mark

Mark nodes — annotations and comment ranges — for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_mark: ^0.1.0
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

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
