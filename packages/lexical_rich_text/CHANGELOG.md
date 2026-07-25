# Changelog

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
