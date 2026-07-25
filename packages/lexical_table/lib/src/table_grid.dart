/// The rectangular view of a table that its node shape does not provide.
library;

import 'package:lexical_core/lexical_core.dart';

import 'table_nodes.dart';

/// One cell, together with where it actually sits.
///
/// A cell's position is **not** its index within its row: a `rowSpan` above
/// it pushes it right, and its own `colSpan` makes it cover several columns.
/// Every structural operation is a statement about the grid rather than about
/// the child list, so it needs this resolution first.
final class TableCellRef {
  /// Records that [cell] occupies [rowSpan] × [colSpan] slots at [row],
  /// [column].
  const TableCellRef({
    required this.cell,
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.colSpan,
  });

  /// The cell node.
  final TableCellNode cell;

  /// The row of its top-left slot.
  final int row;

  /// The column of its top-left slot.
  final int column;

  /// How many rows it covers, clamped to the rows that exist.
  final int rowSpan;

  /// How many columns it covers.
  final int colSpan;

  /// The last row it covers.
  int get lastRow => row + rowSpan - 1;

  /// The last column it covers.
  int get lastColumn => column + colSpan - 1;

  /// Whether this cell covers [row], [column].
  bool covers(int row, int column) =>
      row >= this.row &&
      row <= lastRow &&
      column >= this.column &&
      column <= lastColumn;

  @override
  String toString() =>
      'TableCellRef(${cell.key} at $row,$column ${rowSpan}x$colSpan)';
}

/// A rectangle of grid slots.
///
/// Normalized on construction, so a range dragged upwards or leftwards is the
/// same value as the one dragged the other way.
final class TableCellRange {
  /// Creates the rectangle spanned by the two corners.
  factory TableCellRange(int rowA, int columnA, int rowB, int columnB) =>
      TableCellRange._(
        rowA < rowB ? rowA : rowB,
        columnA < columnB ? columnA : columnB,
        rowA > rowB ? rowA : rowB,
        columnA > columnB ? columnA : columnB,
      );

  const TableCellRange._(
    this.startRow,
    this.startColumn,
    this.endRow,
    this.endColumn,
  );

  /// Topmost row, inclusive.
  final int startRow;

  /// Leftmost column, inclusive.
  final int startColumn;

  /// Bottommost row, inclusive.
  final int endRow;

  /// Rightmost column, inclusive.
  final int endColumn;

  /// How many rows the rectangle covers.
  int get rowCount => endRow - startRow + 1;

  /// How many columns the rectangle covers.
  int get columnCount => endColumn - startColumn + 1;

  /// Whether the rectangle is a single slot.
  bool get isSingleSlot => rowCount == 1 && columnCount == 1;

  /// Whether [row], [column] is inside the rectangle.
  bool contains(int row, int column) =>
      row >= startRow &&
      row <= endRow &&
      column >= startColumn &&
      column <= endColumn;

  @override
  bool operator ==(Object other) =>
      other is TableCellRange &&
      other.startRow == startRow &&
      other.startColumn == startColumn &&
      other.endRow == endRow &&
      other.endColumn == endColumn;

  @override
  int get hashCode => Object.hash(startRow, startColumn, endRow, endColumn);

  @override
  String toString() =>
      'TableCellRange($startRow,$startColumn..$endRow,$endColumn)';
}

/// A table resolved into slots.
///
/// Build one with [$computeTableGrid] inside a read or an update. It is a
/// **snapshot**: every structural operation invalidates it, so recompute
/// rather than keeping one across edits.
final class TableGrid {
  const TableGrid._(this.table, this.rows, this._slots, this._refs);

  /// The table this grid describes.
  final TableNode table;

  /// The row nodes, in order.
  final List<TableRowNode> rows;

  final List<List<TableCellRef?>> _slots;
  final List<TableCellRef> _refs;

  /// How many rows the table has.
  int get rowCount => _slots.length;

  /// How many columns the widest row reaches.
  int get columnCount => _slots.isEmpty ? 0 : _slots.first.length;

  /// Every cell once, in document order.
  List<TableCellRef> get cells => List.unmodifiable(_refs);

  /// The cell covering [row], [column], or `null` outside the grid.
  TableCellRef? at(int row, int column) {
    if (row < 0 || row >= _slots.length) return null;
    final slots = _slots[row];
    if (column < 0 || column >= slots.length) return null;
    return slots[column];
  }

  /// The reference for [cell], or `null` when it is not in this table.
  TableCellRef? refFor(TableCellNode cell) {
    for (final ref in _refs) {
      if (ref.cell.key == cell.key) return ref;
    }
    return null;
  }

