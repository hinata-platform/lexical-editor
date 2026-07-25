![lexical_table](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_table.png)

# lexical_table

Table, row and cell nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_table: ^0.1.0
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

## Not yet

Grid selection — Lexical's third selection kind, shaped like a rectangle of
cells rather than a range — arrives with the editable milestone.

Wire-compatible with `@lexical/table` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
