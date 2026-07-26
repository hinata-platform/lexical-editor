/// Drawing a table as a table.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';
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
///
/// [selectedCellColor] tints the cells a selection covers. Selecting cells
/// and merging them are the same rectangle, and a user who cannot see it is
/// guessing — which is how a merge ends up covering a row nobody meant to
/// include. Pass `null` to draw no tint.
Map<String, BlockLayoutBuilder> tableBlockLayouts({
  double spacing = 0,
  Color? selectedCellColor,
}) => {
  'table': (context, element, buildChild) {
    if (element is! TableNode) return const SizedBox.shrink();
    final grid = $computeTableGrid(element);
    if (grid.columnCount == 0 || grid.rowCount == 0) {
      return const SizedBox.shrink();
    }
    final table = LexicalGrid(
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
            child: selectedCellColor == null
                ? buildChild(ref.cell)
                : _TintedCell(
                    cellKey: ref.cell.key,
                    color: selectedCellColor,
                    child: buildChild(ref.cell),
                  ),
          ),
      ],
    );
    if (selectedCellColor == null) return table;
    return _SelectedCells(tableKey: element.key, child: table);
  },
};

/// Tracks which cells of one table the selection covers.
///
/// A selection change commits nothing — no node is dirty — so the document's
/// reconciler correctly leaves the table's widgets alone. This listens for
/// itself, and publishes the answer through a notifier so that only the tint
/// rebuilds rather than the table.
class _SelectedCells extends StatefulWidget {
  const _SelectedCells({required this.tableKey, required this.child});

  final NodeKey tableKey;
  final Widget child;

  @override
  State<_SelectedCells> createState() => _SelectedCellsState();
}

class _SelectedCellsState extends State<_SelectedCells> {
  final ValueNotifier<Set<NodeKey>> _selected = ValueNotifier(const {});
  LexicalEditor? _editor;
  Unsubscribe? _unsubscribe;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final editor = LexicalEditorScope.maybeOf(context);
    if (identical(editor, _editor)) return;
    _unsubscribe?.call();
    _editor = editor;
    _unsubscribe = editor?.registerUpdateListener((_) => _refresh());
    _refresh();
  }

  void _refresh() {
    final editor = _editor;
    if (editor == null) return;
    final keys = editor.read(() {
      final selection = $tableSelectionOf();
      if (selection == null || selection.table.key != widget.tableKey) {
        return const <NodeKey>{};
      }
      return {for (final cell in selection.cells) cell.key};
    });
    if (setEquals(keys, _selected.value)) return;
    // A commit can land during a build, and a notifier that rebuilds its
    // listeners then is the same error `setState` would be.
    whenBuildIsDone(() {
      if (mounted) _selected.value = keys;
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SelectedCellsScope(selected: _selected, child: widget.child);
}

class _SelectedCellsScope
    extends InheritedNotifier<ValueNotifier<Set<NodeKey>>> {
  const _SelectedCellsScope({
    required ValueNotifier<Set<NodeKey>> selected,
    required super.child,
  }) : super(notifier: selected);

  static ValueListenable<Set<NodeKey>>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SelectedCellsScope>()
      ?.notifier;
}

/// Tints one cell while the selection covers it.
class _TintedCell extends StatelessWidget {
  const _TintedCell({
    required this.cellKey,
    required this.color,
    required this.child,
  });

  final NodeKey cellKey;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selected = _SelectedCellsScope.maybeOf(context);
    if (selected == null) return child;
    return ValueListenableBuilder<Set<NodeKey>>(
      valueListenable: selected,
      // The cell itself is passed through untouched: the tint is drawn over
      // it, so a selection change never rebuilds a line of text.
      child: child,
      builder: (context, keys, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(color: keys.contains(cellKey) ? color : null),
        child: child,
      ),
    );
  }
}
