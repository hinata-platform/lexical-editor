# Changelog

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
