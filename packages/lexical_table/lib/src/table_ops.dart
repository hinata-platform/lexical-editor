/// Structural editing of a table.
///
/// Every operation here takes a `TableGrid` rather than a `TableNode`,
/// because every one of them is a statement about slots — "the column left of
/// this one", "the rectangle these two cells span" — and the child list alone
/// cannot answer that once a single cell is merged.
///
/// A grid is a snapshot. Each function invalidates the one it was given;
/// recompute with `$computeTableGrid` before the next operation.
library;

import 'package:lexical_core/lexical_core.dart';

import 'table_grid.dart';
import 'table_nodes.dart';

/// Inserts [count] rows above or below the row holding [atRow].
///
/// A cell whose `rowSpan` crosses the insertion line grows instead of being
/// duplicated: splitting it would silently un-merge a cell the user merged.
///
/// Must be called inside an update.
void $insertTableRows(
  TableGrid grid, {
  required int atRow,
  required bool below,
  int count = 1,
}) {
  if (count < 1 || grid.rowCount == 0) return;
  final reference = atRow.clamp(0, grid.rowCount - 1);
  final boundary = below ? reference + 1 : reference;

  final fresh = <TableRowNode>[];
  for (var i = 0; i < count; i++) {
    final row = $createTableRowNode();
    var column = 0;
    while (column < grid.columnCount) {
      final above = grid.at(reference, column);
      if (above == null) {
        row.append($createTableCellNode()..append($createParagraphNode()));
        column++;
        continue;
      }
      // A cell that straddles the line is stretched further down instead.
      if (above.row < boundary && above.lastRow >= boundary) {
        column += above.colSpan;
        continue;
      }
      // Otherwise mirror the reference row's shape, so a table with merged
      // columns keeps its columns aligned. The column-header role carries
      // over; the row-header role does not, or every row would be a header.
      row.append(
        $createTableCellNode(
          headerState: above.cell.headerState & TableCellHeaderState.column,
          colSpan: above.colSpan,
        )..append($createParagraphNode()),
      );
      column += above.colSpan;
    }
    fresh.add(row);
  }

  for (final ref in grid.cells) {
    if (ref.row < boundary && ref.lastRow >= boundary) {
      ref.cell.setRowSpan(ref.rowSpan + count);
    }
  }

  if (boundary >= grid.rows.length) {
    for (final row in fresh) {
      grid.table.append(row);
    }
    return;
  }
  final anchor = grid.rows[boundary];
  for (final row in fresh) {
    anchor.insertBefore(row);
  }
}

/// Inserts [count] columns left or right of the column holding [atColumn].
///
/// Must be called inside an update.
void $insertTableColumns(
  TableGrid grid, {
  required int atColumn,
  required bool after,
  int count = 1,
}) {
  if (count < 1 || grid.columnCount == 0) return;
  final reference = atColumn.clamp(0, grid.columnCount - 1);
  final boundary = after ? reference + 1 : reference;

  final grown = <NodeKey>{};
  for (var row = 0; row < grid.rowCount; row++) {
    final left = boundary > 0 ? grid.at(row, boundary - 1) : null;
    if (left != null && left.column < boundary && left.lastColumn >= boundary) {
      // Straddles the line: stretch it once, however many rows it covers.
      if (grown.add(left.cell.key)) {
        left.cell.setColSpan(left.colSpan + count);
      }
      continue;
    }

    final neighbour = grid.at(row, reference);
    final headerState =
        (neighbour?.cell.headerState ?? 0) & TableCellHeaderState.row;
    final fresh = List.generate(
      count,
      (_) =>
          $createTableCellNode(headerState: headerState)
            ..append($createParagraphNode()),
    );

    final rowNode = grid.rows[row];
    final index = grid.childIndexForColumn(row, boundary);
    final children = rowNode.children.toList();
    if (index >= children.length) {
      rowNode.appendAll(fresh);
    } else {
      for (final cell in fresh) {
        children[index].insertBefore(cell);
      }
    }
  }
}

