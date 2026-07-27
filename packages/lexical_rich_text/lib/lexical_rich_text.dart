/// Heading and quote nodes for `lexical_core`.
///
/// ```dart
/// final editor = LexicalEditor(nodes: richTextNodes);
/// editor.update(() {
///   $getRoot().append(
///     $createHeadingNode(HeadingTag.h2)..append($createTextNode('Bericht')),
///   );
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/heading_node.dart';
import 'src/horizontal_rule_node.dart';
import 'src/quote_node.dart';

export 'src/heading_node.dart' show HeadingNode, HeadingTag, $createHeadingNode;
export 'src/horizontal_rule_node.dart'
    show HorizontalRuleNode, $createHorizontalRuleNode, $isHorizontalRuleNode;
export 'src/quote_node.dart' show QuoteNode, $createQuoteNode;

/// The node specs this package contributes.
///
/// Pass them to `LexicalEditor(nodes: ...)`. Omitting this package must not
/// break anything else — that is the test of whether the layering holds.
List<NodeSpec<LexicalNode>> get richTextNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<HeadingNode>(type: 'heading', create: HeadingNode.new),
  NodeSpec<QuoteNode>(type: 'quote', create: QuoteNode.new),
  NodeSpec<HorizontalRuleNode>(
    type: 'horizontalrule',
    create: HorizontalRuleNode.new,
  ),
];
