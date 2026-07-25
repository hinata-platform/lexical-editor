# lexical_flutter

Flutter rendering for [`lexical_core`](https://pub.dev/packages/lexical_core).

```yaml
dependencies:
  lexical_flutter: ^0.1.0
```

```dart
LexicalDocument(
  editor: editor,
  theme: LexicalTheme(
    baseTextStyle: DefaultTextStyle.of(context).style,
    blockStyles: {
      'heading': BlockStyle(
        textStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
    },
  ),
)
```

## Why not build on EditableText

`TextField`, `EditableText` and `TextEditingController` all treat a flat
`String` as the source of truth — which is precisely the premise Lexical
rejects. A controller cannot represent block structure, per-node formatting or
decorators, and it will happily overwrite the document with a flattened string
on any IME event you fail to intercept. This package builds one layer below:
`TextPainter` for layout, custom render objects for painting, and (in M3)
`DeltaTextInputClient` for input.

## Architecture

**One render object per block, never one for the document.** A `TextPainter`
relayouts its entire content on any change, so a single painter makes every
keystroke O(document); per block it is O(block). It is also what allows lazy
layout and viewport culling — the thing that makes a long document viable.

**The span and the offset map are built in one walk.** Selection and IME speak
flat integer offsets; the model speaks `(NodeKey, offset, type)`. Two maps
built separately drift, and the resulting bug — the caret lands one character
off, but only after certain edits — is extremely hard to localize.

**Rebuilds follow the dirty set.** Lexical already knows which nodes changed;
that is exactly what Flutter needs in order not to rebuild everything. Because
committed states share untouched nodes by reference, an identity check is a
sound and very cheap invalidation test. The test suite asserts on this
directly: editing one paragraph in a five-paragraph document rebuilds one
block.

## Theming without dependencies

`LexicalTheme` keys block styles and markers on the node's **type string**, so
this package styles headings, lists, quotes and tables without importing — or
knowing about — the packages that define them. List bullets and checkboxes
come from `markerBuilders`, which the application or an umbrella package
supplies.

CSS is interpreted at render time by an injectable `styleResolver`; the raw
`style` string stays verbatim in the model so documents round-trip unchanged.
The default resolver handles `color`, `background-color`, `font-size`,
`font-family`, `font-weight` and `text-decoration` and ignores the rest —
which loses nothing, because the string is preserved either way.

## One rendering difference from the web

A run formatted `uppercase` reads `STRAßE` here and `STRASSE` on the web:
Dart applies *simple* (1:1) Unicode case mapping while JavaScript applies
*full* mapping. Presentation only — the model text is identical, so documents
still round-trip byte for byte. The upside is that offsets in a
case-transformed run always map one to one in Dart, which removes a class of
caret bug the web implementation has to handle.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
