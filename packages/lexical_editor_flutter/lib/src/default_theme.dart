/// A theme covering every node type this bundle registers.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/widgets.dart';
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

import 'table_layout.dart';

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
  Map<String, TextStyle>? codeHighlightStyles,
}) {
  final tokens = codeHighlightStyles ?? defaultCodeHighlightStyles(palette);
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
    blockLayouts: tableBlockLayouts(
      selectedCellColor: palette.accent.withValues(alpha: 0.18),
    ),
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
    // The same problem one level down: every run in a code block is a
    // `code-highlight` node, and only its `highlightType` says whether it is a
    // keyword or a string.
    textStyleResolver: (node, style) {
      if (node is! CodeHighlightNode) return style;
      final token = tokens[node.highlightType];
      return token == null ? style : style.merge(token);
    },
    markerBuilders: {
      'listitem': (context, node) =>
          _listMarker(context, node, palette, body, _lineMetrics(body)),
    },
  );
}

/// Colours for the syntax-highlight token classes, chosen for [palette].
///
/// The keys are Prism's token names, which is what both Lexical highlighters
/// write into `highlightType` — so this table colours a block highlighted by
/// this package and one highlighted on the web equally well.
///
/// Not every class needs an entry: operators and punctuation deliberately keep
/// the body colour, because colouring every bracket is what makes a code block
/// look like confetti. Anything unlisted simply inherits.
Map<String, TextStyle> defaultCodeHighlightStyles(LexicalPalette palette) {
  // The palette carries no brightness flag, so the text colour answers the
  // only question that matters: light text means a dark surface behind it.
  final dark = palette.text.computeLuminance() > 0.5;

  final comment = Color(dark ? 0xFF8B949E : 0xFF6E7781);
  final keyword = Color(dark ? 0xFFFF7B72 : 0xFFCF222E);
  final string = Color(dark ? 0xFFA5D6FF : 0xFF0A3069);
  final value = Color(dark ? 0xFF79C0FF : 0xFF0550AE);
  final name = Color(dark ? 0xFFD2A8FF : 0xFF8250DF);
  final builtin = Color(dark ? 0xFFFFA657 : 0xFF953800);

  return {
    for (final type in ['comment', 'prolog', 'doctype', 'cdata'])
      type: TextStyle(color: comment, fontStyle: FontStyle.italic),
    for (final type in ['keyword', 'attr', 'atrule', 'attr-name'])
      type: TextStyle(color: keyword),
    for (final type in [
      'string',
      'char',
      'attr-value',
      'selector',
      'regex',
      'url',
      'inserted',
    ])
      type: TextStyle(color: string),
    for (final type in [
      'number',
      'boolean',
      'constant',
      'property',
      'symbol',
      'tag',
      'entity',
    ])
      type: TextStyle(color: value),
    for (final type in ['function', 'class-name', 'class'])
      type: TextStyle(color: name),
    for (final type in ['builtin', 'variable', 'important', 'namespace'])
      type: TextStyle(color: builtin),
    'deleted': TextStyle(
      color: keyword,
      decoration: TextDecoration.lineThrough,
    ),
  };
}

/// The bullet, number or checkbox before a list item.
/// One laid-out line of [style]: its full height, and where its baseline sits.
///
/// Both measured, not derived. A style with no explicit `height` takes its line
/// box from the font's own ascent and descent, and no arithmetic on `fontSize`
/// reproduces that; a style *with* one adds leading whose split between top and
/// bottom is the font's business too. Guessing either left markers a couple of
/// pixels out — exactly the amount that reads as "not quite lined up".
({double height, double baseline}) _lineMetrics(TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'x', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final metrics = (
    height: painter.height,
    baseline: painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
  );
  painter.dispose();
  return metrics;
}

/// The column every list marker is drawn in.
///
/// One width for all three kinds, which is what makes a bulleted list and a
/// numbered one start their words in the same place — a document of mixed
/// lists should not step in and out as the reader goes down it. Wide enough
/// for `10.` without crowding it.
///
/// Every marker sits in the middle of that column — a bullet, a tick box and a
/// number alike — so the distance from the marker to the words is the same in
/// any list, which is the thing a reader actually sees. Right-setting the
/// numbers would line `9.` and `10.` up on the dot at the cost of that.
const double _markerColumn = 28;

/// The fraction of the em a typeface gives its lowercase letters.
///
/// Used to find the x-height band from the baseline, which is what the eye
/// reads as the middle of a line. Near enough across text faces, and only ever
/// halved, so a face that runs large or small moves a marker by a fraction of
/// a pixel.
const double _xHeight = 0.52;