  /// The cells anchored in [row], left to right.
  List<TableCellRef> cellsInRow(int row) =>
      _refs.where((ref) => ref.row == row).toList();

  /// Grows [range] until it holds every cell it partially covers.
  ///
  /// A rectangle that clips a merged cell is not a rectangle the user can act
  /// on — half a cell cannot be deleted — so dragging into one selects all of
  /// it, which then may pull in further cells. Repeated to a fixed point,
  /// which is what a browser does with the same problem.
  TableCellRange expand(TableCellRange range) {
    var current = range;
    while (true) {
      var startRow = current.startRow;
      var startColumn = current.startColumn;
      var endRow = current.endRow;
      var endColumn = current.endColumn;

      for (final ref in _refs) {
        final intersects =
            ref.row <= endRow &&
            ref.lastRow >= startRow &&
            ref.column <= endColumn &&
            ref.lastColumn >= startColumn;
        if (!intersects) continue;
        if (ref.row < startRow) startRow = ref.row;
        if (ref.column < startColumn) startColumn = ref.column;
        if (ref.lastRow > endRow) endRow = ref.lastRow;
        if (ref.lastColumn > endColumn) endColumn = ref.lastColumn;
      }

      final grown = TableCellRange(startRow, startColumn, endRow, endColumn);
      if (grown == current) return current;
      current = grown;
    }
  }

  /// Every cell intersecting [range], once each, in document order.
  List<TableCellRef> refsIn(TableCellRange range) => _refs
      .where(
        (ref) =>
            ref.row <= range.endRow &&
            ref.lastRow >= range.startRow &&
            ref.column <= range.endColumn &&
            ref.lastColumn >= range.startColumn,
      )
      .toList();

  /// The index a cell at [column] would take among [row]'s children.
  ///
  /// Derived from grid columns rather than from the child list, because a
  /// `rowSpan` reaching down from above occupies a column without being a
  /// child of this row at all.
  int childIndexForColumn(int row, int column) {
    var index = 0;
    for (final ref in _refs) {
      if (ref.row != row) continue;
      if (ref.column < column) index++;
    }
    return index;
  }
}

/// Resolves [table] into a grid of slots.
///
/// Must be called inside a read or an update.
TableGrid $computeTableGrid(TableNode table) {
  final rows = table.children.whereType<TableRowNode>().toList();
  final slots = List.generate(
    rows.length,
    (_) => <TableCellRef?>[],
    growable: false,
  );
  final refs = <TableCellRef>[];

  for (var row = 0; row < rows.length; row++) {
    var column = 0;
    for (final cell in rows[row].children.whereType<TableCellNode>()) {
      final rowSlots = slots[row];
      while (column < rowSlots.length && rowSlots[column] != null) {
        column++;
      }
      // A span reaching past the last row is malformed input, not a taller
      // table: clamp it, so every operation downstream can trust the grid.
      final rowSpan = cell.rowSpan < 1
          ? 1
          : (row + cell.rowSpan > rows.length
                ? rows.length - row
                : cell.rowSpan);
      final colSpan = cell.colSpan < 1 ? 1 : cell.colSpan;
      final ref = TableCellRef(
        cell: cell,
        row: row,
        column: column,
        rowSpan: rowSpan,
        colSpan: colSpan,
      );
      refs.add(ref);

      for (var dr = 0; dr < rowSpan; dr++) {
        final target = slots[row + dr];
        for (var dc = 0; dc < colSpan; dc++) {
          final at = column + dc;
          while (target.length <= at) {
            target.add(null);
          }
          target[at] = ref;
        }
      }
      column += colSpan;
    }
  }

  var columns = 0;
  for (final row in slots) {
    if (row.length > columns) columns = row.length;
  }
  for (final row in slots) {
    while (row.length < columns) {
      row.add(null);
    }
  }

  return TableGrid._(table, rows, slots, refs);
}

/// The table cell containing [node], or `null`.
///
/// Must be called inside a read or an update.
TableCellNode? $getTableCellForNode(LexicalNode? node) {
  var current = node;
  while (current != null) {
    if (current is TableCellNode) return current;
    current = current.getParent();
  }
  return null;
}

/// The table containing [node], or `null`.
///
/// Must be called inside a read or an update.
TableNode? $getTableForNode(LexicalNode? node) {
  var current = node;
  while (current != null) {
    if (current is TableNode) return current;
    current = current.getParent();
  }
  return null;
}
