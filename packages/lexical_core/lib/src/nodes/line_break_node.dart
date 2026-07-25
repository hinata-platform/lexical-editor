/// Hard line breaks.
library;

import '../updates.dart';
import 'lexical_node.dart';

/// A hard line break inside a block.
///
/// Text nodes never contain `\n`; a newline in a paragraph is this node.
/// Keeping breaks out of text content is what lets a text run carry a single
/// uniform format and what keeps offset arithmetic honest.
///
/// It serializes to `type` and `version` and nothing else — no `text`, no
/// `format`, no `detail`.
final class LineBreakNode extends LexicalNode {
  /// Creates a line break.
  LineBreakNode();

  @override
  String get type => 'linebreak';

  @override
  bool get isInline => true;

  @override
  LineBreakNode clone() => LineBreakNode();

  @override
  String getTextContent() => '\n';
}

/// Creates a line break, applying any registered node replacement.
LineBreakNode $createLineBreakNode() => $applyNodeReplacement(LineBreakNode());
