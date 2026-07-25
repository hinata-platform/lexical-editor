/// The widget wrapper around [RenderLexicalBlock].
library;

import 'package:flutter/widgets.dart';

import '../render/render_lexical_block.dart';

/// Renders one block's inline content.
///
/// Children come from [WidgetSpan.extractFromInlineSpan], exactly as
/// `RichText` does: each `WidgetSpan` in the tree becomes a real render-object
/// child that the text layout positions as a placeholder.
class LexicalInlineBlock extends MultiChildRenderObjectWidget {
  /// Renders [span] with [textDirection].
  LexicalInlineBlock({
    required this.span,
    required this.textDirection,
    super.key,
    this.textAlign = TextAlign.start,
    this.textScaler = TextScaler.noScaling,
    this.strutStyle,
    this.textHeightBehavior,
    this.selections = const [],
    this.selectionColor,
    this.caret,
  }) : super(children: WidgetSpan.extractFromInlineSpan(span, textScaler));

  /// The span tree to lay out.
  final InlineSpan span;

  /// Resolved writing direction.
  final TextDirection textDirection;

  /// Horizontal alignment of lines.
  final TextAlign textAlign;

  /// Platform text scaling.
  final TextScaler textScaler;

  /// Strut configuration, for consistent line heights.
  final StrutStyle? strutStyle;

  /// Height behaviour for the first and last lines.
  final TextHeightBehavior? textHeightBehavior;

  /// Ranges to paint as selected, in flat offsets.
  final List<TextSelection> selections;

  /// Fill painted behind selected text.
  final Color? selectionColor;

  /// The caret, when this block has one.
  final BlockCaret? caret;

  @override
  RenderLexicalBlock createRenderObject(BuildContext context) =>
      RenderLexicalBlock(
        text: span,
        textDirection: textDirection,
        textAlign: textAlign,
        textScaler: textScaler,
        strutStyle: strutStyle,
        textHeightBehavior: textHeightBehavior,
        selections: selections,
        selectionColor: selectionColor,
        caret: caret,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLexicalBlock renderObject,
  ) {
    renderObject
      ..text = span
      ..textDirection = textDirection
      ..textAlign = textAlign
      ..textScaler = textScaler
      ..selections = selections
      ..selectionColor = selectionColor
      ..caret = caret;
  }
}
