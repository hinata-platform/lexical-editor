/// A block's own box: background, padding, border, width.
///
/// Upstream Lexical has no block style field, but it does have NodeState, and
/// NodeState serializes under `"$"` on any node without the node type knowing.
/// A block's CSS travels there under the key `style`:
///
/// ```json
/// {"type": "paragraph", …,
///  "$": {"style": "background-color:#e60000;padding:16px"}}
/// ```
///
/// Lexical web preserves the entry on every element it round-trips, which is
/// what makes this a wire format rather than a private extension. The string is
/// kept verbatim in the model; [BlockCss.parse] is the reading of it.
library;

import 'css.dart';
import 'css_values.dart';
import 'node_state.dart';
import 'nodes/lexical_node.dart';

/// The NodeState key a block's CSS is stored under.
const String blockStyleStateKey = 'style';

/// The largest `--stack-below` width honoured, in logical pixels.
const double maxStackBelow = 2000;

/// The longest block style string that is interpreted.
///
/// Longer strings stay in the document, untouched, and render as if empty:
/// nothing the allowed properties express takes this much text.
const int maxBlockStyleLength = 512;

/// The CSS stored on [node] as its block style, or `''` when there is none.
String $getBlockStyle(LexicalNode node) {
  final value = node.getLatest<LexicalNode>().state?[blockStyleStateKey];
  return value is String ? value : '';
}

/// Stores [css] as [node]'s block style; an empty string removes it.
///
/// The value is kept verbatim, like a text node's `style`: what a renderer
/// understands is decided when it is read, not when it is written, so a
/// document round-trips through Lexical web unchanged.
T $setBlockStyle<T extends LexicalNode>(T node, String css) {
  final writable = node.getWritable<T>();
  // A clone of the same version shares its state container with the
  // committed node, so it is copied before the write rather than mutated.
  final state = writable.state?.copy() ?? NodeState();
  if (css.isEmpty) {
    state.remove(blockStyleStateKey);
  } else {
    state[blockStyleStateKey] = css;
  }
  writable.state = state.isEmpty ? null : state;
  return writable;
}

/// One side of a border.
final class CssBorderSide {
  /// Creates a side [width] pixels wide in [color] (ARGB).
  const CssBorderSide(this.width, this.color);

  /// Width in logical pixels.
  final double width;

  /// Colour as `0xAARRGGBB`.
  final int color;

  @override
  bool operator ==(Object other) =>
      other is CssBorderSide && other.width == width && other.color == color;

  @override
  int get hashCode => Object.hash(width, color);

  @override
  String toString() => 'CssBorderSide($width, 0x${color.toRadixString(16)})';
}

/// Four corner radii in pixels, in CSS order: top left, top right, bottom
/// right, bottom left.
final class CssCorners {
  /// Creates corner radii.
  const CssCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The same radius on every corner.
  const CssCorners.all(double radius)
    : topLeft = radius,
      topRight = radius,
      bottomRight = radius,
      bottomLeft = radius;

  /// Reads `border-radius`: one to four lengths, the CSS shorthand order.
  /// The elliptical form `a / b` keeps its horizontal radii. `null` when a
  /// value does not parse.
  static CssCorners? _parse(String value) {
    final horizontal = value.split('/').first.trim();
    final parts = horizontal
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(parseCssPixels)
        .toList();
    if (parts.isEmpty || parts.length > 4 || parts.contains(null)) return null;
    final a = parts[0]!;
    final b = parts.length > 1 ? parts[1]! : a;
    final c = parts.length > 2 ? parts[2]! : a;
    final d = parts.length > 3 ? parts[3]! : b;
    return CssCorners(topLeft: a, topRight: b, bottomRight: c, bottomLeft: d);
  }

  /// Top left radius.
  final double topLeft;

  /// Top right radius.
  final double topRight;

  /// Bottom right radius.
  final double bottomRight;

