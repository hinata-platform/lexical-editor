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

/// The default resolver: the handful of declarations Lexical's toolbars emit.
///
/// Handles `color`, `background-color`, `font-size`, `font-family`,
/// `font-weight` and `text-decoration`. Everything else is ignored — which is
/// correct rather than lossy, because the original string stays in the model.
TextStyle defaultCssStyleResolver(String css, TextStyle base) {
  final declarations = parseCssDeclarations(css);
  if (declarations.isEmpty) return base;

  var style = base;
  final color = parseCssColor(declarations['color']);
  if (color != null) style = style.copyWith(color: color);

  final background = parseCssColor(declarations['background-color']);
  if (background != null) style = style.copyWith(backgroundColor: background);

  final fontSize = parseCssLength(declarations['font-size'], base.fontSize);
  if (fontSize != null) style = style.copyWith(fontSize: fontSize);

  final fontFamily = declarations['font-family'];
  if (fontFamily != null && fontFamily.isNotEmpty) {
    final families = fontFamily
        .split(',')
        .map((family) => family.trim().replaceAll(RegExp('^["\']|["\']\$'), ''))
        .where((family) => family.isNotEmpty)
        .toList();
    if (families.isNotEmpty) {
      style = style.copyWith(
        fontFamily: families.first,
        fontFamilyFallback: families.skip(1).toList(),
      );
    }
  }

  final fontWeight = parseCssFontWeight(declarations['font-weight']);
  if (fontWeight != null) style = style.copyWith(fontWeight: fontWeight);

  final decoration = parseCssTextDecoration(declarations['text-decoration']);
  if (decoration != null) style = style.copyWith(decoration: decoration);

  return style;
}

/// Parses `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(...)` and `rgba(...)`.
///
/// Named colours are not resolved: the list is long, rarely emitted by an
/// editor toolbar, and getting a partial list wrong is worse than ignoring
/// the declaration.
Color? parseCssColor(String? value) {
  if (value == null) return null;
  final input = value.trim().toLowerCase();
  if (input.isEmpty) return null;

  if (input.startsWith('#')) {
    final hex = input.substring(1);
    switch (hex.length) {
      case 3:
        final expanded = hex.split('').map((c) => '$c$c').join();
        return _hexColor('ff$expanded');
      case 4:
        final expanded = hex.split('').map((c) => '$c$c').join();
        // CSS is #rrggbbaa; Flutter wants 0xAARRGGBB.
        return _hexColor(
          '${expanded.substring(6, 8)}${expanded.substring(0, 6)}',
        );
      case 6:
        return _hexColor('ff$hex');
      case 8:
        return _hexColor('${hex.substring(6, 8)}${hex.substring(0, 6)}');
    }
    return null;
  }

  final functional = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(input);
  if (functional == null) return null;
  final parts = functional
      .group(1)!
      .split(RegExp('[ ,/]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 3) return null;
  final red = _channel(parts[0]);
  final green = _channel(parts[1]);
  final blue = _channel(parts[2]);
  if (red == null || green == null || blue == null) return null;
  var alpha = 255;
  if (parts.length >= 4) {
    final parsed = double.tryParse(parts[3].replaceAll('%', ''));
    if (parsed == null) return null;
    alpha = parts[3].contains('%')
        ? (parsed * 255 / 100).round()
        : (parsed * 255).round();
  }
  return Color.fromARGB(alpha.clamp(0, 255), red, green, blue);
}

Color? _hexColor(String argb) {
  final value = int.tryParse(argb, radix: 16);
  return value == null ? null : Color(value);
}

int? _channel(String raw) {
  if (raw.endsWith('%')) {
    final percent = double.tryParse(raw.substring(0, raw.length - 1));
    return percent == null ? null : (percent * 255 / 100).round().clamp(0, 255);
  }
  final value = int.tryParse(raw) ?? double.tryParse(raw)?.round();
  return value?.clamp(0, 255);
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
