import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_image/lexical_image.dart';

/// The canonical example from blurha.sh — 4×3 components, 28 characters.
const String _example = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

/// One flat colour, derived from the format rather than copied from anywhere.
///
/// `L` is the size flag for 4×3 components (`3 + 2·9 = 21`), `0` a quantised
/// maximum of zero, `M{oP` the base-83 of `0xC85028` — sRGB(200, 80, 40) — and
/// `fQ` the quantised "no detail" term `(9, 9, 9)`. Every AC term being neutral
/// means this must decode to exactly its DC colour, which is what makes it a
/// sharp assertion rather than an approximate one.
final String _flat = 'L0M{oP${'fQ' * 11}';

/// Bright on the left, dark on the right, derived the same way.
///
/// `~` is a quantised maximum of 82 (so `maximumValue` is 0.5), `Eyb[` is
/// mid-grey sRGB(128, 128, 128), and `~q` sets the *first horizontal* term to
/// its largest positive value. That term's basis is `cos(πx/width)`: `+1` at
/// the left edge, `−1` at the right.
final String _leftBright = 'L~Eyb[~q${'fQ' * 10}';

({int r, int g, int b}) _pixel(Uint8List pixels, int index) => (
  r: pixels[index * 4],
  g: pixels[index * 4 + 1],
  b: pixels[index * 4 + 2],
);

int _luma(({int r, int g, int b}) pixel) => pixel.r + pixel.g + pixel.b;

void main() {
  group('isBlurHash', () {
    test('accepts a hash whose length matches its size flag', () {
      expect(isBlurHash(_example), isTrue);
      expect(isBlurHash(_flat), isTrue);
    });

    test('rejects what is not one', () {
      // Empty, too short, a character outside the alphabet, a truncated hash,
      // and a path that ended up in the wrong field — every way a value
      // arriving inside a document can fail to be a BlurHash.
      expect(isBlurHash(''), isFalse);
      expect(isBlurHash('abc'), isFalse);
      expect(isBlurHash('LEHV6nWB2yk8pyo0adR*.7kCMdn"'), isFalse);
      expect(isBlurHash(_example.substring(0, _example.length - 2)), isFalse);
      expect(isBlurHash('/api/v1/media/1234'), isFalse);
    });
  });

  group('blurHashPixels', () {
    test('decodes to opaque RGBA of the requested size', () {
      final pixels = blurHashPixels(_example, width: 8, height: 6);

      expect(pixels, isNotNull);
      expect(pixels!.length, 8 * 6 * 4);
      for (var i = 3; i < pixels.length; i += 4) {
        expect(pixels[i], 255, reason: 'alpha at byte $i');
      }
    });

    test('a flat hash decodes to exactly its colour', () {
      final pixels = blurHashPixels(_flat, width: 4, height: 4)!;

      for (var i = 0; i < 16; i++) {
        final pixel = _pixel(pixels, i);
        // ±1 for the 8-bit round trip through linear light. A missing sRGB
        // conversion or a swapped channel misses this by tens of levels.
        expect(pixel.r, closeTo(200, 1), reason: 'red at $i');
        expect(pixel.g, closeTo(80, 1), reason: 'green at $i');
        expect(pixel.b, closeTo(40, 1), reason: 'blue at $i');
      }
    });

    test('a picture keeps its orientation', () {
      final pixels = blurHashPixels(_leftBright, width: 8, height: 4)!;

      // Left edge against right edge, on the middle row: a transposed or
      // mirrored basis function shows up here and nowhere else.
      expect(_luma(_pixel(pixels, 8)), greaterThan(_luma(_pixel(pixels, 15))));
      // Flat vertically: the same column in two rows is the same colour.
      expect(_pixel(pixels, 0).r, _pixel(pixels, 24).r);
    });

    test('a malformed hash costs the placeholder, not the frame', () {
      expect(blurHashPixels('not-a-hash', width: 4, height: 4), isNull);
      expect(blurHashPixels('', width: 4, height: 4), isNull);
      expect(blurHashPixels(_example, width: 0, height: 4), isNull);
    });
  });

  group('BlurHashImage', () {
    testWidgets('paints without touching the network', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 120,
            height: 80,
            child: Image(image: BlurHashImage(_example), fit: BoxFit.cover),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    });

    test('two providers for the same hash are the same key', () {
      // Or every rebuild would decode the hash again.
      expect(const BlurHashImage(_example), const BlurHashImage(_example));
      expect(
        const BlurHashImage(_example).hashCode,
        const BlurHashImage(_example).hashCode,
      );
      expect(
        const BlurHashImage(_example),
        isNot(const BlurHashImage(_example, decodeWidth: 16)),
      );
    });
  });
}