  /// Bottom left radius.
  final double bottomLeft;

  /// Whether every corner has the same radius.
  bool get isUniform =>
      topLeft == topRight && topLeft == bottomRight && topLeft == bottomLeft;

  /// Whether no corner is rounded.
  bool get isZero =>
      topLeft <= 0 && topRight <= 0 && bottomRight <= 0 && bottomLeft <= 0;

  @override
  bool operator ==(Object other) =>
      other is CssCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'CssCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// Four pixel lengths, one per edge, each possibly unset.
final class CssEdges {
  /// Creates edges.
  const CssEdges({this.top, this.right, this.bottom, this.left});

  /// Top edge, or `null` when unset.
  final double? top;

  /// Right edge, or `null` when unset.
  final double? right;

  /// Bottom edge, or `null` when unset.
  final double? bottom;

  /// Left edge, or `null` when unset.
  final double? left;

  /// Whether no edge is set.
  bool get isEmpty =>
      top == null && right == null && bottom == null && left == null;

  CssEdges _with({double? top, double? right, double? bottom, double? left}) =>
      CssEdges(
        top: top ?? this.top,
        right: right ?? this.right,
        bottom: bottom ?? this.bottom,
        left: left ?? this.left,
      );

  @override
  bool operator ==(Object other) =>
      other is CssEdges &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'CssEdges($top, $right, $bottom, $left)';
}

/// The block style properties a renderer understands, parsed.
///
/// The allowed subset: `background-color`, `color`, `padding` and its
/// longhands, `margin-top`, `margin-bottom`, horizontal centring through
/// `auto` margins, `max-width`, `width` (pixels, percent or `fit-content`),
/// `border-radius`, `--stack-below` (see [BlockCss.stackBelow]), and
/// `border` with its `-top`/`-right`/`-bottom`/`-left` longhands written
/// as `<width> <style> <colour>`. Everything else is ignored. Alignment is not
/// here: it is the element's own `format`, as upstream has it.
///
/// Pure Dart: colours are ARGB integers and lengths are pixels. Turning them
/// into a decoration is the render layer's work.
final class BlockCss {
  /// Creates a parsed block style. Every property is optional.
  const BlockCss({
    this.backgroundColor,
    this.color,
    this.padding = const CssEdges(),
    this.marginTop,
    this.marginBottom,
    this.maxWidth,
    this.width,
    this.centered = false,
    this.fitContent = false,
    this.stackBelow,
    this.borderRadius,
    this.borderTop,
    this.borderRight,
    this.borderBottom,
    this.borderLeft,
  });

  /// The style with nothing set.
  static const BlockCss empty = BlockCss();

