# Changelog

## 1.9.0

**Tick boxes tick.** The box in front of a check-list item was painted and never
wired to anything — `toggleChecked` existed on the node and no gesture reached
it, so a checklist could be written but never checked off. It now toggles on the
pointer rather than through a recognizer, so it answers immediately instead of
waiting out the editable's tap series.

**Tick boxes are visible.** An unticked box had no fill at all: a hairline
rectangle the reader had to hunt for on a light page. It now carries a tinted
fill and a fuller border, and announces itself through `Semantics` as a control
with a state rather than as decoration.

Fixes the tick itself being drawn in hard-coded white regardless of the palette,
which put an invisible mark on any palette with a pale accent.

**New:** `checkboxKey(NodeKey)` — the key of one item's tick box, so a host can
find one among many without depending on the private widget that draws it.

**New:** `LexicalEditorField.onContextMenu`, forwarded to the editable.

## 1.7.4

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.3

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.2

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_link` for what changed.

## 1.7.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` and
`lexical_flutter` for what changed.

## 1.6.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.6.0

**`lexicalDecoratorBuilders(imagePlaceholderBuilder:)`** forwards to the image
builder. A stand-in that cannot say *which* image failed, or offer to try
again, leaves a grey box and no way forward — and the bundle was the one path
that could not replace it.

## 1.5.0

**`lexicalDecoratorBuilders(imageStyle:)`** forwards a `LexicalImageStyle`, so
a bundled editor can draw the image's selection chrome in its own accent
instead of the built-in blue.

## 1.4.0

**`LexicalMentions.surfaceBuilder`** forwards to `MentionScope`, so a bundle
user can give the typeahead its own material rather than the box a
`Decoration` allows.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

- `LexicalHorizontalRuleView` and `horizontalRuleDecoratorBuilders()`, for the
  `HorizontalRuleNode` new in `lexical_rich_text` 1.2.0. Included in
  `lexicalDecoratorBuilders`, so a bundled editor draws a rule rather than the
  text stand-in a decorator without a builder falls back to. Its colour comes
  from the surrounding text style, so it follows a light or dark document
  without being configured.

## 1.1.0

- `LexicalEditorField.mentions`: the `@` typeahead, given a source. Mentions
  are the one feature that cannot have a default — only the application knows
  who can be mentioned — which is why there is no `registerMention` beside
  `registerTable`.
- Selected table cells are tinted. Selecting cells and merging them are the
  same rectangle, and a user who cannot see it is guessing.

## 1.0.0

First stable release; semantic versioning applies from here.
The batteries-included editor: every node type, the default theme, history and
smart-link interaction in one widget. `registerLexical` now also registers link and
mark behaviour; `editableKey` hands over the selection geometry a floating
toolbar needs, and `contextMenuBuilder` can suppress the platform's own
selection menu for an application that draws its own.

The entries below record how it got here.

## 0.1.0-dev.2

Seeding an empty document waits for the end of the frame, so a listener that
rebuilds is not asked to rebuild during a build.

`LexicalEditorField.interaction` forwards hover and tap, and
`interactiveNodeTypes` names every type in the bundle that can point
somewhere — link, autolink, mention, hashtag.

## 0.1.0-dev.1

First development release.

### Added

- `createLexicalEditor` and `lexicalNodes`: every node type in this family,
  registered together.
- `registerLexical`: rich text, lists, code and history, in the order their
  command priorities require.
- `defaultLexicalTheme` and `LexicalPalette`, presenting every registered type
  — heading scale by level, quote bars, code backgrounds, bullets, numbers and
  checkboxes, table grids, link and mention styling.
- `LexicalEditorField`, the one-widget arrangement of all of it.
