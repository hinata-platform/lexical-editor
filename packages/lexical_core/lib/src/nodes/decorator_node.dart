/// Nodes rendered by host-supplied widgets rather than by the text engine.
library;

import 'lexical_node.dart';

/// A node whose visual representation is supplied by the host application.
///
/// In Lexical web a decorator is a React portal; in this port it becomes a
/// `WidgetSpan` for inline decorators and a block slot for block-level ones.
/// The core knows nothing about either — a decorator here is only a leaf
/// node with its own serialized fields.
///
/// Two decisions belong to each concrete decorator and should be explicit in
/// its API rather than implied: whether it is [isInline], and whether it is
/// selectable as a unit or interactive. Leaving the second ambiguous is what
/// produces the classic "cannot place the caret after the image" bug.
abstract class DecoratorNode extends LexicalNode {
  /// Creates a decorator node.
  DecoratorNode();

  @override
  bool get isInline => false;

  /// The plain-text stand-in for this node, used for copy and for the
  /// accessibility tree.
  ///
  /// Defaults to empty. Returning a single character keeps flat offsets in
  /// step with the object-replacement character a `WidgetSpan` occupies.
  @override
  String getTextContent() => '';
}