  /// Parses [css], keeping the allowed properties. Never throws.
  ///
  /// A string longer than [maxBlockStyleLength] parses as [empty]. Later
  /// declarations override earlier ones, longhands refine shorthands, and a
  /// value that does not parse leaves the property as it was — the cascade
  /// rules of an inline `style` attribute, for the properties kept.
  static BlockCss parse(String css) {
    if (css.isEmpty || css.length > maxBlockStyleLength) return empty;
    final Map<String, String> declarations;
    try {
      declarations = getStyleObjectFromCss(css);
    } on Object {
      return empty;
    }
    if (declarations.isEmpty) return empty;

    int? backgroundColor;
    int? color;
    var padding = const CssEdges();
    double? marginTop;
    double? marginBottom;
    double? maxWidth;
    CssLength? width;
    var fitContent = false;
    double? stackBelow;
    bool? centeredLeft;
    bool? centeredRight;
    CssCorners? borderRadius;
    CssBorderSide? borderTop;
    CssBorderSide? borderRight;
    CssBorderSide? borderBottom;
    CssBorderSide? borderLeft;

    for (final entry in declarations.entries) {
      final name = entry.key.toLowerCase();
      final value = entry.value.replaceAll(
        RegExp(r'\s*!important\s*$', caseSensitive: false),
        '',
      );
      switch (name) {
        case 'background-color' || 'background':
          // `background` is a shorthand that mail HTML uses for a plain
          // colour more often than not; any other form simply fails to parse.
          backgroundColor = parseCssColorValue(value) ?? backgroundColor;
        case 'color':
          color = parseCssColorValue(value) ?? color;
        case 'padding':
          final edges = _boxValues(value);
          if (edges != null) padding = edges;
        case 'padding-top':
          padding = padding._with(top: parseCssPixels(value));
        case 'padding-right':
          padding = padding._with(right: parseCssPixels(value));
        case 'padding-bottom':
          padding = padding._with(bottom: parseCssPixels(value));
        case 'padding-left':
          padding = padding._with(left: parseCssPixels(value));
        case 'margin':
          final parts = _split(value);
          if (parts.isEmpty || parts.length > 4) break;
          final top = parts[0];
          final right = parts.length > 1 ? parts[1] : top;
          final bottom = parts.length > 2 ? parts[2] : top;
          final left = parts.length > 3 ? parts[3] : right;
          marginTop = parseCssPixels(top) ?? marginTop;
          marginBottom = parseCssPixels(bottom) ?? marginBottom;
          centeredLeft = _isAuto(left);
          centeredRight = _isAuto(right);
        case 'margin-top':
          marginTop = parseCssPixels(value) ?? marginTop;
        case 'margin-bottom':
          marginBottom = parseCssPixels(value) ?? marginBottom;
        case 'margin-left':
          centeredLeft = _isAuto(value);
        case 'margin-right':
          centeredRight = _isAuto(value);
        case 'max-width':
          maxWidth = parseCssPixels(value) ?? maxWidth;
        case 'width':
          final keyword = value.trim().toLowerCase();
          if (keyword == 'fit-content' || keyword == '-moz-fit-content') {
            fitContent = true;
            width = null;
          } else {
            final parsed = CssLength.parse(value);
            if (parsed != null) {
              width = parsed;
              fitContent = false;
            } else if (keyword == 'auto') {
              width = null;
              fitContent = false;
            }
          }
        case '--stack-below':
          final pixels = parseCssPixels(value);
          if (pixels != null) {
            // Past the bound it is dropped rather than clamped, which is
            // what the server's reading does too.
            stackBelow = pixels > maxStackBelow ? null : pixels;
          }
        case 'border-radius':
          borderRadius = CssCorners._parse(value) ?? borderRadius;
        case 'border':
          final side = _borderSide(value);
          if (side != null) {
            borderTop = borderRight = borderBottom = borderLeft = side.$1;
          }
        case 'border-top':
          borderTop = _sideOr(value, borderTop);
        case 'border-right':
          borderRight = _sideOr(value, borderRight);
        case 'border-bottom':
          borderBottom = _sideOr(value, borderBottom);
        case 'border-left':
          borderLeft = _sideOr(value, borderLeft);
      }
    }

    return BlockCss(
      backgroundColor: backgroundColor,
      color: color,
      padding: padding,
      marginTop: marginTop,
      marginBottom: marginBottom,
      maxWidth: maxWidth,
      width: width,
      centered: (centeredLeft ?? false) && (centeredRight ?? false),
      fitContent: fitContent,
      stackBelow: stackBelow,
      borderRadius: borderRadius,
      borderTop: _visible(borderTop),
      borderRight: _visible(borderRight),
      borderBottom: _visible(borderBottom),
      borderLeft: _visible(borderLeft),
    );
  }

  /// Fill behind the block, as `0xAARRGGBB`.
  final int? backgroundColor;

  /// Default text colour for the block's content, as `0xAARRGGBB`.
  final int? color;

  /// Space between the border and the content.
  final CssEdges padding;

  /// Space above the block.
  final double? marginTop;

  /// Space below the block.
  final double? marginBottom;

  /// The widest the block may be, in pixels.
  final double? maxWidth;

