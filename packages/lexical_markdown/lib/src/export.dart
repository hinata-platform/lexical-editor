/// A document back into markdown text.
library;

import 'package:lexical_core/lexical_core.dart';

import 'transformers.dart';

/// Renders the document as markdown.
///
/// Must be called inside a read or an update.
String $convertToMarkdown({
  MarkdownTransformers transformers = const MarkdownTransformers(),
}) {
  final blocks = <String>[];
  for (final child in $getRoot().children) {
    final rendered = _exportBlock(child, transformers);
    if (rendered != null) blocks.add(rendered);
  }
  return blocks.join('\n\n');
}

String? _exportBlock(LexicalNode node, MarkdownTransformers transformers) {
  String exportChildren(ElementNode element) =>
      _exportInline(element, transformers);

  // Blocks that contain blocks: a list holds items, and an item may hold a
  // nested list. Rendering only the node a rule claimed would silently drop
  // every level below the first.
  final nested = <String>[
    if (node is ElementNode)
      for (final child in node.children)
        if (child is ElementNode && !child.isInline)
          ?_exportBlock(child, transformers),
  ];

  for (final transformer in transformers.elements) {
    final rendered = transformer.export(node, exportChildren);
    if (rendered == null) continue;
    if (transformer.exportsSubtree) return rendered;
    final parts = <String>[if (rendered.isNotEmpty) rendered, ...nested];
    return parts.join('\n');
  }

  if (nested.isNotEmpty) return nested.join('\n');
  // A block that is not an element has no children to fall back on — a
  // decorator either has a rule that names it or has no markdown spelling.
  return node is ElementNode ? exportChildren(node) : null;
}

/// Renders an element's inline children.
///
/// Formats are opened and closed in a **fixed order** rather than in the order
/// the bits happen to appear. Markdown has no way to express crossing
/// delimiters, so a stable order is what keeps `**_a_**` from coming back as
/// `**_a**_`, which no parser accepts.
String _exportInline(ElementNode element, MarkdownTransformers transformers) {
  final buffer = StringBuffer();
  var open = <TextFormatTransformer>[];

  void close() {
    for (var i = open.length - 1; i >= 0; i--) {
      buffer.write(open[i].tag);
    }
    open = [];
  }

  for (final child in element.children) {
    if (child is TextNode) {
      // One delimiter per format: `**` and `__` both mean bold, and writing
      // both would produce `**__x__**`.
      final wanted = <TextFormatTransformer>[];
      final seen = <TextFormat>{};
      for (final transformer in transformers.textFormats) {
        if (!child.hasFormat(transformer.format)) continue;
        if (!seen.add(transformer.format)) continue;
        wanted.add(transformer);
      }
      // Close everything and reopen what this run needs, rather than trying
      // to keep shared delimiters open across runs. Markdown cannot express
      // crossing delimiters at all, and adjacent runs only survive
      // normalization when their formats genuinely differ — so there is
      // nothing to share.
      close();
      for (final transformer in wanted) {
        buffer.write(transformer.tag);
        open.add(transformer);
      }
      buffer.write(child.getTextContent());
      continue;
    }

    close();
    final rendered = _exportInlineNode(child, transformers);
    if (rendered != null) {
      buffer.write(rendered);
    } else if (child is LineBreakNode) {
      buffer.write('\n');
    } else if (child is ElementNode && child.isInline) {
      buffer.write(_exportInline(child, transformers));
    }
  }

  close();
  return buffer.toString();
}

String? _exportInlineNode(LexicalNode node, MarkdownTransformers transformers) {
  String exportChildren(ElementNode element) =>
      _exportInline(element, transformers);
  for (final transformer in transformers.textMatches) {
    final rendered = transformer.export(node, exportChildren);
    if (rendered != null) return rendered;
  }
  return null;
}
