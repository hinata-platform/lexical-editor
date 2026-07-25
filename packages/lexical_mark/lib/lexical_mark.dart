/// Mark nodes — annotations and comment ranges — for `lexical_core`.
///
/// A mark wraps inline content and carries a set of identifiers. Overlapping
/// annotations are represented by nesting marks rather than by allowing a
/// node to belong to two ranges, which is why [MarkNode.ids] is a list.
///
/// ```dart
/// final editor = LexicalEditor(nodes: markNodes);
/// editor.update(() {
///   final mark = $createMarkNode(['comment-1'])
///     ..append($createTextNode('markiert'));
///   $getRoot().append($createParagraphNode()..append(mark));
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/mark_node.dart';

export 'src/mark_node.dart' show MarkNode, $createMarkNode;
export 'src/mark_ops.dart'
    show
        addMarkCommand,
        registerMark,
        removeMarkCommand,
        $getMarkIdsAtSelection,
        $getMarkedText,
        $markSelection,
        $removeMark;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get markNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<MarkNode>(type: 'mark', create: MarkNode.new),
];
