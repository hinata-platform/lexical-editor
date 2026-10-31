/// Interpreting the CSS subset Lexical's own toolbars emit.
library;

import 'package:flutter/painting.dart';
import 'package:lexical_core/lexical_core.dart';

/// Resolves a node's raw `style` string onto a [TextStyle].
///
/// The model keeps `style` verbatim — it is part of the wire format and a
/// document must round-trip unchanged — so interpretation happens here, at
/// render time, and anything not understood is ignored rather than dropped.
typedef CssStyleResolver = TextStyle Function(String css, TextStyle base);

/// Parses a CSS declaration list into `property -> value` pairs.
///
/// The reading half of [getStyleObjectFromCss], with property names
/// lower-cased for lookup. Splitting the string here instead would get
/// `background: url(a;b)` and quoted font stacks wrong, and would be a second
/// answer to a question the core already answers — the same one that has to
/// round-trip through Lexical web.
///
/// It still does not *implement* CSS. Which declarations mean anything is the
/// consumer's business, which is why [CssStyleResolver] is an injection point
/// rather than a hard-coded parser.
Map<String, String> parseCssDeclarations(String css) {
  if (css.isEmpty) return const {};
  final result = <String, String>{};
  for (final entry in getStyleObjectFromCss(css).entries) {
    result[entry.key.toLowerCase()] = entry.value;
  }
  return result;
}

/// The longest style string the default resolver reads.
///
/// A text node's `style` is untrusted input. Nothing the subset below
/// expresses needs more; a longer string renders as if it were empty and
/// stays in the document untouched.
const int maxTextStyleLength = 2048;

/// The default resolver: the text properties documents and mails carry.
///
/// Handles `color`, `background-color`, `font-size` (`px`, `pt`, `em`,
/// `rem`, `%`), `font-family` (with the generic families mapped, see
/// [resolveCssFontFamily]), `font-weight`, `font-style`, `line-height`,
/// `letter-spacing` and `text-decoration`. `text-transform` changes the
/// rendered string rather than the style, so the span builder applies it;
/// see [cssTextTransformFormat]. Everything else is ignored — which is
/// correct rather than lossy, because the original string stays in the
/// model.
TextStyle defaultCssStyleResolver(String css, TextStyle base) {
  if (css.length > maxTextStyleLength) return base;
  final declarations = parseCssDeclarations(css);
  if (declarations.isEmpty) return base;

  var style = base;
  final color = parseCssColor(declarations['color']);
  if (color != null) style = style.copyWith(color: color);

  final background = parseCssColor(declarations['background-color']);
  if (background != null) style = style.copyWith(backgroundColor: background);

  final fontSize = parseCssLength(declarations['font-size'], base.fontSize);
  if (fontSize != null && fontSize > 0 && fontSize <= 512) {
    style = style.copyWith(fontSize: fontSize);
  }

  final fontFamily = declarations['font-family'];
  if (fontFamily != null && fontFamily.isNotEmpty) {
    final families = resolveCssFontFamily(fontFamily);
    if (families.isNotEmpty) {
      style = style.copyWith(
        fontFamily: families.first,
        fontFamilyFallback: families.skip(1).toList(),
      );
    }
  }

  final fontWeight = parseCssFontWeight(declarations['font-weight']);
  if (fontWeight != null) style = style.copyWith(fontWeight: fontWeight);

  switch (declarations['font-style']?.trim().toLowerCase()) {
    case 'italic' || 'oblique':
      style = style.copyWith(fontStyle: FontStyle.italic);
    case 'normal':
      style = style.copyWith(fontStyle: FontStyle.normal);
  }

  final decoration = parseCssTextDecoration(
    declarations['text-decoration'] ?? declarations['text-decoration-line'],
  );
  if (decoration != null) style = style.copyWith(decoration: decoration);

  final size = style.fontSize ?? 14;
  final lineHeight = _lineHeight(declarations['line-height'], size);
  if (lineHeight != null) style = style.copyWith(height: lineHeight);

  final letterSpacing = declarations['letter-spacing']?.trim().toLowerCase();
  if (letterSpacing == 'normal') {
    style = style.copyWith(letterSpacing: 0);
  } else {
    final spacing = parseCssLength(letterSpacing, size);
    if (spacing != null && spacing.abs() <= 100) {
      style = style.copyWith(letterSpacing: spacing);
    }
  }

  return style;
}

