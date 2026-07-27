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

    final blockStyle = theme.blockStyleForNode(block);
    final base = (baseStyle ?? theme.baseTextStyle).merge(blockStyle.textStyle);

    void visit(ElementNode parent, TextStyle inherited) {
      var index = 0;
      for (final child in parent.children) {
        switch (child) {
          case final TextNode text:
            final format = text.getFormat();
            // A text node's *type* is styled too, not only its formats. A
            // mention and a hashtag are TextNode subclasses that look
            // different from ordinary text without carrying a format bit or a
            // style string, and their theme entry would otherwise do nothing.
            final typeStyle = theme.blockStyleFor(text.type).textStyle;
            var runStyle = typeStyle == null
                ? inherited
                : inherited.merge(typeStyle);
            // What the type string cannot express: a syntax-highlighted run
            // is a `code-highlight` node whether it is a keyword or a string,
            // and only the node knows which.
            final resolver = theme.textStyleResolver;
            if (resolver != null) runStyle = resolver(text, runStyle);
            final style = theme.resolveTextStyle(
              base: runStyle,
              format: format,
              style: text.getStyle(),
            );
            final modelText = text.getTextContent();
            final tokenBuilder = _tokenBuilderFor(text);
            // A token rendered as a widget occupies one flat position for a
            // whole label. The offset map already handles a run whose rendered
            // and model lengths differ by snapping the caret to its edges —
            // which is the rule token mode enforces in the model, arrived at
            // here from the other direction.
            final rendered = tokenBuilder != null
                ? '￼'
                : applyCaseTransform(modelText, format);
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
            if (tokenBuilder == null) {
              children.add(TextSpan(text: rendered, style: style));
            } else {
              hasDecorators = true;
              children.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  baseline: TextBaseline.alphabetic,
                  child: KeyedSubtree(
                    key: ValueKey<String>('lexical-token-${text.key.value}'),
                    child: tokenBuilder(context, text, style),
                  ),
                ),
              );
            }
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
            final prefix = theme.inlinePrefixes[inline.type]?.call(
              context,
              inline,
              style,
            );
            if (prefix != null) {
              hasDecorators = true;
              // The mark holds no text, so it is not the element's content —
              // it is the boundary *before* it, which is exactly the point a
              // caret lands on. Registering it as such is what keeps the flat
              // offsets it shifts from becoming a hole in the block: without a
              // segment covering this position, a tap on the mark resolves to
              // the start of the whole block.
              segments.add(
                OffsetSegment(
                  key: inline.key,
                  flatStart: buffer.length,
                  flatLength: 1,
                  modelLength: 0,
                  type: PointType.element,
                  parent: parent.key,
                  indexInParent: index,
                ),
              );
              buffer.write('￼');
              children.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  baseline: TextBaseline.alphabetic,
                  child: KeyedSubtree(
                    key: ValueKey<String>('lexical-prefix-${inline.key.value}'),
                    child: prefix,
                  ),
                ),
              );
            }
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

  /// The widget builder for [text], or `null` if it renders as text.
  ///
  /// A builder registered for an editable text node is refused: its widget
  /// would occupy one position while the node holds many characters, so every
  /// caret position inside it — and every offset after it in the block —
  /// would be wrong. Rendering it as styled text instead is the failure that
  /// loses the least.
  TokenBuilder? _tokenBuilderFor(TextNode text) {
    final builder = theme.tokenBuilders[text.type];
    if (builder == null) return null;
    assert(
      text.isToken,
      'LexicalTheme.tokenBuilders has an entry for "${text.type}", but that '
      'node is in ${text.getMode().name} mode. Only a token-mode node can be '
      'rendered as a widget; give the node TextMode.token, or style it with '
      'blockStyles instead.',
    );
    return text.isToken ? builder : null;
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
