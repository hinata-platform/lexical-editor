/// Building a block's `InlineSpan` and its offset map in one walk.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import '../theme/lexical_theme.dart';
import 'block_offset_map.dart';

/// The rendered form of one block's inline content.
@immutable
final class BuiltBlockSpan {
  /// Bundles a block's span with the offset map produced alongside it.
  const BuiltBlockSpan({
    required this.span,
    required this.offsets,
    required this.hasDecorators,
  });

  /// The span tree to hand to a `TextPainter`.
  final InlineSpan span;

  /// The flat-offset map for the same content.
  final BlockOffsetMap offsets;

  /// Whether the span contains `WidgetSpan` placeholders.
  final bool hasDecorators;
}

/// Builds spans and offset maps for inline content.
///
/// The two are produced in a single traversal on purpose: the walk is
/// identical, and keeping them together guarantees they cannot disagree.
final class SpanBuilder {
  /// Creates a builder for [theme].
  SpanBuilder({
    required this.theme,
    required this.context,
    this.decoratorBuilders = const {},
  });

  /// The theme resolving formats, CSS and block styles.
  final LexicalTheme theme;

  /// Build context for decorator widgets.
  final BuildContext context;

  /// Per-node-type decorator widget builders.
  final Map<String, DecoratorBuilder> decoratorBuilders;

  /// Builds the inline content of [block] into a span and an offset map.
  ///
  /// Only inline descendants are visited; a block child ends the run and is
  /// laid out as its own block by the caller.
  BuiltBlockSpan buildBlock(ElementNode block, {TextStyle? baseStyle}) {
    final segments = <OffsetSegment>[];
    final buffer = StringBuffer();
    final children = <InlineSpan>[];
    var hasDecorators = false;

    final blockStyle = theme.blockStyleFor(block.type);
    final base = (baseStyle ?? theme.baseTextStyle).merge(blockStyle.textStyle);

    void visit(ElementNode parent, TextStyle inherited) {
      var index = 0;
      for (final child in parent.children) {
        switch (child) {
          case final TextNode text:
            final format = text.getFormat();
            final style = theme.resolveTextStyle(
              base: inherited,
              format: format,
              style: text.getStyle(),
            );
            final modelText = text.getTextContent();
            final rendered = applyCaseTransform(modelText, format);
            segments.add(
              OffsetSegment(
                key: text.key,
                flatStart: buffer.length,
                flatLength: rendered.length,
                modelLength: modelText.length,
                type: PointType.text,
                parent: parent.key,
                indexInParent: index,
              ),
            );
            buffer.write(rendered);
            children.add(TextSpan(text: rendered, style: style));
          case final LineBreakNode lineBreak:
            // A line break occupies exactly one flat position.
            segments.add(
              OffsetSegment(
                key: lineBreak.key,
                flatStart: buffer.length,
                flatLength: 1,
                modelLength: 1,
                type: PointType.element,
                parent: parent.key,
                indexInParent: index,
              ),
            );
            buffer.write('\n');
            children.add(TextSpan(text: '\n', style: inherited));
          case final DecoratorNode decorator when decorator.isInline:
            hasDecorators = true;
            // Matches the object-replacement character a WidgetSpan occupies,
            // so flat offsets stay in step with what TextPainter laid out.
            segments.add(
              OffsetSegment(
                key: decorator.key,
                flatStart: buffer.length,
                flatLength: 1,
                modelLength: 1,
                type: PointType.element,
                parent: parent.key,
                indexInParent: index,
              ),
            );
            buffer.write('￼');
            children.add(_decoratorSpan(decorator, inherited));
          case final ElementNode inline when inline.isInline:
            final style = _inlineElementStyle(inline, inherited);
            visit(inline, style);
          default:
            // A block child ends the inline run; the caller lays it out.
            break;
        }
        index++;
      }
    }

    visit(block, base);

    return BuiltBlockSpan(
      span: TextSpan(style: base, children: children),
      offsets: BlockOffsetMap(
        blockKey: block.key,
        flatText: buffer.toString(),
        segments: segments,
      ),
      hasDecorators: hasDecorators,
    );
  }

  TextStyle _inlineElementStyle(ElementNode node, TextStyle inherited) {
    final blockStyle = theme.blockStyles[node.type];
    var style = inherited;
    if (blockStyle?.textStyle != null) {
      style = style.merge(blockStyle!.textStyle);
    }
    // Links get a dedicated hook because they are the one inline element
    // nearly every theme restyles.
    if (node.type == 'link' || node.type == 'autolink') {
      final linkStyle = theme.linkStyle;
      if (linkStyle != null) style = style.merge(linkStyle);
    }
    return style;
  }

  InlineSpan _decoratorSpan(DecoratorNode node, TextStyle inherited) {
    final builder = decoratorBuilders[node.type];
    if (builder == null) {
      // An unbuildable decorator renders as its text stand-in rather than
      // disappearing — silently dropping content is never the right failure.
      return TextSpan(text: node.getTextContent(), style: inherited);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      // A stable key per node: without it Flutter reuses element state across
      // different nodes, and a decorator keeps the previous node's content
      // after an edit reorders blocks.
      child: KeyedSubtree(
        key: ValueKey<String>('lexical-decorator-${node.key.value}'),
        child: builder(context, node),
      ),
    );
  }
}

/// Whether [node] contributes to an inline run rather than being its own
/// block.
bool isInlineContent(LexicalNode node) {
  if (node is TextNode) return true;
  if (node is LineBreakNode) return true;
  return node.isInline;
}
