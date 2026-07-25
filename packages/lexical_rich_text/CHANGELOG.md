# Changelog

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.

### Added

- `HeadingNode.insertNewAfter`: Enter at the end of a heading starts body
  text, Enter inside it splits the heading. `QuoteNode.insertNewAfter` leaves
  the quote, as Lexical web does.
