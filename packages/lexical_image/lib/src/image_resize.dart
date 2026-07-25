/// The arithmetic of resizing, kept away from the widget that uses it.
library;

import 'dart:ui';

import 'package:meta/meta.dart';

/// Which handle is being dragged.
enum ImageHandle {
  /// The top-left corner.
  topLeft,

  /// The middle of the top edge.
  top,

  /// The top-right corner.
  topRight,

  /// The middle of the right edge.
  right,

  /// The bottom-right corner.
  bottomRight,

  /// The middle of the bottom edge.
  bottom,

  /// The bottom-left corner.
  bottomLeft,

  /// The middle of the left edge.
  left;

  /// How a horizontal drag changes the width: -1, 0 or 1.
  double get horizontal => switch (this) {
    ImageHandle.topLeft || ImageHandle.left || ImageHandle.bottomLeft => -1,
    ImageHandle.topRight || ImageHandle.right || ImageHandle.bottomRight => 1,
    ImageHandle.top || ImageHandle.bottom => 0,
  };

  /// How a vertical drag changes the height: -1, 0 or 1.
  double get vertical => switch (this) {
    ImageHandle.topLeft || ImageHandle.top || ImageHandle.topRight => -1,
    ImageHandle.bottomLeft ||
    ImageHandle.bottom ||
    ImageHandle.bottomRight => 1,
    ImageHandle.left || ImageHandle.right => 0,
  };

  /// Whether this handle drags in both directions at once.
  bool get isCorner => horizontal != 0 && vertical != 0;
}

/// How large an image is allowed to be.
///
/// A policy of the application, not of the document: the same image in a chat
/// bubble and in a full-width article has different limits, and storing them
/// with the image would freeze one app's layout into everyone else's copy.
@immutable
final class ImageSizeLimits {
  /// Creates limits. Defaults allow anything above a still-grabbable size.
  const ImageSizeLimits({
    this.minWidth = 48,
    this.minHeight = 48,
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
  }) : assert(minWidth > 0 && minHeight > 0, 'a size must be positive'),
       assert(
         maxWidth >= minWidth && maxHeight >= minHeight,
         'the maximum cannot be below the minimum',
       );

  /// The smallest width a user may drag to.
  final double minWidth;

  /// The smallest height a user may drag to.
  final double minHeight;

  /// The largest width a user may drag to.
  final double maxWidth;

  /// The largest height a user may drag to.
  final double maxHeight;

  /// [size] brought inside these limits, ignoring aspect ratio.
  Size clamp(Size size) => Size(
    size.width.clamp(minWidth, maxWidth),
    size.height.clamp(minHeight, maxHeight),
  );

  /// [size] brought inside these limits **keeping its shape**.
  ///
  /// Clamping the two axes separately would distort the image the moment one
  /// of them hits a limit — the picture stretches while the pointer keeps
  /// moving, which looks like a bug and is one. Scaling by the tightest of
  /// the four constraints keeps the ratio and lands inside the box.
  Size clampScaled(Size size, double aspectRatio) {
    if (size.width <= 0 || size.height <= 0 || aspectRatio <= 0) {
      return clamp(size);
    }
    var scale = 1.0;
    scale = _tighten(scale, maxWidth / size.width, below: true);
    scale = _tighten(scale, maxHeight / size.height, below: true);
    scale = _tighten(scale, minWidth / size.width, below: false);
    scale = _tighten(scale, minHeight / size.height, below: false);
    return Size(size.width * scale, size.height * scale);
  }

  static double _tighten(double scale, double limit, {required bool below}) {
    if (!limit.isFinite) return scale;
    if (below) return limit < scale ? limit : scale;
    return limit > scale ? limit : scale;
  }

  @override
  bool operator ==(Object other) =>
      other is ImageSizeLimits &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(minWidth, minHeight, maxWidth, maxHeight);
}

/// The size a drag of [delta] on [handle] produces, starting from [start].
///
/// With an [aspectRatio] the corner handles keep the image's shape and the
/// **larger** of the two movements wins, which is what makes a diagonal drag
/// feel like it follows the pointer rather than only its horizontal part.
/// Edge handles resize one axis and derive the other, so an image never
/// distorts by dragging its side either.
Size resizeImage({
  required Size start,
  required Offset delta,
  required ImageHandle handle,
  ImageSizeLimits limits = const ImageSizeLimits(),
  double? aspectRatio,
}) {
  if (aspectRatio == null || aspectRatio <= 0) {
    return limits.clamp(
      Size(
        start.width + delta.dx * handle.horizontal,
        start.height + delta.dy * handle.vertical,
      ),
    );
  }

  final byWidth = start.width + delta.dx * handle.horizontal;
  final byHeight = start.height + delta.dy * handle.vertical;
  final double width;
  if (!handle.isCorner) {
    width = handle.horizontal != 0 ? byWidth : byHeight * aspectRatio;
  } else {
    // Whichever axis the pointer moved further along is the one it meant.
    final horizontal = (delta.dx * handle.horizontal).abs();
    final vertical = (delta.dy * handle.vertical).abs();
    width = horizontal >= vertical ? byWidth : byHeight * aspectRatio;
  }
  return limits.clampScaled(Size(width, width / aspectRatio), aspectRatio);
}