  /// The block's preferred width.
  final CssLength? width;

  /// Whether both horizontal margins are `auto`, centring the block.
  final bool centered;

  /// Whether the block is as wide as its content (`width:fit-content`)
  /// rather than as wide as its container — a mail's button.
  ///
  /// It is centred by `auto` margins or by its parent's `center` format,
  /// and never wider than the space it is given.
  final bool fitContent;

  /// The width, in logical pixels, below which a layout container stacks
  /// its columns — the custom property `--stack-below:<N>px`.
  ///
  /// A mail's media query, kept as data: MJML columns stack on a phone, the
  /// cells of a row of icons do not, and only the converter that saw the
  /// source can tell the two apart. Unset means this rule never stacks.
  /// Bounded to [maxStackBelow].
  final double? stackBelow;

  /// Corner radii in pixels.
  final CssCorners? borderRadius;

  /// Top border, or `null` for none.
  final CssBorderSide? borderTop;

  /// Right border, or `null` for none.
  final CssBorderSide? borderRight;

  /// Bottom border, or `null` for none.
  final CssBorderSide? borderBottom;

  /// Left border, or `null` for none.
  final CssBorderSide? borderLeft;

  /// Whether any border side is drawn.
  bool get hasBorder =>
      borderTop != null ||
      borderRight != null ||
      borderBottom != null ||
      borderLeft != null;

  /// Whether nothing is set.
  bool get isEmpty =>
      backgroundColor == null &&
      color == null &&
      padding.isEmpty &&
      marginTop == null &&
      marginBottom == null &&
      maxWidth == null &&
      width == null &&
      !centered &&
      !fitContent &&
      stackBelow == null &&
      borderRadius == null &&
      !hasBorder;

  /// Whether the block draws a box: a fill, a border or padding.
  bool get hasBox => backgroundColor != null || hasBorder || !padding.isEmpty;

  /// The style as canonical CSS, holding only the allowed properties.
  ///
  /// What an importer stores: whatever the source wrote — shorthands,
  /// legacy attributes, properties nobody draws — comes out as the subset a
  /// renderer reads, in one spelling. `BlockCss.parse(css.toCss()) == css`.
  String toCss() {
    final parts = <String>[];
    final background = backgroundColor;
    if (background != null) parts.add('background-color:${_color(background)}');
    final text = color;
    if (text != null) parts.add('color:${_color(text)}');
    if (!padding.isEmpty) {
      parts.add(
        'padding:${_px(padding.top ?? 0)} ${_px(padding.right ?? 0)} '
        '${_px(padding.bottom ?? 0)} ${_px(padding.left ?? 0)}',
      );
    }
    if (marginTop != null) parts.add('margin-top:${_px(marginTop!)}');
    if (marginBottom != null) parts.add('margin-bottom:${_px(marginBottom!)}');
    if (centered) parts.add('margin-left:auto;margin-right:auto');
    if (maxWidth != null) parts.add('max-width:${_px(maxWidth!)}');
    final w = width;
    if (w != null) {
      parts.add(
        w.unit == CssLengthUnit.px
            ? 'width:${_px(w.value)}'
            : 'width:${_number(w.value)}%',
      );
    }
    if (fitContent) parts.add('width:fit-content');
    if (stackBelow != null) parts.add('--stack-below:${_px(stackBelow!)}');
    final radius = borderRadius;
    if (radius != null) {
      parts.add(
        radius.isUniform
            ? 'border-radius:${_px(radius.topLeft)}'
            : 'border-radius:${_px(radius.topLeft)} ${_px(radius.topRight)} '
                  '${_px(radius.bottomRight)} ${_px(radius.bottomLeft)}',
      );
    }
    for (final (name, side) in [
      ('top', borderTop),
      ('right', borderRight),
      ('bottom', borderBottom),
      ('left', borderLeft),
    ]) {
      if (side != null) {
        parts.add(
          'border-$name:${_px(side.width)} solid ${_color(side.color)}',
        );
      }
    }
    return parts.join(';');
  }

