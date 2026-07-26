/// The widget an [ImageNode] is drawn with.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'image_node.dart';
import 'image_resize.dart';

/// Turns a node's `src` into something Flutter can draw.
///
/// A stored address is untrusted input, which is why this is a hook rather
/// than a switch inside the widget: an application knows which hosts it
/// trusts, whether it has an image cache, and what an offline placeholder
/// looks like. [defaultImageResolver] handles the ordinary cases.
typedef ImageResolver = ImageProvider<Object>? Function(String src);

/// Resolves `http(s):` URLs, `data:` URIs and asset paths, and nothing else.
///
/// Everything else returns `null` and draws the placeholder — a `file:` URL in
/// a document from someone else has no business reading the local disk.
ImageProvider<Object>? defaultImageResolver(String src) {
  final trimmed = src.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (!uri.hasScheme) return AssetImage(trimmed);
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => NetworkImage(trimmed),
    'data' when uri.data != null => MemoryImage(uri.data!.contentAsBytes()),
    'asset' => AssetImage(uri.path),
    _ => null,
  };
}

/// An image with drag handles, drawn for an [ImageNode].
///
/// The handles appear on hover with a mouse and on tap with a finger, and a
/// drag only writes to the document when it **ends** — resizing has to be one
/// undo step, not one per pointer move.
class LexicalImageView extends StatefulWidget {
  /// Draws the image of [nodeKey] in [editor].
  const LexicalImageView({
    required this.editor,
    required this.nodeKey,
    required this.src,
    super.key,
    this.altText = '',
    this.width,
    this.height,
    this.caption,
    this.limits = const ImageSizeLimits(),
    this.resolver = defaultImageResolver,
    this.editable = true,
    this.captionsEnabled = true,
    this.preserveAspectRatio = true,
    this.captionStyle,
    this.placeholderBuilder,
  });

  /// The editor holding the image.
  final LexicalEditor editor;

  /// The image node's key.
  ///
  /// A key rather than the node: this widget is built long after the read the
  /// node came from, and it writes back through a fresh one.
  final NodeKey nodeKey;

  /// The address to draw, verbatim from the model.
  final String src;

  /// The alternative text, used for semantics.
  final String altText;

  /// The chosen width, or `null` for the image's own.
  final double? width;

  /// The chosen height, or `null` for the image's own.
  final double? height;

  /// The caption as plain text, or `null` when none is shown.
  ///
  /// Upstream's caption is a nested editor; this port shows and edits its
  /// text. See [ImageNode] for what that costs and when.
  final String? caption;

  /// How large the user may drag it.
  final ImageSizeLimits limits;

  /// Turns [src] into an `ImageProvider`.
  final ImageResolver resolver;

  /// Whether the image may be resized and its caption edited.
  final bool editable;

  /// Whether a caption may be added at all.
  final bool captionsEnabled;

  /// Whether dragging keeps the image's shape.
  final bool preserveAspectRatio;

  /// Style for the caption text.
  final TextStyle? captionStyle;

  /// Drawn instead of the image when [src] cannot be resolved or fails.
  final Widget Function(BuildContext context, String src)? placeholderBuilder;

  @override
  State<LexicalImageView> createState() => _LexicalImageViewState();
}

class _LexicalImageViewState extends State<LexicalImageView> {
  /// The size being dragged, in logical pixels — not yet in the document.
  Size? _dragging;
  Size? _dragStart;

  /// Where the pointer went down, in global coordinates.
  Offset _origin = Offset.zero;
  bool _hovered = false;
  bool _touched = false;
  bool _editingCaption = false;

  /// The image's own size, once it is known.
  Size? _intrinsic;

  bool get _showHandles => widget.editable && (_hovered || _touched);

  Size? get _size {
    if (_dragging != null) return _dragging;
    final width = widget.width;
    final height = widget.height;
    if (width == null && height == null) return null;
    final ratio = _aspectRatio;
    return Size(
      width ?? (height != null && ratio != null ? height * ratio : 0),
      height ?? (width != null && ratio != null ? width / ratio : 0),
    );
  }

