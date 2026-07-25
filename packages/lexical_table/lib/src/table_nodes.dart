/// Tables, rows and cells.
library;

import 'package:lexical_core/lexical_core.dart';

/// Which header roles a cell plays, as a bitmask.
///
/// It is a bitmask rather than a bool because a corner cell is both a row
/// and a column header, which a bool cannot express. Verified against
/// `$createTableNodeWithDimensions(2, 3, true)`, whose first cell serializes
/// as `3`.
abstract final class TableCellHeaderState {
  /// An ordinary body cell.
  static const int none = 0;

  /// The cell heads its row.
  static const int row = 1;

  /// The cell heads its column.
  static const int column = 2;

  /// Both roles.
  static const int both = row | column;
}

/// A table.
class TableNode extends ElementNode {
  /// Creates an empty table.
  TableNode([List<int>? colWidths]) : _colWidths = colWidths;

  List<int>? _colWidths;

  @override
  String get type => 'table';

  /// A table stops upward traversal: its cells are containment roots.
  @override
  bool get isShadowRoot => true;

  @override
  TableNode clone() => TableNode(_colWidths == null ? null : [..._colWidths!]);

  @override
  void afterCloneFrom(covariant TableNode prev) {
    super.afterCloneFrom(prev);
    _colWidths = prev._colWidths == null ? null : [...prev._colWidths!];
  }

  /// Explicit column widths, or `null` when the table sizes itself.
  List<int>? get colWidths {
    final widths = getLatest<TableNode>()._colWidths;
    return widths == null ? null : List.unmodifiable(widths);
  }

  /// Sets explicit column widths.
  TableNode setColWidths(List<int>? value) =>
      getWritable<TableNode>().._colWidths = value == null ? null : [...value];

  @override
  Map<String, Object?> exportJson() {
    final json = super.exportJson();
    // Omitted entirely when unset — not written as an explicit null. The
    // asymmetry with link.title is upstream's, and it has to be matched
    // field by field rather than by a general rule.
    if (_colWidths != null) json['colWidths'] = [..._colWidths!];
    return json;
  }

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final widths = json['colWidths'];
    _colWidths = widths is List
        ? widths.whereType<int>().toList(growable: false)
        : null;
  }
}

/// A table row.
class TableRowNode extends ElementNode {
  /// Creates a row of optional [height].
  TableRowNode([this._height]);

  int? _height;

  @override
  String get type => 'tablerow';

  @override
  TableRowNode clone() => TableRowNode(_height);

  @override
  void afterCloneFrom(covariant TableRowNode prev) {
    super.afterCloneFrom(prev);
    _height = prev._height;
  }

  /// The explicit row height, or `null`.
  int? get height => getLatest<TableRowNode>()._height;

  /// Sets the explicit row height.
  TableRowNode setHeight(int? value) =>
      getWritable<TableRowNode>().._height = value;

  @override
  Map<String, Object?> exportJson() {
    final json = super.exportJson();
    if (_height != null) json['height'] = _height;
    return json;
  }

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final height = json['height'];
    _height = height is int ? height : null;
  }
}

/// A table cell.
///
/// A cell is a shadow root: traversal upwards stops here, so a paragraph
/// inside a cell is a top-level block *of that cell* rather than of the
/// document.
class TableCellNode extends ElementNode {
  /// Creates a cell.
  TableCellNode({
    int headerState = TableCellHeaderState.none,
    int colSpan = 1,
    int rowSpan = 1,
    String? backgroundColor,
  }) : _headerState = headerState,
       _colSpan = colSpan,
       _rowSpan = rowSpan,
       _backgroundColor = backgroundColor;

  int _headerState;
  int _colSpan;
  int _rowSpan;
  String? _backgroundColor;

  @override
  String get type => 'tablecell';

  @override
  bool get isShadowRoot => true;

  @override
  TableCellNode clone() => TableCellNode(
    headerState: _headerState,
    colSpan: _colSpan,
    rowSpan: _rowSpan,
    backgroundColor: _backgroundColor,
  );

