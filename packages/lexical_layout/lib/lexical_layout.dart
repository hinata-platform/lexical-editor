/// Column layout nodes for `lexical_core`: `layout-container` and
/// `layout-item`, wire-compatible with the Lexical playground's.
///
/// ```dart
/// final editor = LexicalEditor(nodes: layoutNodes);
/// registerLayout(editor);
///
/// editor.update(() {
///   $getRoot().append($createLayoutWithColumns('200px 1fr'));
/// }, discrete: true);
/// ```
///
/// The container carries a CSS grid template; [parseTemplateColumns] reads
/// it and [resolveTemplateColumns] turns it into column widths for a given
/// width, or `null` when the columns should stack. Both are pure Dart, so a
/// renderer and a test agree on the same numbers.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/layout_nodes.dart';
import 'src/template_columns.dart';

export 'src/layout_commands.dart'
    show
        LayoutUpdate,
        insertLayoutCommand,
        layoutColumnCount,
        registerLayout,
        updateLayoutCommand,
        $createLayoutWithColumns;
export 'src/layout_nodes.dart'
    show
        LayoutContainerNode,
        LayoutItemNode,
        $createLayoutContainerNode,
        $createLayoutItemNode,
        $isEmptyLayoutItemNode,
        $isLayoutContainerNode,
        $isLayoutItemNode;
export 'src/template_columns.dart'
    show
        LayoutTrack,
        LayoutTrackKind,
        maxLayoutTracks,
        maxTemplateLength,
        minimumTemplateWidth,
        parseTemplateColumns,
        resolveTemplateColumns;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get layoutNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<LayoutContainerNode>(
    type: 'layout-container',
    create: LayoutContainerNode.new,
  ),
  NodeSpec<LayoutItemNode>(type: 'layout-item', create: LayoutItemNode.new),
];
