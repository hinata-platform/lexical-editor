/// Decoding the BlurHash an image node can carry.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The format's alphabet — a character's index is its digit value.
const String _alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    r'#$%*+,-.:;=?@[]^_{|}~';

/// Whether [hash] could be a BlurHash.
///
/// Cheap enough to call on every build: it checks the length the hash's own
/// size flag promises and that every character is a base-83 digit, which is
/// what separates a real hash from a truncated one, from a URL that ended up
/// in the wrong field, or from an empty string.
bool isBlurHash(String hash) {
  if (hash.length < 6) return false;
  final sizeFlag = _decode83(hash, 0, 1);
  if (sizeFlag < 0) return false;
  final numX = sizeFlag % 9 + 1;
  final numY = sizeFlag ~/ 9 + 1;
  if (hash.length != 4 + 2 * numX * numY) return false;
  return _decode83(hash, 0, hash.length) >= 0;
}

/// An [ImageProvider] that paints a BlurHash.
///
/// The picture it stands in for is not fetched, not cached and not waited on:
/// the ~30 characters *are* the picture, at [decodeWidth]×[decodeHeight]
/// pixels, which is why it can be drawn in the very first frame.
///
/// The algorithm is implemented here rather than taken from a package. It is a
/// hundred lines of arithmetic that has not changed since it was published,
/// and a placeholder is not worth a dependency in every application that draws
/// an image.
@immutable
class BlurHashImage extends ImageProvider<BlurHashImage> {
  /// Creates a provider for [blurHash].
  const BlurHashImage(
    this.blurHash, {
    this.decodeWidth = 32,
    this.decodeHeight = 32,
    this.scale = 1.0,
  }) : assert(decodeWidth > 0, 'decodeWidth must be positive'),
       assert(decodeHeight > 0, 'decodeHeight must be positive');

  /// The hash, as it travels in the document.
  final String blurHash;

  /// Width of the decoded bitmap. Small on purpose: it is stretched to
  /// whatever box it fills, and every high frequency is gone regardless.
  final int decodeWidth;

  /// Height of the decoded bitmap.
  final int decodeHeight;

  /// Pixel density reported for the decoded image.
  final double scale;

  @override
  Future<BlurHashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BlurHashImage>(this);

  @override
  ImageStreamCompleter loadImage(
    BlurHashImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    _decode(key),
    informationCollector: () => [ErrorDescription('BlurHash: ${key.blurHash}')],
  );

  static Future<ImageInfo> _decode(BlurHashImage key) async {
    final pixels = blurHashPixels(
      key.blurHash,
      width: key.decodeWidth,
      height: key.decodeHeight,
    );
    if (pixels == null) {
      throw ArgumentError.value(key.blurHash, 'blurHash', 'not a BlurHash');
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      key.decodeWidth,
      key.decodeHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return ImageInfo(image: await completer.future, scale: key.scale);
  }

  @override
  bool operator ==(Object other) =>
      other is BlurHashImage &&
      other.blurHash == blurHash &&
      other.decodeWidth == decodeWidth &&
      other.decodeHeight == decodeHeight &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(blurHash, decodeWidth, decodeHeight, scale);

  @override
  String toString() => 'BlurHashImage("$blurHash")';
}

/// Decodes [hash] into [width]×[height] RGBA pixels, or null when it is not a
/// BlurHash.
///
/// Null rather than an exception: a document is untrusted input, and a
/// malformed hash inside one should cost the placeholder, not the frame.
Uint8List? blurHashPixels(
  String hash, {
  required int width,
  required int height,
  double punch = 1,
}) {
  if (width <= 0 || height <= 0 || !isBlurHash(hash)) return null;

  final sizeFlag = _decode83(hash, 0, 1);
  final numX = sizeFlag % 9 + 1;
  final numY = sizeFlag ~/ 9 + 1;
  final maximumValue = (_decode83(hash, 1, 2) + 1) / 166;

  // Every component in linear light: index 0 is the image's average colour
  // (stored verbatim), the rest are the detail terms.
  final colours = <List<double>>[
    _decodeDc(_decode83(hash, 2, 6)),
    for (var i = 1; i < numX * numY; i++)
      _decodeAc(_decode83(hash, 4 + i * 2, 6 + i * 2), maximumValue * punch),
  ];

  // Cosines depend only on the axis, so they are computed once per row and
  // column instead of once per pixel and component — the difference between a
  // handful of multiplications per pixel and a few thousand.
  final cosX = List<List<double>>.generate(
    width,
    (x) => List<double>.generate(
      numX,
      (i) => math.cos(math.pi * x * i / width),
      growable: false,
    ),
    growable: false,
  );
  final cosY = List<List<double>>.generate(
    height,
    (y) => List<double>.generate(
      numY,
      (j) => math.cos(math.pi * y * j / height),
      growable: false,
    ),
    growable: false,
  );

  final pixels = Uint8List(width * height * 4);
  var offset = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      for (var j = 0; j < numY; j++) {
        for (var i = 0; i < numX; i++) {
          final basis = cosX[x][i] * cosY[y][j];
          final colour = colours[i + j * numX];
          r += colour[0] * basis;
          g += colour[1] * basis;
          b += colour[2] * basis;
        }
      }
      pixels[offset++] = _linearTosRgb(r);
      pixels[offset++] = _linearTosRgb(g);
      pixels[offset++] = _linearTosRgb(b);
      pixels[offset++] = 255;
    }
  }
  return pixels;
}

List<double> _decodeDc(int value) => [
  _sRgbToLinear((value >> 16) & 0xFF),
  _sRgbToLinear((value >> 8) & 0xFF),
  _sRgbToLinear(value & 0xFF),
];

List<double> _decodeAc(int value, double maximumValue) {
  final r = value ~/ (19 * 19);
  final g = (value ~/ 19) % 19;
  final b = value % 19;
  return [
    _signedSquare((r - 9) / 9) * maximumValue,
    _signedSquare((g - 9) / 9) * maximumValue,
    _signedSquare((b - 9) / 9) * maximumValue,
  ];
}

/// `sign(value) · value²` — the format's quantisation curve.
double _signedSquare(double value) => value * value * (value < 0 ? -1 : 1);

double _sRgbToLinear(int value) {
  final v = value / 255;
  if (v <= 0.04045) return v / 12.92;
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

int _linearTosRgb(double value) {
  final v = value.clamp(0.0, 1.0);
  if (v <= 0.0031308) return (v * 12.92 * 255 + 0.5).toInt();
  final s = 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  return (s * 255 + 0.5).toInt();
}

/// The base-83 value of `hash[from..to)`, or -1 when a character is not one of
/// the alphabet's digits.
int _decode83(String hash, int from, int to) {
  var value = 0;
  for (var i = from; i < to; i++) {
    final digit = _alphabet.indexOf(hash[i]);
    if (digit < 0) return -1;
    value = value * 83 + digit;
  }
  return value;
}
