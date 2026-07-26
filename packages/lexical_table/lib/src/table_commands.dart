/// The commands a table needs beyond its node shape.
library;

import 'package:lexical_core/lexical_core.dart';

import 'table_grid.dart';
import 'table_nodes.dart';
import 'table_ops.dart';
import 'table_selection.dart';

/// The shape a new table is created with.
final class TableShape {
  /// Describes a [rows] × [columns] table.
  const TableShape({
    required this.rows,
    required this.columns,
    this.includeHeaders = true,
  });

  /// How many rows to create.
  final int rows;

  /// How many columns to create.
  final int columns;

  /// Whether the first row and first column head their bands.
  final bool includeHeaders;
}

/// Inserts a table at the caret.
const LexicalCommand<TableShape> insertTableCommand = LexicalCommand(
  'INSERT_TABLE',
);

/// Inserts a row; the payload is `true` for below the current row.
const LexicalCommand<bool> insertTableRowCommand = LexicalCommand(
  'INSERT_TABLE_ROW',
);

/// Inserts a column; the payload is `true` for right of the current column.
const LexicalCommand<bool> insertTableColumnCommand = LexicalCommand(
  'INSERT_TABLE_COLUMN',
);

/// Removes the rows the selection touches.
const LexicalCommand<void> deleteTableRowCommand = LexicalCommand(
  'DELETE_TABLE_ROW',
);

/// Removes the columns the selection touches.
const LexicalCommand<void> deleteTableColumnCommand = LexicalCommand(
  'DELETE_TABLE_COLUMN',
);

/// Removes the whole table.
const LexicalCommand<void> deleteTableCommand = LexicalCommand('DELETE_TABLE');

/// Merges the selected cells into one.
const LexicalCommand<void> mergeTableCellsCommand = LexicalCommand(
  'MERGE_TABLE_CELLS',
);

/// Splits the merged cell at the caret.
const LexicalCommand<void> unmergeTableCellCommand = LexicalCommand(
  'UNMERGE_TABLE_CELL',
);

/// Toggles the header role of the rows the selection touches.
const LexicalCommand<void> toggleTableRowHeaderCommand = LexicalCommand(
  'TOGGLE_TABLE_ROW_HEADER',
);

/// Toggles the header role of the columns the selection touches.
const LexicalCommand<void> toggleTableColumnHeaderCommand = LexicalCommand(
  'TOGGLE_TABLE_COLUMN_HEADER',
);

/// Sets the background of the selected cells, or clears it with `null`.
const LexicalCommand<String?> setTableCellBackgroundCommand = LexicalCommand(
  'SET_TABLE_CELL_BACKGROUND',
);

/// Moves the caret one cell; the payload is `true` to move backwards.
const LexicalCommand<bool> moveTableCellCommand = LexicalCommand(
  'MOVE_TABLE_CELL',
);

