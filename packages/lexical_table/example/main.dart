// Run it with:  dart run example/main.dart
//
// Tables, and the reason they are harder than they look: a cell's position is
// not its index within its row. One merged cell above it pushes it right, so
// "the column left of this one" is a question only the resolved grid can
// answer — which is what TableGrid is for.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_table/lexical_table.dart';

/// Prints the grid as slots, so a merged cell shows up once per slot.
void show(LexicalEditor editor, String label) {
  final rows = editor.read(() {
    final grid = $computeTableGrid($getRoot().getFirstChild()! as TableNode);
    return [
      for (var row = 0; row < grid.rowCount; row++)
        [
          for (var column = 0; column < grid.columnCount; column++)
            (grid.at(row, column)?.cell.getTextContent().replaceAll('\n', '') ??
                    '·')
                .padRight(6)
                .substring(0, 6),
        ].join(' │ '),
    ];
  });
  print('\n$label');
  for (final row in rows) {
    print('  $row');
  }
}

void main() {
  final editor = LexicalEditor(nodes: tableNodes);
  registerTable(editor);

  // A 3×3 table whose cells say where they are.
  editor.update(() {
    final table = $createTableNodeWithDimensions(3, 3, includeHeaders: true);
    var index = 0;
    for (final row in table.children.cast<TableRowNode>()) {
      for (final cell in row.children.cast<TableCellNode>()) {
        (cell.getFirstChild()! as ElementNode).append(
          $createTextNode(String.fromCharCode(97 + index++)),
        );
      }
    }
    $getRoot()
      ..clear()
      ..append(table)
      ..append($createParagraphNode());
  }, discrete: true);
  show(editor, 'a 3×3 table');

  // Merging moves content rather than dropping it.
  editor.update(() {
    final grid = $computeTableGrid($getRoot().getFirstChild()! as TableNode);
    $mergeTableCells(grid, TableCellRange(1, 1, 2, 2));
  }, discrete: true);
  show(editor, 'after merging the bottom-right 2×2 — one cell, four slots');

  // A column inserted through the merged cell stretches it once, rather than
  // splitting it behind the user's back.
  editor.update(() {
    final grid = $computeTableGrid($getRoot().getFirstChild()! as TableNode);
    $insertTableColumns(grid, atColumn: 1, after: true);
  }, discrete: true);
  show(editor, 'after inserting a column through the merged cell');

  // Selecting a rectangle of cells, and emptying it. Note the shape survives:
  // removing the cells instead would leave a ragged table.
  editor.update(() {
    final grid = $computeTableGrid($getRoot().getFirstChild()! as TableNode);
    $selectTableCells(grid.at(0, 0)!.cell, grid.at(0, 2)!.cell);
  }, discrete: true);
  print('\nselected cells: ${editor.read(() => $tableSelectionOf()!.range)}');

  editor.dispatchCommand(deleteCharacterCommand, true);
  show(editor, 'after Delete over the selected cells');

  // Tab walks the cells in reading order and declines at the end, so the
  // host's own Tab handling still gets its turn.
  editor.update(() {
    final grid = $computeTableGrid($getRoot().getFirstChild()! as TableNode);
    $selectTableCellStart(grid.at(0, 0)!.cell);
  }, discrete: true);
  var moves = 0;
  while (editor.dispatchCommand(moveTableCellCommand, false)) {
    moves++;
  }
  // A merged cell is one stop, not four, which is why this is fewer than the
  // number of slots above.
  print('\nTab visited ${moves + 1} cells, then declined at the last one.');
}
