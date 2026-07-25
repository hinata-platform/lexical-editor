/// Tab characters as their own node type.
library;

import '../updates.dart';
import 'text_node.dart';

/// A tab character.
///
/// A tab is a `TextNode` subclass whose content is always `\t` and whose
/// detail carries [TextDetail.unmergeable]. That flag is the whole point:
/// without it a tab would merge into the text around it and stop being
/// independently addressable.
final class TabNode extends TextNode {
  /// Creates a tab node.
  TabNode() : super('\t') {
    detailInternal = TextDetail.unmergeable.bit;
  }

  @override
  String get type => 'tab';

  @override
  TabNode clone() => TabNode();

  /// Ignores [text] and keeps the canonical `\t`.
  ///
  /// Platform IME paths can deliver a mid-composition write onto a tab's
  /// text; upstream stopped throwing here because that froze the editor.
  /// The stored content is canonical regardless of what arrives.
  @override
  TextNode setTextContent(String text) => super.setTextContent('\t');

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    textInternal = '\t';
  }
}

/// Creates a tab node, applying any registered node replacement.
TabNode $createTabNode() => $applyNodeReplacement(TabNode());
