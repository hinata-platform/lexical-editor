/// A theme covering every node type this bundle registers.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

/// The colours a document is drawn with.
///
/// Deliberately not Material's `ColorScheme`: this package must work in a
/// Cupertino app, in a custom design system, and in a golden test with no app
/// at all. Six colours is what a document actually needs.
@immutable
class LexicalPalette {
  /// Creates a palette.
  const LexicalPalette({
    this.text = const Color(0xFF1A1A1A),
    this.muted = const Color(0xFF6B7280),
    this.accent = const Color(0xFF3F8AE0),
    this.surface = const Color(0x0A000000),
    this.border = const Color(0x1F000000),
    this.highlight = const Color(0x66FFE082),
  });

  /// A palette for a dark background.
  const LexicalPalette.dark()
    : text = const Color(0xFFE8EAED),
      muted = const Color(0xFF9AA0A6),
      accent = const Color(0xFF8AB4F8),
      surface = const Color(0x14FFFFFF),
      border = const Color(0x33FFFFFF),
      highlight = const Color(0x66B39B00);

  /// Body text.
  final Color text;

  /// Secondary text: quote bars, list markers, code fences.
  final Color muted;

  /// Links, mentions, the caret and the selection.
  final Color accent;

  /// Fill behind code blocks and inline code.
  final Color surface;

  /// Rules, table grids and quote bars.
  final Color border;

  /// Fill behind highlighted and marked text.
  final Color highlight;
}

/// Builds a theme presenting every node type this bundle registers.
///
/// Everything is derived from [baseTextStyle] and [palette] rather than
/// hard-coded, so an app gets its own typography by passing its body style in
/// and changes nothing else.
LexicalTheme defaultLexicalTheme({
  required TextStyle baseTextStyle,
  LexicalPalette palette = const LexicalPalette(),
  double blockSpacing = 10,
  String monospaceFamily = 'monospace',
  List<String> monospaceFallback = const ['Menlo', 'Consolas', 'Courier New'],
}) {
  final size = baseTextStyle.fontSize ?? 16;
  final body = baseTextStyle.copyWith(
    color: baseTextStyle.color ?? palette.text,
  );
  final headings = defaultHeadingStyles(body);

  final mono = body.copyWith(
    fontFamily: monospaceFamily,
    fontFamilyFallback: monospaceFallback,
    fontSize: size * 0.92,
  );

  return LexicalTheme(
    baseTextStyle: body,
    defaultBlockStyle: BlockStyle(spacing: blockSpacing),
    selectionColor: palette.accent.withValues(alpha: 0.28),
    caretColor: palette.accent,
    linkStyle: TextStyle(
      color: palette.accent,
      decoration: TextDecoration.underline,
      decorationColor: palette.accent.withValues(alpha: 0.5),
    ),
    codeTextStyle: mono.copyWith(backgroundColor: palette.surface),
    textFormatStyles: {
      TextFormat.highlight: (style) =>
          style.copyWith(backgroundColor: palette.highlight),
    },
    blockStyles: {
      'paragraph': BlockStyle(spacing: blockSpacing),
      'heading': BlockStyle(spacing: blockSpacing * 1.6),
      'quote': BlockStyle(
        textStyle: body.copyWith(color: palette.muted),
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.border, width: 3)),
        ),
        spacing: blockSpacing,
      ),
      'code': BlockStyle(
        textStyle: mono,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        spacing: blockSpacing,
      ),
      'list': BlockStyle(spacing: blockSpacing),
      'listitem': const BlockStyle(spacing: 2, indentStep: 24),
      'table': BlockStyle(
        decoration: BoxDecoration(border: Border.all(color: palette.border)),
        spacing: blockSpacing,
      ),
      'tablerow': const BlockStyle(spacing: 0),
      'tablecell': BlockStyle(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: palette.border)),
        spacing: 0,
      ),
      // Inline element types: only their text style is consulted.
      'mark': BlockStyle(
        textStyle: TextStyle(backgroundColor: palette.highlight),
      ),
      'hashtag': BlockStyle(textStyle: TextStyle(color: palette.accent)),
      'mention': BlockStyle(
        textStyle: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    },
    // A heading's size depends on its level, which a type string cannot
    // express — this is what the node hook exists for.
    blockStyleResolver: (node, base) => node is HeadingNode
        ? base.copyWith(textStyle: headings[node.tag])
        : base,
    markerBuilders: {
      'listitem': (context, node) => _listMarker(context, node, palette, body),
    },
  );
}

/// The bullet, number or checkbox before a list item.
BlockMarker? _listMarker(
  BuildContext context,
  ElementNode node,
  LexicalPalette palette,
  TextStyle body,
) {
  if (node is! ListItemNode) return null;
  // An item that only holds a nested list is a structural wrapper; giving it
  // a bullet of its own would show one bullet too many at every level.
  if (node.isNestedListHolder) return null;
  final list = node.getParent();
  if (list is! ListNode) return null;

  switch (list.listType) {
    case ListType.bullet:
      return BlockMarker(
        width: 24,
        child: Text('•', style: body.copyWith(color: palette.muted)),
      );
    case ListType.number:
      return BlockMarker(
        width: 28,
        child: Text(
          '${node.value}.',
          style: body.copyWith(color: palette.muted),
        ),
      );
    case ListType.check:
      final checked = node.checked ?? false;
      return BlockMarker(
        width: 24,
        alignment: Alignment.topCenter,
        child: _Checkbox(checked: checked, palette: palette, size: 16),
      );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.checked,
    required this.palette,
    required this.size,
  });

  final bool checked;
  final LexicalPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? palette.accent : null,
        border: Border.all(
          color: checked ? palette.accent : palette.border,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: checked
          ? CustomPaint(painter: _CheckPainter(color: palette.surface))
          : null,
    ),
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}

/// The heading styles the default theme applies, by tag.
///
/// Exposed because a toolbar usually wants to preview them, and duplicating
/// the scale in application code is how the two drift apart.
Map<HeadingTag, TextStyle> defaultHeadingStyles(TextStyle baseTextStyle) {
  final size = baseTextStyle.fontSize ?? 16;
  TextStyle at(double scale, FontWeight weight) => baseTextStyle.copyWith(
    fontSize: size * scale,
    fontWeight: weight,
    height: 1.25,
  );
  return {
    HeadingTag.h1: at(2, FontWeight.w700),
    HeadingTag.h2: at(1.6, FontWeight.w700),
    HeadingTag.h3: at(1.35, FontWeight.w600),
    HeadingTag.h4: at(1.15, FontWeight.w600),
    HeadingTag.h5: at(1, FontWeight.w600),
    HeadingTag.h6: at(0.9, FontWeight.w600),
  };
}
