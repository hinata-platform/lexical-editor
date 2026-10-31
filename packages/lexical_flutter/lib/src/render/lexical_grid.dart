/// Laying blocks out in a grid, with spans.
library;

import 'package:flutter/foundation.dart';
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
  /// The cell's own height at its width, from when it was last measured.
  double? naturalHeight;

  /// The constraints the cell was stretched to its row with, if it was.
  BoxConstraints? stretched;

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

/// Works out the widths of a grid's columns for the width it is given.
///
/// Returns one width per column, or `null` to stack the children instead —
/// one per row, full width, in child order — which is how a layout too
/// narrow for its fixed columns reflows on a phone.
typedef GridColumnWidths = List<double>? Function(double available);

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
    this.columnWidths,
    this.columnWidthsKey,
  }) : assert(columnCount > 0, 'a grid needs at least one column');

  /// How many columns the grid has.
  final int columnCount;

  /// The gap between cells, horizontally and vertically.
  final double spacing;

  /// Column widths other than equal shares, or `null` for equal shares.
  ///
  /// A widths list of the wrong length is ignored in favour of equal shares.
  final GridColumnWidths? columnWidths;

  /// What [columnWidths] is computed from, compared to decide whether the
  /// columns changed — the template, for example.
  ///
  /// A closure is a new object on every build, so on its own it can only be
  /// compared by identity, and every grid would lay itself out again on
  /// every rebuild. With a key, a new closure under an equal key (`==`, or
  /// element-wise for a list) is taken as the same widths. Without one, the
  /// closure's identity decides, as before.
  final Object? columnWidthsKey;

  @override
  RenderLexicalGrid createRenderObject(BuildContext context) =>
      RenderLexicalGrid(
        columnCount: columnCount,
        spacing: spacing,
        columnWidths: columnWidths,
        columnWidthsKey: columnWidthsKey,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLexicalGrid renderObject,
  ) {
    renderObject
      ..columnCount = columnCount
      ..spacing = spacing
      ..setColumnWidths(columnWidths, key: columnWidthsKey);
  }
}

/// The render object behind [LexicalGrid].
class RenderLexicalGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridParentData> {
  /// Creates a grid render object.
  RenderLexicalGrid({
    required int columnCount,
    double spacing = 0,
    GridColumnWidths? columnWidths,
    Object? columnWidthsKey,
  }) : _columnCount = columnCount,
       _spacing = spacing,
       _columnWidths = columnWidths,
       _columnWidthsKey = columnWidthsKey;

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

  GridColumnWidths? _columnWidths;

  /// See [LexicalGrid.columnWidths].
  GridColumnWidths? get columnWidths => _columnWidths;
  set columnWidths(GridColumnWidths? value) => setColumnWidths(value);

  Object? _columnWidthsKey;

  /// Replaces the column widths, laying out again only when they changed:
  /// by [key] when there is one, otherwise by the closure's identity.
  void setColumnWidths(GridColumnWidths? value, {Object? key}) {
    final same = key != null || _columnWidthsKey != null
        ? (value == null) == (_columnWidths == null) &&
              _sameKey(key, _columnWidthsKey)
        : identical(value, _columnWidths);
    _columnWidths = value;
    _columnWidthsKey = key;
    if (!same) markNeedsLayout();
  }

  static bool _sameKey(Object? a, Object? b) {
    if (a is List && b is List) return listEquals(a, b);
    return a == b;
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
    final equal = ((width - gaps) / columnCount).clamp(0.0, width);
    final resolver = _columnWidths;
    final resolved = resolver?.call(width);
    if (resolver != null && resolved == null) {
      _layoutStacked(width);
      return;
    }
    final widths = resolved != null && resolved.length == columnCount
        ? [for (final w in resolved) w.isFinite && w > 0 ? w : 0.0]
        : List<double>.filled(columnCount, equal);
    final lefts = <double>[];
    var x = 0.0;
    for (final w in widths) {
      lefts.add(x);
      x += w + spacing;
    }

    double widthFor(GridPlacement placement) {
      final column = placement.column.clamp(0, columnCount - 1);
      final last = (column + placement.columnSpan - 1).clamp(
        column,
        columnCount - 1,
      );
      var total = spacing * (last - column);
      for (var c = column; c <= last; c++) {
        total += widths[c];
      }
      return total;
    }

    // Laid out in a bounded loop: a pass is enough unless a stretched cell
    // turns out taller than its row (see `_measure`), and then one more
    // measures it afresh.
    var totalHeight = 0.0;
    for (var attempt = 0; attempt < 3; attempt++) {
      final overflowed = _layoutRows(widthFor, lefts, (height) {
        totalHeight = height;
      });
      if (!overflowed) break;
    }
    size = constraints.constrain(Size(width, totalHeight));
  }

