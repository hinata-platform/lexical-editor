/// HTML into nodes.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

/// Builds nodes from an element, or returns `null` to fall through.
typedef HtmlNodeImport =
    List<LexicalNode>? Function(dom.Element element, HtmlImport importer);

/// Bounds applied while parsing untrusted HTML.
///
/// Pasted HTML is untrusted input, and the shape that hurts is not a large
/// document but a deeply nested one. The limits are the same idea as the JSON
/// importer's, for the same reason.
final class HtmlImportLimits {
  /// Creates limits.
  const HtmlImportLimits({
    this.maxDepth = 64,
    this.maxNodes = 20000,
    this.maxTextLength = 1 << 20,
  });

  /// The default bounds.
  static const HtmlImportLimits defaults = HtmlImportLimits();

  /// Greatest element nesting depth accepted.
  final int maxDepth;

  /// Greatest number of nodes produced.
  final int maxNodes;

  /// Greatest length of a single text run, in UTF-16 code units.
  final int maxTextLength;
}

/// Converts HTML into Lexical nodes.
///
/// Maps the tags a document actually arrives as — a paste from a browser, a
/// mail client, or a CMS — onto the node types this editor knows. Anything
/// unrecognized contributes its **text**, never nothing: dropping content
/// silently is the one outcome a paste must not have.
final class HtmlImport {
  /// Creates an importer.
  HtmlImport({this.custom = const [], this.limits = HtmlImportLimits.defaults});

  /// Rules tried before the built-in ones, so any of them can be overridden.
  final List<HtmlNodeImport> custom;

  /// Bounds applied while parsing.
  final HtmlImportLimits limits;

  int _nodeCount = 0;

  /// Parses [html] into block-level nodes.
  ///
  /// Must be called inside an update.
  List<LexicalNode> parse(String html) {
    _nodeCount = 0;
    final document = html_parser.parseFragment(html);
    final blocks = <LexicalNode>[];
    final inlineRun = <LexicalNode>[];

    void flush() {
      if (inlineRun.isEmpty) return;
      blocks.add($createParagraphNode()..appendAll(List.of(inlineRun)));
      inlineRun.clear();
    }

    for (final child in document.nodes) {
      final produced = _convert(child, format: 0, depth: 0);
      for (final node in produced) {
        if (node is ElementNode && !node.isInline) {
          flush();
          blocks.add(node);
        } else {
          inlineRun.add(node);
        }
      }
    }
    flush();
    return blocks;
  }

  List<LexicalNode> _convert(
    dom.Node node, {
    required int format,
    required int depth,
  }) {
    if (_nodeCount >= limits.maxNodes || depth > limits.maxDepth) {
      return const [];
    }

    if (node is dom.Text) {
      var text = node.text;
      if (text.length > limits.maxTextLength) {
        text = text.substring(0, limits.maxTextLength);
      }
      // Collapse the whitespace HTML would collapse: a pasted document is
      // full of newlines and indentation that mean nothing.
      final collapsed = text.replaceAll(RegExp(r'[\t\n\r ]+'), ' ');
      if (collapsed.trim().isEmpty && !collapsed.contains(' ')) {
        return const [];
      }
      _nodeCount++;
      final textNode = $createTextNode(collapsed);
      if (format != 0) textNode.setFormat(format);
      return [textNode];
    }

    if (node is! dom.Element) return const [];

    for (final rule in custom) {
      final produced = rule(node, this);
      if (produced != null) return produced;
    }
    return _convertElement(node, format: format, depth: depth);
  }

  /// Converts [element]'s children, carrying [format] into their text.
  List<LexicalNode> convertChildren(
    dom.Element element, {
    int format = 0,
    int depth = 0,
  }) {
    final result = <LexicalNode>[];
    for (final child in element.nodes) {
      result.addAll(_convert(child, format: format, depth: depth + 1));
    }
    return result;
  }

