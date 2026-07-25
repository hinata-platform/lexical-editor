![lexical_flutter](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_flutter.png)

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

`tokenBuilders` draws a **token text node** — a mention, a chip — as a widget
instead of as text, which is the only way to get padding, a rounded corner or
an avatar. The node stays text in the model, so the document is unchanged and a
web client reads it as before. Token mode only: the widget occupies one
position while the node holds a whole label, so the caret can sit at its edges
and nowhere else — exactly the guarantee token mode already makes.

Every builder — token, decorator, marker — runs **inside the editor's read**,
and the widget it returns is built later, by Flutter, without one. Read the
node in the builder and hand the widget values; a widget that keeps the node
and reads it in its own `build` throws on the first frame.

CSS is interpreted at render time by an injectable `styleResolver`; the raw
`style` string stays verbatim in the model so documents round-trip unchanged.
The default resolver handles `color`, `background-color`, `font-size`,
`font-family`, `font-weight` and `text-decoration` and ignores the rest —
which loses nothing, because the string is preserved either way.

## Hover and tap

Smart links — hover a mention for a preview, tap it to navigate — need to know
which node is under the pointer. `LexicalInteraction` answers that, keyed on
**type string** so this package still knows nothing about links, mentions or
hashtags:

```dart
LexicalDocument(
  editor: editor,
  theme: theme,
  interaction: LexicalInteraction(
    types: const {'link', 'autolink', 'mention', 'hashtag'},
    onEnter: (hit) => preview.show(hit),      // mouse only
    onExit: (hit) => preview.hide(),
    onTap: (hit) => router.go(hit.json['url'] as String? ?? '/'),
  ),
)
```

A `LexicalNodeHit` is a **snapshot** — key, type, text, the node's serialized
fields and its bounds in global coordinates — not a node. It is handed to
callbacks that outlive the read it came from, and a preview card reads it
frames later, so everything in it is a plain value.

Three details that make it behave:

- The pointer is usually over a link's *text child*; the hit reports the
  **link**, resolved by walking up to the nearest requested type.
- A hit is confirmed against the node's own line boxes. `getPositionForOffset`
  answers with the nearest position however far away the pointer is, so
  without that check a mention at the end of a line owns the whole margin
  beside it.
- Moving *within* a node is not an event. A preview that is torn down and
  rebuilt on every mouse move is unusable.

`onTap` fires on tap **up**, so a selection drag that started on a link does
not navigate. Inside an editable the caret still moves — text inside a link has
to stay reachable — and the tap resolves after the double-tap deadline, since
double-tap-to-select shares the gesture arena. A read-only document reacts
immediately.

## One rendering difference from the web

A run formatted `uppercase` reads `STRAßE` here and `STRASSE` on the web:
Dart applies *simple* (1:1) Unicode case mapping while JavaScript applies
*full* mapping. Presentation only — the model text is identical, so documents
still round-trip byte for byte. The upside is that offsets in a
case-transformed run always map one to one in Dart, which removes a class of
caret bug the web implementation has to handle.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