  double? get _aspectRatio {
    if (!widget.preserveAspectRatio) return null;
    final intrinsic = _intrinsic;
    if (intrinsic != null && intrinsic.height > 0) {
      return intrinsic.width / intrinsic.height;
    }
    final width = widget.width;
    final height = widget.height;
    if (width != null && height != null && height > 0) return width / height;
    return null;
  }

  void _onDragStart(Size? displayed, Offset origin) {
    final current = displayed ?? _size ?? _intrinsic;
    if (current == null) return;
    setState(() {
      _origin = origin;
      _dragStart = current;
      _dragging = current;
    });
  }

  /// [position] is where the pointer is now, in global coordinates.
  ///
  /// The handle reports the position rather than a delta, and the origin it
  /// is measured from lives **here**. That is not a detail: every update calls
  /// `setState`, so anything the handle kept in its own `build` would be reset
  /// to its initial value between the drag starting and the first update — the
  /// pointer's absolute position would then be read as the distance dragged,
  /// and one pixel of movement would resize the image by half the screen.
  void _onDragUpdate(ImageHandle handle, Offset position) {
    final start = _dragStart;
    if (start == null) return;
    setState(() {
      _dragging = resizeImage(
        start: start,
        delta: position - _origin,
        handle: handle,
        limits: widget.limits,
        aspectRatio: _aspectRatio,
      );
    });
  }

  /// Writes the size to the document — once, at the end of the drag.
  void _onDragEnd() {
    final size = _dragging;
    _dragStart = null;
    if (size == null) return;
    // Discrete, so the document has the new size *before* the dragged size is
    // dropped. A scheduled commit would leave one frame in which neither is
    // in effect, and the image would snap back to its old size and forward
    // again.
    widget.editor.update(() {
      final node = $getNodeByKey(widget.nodeKey);
      if (node is ImageNode) node.setSize(size.width, size.height);
    }, discrete: true);
    setState(() => _dragging = null);
  }

  void _setCaption(String? caption) {
    widget.editor.update(() {
      final node = $getNodeByKey(widget.nodeKey);
      if (node is ImageNode) node.setCaptionText(caption);
    });
    setState(() => _editingCaption = false);
  }

  /// [size] brought inside [maxWidth], keeping its shape.
  ///
  /// A stored size is a size somebody chose on *their* screen. The same
  /// document opened on a phone must not push its image past the edge — and
  /// clamping only the width would squash the picture, so the height follows.
  ///
  /// Display only: the document keeps the size it was given, so the image is
  /// full size again on a screen with room for it.
  static Size? _fitted(Size? size, double maxWidth) {
    if (size == null || !maxWidth.isFinite || maxWidth <= 0) return size;
    if (size.width <= maxWidth || size.width <= 0) return size;
    return Size(maxWidth, size.height * maxWidth / size.width);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: () => setState(() => _touched = !_touched),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = _fitted(_size, constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: size?.width,
                    height: size?.height,
                    child: _image(context),
                  ),
                  if (_showHandles && size != null)
                    ..._handles(context, size)
                  else if (_showHandles)
                    // Before the image has reported its own size there is
                    // nothing to drag from; the frame still says it is
                    // selected.
                    Positioned.fill(child: _outline(context)),
                ],
              ),
              if (widget.captionsEnabled) _caption(context),
            ],
          );
        },
      ),
    ),
  );

  Widget _image(BuildContext context) {
    final provider = widget.resolver(widget.src);
    if (provider == null) return _placeholder(context);
    return Image(
      image: provider,
      fit: BoxFit.contain,
      semanticLabel: widget.altText.isEmpty ? null : widget.altText,
      errorBuilder: (context, _, _) => _placeholder(context),
      frameBuilder: (context, child, frame, _) {
        // The image's own size is what keeps a drag proportional before any
        // size has been chosen.
        final stream = provider.resolve(createLocalImageConfiguration(context));
        stream.addListener(
          ImageStreamListener((info, _) {
            final size = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
            if (mounted && _intrinsic != size) {
              setState(() => _intrinsic = size);
            }
          }),
        );
        return child;
      },
    );
  }

  Widget _placeholder(BuildContext context) =>
      widget.placeholderBuilder?.call(context, widget.src) ??
      Container(
        constraints: const BoxConstraints(minWidth: 96, minHeight: 96),
        color: const Color(0x14000000),
        alignment: Alignment.center,
        child: Text(
          widget.altText.isEmpty ? '🖼' : widget.altText,
          textAlign: TextAlign.center,
        ),
      );

  Widget _outline(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3F8AE0), width: 1.5),
      ),
    ),
  );

  List<Widget> _handles(BuildContext context, Size size) => [
    Positioned.fill(child: _outline(context)),
    for (final handle in ImageHandle.values)
      _HandleDot(
        handle: handle,
        size: size,
        // The drag starts from what is on screen, not from what is stored:
        // grabbing a corner of an image that is being shown smaller than its
        // stored size would otherwise jump to that larger size first.
        onStart: (position) => _onDragStart(size, position),
        onUpdate: (position) => _onDragUpdate(handle, position),
        onEnd: _onDragEnd,
      ),
  ];

  Widget _caption(BuildContext context) {
    final caption = widget.caption;
    if (caption == null) {
      if (!widget.editable || !_showHandles) return const SizedBox.shrink();
      return _TextButton(
        label: 'Beschriftung hinzufügen',
        onTap: () => _setCaption(''),
      );
    }
    if (_editingCaption && widget.editable) {
      return _CaptionField(
        initial: caption,
        style: widget.captionStyle,
        onDone: _setCaption,
      );
    }
    return GestureDetector(
      onTap: widget.editable
          ? () => setState(() => _editingCaption = true)
          : null,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          caption.isEmpty ? 'Beschriftung…' : caption,
          style: widget.captionStyle,
        ),
      ),
    );
  }
}