/// Where a digit's ink centre sits inside its own line box, as a distance below
/// the box's baseline is negative — so this is how far *above* the baseline it
/// falls, as a fraction of the em.
///
/// In principle half the figure height. In practice Flutter exposes line boxes
/// and baselines but no ink metrics, so the figure height cannot be read off
/// the font: this is measured against rendered output. It is the one number
/// here that is calibrated rather than derived, and the tests hold it in place
/// by checking the number against the drawn markers rather than against the
/// formula it came from.
const double _digitInkAboveBaseline = 0.42;

/// How far a number comes down from its line box's top to sit on the band.
///
/// Band-relative rather than a fixed fraction of the em: the band moves with
/// the line height, and a constant nudge would agree with the drawn markers at
/// one line height and drift from them at every other.
///
/// Baseline parity is deliberately given up here. A digit's ink runs to the cap
/// height while lowercase letters stop at the x-height, so a number sitting
/// exactly on the shared baseline — which is where it started, and what a word
/// processor would do — reads as floating above the words next to a bullet that
/// is centred on them. Matching the other markers is what a reader is actually
/// comparing.
double _digitDrop(({double height, double baseline}) line, double em) {
  final band = line.baseline - em * _xHeight / 2;
  final ink = line.baseline - em * _digitInkAboveBaseline;
  return (band - ink).clamp(0.0, line.height);
}

/// Places a marker so its ink lands on the text's x-height band.
///
/// Not the middle of the line box. hinata sets a line height of 1.68 and
/// Flutter hands the extra leading out in proportion to the font's ascent and
/// descent, so the letters sit low in their line and its middle is some three
/// pixels above them — which is exactly how far above the words every marker
/// was floating. What the eye reads as the middle of a line is the x-height
/// band: the body of the lowercase letters, measured up from the baseline.
///
/// `inkCentre` is where the ink sits inside the child. For a drawn shape that
/// is the plain middle; for a glyph it is not, and the difference is the point.
/// `childHeight` matters because an [Alignment] addresses the *free* space
/// around a child rather than the box, so ignoring the child's size leaves the
/// marker out by half of it.
Alignment _onTextBand(
  ({double height, double baseline}) line,
  double em,
  double childHeight, {
  double? inkCentre,
  double x = 0,
}) {
  final band = line.baseline - em * _xHeight / 2;
  final free = line.height - childHeight;
  if (free <= 0) return Alignment(x, 0);
  final top = band - (inkCentre ?? childHeight / 2);
  return Alignment(x, (top.clamp(0.0, free) / free) * 2 - 1);
}

BlockMarker? _listMarker(
  BuildContext context,
  ElementNode node,
  LexicalPalette palette,
  TextStyle body,
  ({double height, double baseline}) line,
) {
  if (node is! ListItemNode) return null;
  // An item that only holds a nested list is a structural wrapper; giving it
  // a bullet of its own would show one bullet too many at every level.
  if (node.isNestedListHolder) return null;
  final list = node.getParent();
  if (list is! ListNode) return null;

  // [line] is one laid-out line of body text. Markers are centred against it
  // rather than hung from the top of the block: a bullet belongs beside the
  // line it introduces, level with the words, and a tick box is a square with
  // no baseline to sit on — which is why it used to need a hand-picked padding
  // to look right, and still did not at other text sizes.
  final em = body.fontSize ?? 16;

  switch (list.listType) {
    case ListType.bullet:
      return BlockMarker(
        width: _markerColumn,
        height: line.height,
        alignment: _onTextBand(line, em, em * 0.28),
        // Drawn, not typed. Where a font puts its own `•` is the font's
        // business — some sit near the cap height — and the result is a dot
        // hovering above the words with no way to correct it that does not
        // break at the next typeface. A circle we place ourselves is level
        // with the text in every face and at every size.
        child: _Dot(size: em * 0.28, color: palette.muted),
      );
    case ListType.number:
      // Nudged down onto the same band the drawn markers land on. See
      // [_digitDrop] for why this one number is measured rather than derived.
      return BlockMarker(
        width: _markerColumn,
        height: line.height,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: _digitDrop(line, em)),
          child: Text(
            '${node.value}.',
            style: body.copyWith(color: palette.muted),
          ),
        ),
      );
    case ListType.check:
      final checked = node.checked ?? false;
      return BlockMarker(
        width: _markerColumn,
        height: line.height,
        alignment: _onTextBand(line, em, 16),
        child: _Checkbox(
          checked: checked,
          palette: palette,
          size: 16,
          itemKey: node.key,
        ),
      );
  }
}

