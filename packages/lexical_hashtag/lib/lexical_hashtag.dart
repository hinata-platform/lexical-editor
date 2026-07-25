/// Hashtag nodes for `lexical_core`.
///
/// A hashtag is a `TextNode` subclass with no extra fields — only its type
/// string differs on the wire. That is enough to make it non-mergeable with
/// surrounding text, which is exactly the behaviour a tag needs: it stays a
/// single addressable run rather than dissolving into the sentence.
///
/// ```dart
/// final editor = LexicalEditor(nodes: hashtagNodes);
/// editor.update(() {
///   $getRoot().append(
///     $createParagraphNode()..append($createHashtagNode('#flutter')),
///   );
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

/// A tag such as `#flutter`.
class HashtagNode extends TextNode {
  /// Creates a hashtag holding [text].
  HashtagNode([super.text]);

  @override
  String get type => 'hashtag';

  @override
  HashtagNode clone() => HashtagNode(getTextContent());
}

/// Creates a hashtag, applying any registered node replacement.
HashtagNode $createHashtagNode([String text = '']) =>
    $applyNodeReplacement(HashtagNode(text));

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get hashtagNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<HashtagNode>(type: 'hashtag', create: HashtagNode.new),
];
