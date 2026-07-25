# Changelog

## 0.1.0-dev.1

Milestone M2 — the read-only renderer.

### Added

- `LexicalDocument`, a widget rendering an editor's document, with rebuilds
  driven by each commit's dirty set rather than by rebuilding from the state.
  Untouched blocks are reused by reference.
- `RenderLexicalBlock`: one render object per block, with inline widget
  children for decorators, selection painting and a caret that repaints
  without relayout.
- `SpanBuilder`, producing an `InlineSpan` and a `BlockOffsetMap` in a single
  walk so the two cannot drift apart.
- `BlockOffsetMap`, the bidirectional map between a block's flat text offsets
  and `(NodeKey, offset, type)` model points, with explicit boundary rules.
- `LexicalTheme`: text-format styles, per-type block styles keyed on the
  **type string** so this package never imports the feature packages, marker
  builders for list bullets and checkboxes, and an injectable CSS resolver.
- `BlockRegistry`, tracking mounted blocks so the input layer can locate a
  block's geometry without keeping a key per document node.
- Viewport culling through a lazily built list.

### Known limitations

- Editing arrives in M3: no IME, no keyboard handling, no selection gestures.
- Semantics are not yet emitted per block.