/// Removes [count] rows starting at [startRow].
///
/// Returns `false` when the request would empty the table, in which case
/// nothing changes — removing the last row is [$deleteTable]'s job, and
/// making it implicit here turns a mis-aimed keystroke into a lost table.
///
/// Must be called inside an update.
bool $deleteTableRows(TableGrid grid, int startRow, [int count = 1]) {
  if (count < 1 || grid.rowCount == 0) return false;
  final start = startRow.clamp(0, grid.rowCount - 1);
  final end = (start + count - 1).clamp(start, grid.rowCount - 1);
  if (end - start + 1 >= grid.rowCount) return false;

  // Collected before anything is detached: the grid describes the tree as it
  // is now, and every index in it stops being true after the first removal.
  final survivors = <TableCellRef>[];
  for (final ref in grid.cells) {
    final overlapStart = ref.row < start ? start : ref.row;
    final overlapEnd = ref.lastRow > end ? end : ref.lastRow;
    if (overlapEnd < overlapStart) continue;
    final overlap = overlapEnd - overlapStart + 1;

    if (ref.row < start) {
      ref.cell.setRowSpan(ref.rowSpan - overlap);
      continue;
    }
    // Anchored inside the band but reaching past it: it survives, re-anchored
    // to the first row that is left.
    if (ref.lastRow > end) {
      ref.cell.setRowSpan(ref.rowSpan - overlap);
      survivors.add(ref);
    }
  }

  final target = grid.rows[end + 1];
  if (survivors.isNotEmpty) {
    // Rebuilt in one splice rather than inserted one at a time: every
    // position in the snapshot shifts the moment a cell moves.
    final ordered = <TableCellRef>[...grid.cellsInRow(end + 1), ...survivors]
      ..sort((a, b) => a.column.compareTo(b.column));
    target.splice(
      0,
      target.childrenSize,
      ordered.map((ref) => ref.cell).toList(),
    );
  }

  for (var row = start; row <= end; row++) {
    grid.rows[row].remove(preserveEmptyParent: true);
  }
  return true;
}

/// Removes [count] columns starting at [startColumn].
///
/// Returns `false` when the request would empty the table; see
/// [$deleteTableRows].
///
/// Must be called inside an update.
bool $deleteTableColumns(TableGrid grid, int startColumn, [int count = 1]) {
  if (count < 1 || grid.columnCount == 0) return false;
  final start = startColumn.clamp(0, grid.columnCount - 1);
  final end = (start + count - 1).clamp(start, grid.columnCount - 1);
  if (end - start + 1 >= grid.columnCount) return false;

  for (final ref in grid.cells) {
    final overlapStart = ref.column < start ? start : ref.column;
    final overlapEnd = ref.lastColumn > end ? end : ref.lastColumn;
    if (overlapEnd < overlapStart) continue;
    final overlap = overlapEnd - overlapStart + 1;

    if (overlap >= ref.colSpan) {
      ref.cell.remove(preserveEmptyParent: true);
      continue;
    }
    ref.cell.setColSpan(ref.colSpan - overlap);
  }
  return true;
}

/// Removes the whole table.
///
/// Must be called inside an update.
void $deleteTable(TableNode table) {
  final parent = table.getParent();
  table.remove();
  if (parent is RootNode && parent.isEmpty) {
    parent.append($createParagraphNode());
  }
}

/// Merges every cell in [range] into its top-left cell.
///
/// Returns the surviving cell, or `null` when there was nothing to merge.
/// Content is **moved, never discarded**: a merge that quietly threw away the
/// text in three of four cells is indistinguishable from data loss.
///
/// Must be called inside an update.
TableCellNode? $mergeTableCells(TableGrid grid, TableCellRange range) {
  final expanded = grid.expand(range);
  final refs = grid.refsIn(expanded);
  if (refs.length < 2) return null;

  final anchorRef = grid.at(expanded.startRow, expanded.startColumn);
  if (anchorRef == null) return null;
  final anchor = anchorRef.cell;

  for (final ref in refs) {
    if (ref.cell.key == anchor.key) continue;
    for (final child in ref.cell.children.toList()) {
      if (child is ElementNode && child.getTextContent().isEmpty) continue;
      anchor.append(child);
    }
    ref.cell.remove(preserveEmptyParent: true);
  }

  anchor
    ..setRowSpan(expanded.rowCount)
    ..setColSpan(expanded.columnCount);
  if (anchor.isEmpty) anchor.append($createParagraphNode());
  return anchor;
}

