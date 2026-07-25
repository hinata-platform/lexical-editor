/// Link and auto-link nodes for `lexical_core`.
///
/// URLs are stored **verbatim** so documents round-trip unchanged, and
/// validated at the point of use with [isSafeUrl]. A renderer must call it
/// before making a link tappable — a stored document is untrusted input, and
/// a link is where that input becomes an action.
///
/// ```dart
/// final editor = LexicalEditor(nodes: linkNodes);
/// editor.update(() {
///   final link = $createLinkNode('https://lexical.dev')
///     ..append($createTextNode('Quelle'));
///   $getRoot().append($createParagraphNode()..append(link));
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/link_node.dart';

export 'src/link_node.dart'
    show
        AutoLinkNode,
        LinkNode,
        isSafeUrl,
        safeUrlSchemes,
        $createAutoLinkNode,
        $createLinkNode;
export 'src/link_ops.dart'
    show registerLink, toggleLinkCommand, $getLinkAtSelection, $toggleLink;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get linkNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<LinkNode>(type: 'link', create: LinkNode.new),
  NodeSpec<AutoLinkNode>(type: 'autolink', create: AutoLinkNode.new),
];
