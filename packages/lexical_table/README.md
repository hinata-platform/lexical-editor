![lexical_table](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_table.png)

# lexical_table

Table, row and cell nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_table: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: tableNodes);

editor.update(() {
  $getRoot().append($createTableNodeWithDimensions(3, 4, includeHeaders: true));
}, discrete: true);
```

## Header state is a bitmask, not a bool

A corner cell heads both its row and its column, which a bool cannot express:

```dart
TableCellHeaderState.none   // 0
TableCellHeaderState.row    // 1
TableCellHeaderState.column // 2
TableCellHeaderState.both   // 3
```

## Optional fields differ per field

`tablerow.height` and `table.colWidths` are **omitted** when unset;
`tablecell.backgroundColor` is written as an explicit **null**. There is no
general rule to infer — it follows from whether upstream's `exportJSON` guards
the property, and each field has to be matched against a fixture individually.

Tables and cells are shadow roots: traversal upwards stops at them, so a
paragraph in a cell is a top-level block *of that cell*.

## Markdown

`tableTransformer` reads and writes GitHub-flavoured tables. Like upstream's
it is **not** part of `defaultMarkdownTransformers` — add it to the list you
pass in:

```dart
final transformers = defaultMarkdownTransformers.extend(
  elements: [tableTransformer],
);
```

Without it a table still exports, as its cells one per line — which reads like
a document, so nobody notices the table is gone.

A merged cell has no markdown spelling: export writes its content in its own
slot and leaves the slots it covers empty, so the table stays rectangular and
parses back as ordinary cells.

## Selecting a rectangle of cells

`$tableSelectionOf()` reads the active selection as a rectangle, from either
shape one arrives in: a `NodeSelection` of cells, or a `RangeSelection` whose
ends sit in different cells — which is what dragging across a table produces.
The rectangle grows over any merged cell it clips, because half a cell is not
something a merge or a delete can act on.

Lexical's third selection kind has no counterpart here on purpose:
`BaseSelection` is sealed, so the core's switches stay exhaustive and no
package can introduce a selection shape the core has never heard of.

`lexical_editor_flutter` tints the covered cells, so the rectangle a merge
will act on is the rectangle you can see.

Wire-compatible with `@lexical/table` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
