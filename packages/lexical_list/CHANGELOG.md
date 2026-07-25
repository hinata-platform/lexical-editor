# Changelog

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.

### Added

- `registerList`: Enter on an empty item leaves the list — without it there is
  no way out except the mouse — and Tab / Shift-Tab nest and un-nest.
- `ListItemNode.insertNewAfter`, continuing the list; a new check-list item
  starts unticked rather than inheriting the state above it.
