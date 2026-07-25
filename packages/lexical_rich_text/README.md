![lexical_rich_text](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_rich_text.png)

# lexical_rich_text

Heading and quote nodes for [`lexical_core`](https://pub.dev/packages/lexical_core).
Pure Dart, no Flutter dependency.

```yaml
dependencies:
  lexical_rich_text: ^0.1.0
```

```dart
final editor = LexicalEditor(nodes: richTextNodes);

editor.update(() {
  $getRoot()
    ..append($createHeadingNode(HeadingTag.h2)..append($createTextNode('Bericht')))
    ..append($createQuoteNode()..append($createTextNode('Zitiert')));
}, discrete: true);
```

`HeadingNode` carries a `tag` of `h1`…`h6`; `HeadingTag.level` gives the
numeric level for styling. `QuoteNode` has no fields of its own — only the
element base shape.

Wire-compatible with `@lexical/rich-text` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
