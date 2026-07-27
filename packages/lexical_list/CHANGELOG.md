# Changelog

## 1.2.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

## 1.0.0

First stable release; semantic versioning applies from here.
Bullet, numbered and check lists, with Enter-to-leave and Tab-to-nest.

The entries below record how it got here.

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.

### Added

- `registerList`: Enter on an empty item leaves the list — without it there is
  no way out except the mouse — and Tab / Shift-Tab nest and un-nest.
- `ListItemNode.insertNewAfter`, continuing the list; a new check-list item
  starts unticked rather than inheriting the state above it.
