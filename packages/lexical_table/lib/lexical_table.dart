/// Table, row and cell nodes for `lexical_core`, with the editing they need.
///
/// ```dart
/// final editor = LexicalEditor(nodes: tableNodes);
/// registerTable(editor);
///
/// editor.update(() {
///   $getRoot().append(
///     $createTableNodeWithDimensions(2, 3, includeHeaders: true),
///   );
/// }, discrete: true);
/// ```
///
/// Structural editing works on a `TableGrid` rather than on the child list.
/// A cell's position is not its index within its row — a `rowSpan` above it
/// pushes it right — so "the column left of this one" is a question only the
/// resolved grid can answer.
///
/// ```dart
/// editor.update(() {
///   final table = $getRoot().getFirstChild()! as TableNode;
///   $insertTableColumns($computeTableGrid(table), atColumn: 0, after: true);
/// });
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/table_nodes.dart';

export 'src/table_commands.dart'
    show
        TableShape,
        deleteTableColumnCommand,
        deleteTableCommand,
        deleteTableRowCommand,
        insertTableColumnCommand,
        insertTableCommand,
        insertTableRowCommand,
        mergeTableCellsCommand,
        moveTableCellCommand,
        registerTable,
        setTableCellBackgroundCommand,
        toggleTableColumnHeaderCommand,
        toggleTableRowHeaderCommand,
        unmergeTableCellCommand;
export 'src/table_grid.dart'
    show
        TableCellRange,
        TableCellRef,
        TableGrid,
        $computeTableGrid,
        $getTableCellForNode,
        $getTableForNode;
export 'src/table_markdown.dart' show tableTransformer;
export 'src/table_nodes.dart'
    show
        TableCellHeaderState,
        TableCellNode,
        TableNode,
        TableRowNode,
        $createTableCellNode,
        $createTableNode,
        $createTableNodeWithDimensions,
        $createTableRowNode;
export 'src/table_ops.dart'
    show
        $clearTableCells,
        $deleteTable,
        $deleteTableColumns,
        $deleteTableRows,
        $insertTableColumns,
        $insertTableRows,
        $mergeTableCells,
        $nextTableCell,
        $rescueTableSelection,
        $setTableCellBackground,
        $toggleTableColumnHeader,
        $toggleTableRowHeader,
        $unmergeTableCell;
export 'src/table_selection.dart'
    show
        TableSelection,
        $selectTableCellStart,
        $selectTableCells,
        $tableSelectionOf;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get tableNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<TableNode>(type: 'table', create: TableNode.new),
  NodeSpec<TableRowNode>(type: 'tablerow', create: TableRowNode.new),
  NodeSpec<TableCellNode>(type: 'tablecell', create: TableCellNode.new),
];