/// Splits [cell] back into one cell per slot it covered.
///
/// Must be called inside an update.
void $unmergeTableCell(TableGrid grid, TableCellNode cell) {
  final ref = grid.refFor(cell);
  if (ref == null || (ref.rowSpan == 1 && ref.colSpan == 1)) return;

  cell
    ..setRowSpan(1)
    ..setColSpan(1);

  for (var row = ref.row; row <= ref.lastRow; row++) {
    final fresh = <TableCellNode>[];
    final firstColumn = row == ref.row ? ref.column + 1 : ref.column;
    for (var column = firstColumn; column <= ref.lastColumn; column++) {
      // A freed slot inherits only the header role that still applies: a
      // column header stays one, and a row header does not repeat down the
      // rows it used to cover.
      var headerState = TableCellHeaderState.none;
      if (row == ref.row) {
        headerState |= cell.headerState & TableCellHeaderState.row;
      }
      if (column == ref.column) {
        headerState |= cell.headerState & TableCellHeaderState.column;
      }
      fresh.add(
        $createTableCellNode(headerState: headerState)
          ..append($createParagraphNode()),
      );
    }
    if (fresh.isEmpty) continue;

    final rowNode = grid.rows[row];
    final index = grid.childIndexForColumn(row, firstColumn);
    final children = rowNode.children.toList();
    if (index >= children.length) {
      rowNode.appendAll(fresh);
    } else {
      for (final entry in fresh) {
        children[index].insertBefore(entry);
      }
    }
  }
}

/// Turns the header role of every cell anchored in [row] on or off.
///
/// The whole band is switched to whatever the majority is *not*, so a
/// repeated invocation is a toggle rather than a shuffle.
///
/// Must be called inside an update.
void $toggleTableRowHeader(TableGrid grid, int row) =>
    _toggleHeader(grid.cellsInRow(row), TableCellHeaderState.row);

/// Turns the header role of every cell in [column] on or off.
///
/// Must be called inside an update.
void $toggleTableColumnHeader(TableGrid grid, int column) {
  final seen = <NodeKey>{};
  final cells = <TableCellRef>[];
  for (var row = 0; row < grid.rowCount; row++) {
    final ref = grid.at(row, column);
    if (ref == null || !seen.add(ref.cell.key)) continue;
    cells.add(ref);
  }
  _toggleHeader(cells, TableCellHeaderState.column);
}

void _toggleHeader(List<TableCellRef> refs, int bit) {
  if (refs.isEmpty) return;
  final allSet = refs.every((ref) => (ref.cell.headerState & bit) == bit);
  for (final ref in refs) {
    final state = ref.cell.headerState;
    ref.cell.setHeaderState(allSet ? state & ~bit : state | bit);
  }
}

/// Sets the raw background colour of [cells], or clears it with `null`.
///
/// Must be called inside an update.
void $setTableCellBackground(Iterable<TableCellNode> cells, String? color) {
  for (final cell in cells) {
    cell.setBackgroundColor(color);
  }
}

/// Empties every cell in [range], leaving the table's shape alone.
///
/// This is what Delete over a block of selected cells means. Removing the
/// cells instead would leave a ragged table nobody asked for.
///
/// Must be called inside an update.
void $clearTableCells(TableGrid grid, TableCellRange range) {
  for (final ref in grid.refsIn(range)) {
    ref.cell
      ..clear()
      ..append($createParagraphNode());
  }
}

/// The cell after [from] in reading order, or `null` at the table's end.
///
/// Must be called inside a read or an update.
TableCellNode? $nextTableCell(
  TableGrid grid,
  TableCellNode from, {
  bool backwards = false,
}) {
  final order = grid.cells;
  final index = order.indexWhere((entry) => entry.cell.key == from.key);
  if (index < 0) return null;
  final next = backwards ? index - 1 : index + 1;
  if (next < 0 || next >= order.length) return null;
  return order[next].cell;
}
