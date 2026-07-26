![lexical_code](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_code.png)

# lexical_code

Code blocks and syntax highlighting for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart, no
dependencies.

```yaml
dependencies:
  lexical_code: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: codeNodes);
registerCode(editor);              // Enter and Tab inside a code block
registerCodeHighlighting(editor);  // colour, kept in step with the text

editor.update(() {
  $getRoot().append(
    $createCodeNode('dart')..append($createTextNode('void main() {}')),
  );
}, discrete: true);
```

That is the whole feature. The text goes in; a transform splits it into
classified runs on every commit, so typing, pasting and undo stay coloured
without anything else being wired up. Changing `language` re-colours the same
text.

Fifteen languages out of the box — `c`, `cpp`, `csharp`, `dart`, `go`, `java`,
`javascript`, `json`, `kotlin`, `python`, `rust`, `shell`, `sql`, `swift`,
`typescript`, plus the usual aliases (`js`, `ts`, `py`, `kt`, `sh`, `c++`).
Anything else is a `CodeLanguage.register` call: a set of keywords and how the
language spells comments and strings, not a grammar.

The tokenizer is usable on its own, without an editor:

```dart
tokenizeCode('SELECT 1;', language: 'sql');
// [CodeToken(keyword: SELECT), CodeToken(number: 1), CodeToken(punctuation: ;)]
```

## Colour is the renderer's job

A run says what it *is* — `keyword`, `string`, `comment` — and never what
colour it is. The names are Prism's, which is what Lexical web writes into
`highlightType`, so a block highlighted here is coloured by the playground's
stylesheet and one highlighted there is coloured by your Flutter theme.
`lexical_editor_flutter` ships that mapping; a custom theme supplies it through
`LexicalTheme.textStyleResolver`.

`@lexical/code-shiki` takes the other route and bakes its palette into each
node's `style` as inline CSS. Those documents render here too — the CSS is
honoured — but a stored document that remembers a light theme forever is the
wrong trade, so this package does not produce them.

## One thing that surprises every port

A code block's children are **flat**: highlight runs, `LineBreakNode`s and
`TabNode`s side by side, never nested. But a block authored by appending a
multi-line text node — from a markdown import, say, or a client with no
highlighter — keeps its newlines *inside that text node*, and Lexical's
serializer preserves them. A renderer must handle newlines in text content
rather than assuming every break is a `LineBreakNode`.

Highlighting leaves a block whose language it does not know exactly as it
found it, for the same reason: another client may have classified it for a
language this build has never heard of.

Wire-compatible with `@lexical/code` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