/// The key of the tick box belonging to the check-list item [itemKey].
///
/// Published so a host's tests — and its own overlays — can find one box among
/// many without depending on the private widget that draws it.
Key checkboxKey(NodeKey itemKey) =>
    ValueKey<String>('lexical-checkbox-${itemKey.value}');

/// The bullet of an unordered list, drawn rather than typed.
class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The box in front of a check-list item, and the thing you tick it with.
///
/// Live only while the editor is editable.
///
/// Ticking a list off is closer to reading it than to editing it, so it is
/// tempting to leave the box live everywhere — but a document is rendered
/// read-only in places where nothing is listening for a change, and there the
/// tick would set the node, look like it worked and revert on the next rebuild.
/// A box that reports success for a write nobody saved is worse than one that
/// does nothing.
///
/// So a host that wants tickable checklists in a rendered document says so by
/// making that editor editable and persisting what it hears back. A consumer
/// that needs a genuinely inert rendering — an export, a thumbnail — can also
/// supply its own marker builder, which is what [BlockMarkerBuilder] is for.
class _Checkbox extends StatefulWidget {
  const _Checkbox({
    required this.checked,
    required this.palette,
    required this.size,
    required this.itemKey,
  });

  final bool checked;
  final LexicalPalette palette;
  final double size;

  /// The item to toggle, looked up afresh on tap.
  ///
  /// The key rather than the node: nodes are replaced on every commit, so one
  /// captured here would be stale by the time it was tapped.
  final NodeKey itemKey;

  @override
  State<_Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<_Checkbox> {
  /// Where the finger went down, so a drag can be told from a tap.
  Offset? _downAt;

  /// Ticks the box.
  ///
  /// Discrete because this is a finished user action, not a keystroke waiting
  /// to be batched with the next one: a deferred commit leaves the box drawn
  /// in its old state until something else happens to flush the editor, which
  /// reads as a tap that did nothing.
  void _toggle(LexicalEditor editor) => editor.update(() {
    final node = $getNodeByKey(widget.itemKey);
    if (node is ListItemNode) node.toggleChecked();
  }, discrete: true);

  @override
  Widget build(BuildContext context) {
    // Resolved from this widget's own context, which sits inside the document
    // that publishes the scope — the context the marker builder was called
    // with is the document's own, one level above it.
    final scope = LexicalEditorScope.maybeOf(context);
    final editor = scope != null && scope.isEditable ? scope : null;
    final checked = widget.checked;
    final palette = widget.palette;
    final box = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        // An empty box on a light page was a hairline rectangle the writer had
        // to hunt for. A tinted fill and a fuller border give it a body, so it
        // reads as something to press rather than as a rendering artefact.
        color: checked
            ? palette.accent
            : palette.border.withValues(alpha: 0.18),
        border: Border.all(
          color: checked ? palette.accent : palette.border,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: checked
          ? CustomPaint(painter: _CheckPainter(color: palette.surface))
          : null,
    );

    return editor == null
        ? box
        : Semantics(
            checked: checked,
            // A tick box is a control, and until now it announced itself as
            // a decoration: nothing to press, no state to read out.
            button: true,
            onTap: () => _toggle(editor),
            // A Listener rather than a GestureDetector, deliberately.
            //
            // The editable arms a SerialTapGestureRecognizer over the whole
            // document, and that one declares victory aggressively — it
            // takes the arena regardless of who entered it first, which is
            // exactly what makes the caret land on the frame it was tapped.
            // A recognizer here would be competing with it for the same
            // pointer, and losing.
            //
            // Pointer events are dispatched during hit-testing, before any
            // arena runs at all, so this fires whatever the recognizers
            // decide between themselves. The slop check is what a tap
            // recognizer would have given us: a drag that merely begins on
            // the box scrolls or selects, and leaves the box alone.
            child: Listener(
              key: checkboxKey(widget.itemKey),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _downAt = event.position,
              onPointerUp: (event) {
                final down = _downAt;
                _downAt = null;
                if (down == null) return;
                if ((event.position - down).distance > kTouchSlop) return;
                _toggle(editor);
              },
              onPointerCancel: (_) => _downAt = null,
              child: box,
            ),
          );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      // The tick is drawn on the accent fill, so it has to be the colour the
      // palette nominates to sit on it. Hard-coding white put an invisible
      // tick on any palette whose accent is pale.
      ..color = color
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