/// A CSS `line-height` as a multiple of [fontSize], which is what
/// [TextStyle.height] is.
///
/// A bare number is already that multiple; a length is divided by the font
/// size; `normal` answers `null`, leaving the font's own line height.
double? _lineHeight(String? value, double fontSize) {
  if (value == null || fontSize <= 0) return null;
  final input = value.trim().toLowerCase();
  if (input == 'normal') return null;
  final number = double.tryParse(input);
  final double? multiple;
  if (number != null) {
    multiple = number;
  } else if (input.endsWith('%')) {
    final percent = double.tryParse(input.substring(0, input.length - 1));
    multiple = percent == null ? null : percent / 100;
  } else {
    final length = parseCssLength(input, fontSize);
    multiple = length == null ? null : length / fontSize;
  }
  if (multiple == null || !multiple.isFinite || multiple <= 0) return null;
  return multiple.clamp(0.5, 10).toDouble();
}

/// The families to try for a CSS `font-family` stack, in order.
///
/// Named families are kept: the engine takes the first one the platform has,
/// which is what a browser does too. The generic families have no font of
/// that name in Flutter, so they are replaced by the faces each platform
/// ships for them — `serif` by Times New Roman, Georgia and Noto Serif,
/// `monospace` by Menlo, Courier New and Roboto Mono. `sans-serif`,
/// `system-ui` and `-apple-system` end the list instead: what comes after
/// the stack is the platform's own sans-serif, which is that family.
///
/// Bounded to eight families.
List<String> resolveCssFontFamily(String value) {
  final families = <String>[];
  for (final raw in value.split(',').take(8)) {
    final family = raw.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
    if (family.isEmpty) continue;
    switch (family.toLowerCase()) {
      case 'serif':
        return _withFaces(families, const [
          'Times New Roman',
          'Georgia',
          'Noto Serif',
        ]);
      case 'monospace':
        return _withFaces(families, const [
          'Menlo',
          'Courier New',
          'Roboto Mono',
        ]);
      case 'sans-serif' ||
          'system-ui' ||
          '-apple-system' ||
          'blinkmacsystemfont':
        return families;
      default:
        families.add(family);
    }
  }
  return families;
}

List<String> _withFaces(List<String> families, List<String> faces) => [
  ...families,
  for (final face in faces)
    if (!families.contains(face)) face,
];

/// The case-transform format bit a CSS `text-transform` in [css] asks for,
/// or `0`.
///
/// `uppercase`, `lowercase` and `capitalize` are the same presentational
/// transforms as the text format bits of those names, so they are applied
/// the same way — to the rendered string, never to the model.
int cssTextTransformFormat(String css) {
  if (css.length > maxTextStyleLength || !css.contains('text-transform')) {
    return 0;
  }
  final value = parseCssDeclarations(css)['text-transform'];
  return switch (value?.trim().toLowerCase()) {
    'uppercase' => TextFormat.uppercase.bit,
    'lowercase' => TextFormat.lowercase.bit,
    'capitalize' => TextFormat.capitalize.bit,
    _ => 0,
  };
}

/// Parses a CSS colour: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb(...)`,
/// `rgba(...)`, `transparent` and the CSS named colours.
///
/// The reading is `lexical_core`'s [parseCssColorValue], so the model and
/// the renderer agree on what a colour is.
Color? parseCssColor(String? value) {
  final argb = parseCssColorValue(value);
  return argb == null ? null : Color(argb);
}