/// Wires table editing onto [editor].
///
/// Three groups, and the priorities differ on purpose:
///
/// * The table commands above run at [CommandPriority.editor] — this
///   package's own defaults, overridable by anything.
/// * **Tab moves between cells.** It arrives as indent/outdent, the same
///   commands `registerList` claims, so the interception sits at
///   [CommandPriority.beforeEditor] and falls through the moment the caret is
///   outside a table.
/// * **Delete over selected cells empties them** instead of removing them.
///   Without this, one keystroke over a selected block of cells leaves a
///   ragged table, which is not a shape the user can get back to by hand.
Unsubscribe registerTable(LexicalEditor editor) {
  final unsubscribes = <Unsubscribe>[
    editor.registerCommand<TableShape>(
      insertTableCommand,
      _insertTable,
      CommandPriority.editor,
    ),
    editor.registerCommand<bool>(
      insertTableRowCommand,
      (below) => _withGrid((grid, range) {
        $insertTableRows(
          grid,
          atRow: below ? range.endRow : range.startRow,
          below: below,
        );
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<bool>(
      insertTableColumnCommand,
      (after) => _withGrid((grid, range) {
        $insertTableColumns(
          grid,
          atColumn: after ? range.endColumn : range.startColumn,
          after: after,
        );
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      deleteTableRowCommand,
      (_) => _withGrid(
        (grid, range) => $deleteTableRows(grid, range.startRow, range.rowCount),
      ),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      deleteTableColumnCommand,
      (_) => _withGrid(
        (grid, range) =>
            $deleteTableColumns(grid, range.startColumn, range.columnCount),
      ),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      deleteTableCommand,
      (_) => _withGrid((grid, range) {
        $deleteTable(grid.table);
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      mergeTableCellsCommand,
      (_) => _withGrid((grid, range) {
        final merged = $mergeTableCells(grid, range);
        if (merged == null) return false;
        $selectTableCellStart(merged);
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      unmergeTableCellCommand,
      (_) => _withCell((grid, ref) {
        if (ref.rowSpan == 1 && ref.colSpan == 1) return false;
        $unmergeTableCell(grid, ref.cell);
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      toggleTableRowHeaderCommand,
      (_) => _withGrid((grid, range) {
        for (var row = range.startRow; row <= range.endRow; row++) {
          $toggleTableRowHeader(grid, row);
        }
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      toggleTableColumnHeaderCommand,
      (_) => _withGrid((grid, range) {
        for (var col = range.startColumn; col <= range.endColumn; col++) {
          $toggleTableColumnHeader(grid, col);
        }
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<String?>(
      setTableCellBackgroundCommand,
      (color) => _withGrid((grid, range) {
        $setTableCellBackground(
          grid.refsIn(range).map((ref) => ref.cell),
          color,
        );
        return true;
      }),
      CommandPriority.editor,
    ),
    editor.registerCommand<bool>(
      moveTableCellCommand,
      _moveCell,
      CommandPriority.editor,
    ),
    editor.registerCommand<void>(
      indentContentCommand,
      (_) => _moveCell(false),
      CommandPriority.beforeEditor,
    ),
    editor.registerCommand<void>(
      outdentContentCommand,
      (_) => _moveCell(true),
      CommandPriority.beforeEditor,
    ),
    for (final command in const [
      deleteCharacterCommand,
      deleteWordCommand,
      deleteLineCommand,
    ])
      editor.registerCommand<bool>(
        command,
        (_) => _clearSelectedCells(),
        CommandPriority.beforeEditor,
      ),
    editor.registerCommand<void>(
      removeTextCommand,
      (_) => _clearSelectedCells(),
      CommandPriority.beforeEditor,
    ),
  ];

  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

/// Creates a table of [shape] and puts the caret in its first cell.
///
/// A paragraph is left after the table when it would otherwise end the
/// document: a table as the last block is a document with no way to type past
/// it, and the caret cannot be placed after something that has no after.
bool _insertTable(TableShape shape) {
  final selection = $getSelection();
  final table = $createTableNodeWithDimensions(
    shape.rows,
    shape.columns,
    includeHeaders: shape.includeHeaders,
  );

  // No caret is not a reason to do nothing. A toolbar button is pressed
  // while the editor has not been focused yet more often than not, and a
  // command that silently declines looks exactly like a broken button.
  final block = selection is RangeSelection
      ? $getNearestBlock(selection.focus.getNode() ?? $getRoot())
      : $getRoot();
  if (block is RootNode) {
    $getRoot().append(table);
  } else if (block.getTextContent().isEmpty && block.getParent() is RootNode) {
    block.replace(table);
  } else {
    block.insertAfter(table);
  }

  if (table.getNextSibling() == null && table.getParent() is RootNode) {
    table.insertAfter($createParagraphNode());
  }
  final firstCell = (table.getFirstChild() as TableRowNode?)?.getFirstChild();
  if (firstCell is TableCellNode) $selectTableCellStart(firstCell);
  return true;
}

bool _moveCell(bool backwards) {
  final located = _locate();
  if (located == null) return false;
  final (grid, ref) = located;
  final next = $nextTableCell(grid, ref.cell, backwards: backwards);
  if (next == null) return false;
  $selectTableCellStart(next);
  return true;
}

bool _clearSelectedCells() {
  final selection = $tableSelectionOf();
  if (selection == null || selection.isSingleCell) return false;
  $clearTableCells(selection.grid, selection.range);
  $selectTableCellStart(selection.cells.first);
  return true;
}

/// Runs [action] over the rectangle the selection covers.
bool _withGrid(bool Function(TableGrid grid, TableCellRange range) action) {
  final table = $tableSelectionOf();
  if (table != null) return action(table.grid, table.range);
  final located = _locate();
  if (located == null) return false;
  final (grid, ref) = located;
  return action(
    grid,
    TableCellRange(ref.row, ref.column, ref.lastRow, ref.lastColumn),
  );
}

/// Runs [action] over the single cell the caret is in.
bool _withCell(bool Function(TableGrid grid, TableCellRef ref) action) {
  final located = _locate();
  if (located == null) return false;
  final (grid, ref) = located;
  return action(grid, ref);
}

(TableGrid, TableCellRef)? _locate() {
  final selection = $getSelection();
  LexicalNode? node;
  if (selection is RangeSelection) {
    node = selection.focus.getNode();
  } else if (selection is NodeSelection) {
    final keys = selection.keys;
    node = keys.isEmpty ? null : $getNodeByKey(keys.first);
  }
  final cell = $getTableCellForNode(node);
  if (cell == null) return null;
  final table = $getTableForNode(cell);
  if (table == null) return null;
  final grid = $computeTableGrid(table);
  final ref = grid.refFor(cell);
  if (ref == null) return null;
  return (grid, ref);
}
