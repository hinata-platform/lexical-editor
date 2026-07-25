/// Theming: the Dart analogue of Lexical's CSS class names.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'css_style.dart';

/// Everything a block-level element needs to present itself.
///
/// Keyed by node **type string** rather than by class, which is what lets
/// this package style headings, lists and tables without importing — or even
/// knowing about — the packages that define them.
@immutable
class BlockStyle {
  /// Creates a block presentation.
  const BlockStyle({
    this.textStyle,
    this.padding = EdgeInsets.zero,
    this.decoration,
    this.indentStep = 24,
    this.align,
    this.spacing = 8,
  });

  /// Base text style for inline content in this block.
  final TextStyle? textStyle;

  /// Space between the block's edge and its content.
  final EdgeInsetsGeometry padding;

  /// Background, border, and so on.
  final Decoration? decoration;

  /// Logical pixels added per level of `indent`.
  final double indentStep;

  /// Alignment override, when the document does not specify one.
  final TextAlign? align;

  /// Vertical space below this block.
  final double spacing;

  /// Returns a copy with the given fields replaced.
  BlockStyle copyWith({
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
    double? indentStep,
    TextAlign? align,
    double? spacing,
  }) => BlockStyle(
    textStyle: textStyle ?? this.textStyle,
    padding: padding ?? this.padding,
    decoration: decoration ?? this.decoration,
    indentStep: indentStep ?? this.indentStep,
    align: align ?? this.align,
    spacing: spacing ?? this.spacing,
  );
}

/// A marker rendered before a block's content, such as a bullet or a number.
@immutable
class BlockMarker {
  /// Creates a marker [child] occupying [width] before the block content.
  const BlockMarker({
    required this.child,
    this.width = 28,
    this.alignment = Alignment.topRight,
  });

  /// The marker widget.
  final Widget child;

  /// Reserved width, so markers of different lengths stay aligned.
  final double width;

  /// How the marker sits inside its reserved box.
  final AlignmentGeometry alignment;
}

/// Builds the marker for one block, or returns `null` for none.
///
/// This is the extension point that keeps list bullets, ordered numbers and
/// checkboxes out of this package: a feature package's Flutter integration —
/// or the application — supplies a builder keyed on the type string.
///
/// {@macro lexical_flutter.builder_read_scope}
typedef BlockMarkerBuilder =
    BlockMarker? Function(BuildContext context, ElementNode node);

/// Refines a block's presentation using the node itself.
///
/// [LexicalTheme.blockStyles] is keyed on the **type string**, which is what
/// lets this package style headings and lists without importing the packages
/// that define them. Some types present differently depending on a field —
/// a heading's level, a table cell's header flags — and a type string cannot
/// express that. This hook is where those cases live, and it is supplied by
/// whoever does know the node type.
typedef BlockStyleResolver =
    BlockStyle Function(ElementNode node, BlockStyle base);

/// Renders a decorator node.
///
/// Inline decorators become `WidgetSpan`s; block decorators become their own
/// block. Give the returned widget a stable identity — the renderer keys it
/// on the node key — or Flutter will reuse element state across different
/// nodes and, for example, keep playing the previous node's video.
///
/// {@template lexical_flutter.builder_read_scope}
/// **Read the node here, hand the widget values.** This builder runs inside
/// the editor's read, so every node accessor works. The widget it returns is
/// built later, by Flutter, with no editor state around it — a widget that
/// stored the node and reads it in its own `build` throws `LexicalStateError`
/// on the first frame, and again on every hover or animation frame after
/// that. Passing plain values also makes the widget testable on its own,
/// which is the same advice from the other direction.
/// {@endtemplate}
typedef DecoratorBuilder =
    Widget Function(BuildContext context, DecoratorNode node);

/// Renders a **token-mode text node** as a widget rather than as text.
///
/// This is how a mention becomes a rounded chip: a `TextStyle` can change
/// colour, weight and even paint a rectangular background, but it cannot round
/// a corner, add padding or put an avatar beside the label. Those need a real
/// widget, and this is the hook that supplies one while the node stays
/// ordinary text in the model — still a `TextNode`, still serialized as text,
/// still readable by a Lexical web client that never heard of chips.
///
/// [style] is the style the node would have been drawn with, formats, theme
/// and CSS already resolved. Merge it into the chip's own text rather than
/// starting from scratch, or the chip will ignore the document's font size and
/// stop scaling with the platform's text scale.
///
/// **Token mode only.** The widget occupies exactly one position in the laid
/// out text while the node holds a whole label, so the caret can only sit at
/// its edges — which is precisely what token mode already guarantees, and
/// precisely what it does not guarantee for ordinary text. A builder
/// registered for a non-token type is ignored, with an assertion in debug
/// builds; the node then renders as styled text instead of vanishing.
///
/// {@macro lexical_flutter.builder_read_scope}
///
/// ```dart
/// 'mention': (context, node, style) => MentionChip(
///   label: node.getTextContent(),                  // read it now …
///   kind: (node as MentionNode).mentionType,
///   style: style,
/// )                                                // … not in MentionChip.
/// ```
typedef TokenBuilder =
    Widget Function(BuildContext context, TextNode node, TextStyle style);

