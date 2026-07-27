/// The widget an [ImageNode] is drawn with.
library;

import 'package:flutter/foundation.dart';
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
    'data' when uri.data != null => _DataUriImage(
      trimmed,
      uri.data!.contentAsBytes(),
    ),
    'asset' => AssetImage(uri.path),
    _ => null,
  };
}

/// A `data:` image identified by its URI rather than by the buffer it decoded
/// into.
///
/// `MemoryImage` compares its bytes by **identity**, and decoding a URI hands
/// back a fresh `Uint8List` every time — so a plain `MemoryImage` here was
/// never `==` to the one from the previous build. A widget that resolves its
/// provider each build then re-resolved on every frame, and an inline image
/// never settled long enough to report a size: it stayed invisible, and it
/// re-decoded its payload for as long as it was on screen. The URI is what
/// actually identifies the picture.
@immutable
class _DataUriImage extends MemoryImage {
  _DataUriImage(this.uri, super.bytes);

  /// The `data:` URI the bytes came from.
  final String uri;

  @override
  bool operator ==(Object other) =>
      other is _DataUriImage && other.uri == uri && other.scale == scale;

  @override
  int get hashCode => Object.hash(uri, scale);
}

/// How the selection chrome around an editable image is drawn.
///
/// The handles, the outline and the caption caret used to be one hard-coded
/// blue. That is a reasonable default and a wrong answer in any product with
/// an accent of its own — and the chrome is the most visible thing about
/// editing an image, so "close enough" reads as a component from somewhere
/// else.
@immutable
class LexicalImageStyle {
  /// Creates a chrome style. The defaults are the blue this always drew.
  const LexicalImageStyle({
    this.accent = const Color(0xFF3F8AE0),
    this.handleFill,
    this.handleBorder = const Color(0xFFFFFFFF),
    this.handleSize = 10,
    this.handleRadius = 0,
    this.outlineWidth = 1.5,
    this.handleShadows = const <BoxShadow>[],
  });

  /// The outline around a selected image, and the caption's caret.
  final Color accent;

  /// The fill of a drag handle. [accent] when omitted.
  final Color? handleFill;

  /// The ring around a drag handle, so it stays visible over the image.
  final Color handleBorder;

  /// Edge length of a drag handle, in logical pixels.
  final double handleSize;

  /// Corner radius of a drag handle. Zero is a square.
  final double handleRadius;

  /// Thickness of the outline.
  final double outlineWidth;

  /// Shadow cast by a handle, for chrome that has to read over a photograph.
  final List<BoxShadow> handleShadows;

  @override
  bool operator ==(Object other) =>
      other is LexicalImageStyle &&
      other.accent == accent &&
      other.handleFill == handleFill &&
      other.handleBorder == handleBorder &&
      other.handleSize == handleSize &&
      other.handleRadius == handleRadius &&
      other.outlineWidth == outlineWidth &&
      listEquals(other.handleShadows, handleShadows);

  @override
  int get hashCode => Object.hash(
    accent,
    handleFill,
    handleBorder,
    handleSize,
    handleRadius,
    outlineWidth,
    Object.hashAll(handleShadows),
  );
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
    this.style = const LexicalImageStyle(),
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

  /// How the selection chrome — outline, handles, caption caret — is drawn.
  final LexicalImageStyle style;

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

  /// What [LexicalImageView.src] resolved to, kept between builds.
  ImageProvider<Object>? _provider;

  /// The stream [_provider] resolved to, and the listener watching it.
  ///
  /// Held so that it can be **removed**. A listener that is added and never
  /// taken off keeps the completer alive in the application's image cache for
  /// as long as the process runs, and every call hands over a fresh handle on
  /// a decoded picture that nothing will ever release.
  ImageStream? _stream;
  ImageStreamListener? _listener;

  bool get _showHandles => widget.editable && (_hovered || _touched);