/// The fill and border a parsed block style draws, or `null` for none.
///
/// A corner radius is only drawn with a border that is the same on every
/// side, or with no border at all: Flutter cannot round a border whose sides
/// differ, and a radius dropped is better than a frame that fails to paint.
BoxDecoration? blockCssDecoration(BlockCss css) {
  if (css.backgroundColor == null && !css.hasBorder) return null;
  BorderSide side(CssBorderSide? value) => value == null
      ? BorderSide.none
      : BorderSide(color: Color(value.color), width: value.width);
  final border = css.hasBorder
      ? Border(
          top: side(css.borderTop),
          right: side(css.borderRight),
          bottom: side(css.borderBottom),
          left: side(css.borderLeft),
        )
      : null;
  final radius = css.borderRadius;
  final canRound =
      radius != null &&
      !radius.isZero &&
      (border == null || border.isUniform);
  final background = css.backgroundColor;
  return BoxDecoration(
    color: background == null ? null : Color(background),
    border: border,
    borderRadius: canRound
        ? BorderRadius.only(
            topLeft: _radius(radius.topLeft),
            topRight: _radius(radius.topRight),
            bottomRight: _radius(radius.bottomRight),
            bottomLeft: _radius(radius.bottomLeft),
          )
        : null,
  );
}

Radius _radius(double value) =>
    value <= 0 ? Radius.zero : Radius.circular(value);

/// The inset a parsed block style puts around its content: its padding plus
/// its border widths, because a decoration draws its border inside the box
/// and the content has to make room for it the way a CSS box does.
EdgeInsets blockCssPadding(BlockCss css) {
  final padding = css.padding;
  return EdgeInsets.fromLTRB(
    (padding.left ?? 0) + (css.borderLeft?.width ?? 0),
    (padding.top ?? 0) + (css.borderTop?.width ?? 0),
    (padding.right ?? 0) + (css.borderRight?.width ?? 0),
    (padding.bottom ?? 0) + (css.borderBottom?.width ?? 0),
  );
}

/// Parses a CSS length in `px`, `pt`, `em` or `rem` into logical pixels.
///
/// Relative units resolve against [base], which is the inherited font size.
double? parseCssLength(String? value, double? base) {
  if (value == null) return null;
  final input = value.trim().toLowerCase();
  final match = RegExp(r'^(-?[\d.]+)([a-z%]*)$').firstMatch(input);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null) return null;
  final unit = match.group(2)!;
  final reference = base ?? 14.0;
  return switch (unit) {
    '' || 'px' => amount,
    'pt' => amount * 96 / 72,
    'em' || 'rem' => amount * reference,
    '%' => amount * reference / 100,
    _ => null,
  };
}

/// Parses a CSS `font-weight`, numeric or keyword.
FontWeight? parseCssFontWeight(String? value) {
  if (value == null) return null;
  final input = value.trim().toLowerCase();
  switch (input) {
    case 'normal':
      return FontWeight.w400;
    case 'bold':
      return FontWeight.w700;
    case 'lighter':
      return FontWeight.w300;
    case 'bolder':
      return FontWeight.w800;
  }
  final numeric = int.tryParse(input);
  if (numeric == null) return null;
  // Snap to the nearest supported weight rather than rejecting 350.
  final index = ((numeric / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[index];
}

/// Parses a CSS `text-decoration` shorthand, keeping only the line values.
TextDecoration? parseCssTextDecoration(String? value) {
  if (value == null) return null;
  final tokens = value.trim().toLowerCase().split(RegExp(r'\s+'));
  final lines = <TextDecoration>[];
  for (final token in tokens) {
    switch (token) {
      case 'underline':
        lines.add(TextDecoration.underline);
      case 'line-through':
        lines.add(TextDecoration.lineThrough);
      case 'overline':
        lines.add(TextDecoration.overline);
      case 'none':
        return TextDecoration.none;
    }
  }
  if (lines.isEmpty) return null;
  return lines.length == 1 ? lines.first : TextDecoration.combine(lines);
}