/// One draggable square.
class _HandleDot extends StatelessWidget {
  const _HandleDot({
    required this.handle,
    required this.size,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final ImageHandle handle;
  final Size size;

  /// Both report the pointer's **global position**, not a distance.
  ///
  /// A handle is rebuilt on every frame of the drag, so it cannot remember
  /// where the drag began; only the state above it can.
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  static const double _dot = 10;

  @override
  Widget build(BuildContext context) {
    final x = switch (handle.horizontal) {
      < 0 => -_dot / 2,
      > 0 => size.width - _dot / 2,
      _ => size.width / 2 - _dot / 2,
    };
    final y = switch (handle.vertical) {
      < 0 => -_dot / 2,
      > 0 => size.height - _dot / 2,
      _ => size.height / 2 - _dot / 2,
    };
    return Positioned(
      left: x,
      top: y,
      child: MouseRegion(
        cursor: switch (handle) {
          ImageHandle.left ||
          ImageHandle.right => SystemMouseCursors.resizeLeftRight,
          ImageHandle.top ||
          ImageHandle.bottom => SystemMouseCursors.resizeUpDown,
          ImageHandle.topLeft ||
          ImageHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
          _ => SystemMouseCursors.resizeUpRightDownLeft,
        },
        child: GestureDetector(
          // The handle sits over the image, which has its own tap handler;
          // claiming the drag here keeps the two from fighting.
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details) => onStart(details.globalPosition),
          onPanUpdate: (details) => onUpdate(details.globalPosition),
          onPanEnd: (_) => onEnd(),
          child: Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(
              color: const Color(0xFF3F8AE0),
              border: Border.all(color: const Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF3F8AE0)),
      ),
    ),
  );
}

class _CaptionField extends StatefulWidget {
  const _CaptionField({
    required this.initial,
    required this.onDone,
    this.style,
  });

  final String initial;
  final TextStyle? style;

  /// Called with the caption, or `null` when it was emptied and removed.
  final ValueChanged<String?> onDone;

  @override
  State<_CaptionField> createState() => _CaptionFieldState();
}

class _CaptionFieldState extends State<_CaptionField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      // Leaving the field commits it: a caption that is lost because someone
      // clicked away is worse than one saved by accident.
      if (!_focusNode.hasFocus) _submit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    widget.onDone(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: EditableText(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      style: widget.style ?? const TextStyle(fontSize: 12),
      cursorColor: const Color(0xFF3F8AE0),
      backgroundCursorColor: const Color(0x33000000),
      onSubmitted: (_) => _submit(),
    ),
  );
}