  Size? get _size {
    if (_dragging != null) return _dragging;
    // A non-positive dimension is not a size, it is the absence of one. The
    // node spells "the image's own size" `0` and this widget spells it `null`;
    // treating the two the same here means a caller that forwards the node's
    // value verbatim gets the image rather than a 0×0 box.
    final width = (widget.width ?? 0) > 0 ? widget.width : null;
    final height = (widget.height ?? 0) > 0 ? widget.height : null;
    // Nothing stored, but the image has told us how big it is: that is a size,
    // and until it counted as one an image that had never been resized had no
    // geometry to hang handles off — so the only image anyone ever wants to
    // resize, a freshly inserted one, was the one image that could not be.
    // Before the first frame decodes there is still nothing, which is what the
    // outline-only branch upstream draws.
    if (width == null && height == null) return _intrinsic;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant LexicalImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different address is a different picture, and the size of the last one
    // must not outlive it.
    if (widget.src != oldWidget.src) _intrinsic = null;
    _resolveImage();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  /// Points the size listener at whatever [LexicalImageView.src] resolves to
  /// now.
  ///
  /// Resolving **here** rather than in `build` is the whole point, and the
  /// reason is not tidiness. `ImageStream.addListener` calls its listener
  /// *synchronously* when the picture is already decoded — which it is every
  /// time but the first — and a listener that calls `setState` from inside a
  /// build throws. The completer catches that throw and reports it as an
  /// **image error**: a picture that had just loaded perfectly draws its
  /// placeholder instead, and an error is not something an image stream
  /// forgets.
  ///
  /// [State.didChangeDependencies] and [State.didUpdateWidget] are where the
  /// framework allows this call, which is where Flutter's own `Image` makes
  /// it.
  ///
  /// Resolving is also not free, and the cost is not the lookup: a provider
  /// whose picture is not in the cache **starts a fetch**. A provider behind
  /// an API has to evict itself when a request fails — otherwise one timeout
  /// is remembered as "this picture is broken" for the life of the process —
  /// so after a failure it is exactly the provider that is not in the cache.
  /// Asking it to resolve again is asking the server again. Once per rebuild
  /// is not a rate anything should be asked at.
  void _resolveImage() {
    final provider = widget.resolver(widget.src);
    // Already listening to exactly this picture. Note what is *not* asked:
    // whether the cache still holds it. It may well not — see above — and
    // asking would be the storm.
    if (provider == _provider && _stream != null) return;
    _provider = provider;
    if (provider == null) {
      _stopListening();
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    // The same picture as before: the listener already on it is the one that
    // would be added, so adding it again would only duplicate it.
    if (stream.key == _stream?.key) return;
    _stopListening();
    final listener = ImageStreamListener(_onImage, onError: _onImageError);
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  /// The image's own size is what keeps a drag proportional before any size
  /// has been chosen.
  void _onImage(ImageInfo info, bool synchronousCall) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    // A listener owns the handle it is given. Not disposing it holds a decoded
    // bitmap for the life of the process — once per frame, for a GIF.
    info.dispose();
    if (!mounted || _intrinsic == size) return;
    setState(() => _intrinsic = size);
  }

  /// A picture that cannot be loaded has no size to report; the [Image] below
  /// draws the placeholder.
  ///
  /// It is also **taken out of the image cache**, and that is the important
  /// part. Flutter's cache never forgets a failure: the completer that
  /// reported one stays in it, and every later request for that address — a
  /// different document, a different screen, an hour later — is answered with
  /// the remembered error rather than a request. One dropped connection then
  /// means that picture is broken until the application is restarted. Evicting
  /// makes the failure last exactly as long as the reason for it: the next
  /// time the image is built, it is fetched again.
  void _onImageError(Object _, StackTrace? _) {
    _provider?.evict().ignore();
    if (!mounted || _intrinsic == null) return;
    setState(() => _intrinsic = null);
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
    final provider = _provider;
    if (provider == null) return _placeholder(context);
    return Image(
      image: provider,
      fit: BoxFit.contain,
      semanticLabel: widget.altText.isEmpty ? null : widget.altText,
      errorBuilder: (context, _, _) => _placeholder(context),
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
        border: Border.all(
          color: widget.style.accent,
          width: widget.style.outlineWidth,
        ),
      ),
    ),
  );

  List<Widget> _handles(BuildContext context, Size size) => [
    Positioned.fill(child: _outline(context)),
    for (final handle in ImageHandle.values)
      _HandleDot(
        handle: handle,
        size: size,
        style: widget.style,
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
        color: widget.style.accent,
      );
    }
    if (_editingCaption && widget.editable) {
      return _CaptionField(
        initial: caption,
        style: widget.captionStyle,
        cursorColor: widget.style.accent,
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
    required this.style,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final ImageHandle handle;
  final Size size;
  final LexicalImageStyle style;

  /// Both report the pointer's **global position**, not a distance.
  ///
  /// A handle is rebuilt on every frame of the drag, so it cannot remember
  /// where the drag began; only the state above it can.
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final dot = style.handleSize;
    final x = switch (handle.horizontal) {
      < 0 => -dot / 2,
      > 0 => size.width - dot / 2,
      _ => size.width / 2 - dot / 2,
    };
    final y = switch (handle.vertical) {
      < 0 => -dot / 2,
      > 0 => size.height - dot / 2,
      _ => size.height / 2 - dot / 2,
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
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: style.handleFill ?? style.accent,
              border: Border.all(color: style.handleBorder),
              borderRadius: style.handleRadius > 0
                  ? BorderRadius.circular(style.handleRadius)
                  : null,
              boxShadow: style.handleShadows,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    ),
  );
}

class _CaptionField extends StatefulWidget {
  const _CaptionField({
    required this.initial,
    required this.onDone,
    required this.cursorColor,
    this.style,
  });

  final String initial;
  final TextStyle? style;

  /// Colour of the caret while the caption is being written.
  final Color cursorColor;

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
      cursorColor: widget.cursorColor,
      backgroundCursorColor: const Color(0x33000000),
      onSubmitted: (_) => _submit(),
    ),
  );
}
