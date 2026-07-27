/// Thematic breaks.
library;

import 'package:lexical_core/lexical_core.dart';

/// A horizontal rule — the `---` between two sections.
///
/// A *decorator*, not an element: it has no children and no text, and what it
/// draws is entirely the renderer's business. That is also why it is here
/// rather than in a Flutter package — the model is pure Dart, and only the
/// widget that paints it needs a binding.
///
/// It carries no fields, so the whole implementation is its type string. The
/// wire shape matches upstream's exactly:
/// `{"type": "horizontalrule", "version": 1}`.
class HorizontalRuleNode extends DecoratorNode {
  /// Creates a rule.
  HorizontalRuleNode();

  @override
  String get type => 'horizontalrule';

  @override
  HorizontalRuleNode clone() => HorizontalRuleNode();

  /// A block: it separates paragraphs, and never sits inside a line.
  @override
  bool get isInline => false;
}

/// Creates a horizontal rule, applying any registered node replacement.
HorizontalRuleNode $createHorizontalRuleNode() =>
    $applyNodeReplacement(HorizontalRuleNode());

/// Whether [node] is a horizontal rule.
bool $isHorizontalRuleNode(LexicalNode? node) => node is HorizontalRuleNode;
