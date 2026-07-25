# lexical_editor_flutter

A [Lexical](https://lexical.dev)-compatible editor for Flutter with everything
already wired up.

```yaml
dependencies:
  lexical_editor_flutter: ^0.1.0
```

```dart
final editor = createLexicalEditor();

LexicalEditorField(
  editor: editor,
  baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
)
```

That is the whole setup: every node type registered, the editing behaviour each
of them needs, undo, and a theme that presents all of them.

## What it assembles

Headings, quotes, bullet / ordered / check lists with nesting, links, code
blocks, tables, marks, hashtags and mentions — plus the rich-text command set,
list and code behaviour for Enter and Tab, and history.

Everything is available separately. The other packages in this family are
deliberately narrow so an application pays only for what it uses; this one is
the opposite, and is the right place to start.

## When to drop to the narrower packages

When a document must **not** contain something. The node registry is closed at
construction, so a type that was never registered cannot be created, pasted or
imported — and an unknown type in a stored document is refused loudly rather
than silently dropped.

```dart
final editor = LexicalEditor(nodes: [...richTextNodes, ...listNodes]);
registerRichText(editor);
registerList(editor);
```

## Theming

`defaultLexicalTheme` derives everything from a body text style and a
six-colour `LexicalPalette`, so an app gets its own typography by passing its
body style in and changing nothing else. `LexicalPalette.dark()` is provided;
any `LexicalTheme` can be passed instead.

## What is deliberately not here

Selection handles and a context toolbar. Material and Cupertino disagree about
what those look like, and so will your design system — so the geometry is
exposed (`LexicalEditableState.caretRect`, `.selectionRects`) and the design is
left to the application.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
