/// Inserting an image, and wiring it to a builder.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'image_node.dart';
import 'image_resize.dart';
import 'image_view.dart';

/// What an inserted image starts out as.
@immutable
final class ImageAttributes {
  /// Describes an image at [src].
  const ImageAttributes({
    required this.src,
    this.altText = '',
    this.width = 0,
    this.height = 0,
    this.maxWidth = ImageNode.defaultMaxWidth,
    this.caption,
  });

  /// Where the image comes from.
  final String src;

  /// The alternative text.
  final String altText;

  /// An initial width, or `0` for the image's own.
  final double width;

  /// An initial height, or `0` for the image's own.
  final double height;

  /// The largest width the document asks for.
  final double maxWidth;

  /// An initial caption as plain text, or `null` for none.
  final String? caption;

  @override
  bool operator ==(Object other) =>
      other is ImageAttributes &&
      other.src == src &&
      other.altText == altText &&
      other.width == width &&
      other.height == height &&
      other.maxWidth == maxWidth &&
      other.caption == caption;

  @override
  int get hashCode =>
      Object.hash(src, altText, width, height, maxWidth, caption);
}

/// Inserts an image at the selection.
const LexicalCommand<ImageAttributes> insertImageCommand = LexicalCommand(
  'INSERT_IMAGE',
);

/// Registers [insertImageCommand] on [editor].
Unsubscribe registerImage(LexicalEditor editor) =>
    editor.registerCommand<ImageAttributes>(insertImageCommand, (attributes) {
      $insertImage(attributes);
      return true;
    }, CommandPriority.editor);

/// Inserts an image at the selection, on its own line.
///
/// An image is a block, so it cannot live inside the paragraph the caret is
/// in: it is placed after that paragraph, and an empty paragraph follows it so
/// there is somewhere to keep typing. Without that last part an image at the
/// end of a document is a trap — nothing below it will take the caret.
void $insertImage(ImageAttributes attributes) {
  final image = $createImageNode(
    src: attributes.src,
    altText: attributes.altText,
    width: attributes.width,
    height: attributes.height,
    maxWidth: attributes.maxWidth,
  );
  if (attributes.caption != null) image.setCaptionText(attributes.caption);

  final selection = $getSelection();
  final block = selection is RangeSelection
      ? _topLevelBlockOf(selection.focus.getNode())
      : null;

  if (block == null) {
    $getRoot()
      ..append(image)
      ..append($createParagraphNode());
    image.selectNext();
    return;
  }

  final after = $createParagraphNode();
  block.insertAfter(image);
  image.insertAfter(after);
  after.selectStart();
}

/// The top-level block [node] sits in, or `null`.
LexicalNode? _topLevelBlockOf(LexicalNode? node) {
  var current = node;
  while (current != null) {
    final parent = current.getParent();
    if (parent == null) return null;
    if (parent is RootNode) return current;
    current = parent;
  }
  return null;
}

/// A decorator builder for `image`, ready to hand to the renderer.
///
/// ```dart
/// LexicalEditable(
///   editor: editor,
///   theme: theme,
///   decoratorBuilders: imageDecoratorBuilders(editor: editor),
/// )
/// ```
///
/// The builder runs inside the editor's read and hands the widget **values**,
/// never the node — the widget is built later, by Flutter, with no editor
/// state around it.
Map<String, Widget Function(BuildContext, DecoratorNode)>
imageDecoratorBuilders({
  required LexicalEditor editor,
  ImageSizeLimits limits = const ImageSizeLimits(),
  ImageResolver resolver = defaultImageResolver,
  bool editable = true,
  bool captionsEnabled = true,
  bool preserveAspectRatio = true,
  TextStyle? captionStyle,
  Widget Function(BuildContext context, String src)? placeholderBuilder,
}) => {
  'image': (context, node) {
    final image = node as ImageNode;
    return LexicalImageView(
      editor: editor,
      nodeKey: image.key,
      src: image.src,
      altText: image.altText,
      width: image.width,
      height: image.height,
      caption: image.showCaption ? image.captionText : null,
      limits: limits,
      resolver: resolver,
      editable: editable,
      captionsEnabled: captionsEnabled,
      preserveAspectRatio: preserveAspectRatio,
      captionStyle: captionStyle,
      placeholderBuilder: placeholderBuilder,
    );
  },
};
