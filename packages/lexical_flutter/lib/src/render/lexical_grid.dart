/// Laying blocks out in a grid, with spans.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where a child sits in a [LexicalGrid], and how far it reaches.
@immutable
class GridPlacement {
  /// Places a child at [row], [column], covering [rowSpan] × [columnSpan].
  const GridPlacement({
    required this.row,
    required this.column,
    this.rowSpan = 1,
    this.columnSpan = 1,
  }) : assert(row >= 0 && column >= 0, 'a position cannot be negative'),
       assert(rowSpan >= 1 && columnSpan >= 1, 'a span covers at least one');

  /// The first row the child occupies.
  final int row;

  /// The first column the child occupies.
  final int column;

  /// How many rows it covers.
  final int rowSpan;

  /// How many columns it covers.
  final int columnSpan;

  @override
  bool operator ==(Object other) =>
      other is GridPlacement &&
      other.row == row &&
      other.column == column &&
      other.rowSpan == rowSpan &&
      other.columnSpan == columnSpan;

  @override
  int get hashCode => Object.hash(row, column, rowSpan, columnSpan);
}

/// Parent data carrying a child's [GridPlacement].
class GridParentData extends ContainerBoxParentData<RenderBox> {
  /// Where this child sits.
  GridPlacement placement = const GridPlacement(row: 0, column: 0);
}

/// Assigns a [GridPlacement] to a child of [LexicalGrid].
class GridCell extends ParentDataWidget<GridParentData> {
  /// Places [child] according to [placement].
  const GridCell({required this.placement, required super.child, super.key});

  /// Where the child sits.
  final GridPlacement placement;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as GridParentData;
    if (data.placement == placement) return;
    data.placement = placement;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => LexicalGrid;
}

/// Lays children out in a grid of [columnCount] equal columns.
///
/// The layout a table needs and that a `Column` of `Row`s cannot give it: a
/// cell with a `rowSpan` has to reach *into* the rows below it, and rows have
/// to agree on their heights across every cell in them, spans included.
///
/// Columns share the available width equally. That is upstream's default too,
/// and it is the only rule that does not need measuring every cell's content
/// twice — a table in a document is a layout, not a spreadsheet.
class LexicalGrid extends MultiChildRenderObjectWidget {
  /// Creates a grid of [columnCount] columns holding [children].
  const LexicalGrid({
    required this.columnCount,
    required super.children,
    super.key,
    this.spacing = 0,
  }) : assert(columnCount > 0, 'a grid needs at least one column');

  /// How many columns the grid has.
  final int columnCount;

  /// The gap between cells, horizontally and vertically.
  final double spacing;

  @override
  RenderLexicalGrid createRenderObject(BuildContext context) =>
      RenderLexicalGrid(columnCount: columnCount, spacing: spacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLexicalGrid renderObject,
  ) {
    renderObject
      ..columnCount = columnCount
      ..spacing = spacing;
  }
}

/// The render object behind [LexicalGrid].
class RenderLexicalGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridParentData> {
  /// Creates a grid render object.
  RenderLexicalGrid({required int columnCount, double spacing = 0})
    : _columnCount = columnCount,
      _spacing = spacing;

  int _columnCount;

  /// How many columns the grid has.
  int get columnCount => _columnCount;
  set columnCount(int value) {
    if (_columnCount == value) return;
    _columnCount = value;
    markNeedsLayout();
  }

  double _spacing;

  /// The gap between cells.
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;
    final gaps = spacing * (columnCount - 1);
    final columnWidth = ((width - gaps) / columnCount).clamp(0.0, width);

    double widthFor(GridPlacement placement) {
      final span = placement.columnSpan.clamp(1, columnCount);
      return columnWidth * span + spacing * (span - 1);
    }

    // Pass one: lay every child out at its width, and let each row be as tall
    // as the cells that *end* in it. A cell spanning rows contributes only to
    // its last row, so it can never make a row it merely passes through
    // taller than that row's own content needs.
    final rowHeights = <int, double>{};
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as GridParentData;
      final placement = data.placement;
      child.layout(
        BoxConstraints.tightFor(width: widthFor(placement)),
        parentUsesSize: true,
      );
      final lastRow = placement.row + placement.rowSpan - 1;
      if (placement.rowSpan == 1) {
        rowHeights[lastRow] = _max(rowHeights[lastRow], child.size.height);
      }
      child = data.nextSibling;
    }

    // Pass two: a spanning cell taller than the rows it covers pushes the
    // last of them down, which is what keeps its own content inside the grid.
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as GridParentData;
      final placement = data.placement;
      if (placement.rowSpan > 1) {
        final lastRow = placement.row + placement.rowSpan - 1;
        var covered = spacing * (placement.rowSpan - 1);
        for (var row = placement.row; row <= lastRow; row++) {
          covered += rowHeights[row] ?? 0;
        }
        if (child.size.height > covered) {
          rowHeights[lastRow] =
              (rowHeights[lastRow] ?? 0) + child.size.height - covered;
        }
      }
      child = data.nextSibling;
    }

    // Where each row starts.
    final rowCount = rowHeights.keys.isEmpty
        ? 0
        : rowHeights.keys.reduce((a, b) => a > b ? a : b) + 1;
    final rowTops = <double>[];
    var y = 0.0;
    for (var row = 0; row < rowCount; row++) {
      rowTops.add(y);
      y += (rowHeights[row] ?? 0) + spacing;
    }
    final totalHeight = rowCount == 0 ? 0.0 : y - spacing;

    // Pass three: place, and stretch every cell to the height of the band it
    // covers so that borders and backgrounds line up across a row.
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as GridParentData;
      final placement = data.placement;
      final row = placement.row.clamp(0, rowCount == 0 ? 0 : rowCount - 1);
      final lastRow = (placement.row + placement.rowSpan - 1).clamp(
        row,
        rowCount == 0 ? 0 : rowCount - 1,
      );
      var height = 0.0;
      for (var r = row; r <= lastRow; r++) {
        height += rowHeights[r] ?? 0;
      }
      height += spacing * (lastRow - row);

      child.layout(
        BoxConstraints.tightFor(width: widthFor(placement), height: height),
      );
      data.offset = Offset(
        (columnWidth + spacing) * placement.column.clamp(0, columnCount - 1),
        rowTops.isEmpty ? 0 : rowTops[row],
      );
      child = data.nextSibling;
    }

    size = constraints.constrain(Size(width, totalHeight));
  }

  static double _max(double? a, double b) => a == null || b > a ? b : a;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => double.infinity;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
