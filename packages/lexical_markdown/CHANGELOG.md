# Changelog

## 1.2.0

**Fixed: a nested list was built in the wrong shape.** The nested list was
appended to the item holding its parent's text, and every item stayed at
`indent: 0`. Lexical puts a nested list in an item of its own, next to the one
it sits under, and carries the nesting depth on the items. Both shapes hold the
same words, which is why this survived reading the output — but anything that
walks structure rather than text, including a Lexical web client opening the
same document, saw a different tree. Import now produces the canonical shape,
and numbering counts the holder items the way Lexical does.

**Fixed: a link label was taken as characters rather than as markdown.**
`[ein *kursiver* Link](url)` kept its asterisks, where CommonMark — and every
parser a document travels to — reads emphasis inside a label. The label is now
parsed with the same inline rules, and emphasis around the link is kept rather
than traded for the emphasis inside it.

- `horizontalRuleTransformer`, in `defaultMarkdownTransformers`: `---`, `***`
  and `___` on a line of their own become a `HorizontalRuleNode` (new in
  `lexical_rich_text` 1.2.0). All three spellings, because the inline rules
  claim the other two otherwise — by the time a `***` line reaches a block rule
  it has already become an empty emphasis run and a stray asterisk.
- `TextMatchTransformer.parsesInlineContent`, off by default: says that the
  text a rule puts inside its node is itself markdown. A link opts in; a rule
  whose content is deliberately literal does not, and keeps its characters.

## 1.1.0

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
