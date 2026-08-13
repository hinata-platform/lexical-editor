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
    this.blurHash = '',
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

  /// A BlurHash of the picture, or `''` — what the reader sees until the
  /// image itself has loaded.
  final String blurHash;

  @override
  bool operator ==(Object other) =>
      other is ImageAttributes &&
      other.src == src &&
      other.altText == altText &&
      other.width == width &&
      other.height == height &&
      other.maxWidth == maxWidth &&
      other.caption == caption &&
      other.blurHash == blurHash;

  @override
  int get hashCode =>
      Object.hash(src, altText, width, height, maxWidth, caption, blurHash);
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

/// Inserts an image at the selection, inside a paragraph.
///
/// This mirrors upstream's insert step exactly — put the image where the caret
/// is, and if that turns out to be the root, wrap it in a paragraph. An image
/// is an *inline* decorator (see [ImageNode.isInline]), so a document written
/// here has the same shape as one written on the web: `paragraph > image`,
/// never `root > image`.
void $insertImage(ImageAttributes attributes) {
  final image = $createImageNode(
    src: attributes.src,
    altText: attributes.altText,
    width: attributes.width,
    height: attributes.height,
    maxWidth: attributes.maxWidth,
    blurHash: attributes.blurHash,
  );
  if (attributes.caption != null) image.setCaptionText(attributes.caption);

  final selection = $getSelection();
  if (selection is RangeSelection) selection.insertNodes([image]);

  // The caret can sit on the root itself — an empty document, or no selection
  // at all — and an inline node there would be a tree nothing else writes.
  final parent = image.getParent();
  if (parent != null && parent is! RootNode) return;

  final paragraph = $createParagraphNode();
  if (parent == null) {
    $getRoot().append(paragraph);
  } else {
    image.insertBefore(paragraph);
  }
  // `append` reparents, so this both moves the image and empties its old slot.
  paragraph
    ..append(image)
    ..selectEnd();
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
  LexicalImageStyle style = const LexicalImageStyle(),
}) => {
  'image': (context, node) {
    final image = node as ImageNode;
    return LexicalImageView(
      editor: editor,
      nodeKey: image.key,
      src: image.src,
      altText: image.altText,
      blurHash: image.blurHash,
      // The node says "the image's own size" with `0`; the view says it with
      // `null`. Passing the zero straight through made `SizedBox` force every
      // image that had never been resized to 0×0 — inserted, stored, exported
      // and completely invisible.
      width: image.width == 0 ? null : image.width,
      height: image.height == 0 ? null : image.height,
      caption: image.showCaption ? image.captionText : null,
      limits: limits,
      resolver: resolver,
      editable: editable,
      captionsEnabled: captionsEnabled,
      preserveAspectRatio: preserveAspectRatio,
      captionStyle: captionStyle,
      placeholderBuilder: placeholderBuilder,
      style: style,
    );
  },
};
