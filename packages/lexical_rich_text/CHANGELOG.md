# Changelog

## 1.7.4

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.3

**Backspace at the start of a leading quote un-quotes it, and an empty leading
heading becomes a paragraph.** With nothing before them there was no character
to delete and the key did nothing, so a quote at the top of a document could
not be undone with the keyboard. Both are upstream's rules, through the new
`ElementNode.collapseAtStart`; a heading with words in it keeps them.

**A divider can be removed again.** See `lexical_core` — backspace under a
block decorator, or forward delete above one, now removes it instead of doing
nothing.

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

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.5.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.4.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_flutter` for what changed.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

- `HorizontalRuleNode`, with `$createHorizontalRuleNode` and
  `$isHorizontalRuleNode`, registered by `richTextNodes`. A standard Lexical
  node the port was missing: the registry is closed on purpose, so a stored
  document containing a `---` could not be opened at all until an application
  declared the type itself. The wire shape is upstream's exactly —
  `{"type": "horizontalrule", "version": 1}`. A decorator, so what it draws is
  the renderer's business; `lexical_editor_flutter` supplies a default.

## 1.1.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

## 1.0.0

First stable release; semantic versioning applies from here.
Headings, quotes and the rich-text command defaults.

The entries below record how it got here.

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.

### Added

- `HeadingNode.insertNewAfter`: Enter at the end of a heading starts body
  text, Enter inside it splits the heading. `QuoteNode.insertNewAfter` leaves
  the quote, as Lexical web does.
