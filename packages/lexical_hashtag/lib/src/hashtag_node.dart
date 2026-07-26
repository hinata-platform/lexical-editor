/// The hashtag node.
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
