/// CSS colour and length values, parsed without a rendering layer.
///
/// The model keeps CSS verbatim; these are the building blocks for code that
/// has to *read* it — a renderer, an importer deciding what to keep. They are
/// plain Dart on purpose: a colour is an ARGB integer here, and turning it
/// into a `Color` is the render layer's job.
library;

/// Parses a CSS colour into a 32-bit ARGB integer (`0xAARRGGBB`).
///
/// Understands `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`/`rgba()` with
/// comma or space separated channels (numbers or percentages), `transparent`
/// and the CSS named colours. Anything else — `currentColor`, `hsl()`, a
/// typo — answers `null`, which a caller treats as "not set". Never throws.
int? parseCssColorValue(String? value) {
  if (value == null) return null;
  final input = value.trim().toLowerCase();
  if (input.isEmpty || input.length > 64) return null;

  if (input.startsWith('#')) {
    final hex = input.substring(1);
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
    switch (hex.length) {
      case 3:
        return _argb('ff${_double(hex)}');
      case 4:
        final expanded = _double(hex);
        return _argb('${expanded.substring(6, 8)}${expanded.substring(0, 6)}');
      case 6:
        return _argb('ff$hex');
      case 8:
        return _argb('${hex.substring(6, 8)}${hex.substring(0, 6)}');
    }
    return null;
  }

  if (input == 'transparent') return 0x00000000;
  final named = _namedColors[input];
  if (named != null) return 0xFF000000 | named;

  final functional = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(input);
  if (functional == null) return null;
  final parts = functional
      .group(1)!
      .split(RegExp('[ ,/]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 3 || parts.length > 4) return null;
  final red = _channel(parts[0]);
  final green = _channel(parts[1]);
  final blue = _channel(parts[2]);
  if (red == null || green == null || blue == null) return null;
  var alpha = 255;
  if (parts.length == 4) {
    final raw = parts[3];
    final parsed = double.tryParse(raw.replaceAll('%', ''));
    if (parsed == null || !parsed.isFinite) return null;
    alpha = (raw.endsWith('%') ? parsed * 255 / 100 : parsed * 255)
        .round()
        .clamp(0, 255);
  }
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

String _double(String hex) => hex.split('').map((c) => '$c$c').join();

int? _argb(String hex) => int.tryParse(hex, radix: 16);

int? _channel(String raw) {
  if (raw.endsWith('%')) {
    final percent = double.tryParse(raw.substring(0, raw.length - 1));
    if (percent == null || !percent.isFinite) return null;
    return (percent * 255 / 100).round().clamp(0, 255);
  }
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) return null;
  return value.round().clamp(0, 255);
}

/// The largest length, in logical pixels, a parsed CSS value may take.
///
/// A style string is untrusted input, and `padding: 1e9px` is a layout that
/// never ends. Nothing a mail or a document means is wider than this.
const double maxCssLength = 10000;

/// Parses a CSS length into logical pixels.
///
/// `px` (and a bare number, which mail HTML writes for `0`), `pt` (× 4/3),
/// `em` and `rem` (× [emSize], 16 by default, the browser's default font
/// size). Percentages and `auto` are not lengths here and answer `null`;
/// [CssLength.parse] keeps them. Negative values answer `null`: the box
/// model this feeds has no use for them. Never throws.
double? parseCssPixels(String? value, {double emSize = 16}) {
  if (value == null) return null;
  final input = value.trim().toLowerCase();
  if (input.isEmpty || input.length > 32) return null;
  final match = RegExp(r'^(\d*\.?\d+)(px|pt|em|rem)?$').firstMatch(input);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null || !amount.isFinite) return null;
  final pixels = switch (match.group(2)) {
    null || 'px' => amount,
    'pt' => amount * 4 / 3,
    _ => amount * emSize,
  };
  return pixels.clamp(0, maxCssLength).toDouble();
}

/// The unit a [CssLength] is measured in.
enum CssLengthUnit {
  /// Logical pixels.
  px,

  /// A percentage of the containing block's width.
  percent,
}

/// A width: an absolute length in pixels or a percentage.
final class CssLength {
  /// Creates a length.
  const CssLength(this.value, this.unit);

  /// Parses `Npx`, `Npt`, `Nem`, a bare number or `N%`. `auto` and anything
  /// else answer `null`.
  static CssLength? parse(String? value) {
    if (value == null) return null;
    final input = value.trim().toLowerCase();
    if (input.endsWith('%')) {
      final amount = double.tryParse(input.substring(0, input.length - 1));
      if (amount == null || !amount.isFinite || amount < 0) return null;
      return CssLength(amount.clamp(0, 100).toDouble(), CssLengthUnit.percent);
    }
    final pixels = parseCssPixels(input);
    return pixels == null ? null : CssLength(pixels, CssLengthUnit.px);
  }

  /// The amount, in [unit].
  final double value;

  /// Pixels or percent.
  final CssLengthUnit unit;

  /// The length in pixels against a containing block [available] wide.
  double resolve(double available) =>
      unit == CssLengthUnit.px ? value : available * value / 100;

  @override
  bool operator ==(Object other) =>
      other is CssLength && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() =>
      unit == CssLengthUnit.px ? '${value}px' : '$value%';
}

const Map<String, int> _namedColors = {
  'aliceblue': 0xf0f8ff,
  'antiquewhite': 0xfaebd7,
  'aqua': 0x00ffff,
  'aquamarine': 0x7fffd4,
  'azure': 0xf0ffff,
  'beige': 0xf5f5dc,
  'bisque': 0xffe4c4,
  'black': 0x000000,
  'blanchedalmond': 0xffebcd,
  'blue': 0x0000ff,
  'blueviolet': 0x8a2be2,
  'brown': 0xa52a2a,
  'burlywood': 0xdeb887,
  'cadetblue': 0x5f9ea0,
  'chartreuse': 0x7fff00,
  'chocolate': 0xd2691e,
  'coral': 0xff7f50,
  'cornflowerblue': 0x6495ed,
  'cornsilk': 0xfff8dc,
  'crimson': 0xdc143c,
  'cyan': 0x00ffff,
  'darkblue': 0x00008b,
  'darkcyan': 0x008b8b,
  'darkgoldenrod': 0xb8860b,
  'darkgray': 0xa9a9a9,
  'darkgreen': 0x006400,
  'darkgrey': 0xa9a9a9,
  'darkkhaki': 0xbdb76b,
  'darkmagenta': 0x8b008b,
  'darkolivegreen': 0x556b2f,
  'darkorange': 0xff8c00,
  'darkorchid': 0x9932cc,
  'darkred': 0x8b0000,
  'darksalmon': 0xe9967a,
  'darkseagreen': 0x8fbc8f,
  'darkslateblue': 0x483d8b,
  'darkslategray': 0x2f4f4f,
  'darkslategrey': 0x2f4f4f,
  'darkturquoise': 0x00ced1,
  'darkviolet': 0x9400d3,
  'deeppink': 0xff1493,
  'deepskyblue': 0x00bfff,
  'dimgray': 0x696969,
  'dimgrey': 0x696969,
  'dodgerblue': 0x1e90ff,
  'firebrick': 0xb22222,
  'floralwhite': 0xfffaf0,
  'forestgreen': 0x228b22,
  'fuchsia': 0xff00ff,
  'gainsboro': 0xdcdcdc,
  'ghostwhite': 0xf8f8ff,
  'gold': 0xffd700,
  'goldenrod': 0xdaa520,
  'gray': 0x808080,
  'green': 0x008000,
  'greenyellow': 0xadff2f,
  'grey': 0x808080,
  'honeydew': 0xf0fff0,
  'hotpink': 0xff69b4,
  'indianred': 0xcd5c5c,
  'indigo': 0x4b0082,
  'ivory': 0xfffff0,
  'khaki': 0xf0e68c,
  'lavender': 0xe6e6fa,
  'lavenderblush': 0xfff0f5,
  'lawngreen': 0x7cfc00,
  'lemonchiffon': 0xfffacd,
  'lightblue': 0xadd8e6,
  'lightcoral': 0xf08080,
  'lightcyan': 0xe0ffff,
  'lightgoldenrodyellow': 0xfafad2,
  'lightgray': 0xd3d3d3,
  'lightgreen': 0x90ee90,
  'lightgrey': 0xd3d3d3,
  'lightpink': 0xffb6c1,
  'lightsalmon': 0xffa07a,
  'lightseagreen': 0x20b2aa,
  'lightskyblue': 0x87cefa,
  'lightslategray': 0x778899,
  'lightslategrey': 0x778899,
  'lightsteelblue': 0xb0c4de,
  'lightyellow': 0xffffe0,
  'lime': 0x00ff00,
  'limegreen': 0x32cd32,
  'linen': 0xfaf0e6,
  'magenta': 0xff00ff,
  'maroon': 0x800000,
  'mediumaquamarine': 0x66cdaa,
  'mediumblue': 0x0000cd,
  'mediumorchid': 0xba55d3,
  'mediumpurple': 0x9370db,
  'mediumseagreen': 0x3cb371,
  'mediumslateblue': 0x7b68ee,
  'mediumspringgreen': 0x00fa9a,
  'mediumturquoise': 0x48d1cc,
  'mediumvioletred': 0xc71585,
  'midnightblue': 0x191970,
  'mintcream': 0xf5fffa,
  'mistyrose': 0xffe4e1,
  'moccasin': 0xffe4b5,
  'navajowhite': 0xffdead,
  'navy': 0x000080,
  'oldlace': 0xfdf5e6,
  'olive': 0x808000,
  'olivedrab': 0x6b8e23,
  'orange': 0xffa500,
  'orangered': 0xff4500,
  'orchid': 0xda70d6,
  'palegoldenrod': 0xeee8aa,
  'palegreen': 0x98fb98,
  'paleturquoise': 0xafeeee,
  'palevioletred': 0xdb7093,
  'papayawhip': 0xffefd5,
  'peachpuff': 0xffdab9,
  'peru': 0xcd853f,
  'pink': 0xffc0cb,
  'plum': 0xdda0dd,
  'powderblue': 0xb0e0e6,
  'purple': 0x800080,
  'rebeccapurple': 0x663399,
  'red': 0xff0000,
  'rosybrown': 0xbc8f8f,
  'royalblue': 0x4169e1,
  'saddlebrown': 0x8b4513,
  'salmon': 0xfa8072,
  'sandybrown': 0xf4a460,
  'seagreen': 0x2e8b57,
  'seashell': 0xfff5ee,
  'sienna': 0xa0522d,
  'silver': 0xc0c0c0,
  'skyblue': 0x87ceeb,
  'slateblue': 0x6a5acd,
  'slategray': 0x708090,
  'slategrey': 0x708090,
  'snow': 0xfffafa,
  'springgreen': 0x00ff7f,
  'steelblue': 0x4682b4,
  'tan': 0xd2b48c,
  'teal': 0x008080,
  'thistle': 0xd8bfd8,
  'tomato': 0xff6347,
  'turquoise': 0x40e0d0,
  'violet': 0xee82ee,
  'wheat': 0xf5deb3,
  'white': 0xffffff,
  'whitesmoke': 0xf5f5f5,
  'yellow': 0xffff00,
  'yellowgreen': 0x9acd32,
};