  static String _number(double value) {
    final rounded = (value * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
  }

  static String _px(double value) => '${_number(value)}px';

  static String _color(int argb) {
    final alpha = (argb >> 24) & 0xFF;
    final rgb = argb & 0xFFFFFF;
    if (alpha == 0xFF) return '#${rgb.toRadixString(16).padLeft(6, '0')}';
    return 'rgba(${(rgb >> 16) & 0xFF},${(rgb >> 8) & 0xFF},${rgb & 0xFF},'
        '${_number(alpha / 255)})';
  }

  static List<String> _split(String value) =>
      value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

  static bool _isAuto(String value) => value.trim().toLowerCase() == 'auto';

  static CssEdges? _boxValues(String value) {
    final parts = _split(value).map(parseCssPixels).toList();
    if (parts.isEmpty || parts.length > 4 || parts.contains(null)) return null;
    final top = parts[0]!;
    final right = parts.length > 1 ? parts[1]! : top;
    final bottom = parts.length > 2 ? parts[2]! : top;
    final left = parts.length > 3 ? parts[3]! : right;
    return CssEdges(top: top, right: right, bottom: bottom, left: left);
  }

  /// A border shorthand: `(side,)`, with a `null` side for "no border", or
  /// `null` when the value does not parse.
  static (CssBorderSide?,)? _borderSide(String value) {
    final parts = _split(value.toLowerCase());
    if (parts.isEmpty || parts.length > 3) return null;
    double? width;
    int? color;
    String? style;
    for (final part in parts) {
      if (_borderStyles.contains(part)) {
        style = part;
        continue;
      }
      final keyword = _borderWidths[part];
      final pixels = keyword ?? parseCssPixels(part);
      if (pixels != null && width == null) {
        width = pixels;
        continue;
      }
      final parsed = parseCssColorValue(part);
      if (parsed != null && color == null) {
        color = parsed;
        continue;
      }
      return null;
    }
    // CSS draws nothing for a border without a style; `none` and `hidden`
    // are explicit about it.
    if (style == null || style == 'none' || style == 'hidden') return (null,);
    return (CssBorderSide(width ?? 3, color ?? 0xFF000000),);
  }

  /// The side [value] declares, or [previous] when it does not parse.
  static CssBorderSide? _sideOr(String value, CssBorderSide? previous) {
    final parsed = _borderSide(value);
    return parsed == null ? previous : parsed.$1;
  }

  static CssBorderSide? _visible(CssBorderSide? side) =>
      side == null || side.width <= 0 ? null : side;

  static const Set<String> _borderStyles = {
    'none',
    'hidden',
    'solid',
    'dashed',
    'dotted',
    'double',
    'groove',
    'ridge',
    'inset',
    'outset',
  };

  static const Map<String, double> _borderWidths = {
    'thin': 1,
    'medium': 3,
    'thick': 5,
  };

  @override
  bool operator ==(Object other) =>
      other is BlockCss &&
      other.backgroundColor == backgroundColor &&
      other.color == color &&
      other.padding == padding &&
      other.marginTop == marginTop &&
      other.marginBottom == marginBottom &&
      other.maxWidth == maxWidth &&
      other.width == width &&
      other.centered == centered &&
      other.fitContent == fitContent &&
      other.stackBelow == stackBelow &&
      other.borderRadius == borderRadius &&
      other.borderTop == borderTop &&
      other.borderRight == borderRight &&
      other.borderBottom == borderBottom &&
      other.borderLeft == borderLeft;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    color,
    padding,
    marginTop,
    marginBottom,
    maxWidth,
    width,
    centered,
    fitContent,
    stackBelow,
    borderRadius,
    borderTop,
    borderRight,
    borderBottom,
    borderLeft,
  );
}