/// The visual configuration of a rendered document.
///
/// Upstream themes are CSS class names; this is the Dart analogue. There is
/// deliberately no `Color` or `TextStyle` anywhere in `lexical_core` — theming
/// belongs to the render layer, and keeping it there is what lets the model be
/// tested without a Flutter binding.
@immutable
class LexicalTheme {
  /// Creates a theme.
  const LexicalTheme({
    required this.baseTextStyle,
    this.textFormatStyles = const {},
    this.blockStyles = const {},
    this.blockStyleResolver,
    this.markerBuilders = const {},
    this.tokenBuilders = const {},
    this.styleResolver = defaultCssStyleResolver,
    this.defaultBlockStyle = const BlockStyle(),
    this.linkStyle,
    this.codeTextStyle,
    this.selectionColor = const Color(0x553F8AE0),
    this.caretColor = const Color(0xFF3F8AE0),
    this.caretWidth = 2,
  });

  /// The style inline text inherits before any formatting is applied.
  final TextStyle baseTextStyle;

  /// How each text format bit modifies the inherited style.
  ///
  /// A format with no entry falls back to a built-in default, so a theme only
  /// has to describe what it wants to change.
  final Map<TextFormat, TextStyle Function(TextStyle)> textFormatStyles;

  /// Per-node-type block presentation.
  final Map<String, BlockStyle> blockStyles;

  /// Refines a block style using the node, for types whose presentation
  /// depends on a field rather than only on their type.
  final BlockStyleResolver? blockStyleResolver;

  /// Per-node-type marker builders.
  final Map<String, BlockMarkerBuilder> markerBuilders;

  /// Per-node-type widget builders for token text nodes, keyed on type.
  ///
  /// The entry point for chip-shaped mentions; see [TokenBuilder] for what a
  /// builder is handed and why only token-mode nodes qualify.
  final Map<String, TokenBuilder> tokenBuilders;

  /// Interprets a node's raw CSS `style` string.
  final CssStyleResolver styleResolver;

  /// Presentation for a block type with no entry in [blockStyles].
  final BlockStyle defaultBlockStyle;

  /// Style applied to the contents of a link.
  final TextStyle? linkStyle;

  /// Style for inline code.
  ///
  /// Inline code usually needs a different family, size and background — not
  /// merely a monospace family — which is why it is its own style rather than
  /// a font-family override.
  final TextStyle? codeTextStyle;

  /// Fill painted behind selected text.
  final Color selectionColor;

  /// Colour of the caret.
  final Color caretColor;

  /// Width of the caret in logical pixels.
  final double caretWidth;

  /// The block presentation for [type].
  BlockStyle blockStyleFor(String type) =>
      blockStyles[type] ?? defaultBlockStyle;

  /// The block presentation for [node], after [blockStyleResolver].
  ///
  /// Prefer this over [blockStyleFor] wherever a node is in hand: it is the
  /// only one that sees a heading's level.
  BlockStyle blockStyleForNode(ElementNode node) {
    final base = blockStyleFor(node.type);
    return blockStyleResolver?.call(node, base) ?? base;
  }

  /// Applies [format] and [style] to the inherited [base].
  ///
  /// Case transforms (`lowercase`, `uppercase`, `capitalize`) are **not**
  /// applied here: they have no `TextStyle` equivalent and must transform the
  /// rendered string instead. See `applyCaseTransform`.
  TextStyle resolveTextStyle({
    required TextStyle base,
    required int format,
    required String style,
  }) {
    var resolved = base;
    for (final entry in TextFormat.values) {
      if ((format & entry.bit) == 0) continue;
      final custom = textFormatStyles[entry];
      if (custom != null) {
        resolved = custom(resolved);
        continue;
      }
      resolved = _applyDefaultFormat(entry, resolved);
    }
    if (style.isNotEmpty) {
      resolved = styleResolver(style, resolved);
    }
    return resolved;
  }

  TextStyle _applyDefaultFormat(TextFormat format, TextStyle style) {
    switch (format) {
      case TextFormat.bold:
        return style.copyWith(fontWeight: FontWeight.bold);
      case TextFormat.italic:
        return style.copyWith(fontStyle: FontStyle.italic);
      case TextFormat.underline:
        return style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
        );
      case TextFormat.strikethrough:
        return style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.lineThrough,
          ),
        );
      case TextFormat.code:
        return style.merge(
          codeTextStyle ??
              const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['Menlo', 'Courier New'],
                backgroundColor: Color(0x14000000),
              ),
        );
      case TextFormat.highlight:
        return style.copyWith(backgroundColor: const Color(0x66FFE082));
      case TextFormat.subscript:
        return style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.75,
          textBaseline: TextBaseline.alphabetic,
        );
      case TextFormat.superscript:
        return style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.75,
          textBaseline: TextBaseline.alphabetic,
        );
      case TextFormat.lowercase:
      case TextFormat.uppercase:
      case TextFormat.capitalize:
        // Presentational transforms of the string, handled by the span
        // builder. Applying them here is impossible: TextStyle has no
        // equivalent.
        return style;
    }
  }

  static TextDecoration _addDecoration(
    TextDecoration? existing,
    TextDecoration added,
  ) {
    if (existing == null || existing == TextDecoration.none) return added;
    return TextDecoration.combine([existing, added]);
  }
}

/// Applies the case-transform format bits to a rendered string.
///
/// This must never mutate the node's own text: the transform is
/// presentational, and rewriting the model would make it destructive and
/// break the round trip.
///
/// Note that case mapping is not always length-preserving — German `ß`
/// uppercases to `SS` — so the offset map records both lengths and the caret
/// snaps to run boundaries inside such a run.
String applyCaseTransform(String text, int format) {
  if ((format & TextFormat.uppercase.bit) != 0) return text.toUpperCase();
  if ((format & TextFormat.lowercase.bit) != 0) return text.toLowerCase();
  if ((format & TextFormat.capitalize.bit) != 0) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(r'(^|\s)(\S)'),
      (match) => '${match[1]}${match[2]!.toUpperCase()}',
    );
  }
  return text;
}
