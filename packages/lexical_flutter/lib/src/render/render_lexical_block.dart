/// The render object that lays out and paints one block's inline content.
library;

import 'dart:ui' as ui show TextBox;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// A caret to paint over a block's text.
@immutable
class BlockCaret {
  /// Paints a caret at flat [offset], [width] wide, in [color].
  const BlockCaret({
    required this.offset,
    required this.color,
    this.width = 2,
    this.opacity = 1,
  });

  /// Flat text offset the caret sits at.
  final int offset;

  /// Caret colour.
  final Color color;

  /// Caret width in logical pixels.
  final double width;

  /// Blink opacity. Animating this repaints without relayout.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is BlockCaret &&
      other.offset == offset &&
      other.color == color &&
      other.width == width &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(offset, color, width, opacity);
}

/// Lays out and paints the inline content of a single block.
///
/// One render object **per block**, not per document. A `TextPainter`
/// relayouts its entire content on any change, so a single painter for the
/// whole document makes every keystroke O(document); per block it is
/// O(block). It is also what lets blocks be laid out lazily and culled when
/// off-screen, which is what makes long documents viable.
class RenderLexicalBlock extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TextParentData>,
        RenderInlineChildrenContainerDefaults {
  /// Creates a block render object.
  RenderLexicalBlock({
    required InlineSpan text,
    required TextDirection textDirection,
    TextAlign textAlign = TextAlign.start,
    TextScaler textScaler = TextScaler.noScaling,
    StrutStyle? strutStyle,
    TextHeightBehavior? textHeightBehavior,
    List<TextSelection> selections = const [],
    Color? selectionColor,
    BlockCaret? caret,
  }) : _textPainter = TextPainter(
         text: text,
         textAlign: textAlign,
         textDirection: textDirection,
         textScaler: textScaler,
         strutStyle: strutStyle,
         textHeightBehavior: textHeightBehavior,
       ),
       _selections = selections,
       _selectionColor = selectionColor,
       _caret = caret;

  final TextPainter _textPainter;
  List<ui.TextBox>? _placeholderBoxes;

  /// The span tree being laid out.
  InlineSpan get text => _textPainter.text!;
  set text(InlineSpan value) {
    if (_textPainter.text == value) return;
    // A cheap comparison first: InlineSpan implements value equality, and
    // reusing the layout when nothing changed is the whole point of the
    // reconciler upstream of this.
    switch (_textPainter.text!.compareTo(value)) {
      case RenderComparison.identical:
      case RenderComparison.metadata:
        return;
      case RenderComparison.paint:
        _textPainter.text = value;
        markNeedsPaint();
      case RenderComparison.layout:
        _textPainter.text = value;
        markNeedsLayout();
    }
  }

  /// Horizontal alignment of the block's lines.
  TextAlign get textAlign => _textPainter.textAlign;
  set textAlign(TextAlign value) {
    if (_textPainter.textAlign == value) return;
    _textPainter.textAlign = value;
    markNeedsLayout();
  }

  /// Resolved writing direction.
  TextDirection get textDirection => _textPainter.textDirection!;
  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) return;
    _textPainter.textDirection = value;
    markNeedsLayout();
  }

  /// Text scaling applied by the platform's accessibility settings.
  TextScaler get textScaler => _textPainter.textScaler;
  set textScaler(TextScaler value) {
    if (_textPainter.textScaler == value) return;
    _textPainter.textScaler = value;
    markNeedsLayout();
  }

  List<TextSelection> _selections;

  /// Ranges to paint as selected, in flat offsets.
  List<TextSelection> get selections => _selections;
  set selections(List<TextSelection> value) {
    if (listEquals(_selections, value)) return;
    _selections = value;
    markNeedsPaint();
  }

  Color? _selectionColor;

  /// Fill painted behind selected text.
  Color? get selectionColor => _selectionColor;
  set selectionColor(Color? value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  TextRange? _composing;

  /// The input method's composing region, in flat offsets, or `null`.
  ///
  /// Painted as an underline and **never stored in the editor state**: the
  /// text itself is already in the document, and only the hint that it is
  /// still being composed lives here.
  TextRange? get composing => _composing;
  set composing(TextRange? value) {
    if (_composing == value) return;
    _composing = value;
    markNeedsPaint();
  }

  Color? _composingColor;

  /// Colour of the composing underline.
  Color? get composingColor => _composingColor;
  set composingColor(Color? value) {
    if (_composingColor == value) return;
    _composingColor = value;
    markNeedsPaint();
  }

  BlockCaret? _caret;

  /// The caret to paint, or `null` when this block has no caret.
  ///
  /// Changing it marks needs-paint only. Caret blink must never relayout —
  /// that is the difference between a smooth cursor and a document that
  /// stutters once per second.
  BlockCaret? get caret => _caret;
  set caret(BlockCaret? value) {
    if (_caret == value) return;
    _caret = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TextParentData) {
      child.parentData = TextParentData();
    }
  }

  // -------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------

  void _layoutTextWithConstraints(BoxConstraints constraints) {
    final placeholders = layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    _textPainter
      ..setPlaceholderDimensions(placeholders)
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
  }

  @override
  void performLayout() {
    _layoutTextWithConstraints(constraints);
    _placeholderBoxes = _textPainter.inlinePlaceholderBoxes;
    positionInlineChildren(_placeholderBoxes ?? const []);
    size = constraints.constrain(Size(_textPainter.width, _textPainter.height));
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final placeholders = layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.dryLayoutChild,
      ChildLayoutHelper.getDryBaseline,
    );
    _textPainter
      ..setPlaceholderDimensions(placeholders)
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    return constraints.constrain(Size(_textPainter.width, _textPainter.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _textPainter.setPlaceholderDimensions(
      layoutInlineChildren(
        double.infinity,
        ChildLayoutHelper.dryLayoutChild,
        ChildLayoutHelper.getDryBaseline,
      ),
    );
    _textPainter.layout();
    return _textPainter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _textPainter.setPlaceholderDimensions(
      layoutInlineChildren(
        double.infinity,
        ChildLayoutHelper.dryLayoutChild,
        ChildLayoutHelper.getDryBaseline,
      ),
    );
    _textPainter.layout();
    return _textPainter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    assert(!debugNeedsLayout);
    return _textPainter.computeDistanceToActualBaseline(baseline);
  }

  // -------------------------------------------------------------------
  // Painting
  // -------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintSelection(context.canvas, offset);
    _textPainter.paint(context.canvas, offset);
    paintInlineChildren(context, offset);
    _paintComposing(context.canvas, offset);
    _paintCaret(context.canvas, offset);
  }

  void _paintComposing(Canvas canvas, Offset offset) {
    final composing = _composing;
    final color = _composingColor;
    if (composing == null || color == null) return;
    if (!composing.isValid || composing.isCollapsed) return;
    final selection = TextSelection(
      baseOffset: composing.start.clamp(0, _flatLength),
      extentOffset: composing.end.clamp(0, _flatLength),
    );
    if (selection.isCollapsed) return;
    final paint = Paint()..color = color;
    for (final box in _textPainter.getBoxesForSelection(selection)) {
      final rect = box.toRect();
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 1, rect.width, 1).shift(offset),
        paint,
      );
    }
  }

  void _paintSelection(Canvas canvas, Offset offset) {
    final color = _selectionColor;
    if (color == null || _selections.isEmpty) return;
    final paint = Paint()..color = color;
    for (final selection in _selections) {
      if (selection.isCollapsed) continue;
      for (final box in _textPainter.getBoxesForSelection(selection)) {
        canvas.drawRect(box.toRect().shift(offset), paint);
      }
    }
  }

  void _paintCaret(Canvas canvas, Offset offset) {
    final caret = _caret;
    if (caret == null || caret.opacity <= 0) return;
    final rect = caretRect(caret.offset, width: caret.width);
    final paint = Paint()
      ..color = caret.opacity >= 1
          ? caret.color
          : caret.color.withValues(alpha: caret.color.a * caret.opacity);
    canvas.drawRect(rect.shift(offset), paint);
  }

  // -------------------------------------------------------------------
  // Geometry, for selection and hit testing
  // -------------------------------------------------------------------

  /// The flat text position under [offset], in this block's coordinates.
  TextPosition getPositionForOffset(Offset offset) {
    assert(!debugNeedsLayout);
    return _textPainter.getPositionForOffset(offset);
  }

  /// The boxes covering [selection], in this block's coordinates.
  List<ui.TextBox> getBoxesForSelection(TextSelection selection) {
    assert(!debugNeedsLayout);
    return _textPainter.getBoxesForSelection(selection);
  }

  /// The caret rectangle for flat [offset].
  Rect caretRect(int offset, {double width = 2}) {
    assert(!debugNeedsLayout);
    final position = TextPosition(offset: offset.clamp(0, _flatLength));
    final prototype = Rect.fromLTWH(
      0,
      0,
      width,
      _textPainter.preferredLineHeight,
    );
    final caretOffset = _textPainter.getOffsetForCaret(position, prototype);
    final height = _textPainter.getFullHeightForCaret(position, prototype);
    return Rect.fromLTWH(caretOffset.dx, caretOffset.dy, width, height);
  }

  /// Line metrics for the laid-out block, for line-wise caret movement.
  List<LineMetrics> computeLineMetrics() {
    assert(!debugNeedsLayout);
    return _textPainter.computeLineMetrics();
  }

  int get _flatLength => _textPainter.plainText.length;

  // -------------------------------------------------------------------
  // Hit testing
  // -------------------------------------------------------------------

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitTestInlineChildren(result, position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    defaultApplyPaintTransform(child, transform);
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<TextAlign>('textAlign', textAlign))
      ..add(EnumProperty<TextDirection>('textDirection', textDirection))
      ..add(IntProperty('caretOffset', _caret?.offset, defaultValue: null))
      ..add(IntProperty('selections', _selections.length, defaultValue: 0));
  }
}
