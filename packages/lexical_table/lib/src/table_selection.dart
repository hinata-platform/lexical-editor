/// Selecting a rectangle of cells.
///
/// Lexical web has a third selection kind for this, alongside range and node
/// selections. Here `BaseSelection` is **sealed**, so the core's switches over
/// it stay exhaustive and a new selection shape cannot appear from a package
/// the core has never heard of. A table selection is therefore carried as a
/// [NodeSelection] over the covered cells, and the rectangle is re-derived
/// from the grid whenever it is needed.
///
/// The consequence worth knowing: a node selection is a *set*, so it does not
/// record which corner the drag started at. That corner is transient pointer
/// state and belongs to the gesture handler, the same way a composing region
/// belongs to the input connection rather than to the document.
library;

import 'package:lexical_core/lexical_core.dart';

import 'table_grid.dart';
import 'table_nodes.dart';

/// A rectangle of selected cells, resolved against a table.
final class TableSelection {
  /// Records [range] as covering [cells] of [table].
  const TableSelection({
    required this.table,
    required this.grid,
    required this.range,
    required this.cells,
  });

  /// The table the selection is in.
  final TableNode table;

  /// The grid the rectangle was resolved against.
  final TableGrid grid;

  /// The covered rectangle, already expanded over merged cells.
  final TableCellRange range;

  /// Every covered cell, once each, in document order.
  final List<TableCellNode> cells;

  /// Whether the rectangle covers exactly one cell.
  bool get isSingleCell => cells.length == 1;

  @override
  String toString() => 'TableSelection($range, ${cells.length} cells)';
}

/// Reads the active selection as a rectangle of cells, or `null`.
///
/// Recognizes both shapes a table selection arrives in: an explicit
/// [NodeSelection] of cells, and a [RangeSelection] whose ends sit in
/// different cells of the same table — which is what a plain drag across a
/// table produces, and which must not be treated as a text range or Delete
/// would tear the table apart.
///
/// Must be called inside a read or an update.
TableSelection? $tableSelectionOf([BaseSelection? selection]) {
  final active = selection ?? $getSelection();
  switch (active) {
    case final NodeSelection nodes:
      final cells = <TableCellNode>[];
      for (final key in nodes.keys) {
        final node = $getNodeByKey(key);
        if (node is! TableCellNode) return null;
        cells.add(node);
      }
      if (cells.isEmpty) return null;
      return _resolve(cells.first, cells.last, extra: cells);
    case final RangeSelection range:
      final anchor = $getTableCellForNode(range.anchor.getNode());
      final focus = $getTableCellForNode(range.focus.getNode());
      if (anchor == null || focus == null) return null;
      if (anchor.key == focus.key) return null;
      return _resolve(anchor, focus);
    case null:
      return null;
  }
}

/// Selects every cell in the rectangle [from] and [to] span.
///
/// Returns the resolved selection, or `null` when the two cells are not in
/// the same table.
///
/// Must be called inside an update.
TableSelection? $selectTableCells(TableCellNode from, TableCellNode to) {
  final resolved = _resolve(from, to);
  if (resolved == null) return null;
  $setSelection(NodeSelection(resolved.cells.map((cell) => cell.key).toSet()));
  return resolved;
}

/// Places a collapsed caret at the start of [cell]'s content.
///
/// Must be called inside an update.
void $selectTableCellStart(TableCellNode cell) {
  final first = cell.getFirstChild();
  if (first is ElementNode) {
    first.selectStart();
    return;
  }
  cell.selectStart();
}

TableSelection? _resolve(
  TableCellNode from,
  TableCellNode to, {
  List<TableCellNode>? extra,
}) {
  final table = $getTableForNode(from);
  if (table == null || $getTableForNode(to)?.key != table.key) return null;
  final grid = $computeTableGrid(table);
  final start = grid.refFor(from);
  final end = grid.refFor(to);
  if (start == null || end == null) return null;

  var range = TableCellRange(start.row, start.column, end.row, end.column);
  // A node selection reaching two cells on one diagonal still means the whole
  // rectangle between them, and any extra cells the caller listed have to fit
  // inside it or the rectangle was not the one they meant.
  for (final cell in extra ?? const <TableCellNode>[]) {
    final ref = grid.refFor(cell);
    if (ref == null) continue;
    range = TableCellRange(
      range.startRow < ref.row ? range.startRow : ref.row,
      range.startColumn < ref.column ? range.startColumn : ref.column,
      range.endRow > ref.lastRow ? range.endRow : ref.lastRow,
      range.endColumn > ref.lastColumn ? range.endColumn : ref.lastColumn,
    );
  }
  final expanded = grid.expand(range);
  return TableSelection(
    table: table,
    grid: grid,
    range: expanded,
    cells: grid.refsIn(expanded).map((ref) => ref.cell).toList(),
  );
}
