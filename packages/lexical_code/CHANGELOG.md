# Changelog

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

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

- Syntax highlighting, in the package rather than left to the application:
  `tokenizeCode` classifies source for fifteen languages, and
  `registerCodeHighlighting` keeps a block's runs in step with its text as it
  is typed, pasted and undone. No dependencies — a table of rules per
  language, extensible with `CodeLanguage.register`.
- The runs it produces are upstream's shape: a flat list of highlight runs,
  line breaks and tabs, classified with Prism's token names, so a block
  highlighted here is coloured by Lexical web's stylesheet and one highlighted
  there is coloured by a Flutter theme.
- A code block whose language is unknown is left untouched rather than
  flattened, so a document classified by another client survives opening here.
- A highlight run that leaves a code block — when the block is turned into a
  paragraph — becomes ordinary text instead of keeping its code colours.

## 1.0.0

First stable release; semantic versioning applies from here.
Code blocks with language-tagged, incrementally re-highlighted runs.

The entries below record how it got here.

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.

### Added

- `registerCode`: Enter inserts a newline into the text rather than splitting
  the block, and Tab indents. Both match the wire format — the canonical
  fixture keeps a code block's line breaks inside one text node.