  /// Measures, sizes the rows, then stretches and places every cell.
  ///
  /// Returns whether a cell came out taller than the band it was given, in
  /// which case its measurement was stale and has been dropped.
  bool _layoutRows(
    double Function(GridPlacement placement) widthFor,
    List<double> lefts,
    void Function(double height) reportHeight,
  ) {
    // Pass one: every cell's own height at its width, and each row as tall
    // as the cells that *end* in it. A cell spanning rows contributes only to
    // its last row, so it can never make a row it merely passes through
    // taller than that row's own content needs.
    final rowHeights = <int, double>{};
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as GridParentData;
      final placement = data.placement;
      final natural = _measure(child, data, widthFor(placement));
      final lastRow = placement.row + placement.rowSpan - 1;
      if (placement.rowSpan == 1) {
        rowHeights[lastRow] = _max(rowHeights[lastRow], natural);
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
        final natural = data.naturalHeight ?? 0;
        if (natural > covered) {
          rowHeights[lastRow] = (rowHeights[lastRow] ?? 0) + natural - covered;
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
    reportHeight(rowCount == 0 ? 0.0 : y - spacing);

    // Pass three: place, and stretch a cell shorter than the band it covers
    // to its height, so that borders and backgrounds line up across a row.
    // A cell that already fills its band is not laid out again.
    var overflowed = false;
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

      final cellWidth = widthFor(placement);
      if ((data.naturalHeight ?? 0) < height) {
        final stretched = BoxConstraints(
          minWidth: cellWidth,
          maxWidth: cellWidth,
          minHeight: height,
        );
        child.layout(stretched, parentUsesSize: true);
        data.stretched = stretched;
        if (child.size.height > height + 0.01) {
          // Its content grew while it was stretched, which the stretch hid:
          // measure it again on the next round.
          data.stretched = null;
          overflowed = true;
        }
      } else if (data.stretched != null) {
        _measure(child, data..stretched = null, cellWidth);
      }
      data.offset = Offset(
        lefts[placement.column.clamp(0, columnCount - 1)],
        rowTops.isEmpty ? 0 : rowTops[row],
      );
      child = data.nextSibling;
    }
    return overflowed;
  }

  /// [child]'s own height at [width], laying it out only when that can
  /// change it.
  ///
  /// The size is always used — never a tight constraint, never a relayout
  /// boundary — because a cell whose content grows later, an image that
  /// decodes, has to tell the grid, or the row keeps its old height and the
  /// content runs over the blocks below.
  ///
  /// A cell that was stretched to its row last time is *not* laid out again
  /// at its own height just to be measured: with the stretch laid out right
  /// after, that is two layouts of the cell per layout of the grid, and in
  /// grids nested in stretched cells it doubles per level. Its stretched
  /// constraints are reused — a no-op while it is clean — and its height
  /// from when it was last measured stands, unless it has grown past the
  /// stretch since.
  double _measure(RenderBox child, GridParentData data, double width) {
    final stretched = data.stretched;
    if (stretched != null && stretched.minWidth == width) {
      child.layout(stretched, parentUsesSize: true);
      if (child.size.height > stretched.minHeight + 0.01) {
        data.naturalHeight = child.size.height;
      }
      return data.naturalHeight ?? child.size.height;
    }
    data.stretched = null;
    child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    return data.naturalHeight = child.size.height;
  }


  /// Every child on its own row, full width, in child order.
  void _layoutStacked(double width) {
    var y = 0.0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as GridParentData;
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      data.offset = Offset(0, y);
      y += child.size.height;
      child = data.nextSibling;
      if (child != null) y += spacing;
    }
    size = constraints.constrain(Size(width, y));
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
