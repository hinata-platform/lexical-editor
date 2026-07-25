# Changelog

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
