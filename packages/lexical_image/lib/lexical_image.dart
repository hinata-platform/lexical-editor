/// Images for `lexical_core`, with a resizable Flutter widget.
///
/// An image is a **decorator**: the model holds where it is and how big it
/// should be, the host draws it. Unlike the other node packages this one ships
/// its Flutter widget rather than a separate `_flutter` companion — a
/// decorator with no builder renders nothing at all, so the node and the
/// widget are one feature, not two.
///
/// ```dart
/// final editor = LexicalEditor(nodes: imageNodes);
/// registerImage(editor);
///
/// LexicalEditable(
///   editor: editor,
///   theme: theme,
///   decoratorBuilders: imageDecoratorBuilders(
///     editor: editor,
///     limits: const ImageSizeLimits(minWidth: 80, maxWidth: 640),
///   ),
/// );
///
/// editor.dispatchCommand(
///   insertImageCommand,
///   const ImageAttributes(src: 'https://…/flowers.jpg', altText: 'Blumen'),
/// );
/// ```
///
/// The minimum and maximum size live with the widget, not in the document:
/// they are a policy of the application showing it, and storing them would
/// freeze one app's layout into everyone else's copy of the file.
///
/// Markdown exchange is opt-in, exactly as it is upstream — `@lexical/markdown`
/// ships no image rule and the playground adds its own:
///
/// ```dart
/// final transformers = defaultMarkdownTransformers.extend(
///   textMatches: [imageTransformer],
/// );
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/image_node.dart';

export 'src/image_commands.dart'
    show
        ImageAttributes,
        imageDecoratorBuilders,
        insertImageCommand,
        registerImage,
        $insertImage;
export 'src/image_markdown.dart'
    show imageMarkdownTransformer, imageTransformer, markdownImageMaxWidth;
export 'src/image_node.dart' show ImageNode, $createImageNode;
export 'src/image_resize.dart' show ImageHandle, ImageSizeLimits, resizeImage;
export 'src/image_view.dart'
    show ImageResolver, LexicalImageView, defaultImageResolver;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get imageNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<ImageNode>(type: 'image', create: ImageNode.new),
];