  @override
  void afterCloneFrom(covariant TableCellNode prev) {
    super.afterCloneFrom(prev);
    _headerState = prev._headerState;
    _colSpan = prev._colSpan;
    _rowSpan = prev._rowSpan;
    _backgroundColor = prev._backgroundColor;
  }

  /// The header roles this cell plays. See [TableCellHeaderState].
  int get headerState => getLatest<TableCellNode>()._headerState;

  /// How many columns this cell spans.
  int get colSpan => getLatest<TableCellNode>()._colSpan;

  /// How many rows this cell spans.
  int get rowSpan => getLatest<TableCellNode>()._rowSpan;

  /// The raw background colour string, or `null`.
  String? get backgroundColor => getLatest<TableCellNode>()._backgroundColor;

  /// Whether this cell heads its row.
  bool get isRowHeader =>
      (headerState & TableCellHeaderState.row) == TableCellHeaderState.row;

  /// Whether this cell heads its column.
  bool get isColumnHeader =>
      (headerState & TableCellHeaderState.column) ==
      TableCellHeaderState.column;

  /// Sets the header roles.
  TableCellNode setHeaderState(int value) =>
      getWritable<TableCellNode>().._headerState = value;

  /// Sets the column span.
  TableCellNode setColSpan(int value) =>
      getWritable<TableCellNode>().._colSpan = value;

  /// Sets the row span.
  TableCellNode setRowSpan(int value) =>
      getWritable<TableCellNode>().._rowSpan = value;

  /// Sets the raw background colour string.
  TableCellNode setBackgroundColor(String? value) =>
      getWritable<TableCellNode>().._backgroundColor = value;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    // backgroundColor is written even when null, unlike tablerow.height.
    'backgroundColor': _backgroundColor,
    'colSpan': _colSpan,
    'headerState': _headerState,
    'rowSpan': _rowSpan,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final headerState = json['headerState'];
    _headerState = headerState is int ? headerState : 0;
    final colSpan = json['colSpan'];
    _colSpan = colSpan is int ? colSpan : 1;
    final rowSpan = json['rowSpan'];
    _rowSpan = rowSpan is int ? rowSpan : 1;
    final backgroundColor = json['backgroundColor'];
    _backgroundColor = backgroundColor is String ? backgroundColor : null;
  }
}

/// Creates a table, applying any registered node replacement.
TableNode $createTableNode() => $applyNodeReplacement(TableNode());

/// Creates a table row, applying any registered node replacement.
TableRowNode $createTableRowNode([int? height]) =>
    $applyNodeReplacement(TableRowNode(height));

/// Creates a table cell, applying any registered node replacement.
TableCellNode $createTableCellNode({
  int headerState = TableCellHeaderState.none,
  int colSpan = 1,
  int rowSpan = 1,
  String? backgroundColor,
}) => $applyNodeReplacement(
  TableCellNode(
    headerState: headerState,
    colSpan: colSpan,
    rowSpan: rowSpan,
    backgroundColor: backgroundColor,
  ),
);

/// Builds a [rows] × [columns] table, each cell holding an empty paragraph.
///
/// With [includeHeaders], the first row heads its columns and the first
/// column heads its rows, which is what
/// `$createTableNodeWithDimensions(_, _, true)` produces upstream.
TableNode $createTableNodeWithDimensions(
  int rows,
  int columns, {
  bool includeHeaders = false,
}) {
  final table = $createTableNode();
  for (var row = 0; row < rows; row++) {
    final tableRow = $createTableRowNode();
    for (var column = 0; column < columns; column++) {
      var headerState = TableCellHeaderState.none;
      if (includeHeaders) {
        if (row == 0) headerState |= TableCellHeaderState.row;
        if (column == 0) headerState |= TableCellHeaderState.column;
      }
      tableRow.append(
        $createTableCellNode(headerState: headerState)
          ..append($createParagraphNode()),
      );
    }
    table.append(tableRow);
  }
  return table;
}
