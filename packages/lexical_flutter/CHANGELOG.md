# Changelog

## 1.7.1

**An inline prefix is not drawn for an element with nothing in it.** An empty
inline element renders nothing at all, which is what makes one easy to leave
behind — and three abandoned anchors in a paragraph lined up three icons in
front of the one link that still had its text.

## 1.7.0

**`LexicalTheme.inlinePrefixes`** — a widget drawn immediately before the
contents of an inline element, keyed by node type. What a `TextStyle` cannot
do is put a mark *beside* a run: colour and an underline are the whole
vocabulary text styling has for "this goes somewhere", and in a document where
headings and mentions are also coloured, that is not much. A link can carry a
link icon now.

The mark occupies one position in the laid-out text and **nothing at all in
the document** — nothing is inserted, nothing is serialized, and a Lexical web
client sees the link it wrote. The offset map is told about it, so the caret,
the IME and the selection all keep their footing: it is registered as the
*boundary* in front of the element rather than as a run with two sides, which
is what keeps a tap on a link's own icon from landing the caret past the whole
link.

## 1.6.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.6.0

**Space no longer scrolls the page instead of typing.**
`DefaultTextEditingShortcuts` — which `WidgetsApp` installs over the whole
application — binds space, and a handful of other keys, to text intents that
only `EditableText` supplies actions for. Unhandled, the binding fell through
and the key carried on up the widget tree; what sits above an editor is a
scrollable, so finishing a word threw the page a screen down and the character
never arrived. `LexicalEditable` now supplies
`DoNothingAndStopPropagationTextIntent` the same way `EditableText` does, with
`consumesKey: false`: the intent is handled so the key stops travelling, and
the key itself is left unconsumed so the input method still delivers it.

## 1.5.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.4.0

**The caret no longer shrinks and rides up when a space is typed at the end of
a line.** `getFullHeightForCaret` reports the height of the *glyph run* at the
position, and for trailing whitespace the engine reports that run without the
style's height multiplier — 16 logical pixels where the line is 27. The visible
result was a caret that jumped the moment a space was typed, which reads as the
space having broken something rather than as a measuring artefact.
`RenderLexicalBlock.caretRect` now never returns a caret shorter than the line
it sits on.

## 1.3.0

**Dragging a selection no longer stutters.** Four things ran on every pointer
move, and none of them had to:

* The caret was scrolled into view on every move. While a pointer is dragging,
  the user is looking at where they are pointing — and this was the most
  expensive thing on the path, because it walks to the enclosing scrollable and
  repaints everything in between.
* The block's flat text and offset map were rebuilt from the model on every
  move, to hand the platform an editing value whose text had not changed.
  `$buildEditingWindow` now takes `reuseOffsets`, and `LexicalInput.syncToModel`
  passes the previous map when the commit moved only the selection.
* The caret blink timer was cancelled and re-armed on every move, for a caret
  that is not drawn at all while a range is selected.
* Resolving the selection into per-block spans walked every leaf it covered
  rather than every block (fixed in `lexical_core` 1.3.0).

`parseCssDeclarations` now defers to `lexical_core`'s
`getStyleObjectFromCss`. Splitting the string on `;` and `:` — which is what it
did — truncates `background: url(a;b)` and mangles a quoted font stack, and it
was a second answer to a question the core already answers for the value that
has to round-trip through Lexical web.

## 1.2.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

- Fixed: a press that lands inside a block's padding — a cell's, or the empty
  area below the last block — now places the caret in the nearest block
  instead of being ignored. Ignoring it was not neutral: the selection kept
  the anchor it already had, so the next drag spanned from wherever the user
  had last clicked. In a table that showed up as a merge covering rows nobody
  selected.
- `LexicalEditorScope`: the editor drawing a document, reachable from anything
  drawn inside it — a decorator, a block layout, an overlay.

## 1.0.0

First stable release; semantic versioning applies from here.
The Flutter layer: per-block render objects, span and offset map built in one
walk, IME, selection handles, token widgets and pointer interaction.

The entries below record how it got here.

## 0.1.0-dev.2

- `LexicalInteraction`: hover and tap for links, mentions and hashtags, keyed
  on node **type string** so this package still imports none of them. Reports
  the interactive ancestor rather than the text node under the pointer,
  confirms the hit against the node's own line boxes, and hands callbacks a
  snapshot — key, type, text, serialized fields and global bounds — that stays
  valid outside the read it came from.
- `LexicalTheme.tokenBuilders`: render a token text node as a widget, so a
  mention can be a rounded chip. The node stays text in the model — same JSON,
  same atomic delete — and only token-mode nodes qualify, because the widget
  occupies one position while the node holds a whole label.
- Selection handles, the platform context menu and the magnifier, built on
  Flutter's own `TextSelectionControls` and `AdaptiveTextSelectionToolbar`.
- `RemoteSelection`: other people's carets and ranges, painted in their own
  colour.
- `LexicalBuilder`, for rebuilding a widget after every commit without
  tripping over a commit that lands during a build.
- Fixed: a text node's *type* is styled again, so a theme entry for `mention`
  or `hashtag` reaches the node it names.

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

### Added — editable

- `LexicalEditable`: focus, pointer, keyboard, caret, selection painting and
  the composing underline, with caret and selection pushed straight onto
  render objects so a blink never rebuilds a widget.
- `LexicalInput`, a `DeltaTextInputClient`. The platform is given a **bounded
  window** around the caret rather than the document, with newline sentinels
  standing in for the block boundaries — without them, backspace at the start
  of a paragraph produces no delta at all and blocks can never be merged from
  a soft keyboard.
- The model stays authoritative about the caret: after a text-changing delta
  the corrected value is pushed back, which is what lets an atomic token
  delete whole when the platform thinks one character went.
- A delta computed against a value we no longer hold is refused and our value
  re-stated, rather than corrupting the document over a transient race.
- `$resolveDocumentSelection` and `flatSelectionFor`, mapping the model's
  selection onto the blocks that paint it.
- `buildModelOffsets`: the model-side offset map, deliberately distinct from
  the renderer's — handing a presentational uppercase to an input method would
  have it autocorrect text that does not exist.
- `LexicalTheme.blockStyleResolver`, for types whose presentation depends on a
  field rather than only on their type string.
