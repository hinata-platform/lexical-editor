/// Drawing a table as a table.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_table/lexical_table.dart';

/// The block layout that makes a table look like one.
///
/// Without it a table is drawn the way every other block is — its children
/// stacked vertically — and a three-column table becomes a list of every cell,
/// one under the other. Adding a row then looks like adding three lines, and
/// adding a column looks like rows appearing all over the table, which is
/// exactly what it is: cells with nowhere else to go.
///
/// ```dart
/// LexicalTheme(
///   baseTextStyle: …,
///   blockLayouts: tableBlockLayouts(),
/// )
/// ```
///
/// `defaultLexicalTheme` already includes it.
///
/// The placement of every cell comes from `$computeTableGrid`, not from its
/// index in its row: a `rowSpan` above a cell pushes it right, so the child
/// list alone cannot say which column a cell is in. That resolution is the
/// whole reason `lexical_table` computes a grid at all, and the layout uses
/// the same answer the editing commands do.
Map<String, BlockLayoutBuilder> tableBlockLayouts({double spacing = 0}) => {
  'table': (context, element, buildChild) {
    if (element is! TableNode) return const SizedBox.shrink();
    final grid = $computeTableGrid(element);
    if (grid.columnCount == 0 || grid.rowCount == 0) {
      return const SizedBox.shrink();
    }
    return LexicalGrid(
      columnCount: grid.columnCount,
      spacing: spacing,
      children: [
        for (final ref in grid.cells)
          GridCell(
            // A cell that spans is listed once, at its anchor. The grid knows
            // where the continuation slots are and does not repeat it.
            key: ValueKey<String>('lexical-cell-${ref.cell.key.value}'),
            placement: GridPlacement(
              row: ref.row,
              column: ref.column,
              rowSpan: ref.rowSpan,
              columnSpan: ref.colSpan,
            ),
            child: buildChild(ref.cell),
          ),
      ],
    );
  },
};
