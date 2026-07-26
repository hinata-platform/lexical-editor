# Changelog

## Unreleased

- `$parseMarkdownInline`, for a rule whose text is not the last captured
  group — a table row, where every cell is its own inline run.
- `ElementTransformer.exportsSubtree`, for a block that renders its own
  children. Without it a table's cells are appended a second time under the
  table.

## 1.0.0

First stable release; semantic versioning applies from here.
Markdown import, export and shortcut transforms.

The entries below record how it got here.

## 0.1.0-dev.1

First development release.

### Added

- `$convertFromMarkdown` and `$convertToMarkdown`, driven by a
  `MarkdownTransformers` set that describes each construct in both directions.
- `defaultMarkdownTransformers`: headings, quotes, fenced code, bullet,
  ordered and check lists with nesting, links, and the four inline formats.
- Delimiter matching that gets `***both***` right, by requiring a closing
  delimiter to sit at the end of its run rather than taking the first one it
  finds.
