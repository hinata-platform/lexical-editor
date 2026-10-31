/// The image node on its own, without the widgets that draw it.
///
/// `package:lexical_image/lexical_image.dart` brings the Flutter view, the
/// resize handles and the commands with it. A program that only reads or
/// writes documents — a server converting mail, a conformance suite — needs
/// the node and nothing else, and this library is exactly that: it imports
/// `lexical_core` and no Flutter.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/image_node.dart';

export 'src/image_node.dart' show ImageNode, $createImageNode;

/// The node specs this package contributes; the same list
/// `lexical_image.dart` exports.
List<NodeSpec<LexicalNode>> get imageNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<ImageNode>(type: 'image', create: ImageNode.new),
];
