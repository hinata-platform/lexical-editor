![lexical_code](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_code.png)

# lexical_code

Code block and syntax-highlight nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_code: ^0.1.0
```

```dart
final editor = LexicalEditor(nodes: codeNodes);

editor.update(() {
  $getRoot().append(
    $createCodeNode('dart')
      ..append($createCodeHighlightNode('void', 'keyword'))
      ..append($createTextNode(' main() {}')),
  );
}, discrete: true);
```

This package **models** code; it does not tokenize it. Highlighting is a
per-language concern with its own dependency weight, so producing
`CodeHighlightNode`s is left to whatever highlighter your app already uses —
the wire format only needs the classification string.

## One thing that surprises every port

A code block authored by appending a multi-line text node keeps the newlines
**inside that text node**. Lexical's editing paths avoid `\n` in text, but its
serializer preserves it, so splitting those runs into line breaks would make
you unable to open documents Lexical itself produces. A renderer must handle
newlines in text content rather than assuming every break is a `LineBreakNode`.

Wire-compatible with `@lexical/code` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
