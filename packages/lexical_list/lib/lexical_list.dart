/// List, ordered list and check-list nodes for `lexical_core`.
///
/// ```dart
/// final editor = LexicalEditor(nodes: listNodes);
/// registerListNumbering(editor);   // keeps `value` in step with position
///
/// editor.update(() {
///   final list = $createListNode(ListType.check);
///   list
///     ..append($createListItemNode(true)..append($createTextNode('erledigt')))
///     ..append($createListItemNode(false)..append($createTextNode('offen')));
///   $getRoot().append(list);
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/list_item_node.dart';
import 'src/list_node.dart';

export 'src/list_commands.dart' show registerList;
export 'src/list_item_node.dart' show ListItemNode, $createListItemNode;
export 'src/list_node.dart'
    show
        ListNode,
        ListType,
        registerListNumbering,
        renumberItems,
        $createListNode;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get listNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<ListNode>(type: 'list', create: ListNode.new),
  NodeSpec<ListItemNode>(type: 'listitem', create: ListItemNode.new),
];