  List<LexicalNode> _convertElement(
    dom.Element element, {
    required int format,
    required int depth,
  }) {
    final tag = element.localName?.toLowerCase() ?? '';
    final style = element.attributes['style'] ?? '';
    _nodeCount++;

    ElementNode block(ElementNode node) {
      node.appendAll(convertChildren(element, format: format, depth: depth));
      _applyBlockStyle(node, element, style);
      return node;
    }

    switch (tag) {
      case 'br':
        return [$createLineBreakNode()];

      case 'b' || 'strong':
        return convertChildren(
          element,
          format: format | TextFormat.bold.bit,
          depth: depth,
        );
      case 'i' || 'em':
        return convertChildren(
          element,
          format: format | TextFormat.italic.bit,
          depth: depth,
        );
      case 'u' || 'ins':
        return convertChildren(
          element,
          format: format | TextFormat.underline.bit,
          depth: depth,
        );
      case 's' || 'strike' || 'del':
        return convertChildren(
          element,
          format: format | TextFormat.strikethrough.bit,
          depth: depth,
        );
      case 'mark':
        return convertChildren(
          element,
          format: format | TextFormat.highlight.bit,
          depth: depth,
        );
      case 'sub':
        return convertChildren(
          element,
          format: format | TextFormat.subscript.bit,
          depth: depth,
        );
      case 'sup':
        return convertChildren(
          element,
          format: format | TextFormat.superscript.bit,
          depth: depth,
        );
      case 'code' when !_isInsidePre(element):
        return convertChildren(
          element,
          format: format | TextFormat.code.bit,
          depth: depth,
        );

      case 'p':
        return [block($createParagraphNode())];
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tag.substring(1));
        return [block($createHeadingNode(HeadingTag.values[level - 1]))];
      case 'blockquote':
        return [block($createQuoteNode())];
      case 'pre':
        return [
          $createCodeNode(_languageOf(element))
            ..append($createTextNode(element.text)),
        ];
      case 'code':
        return [
          $createCodeNode(_languageOf(element))
            ..append($createTextNode(element.text)),
        ];

      case 'ul' || 'ol':
        final isCheck = element
            .querySelectorAll('li[role="checkbox"]')
            .isNotEmpty;
        final type = isCheck
            ? ListType.check
            : (tag == 'ol' ? ListType.number : ListType.bullet);
        final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
        final list = $createListNode(type, start);
        for (final child in element.children) {
          if (child.localName?.toLowerCase() != 'li') continue;
          list.append(_convertListItem(child, type, depth: depth));
        }
        if (list.isEmpty) return const [];
        renumberItems(list);
        return [list];
      case 'li':
        return [_convertListItem(element, ListType.bullet, depth: depth)];

      case 'a':
        final href = element.attributes['href'];
        if (href == null || href.isEmpty) {
          return convertChildren(element, format: format, depth: depth);
        }
        // The URL is kept verbatim; whether it may be opened is decided where
        // it is made tappable, not here.
        final link = $createLinkNode(
          href,
          title: element.attributes['title'],
          target: element.attributes['target'],
          rel: element.attributes['rel'],
        );
        final children = convertChildren(
          element,
          format: format,
          depth: depth,
        ).whereType<LexicalNode>().where((node) => node.isInline).toList();
        if (children.isEmpty) {
          children.add($createTextNode(href));
        }
        return [link..appendAll(children)];

      case 'table':
      case 'thead':
      case 'tbody':
      case 'tr':
      case 'td':
      case 'th':
        // Tables are converted as their text. Reproducing a browser's table
        // model — colspan, rowspan, implied sections — inside a paste path is
        // a large amount of code that fails in ways nobody can predict from a
        // screenshot. The content survives; the grid does not.
        return convertChildren(element, format: format, depth: depth);

      case 'script' || 'style' || 'head' || 'meta' || 'link' || 'title':
        // Never text: the contents of these are code, not content.
        return const [];

      case 'div' || 'section' || 'article' || 'main' || 'body' || 'html':
        final children = convertChildren(element, format: format, depth: depth);
        if (children.any((node) => node is ElementNode && !node.isInline)) {
          return children;
        }
        if (children.isEmpty) return const [];
        return [block($createParagraphNode()..appendAll(children))];

      default:
        return convertChildren(element, format: format, depth: depth);
    }
  }

  ListItemNode _convertListItem(
    dom.Element element,
    ListType type, {
    required int depth,
  }) {
    final checked = element.attributes['aria-checked'];
    final item = $createListItemNode(
      type == ListType.check ? checked == 'true' : null,
    );
    for (final child in element.nodes) {
      item.appendAll(_convert(child, format: 0, depth: depth + 1));
    }
    return item;
  }

  bool _isInsidePre(dom.Element element) {
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName?.toLowerCase() == 'pre') return true;
      parent = parent.parent;
    }
    return false;
  }

  String? _languageOf(dom.Element element) {
    for (final candidate in [element, ...element.children]) {
      final classes = candidate.attributes['class'] ?? '';
      for (final name in classes.split(RegExp(r'\s+'))) {
        if (name.startsWith('language-')) return name.substring(9);
        if (name.startsWith('lang-')) return name.substring(5);
      }
    }
    return null;
  }

  void _applyBlockStyle(ElementNode node, dom.Element element, String style) {
    final direction = element.attributes['dir']?.toLowerCase();
    if (direction == 'rtl') {
      node.setDirection(NodeDirection.rtl);
    } else if (direction == 'ltr') {
      node.setDirection(NodeDirection.ltr);
    }
    final align = RegExp(
      r'text-align\s*:\s*([a-z]+)',
    ).firstMatch(style)?.group(1);
    if (align != null) {
      node.setFormat(ElementFormat.fromWire(align));
    }
  }
}

/// Parses [html] into block-level nodes ready to be inserted.
///
/// Must be called inside an update.
List<LexicalNode> $generateNodesFromHtml(
  String html, {
  List<HtmlNodeImport> custom = const [],
  HtmlImportLimits limits = HtmlImportLimits.defaults,
}) => HtmlImport(custom: custom, limits: limits).parse(html);
