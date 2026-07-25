/// Table, row and cell nodes for `lexical_core`.
///
/// ```dart
/// final editor = LexicalEditor(nodes: tableNodes);
/// editor.update(() {
///   $getRoot().append(
///     $createTableNodeWithDimensions(2, 3, includeHeaders: true),
///   );
/// }, discrete: true);
/// ```
///
/// Grid selection — Lexical's third selection kind, shaped like a rectangle
/// of cells rather than a range — is not modelled yet; it arrives with the
/// editable milestone.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/table_nodes.dart';

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

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get tableNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<TableNode>(type: 'table', create: TableNode.new),
  NodeSpec<TableRowNode>(type: 'tablerow', create: TableRowNode.new),
  NodeSpec<TableCellNode>(type: 'tablecell', create: TableCellNode.new),
];
