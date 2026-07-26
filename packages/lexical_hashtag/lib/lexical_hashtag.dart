/// Hashtag nodes for `lexical_core`.
///
/// A hashtag is a `TextNode` subclass with no extra fields — only its type
/// string differs on the wire. That is enough to make it non-mergeable with
/// surrounding text, which is exactly the behaviour a tag needs: it stays a
/// single addressable run rather than dissolving into the sentence.
///
/// ```dart
/// final editor = LexicalEditor(nodes: hashtagNodes);
/// registerHashtag(editor);   // detects `#flutter` as it is typed
/// ```
///
/// Detection is a pair of transforms, and registering them is what makes the
/// package do anything without being asked: text that becomes a tag turns
/// into one, and a tag that stops looking like a tag turns back into text.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/hashtag_node.dart';

export 'src/hashtag_node.dart' show HashtagNode, $createHashtagNode;
export 'src/hashtag_transform.dart' show defaultHashtagPattern, registerHashtag;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get hashtagNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<HashtagNode>(type: 'hashtag', create: HashtagNode.new),
];
