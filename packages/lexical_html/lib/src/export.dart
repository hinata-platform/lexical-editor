/// A document into HTML.
library;

import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

/// Renders a node to HTML, or returns `null` to fall through to the default.
typedef HtmlNodeExport = String? Function(LexicalNode node, HtmlExport export);

/// Renders a document to HTML.
///
/// Emits the tags a mail client, a CMS and a browser all understand, rather
/// than a private dialect: `<strong>`, not `<span class="lexical-bold">`. That
/// is the whole point of an HTML export — text that leaves this editor has to
/// be readable by things that have never heard of it.
///
/// The document's raw `style` strings are passed through onto `<span
/// style="…">` verbatim. They came from a document, not from this package, and
/// rewriting them would break the round trip; a consumer that renders
/// untrusted HTML must sanitize at that point, as it must for any HTML.
final class HtmlExport {
  /// Creates an exporter, optionally with extra rules.
  const HtmlExport({this.custom = const []});

  /// Rules tried before the built-in ones, so any of them can be overridden.
  final List<HtmlNodeExport> custom;

  /// Renders every top-level block of the active document.
  ///
  /// Must be called inside a read or an update.
  String renderDocument() => renderChildren($getRoot());

  /// Renders [element]'s children.
  String renderChildren(ElementNode element) {
    final buffer = StringBuffer();
    for (final child in element.children) {
      buffer.write(renderNode(child));
    }
    return buffer.toString();
  }

  /// Renders one node.
  String renderNode(LexicalNode node) {
    for (final rule in custom) {
      final rendered = rule(node, this);
      if (rendered != null) return rendered;
    }
    return _renderDefault(node);
  }

  String _renderDefault(LexicalNode node) {
    switch (node) {
      case final LineBreakNode _:
        return '<br>';
      case final CodeHighlightNode highlight:
        final type = highlight.highlightType;
        final classAttribute = type == null
            ? ''
            : ' class="${escapeHtml(type)}"';
        return '<span$classAttribute>'
            '${escapeHtml(highlight.getTextContent())}</span>';
      case final TextNode text:
        return _renderText(text);
      case final CodeNode code:
        final language = code.language;
        final classAttribute = language == null
            ? ''
            : ' class="language-${escapeHtml(language)}"';
        return '<pre><code$classAttribute>'
            '${renderChildren(code)}</code></pre>';
      case final HeadingNode heading:
        final tag = 'h${heading.tag.level}';
        return '<$tag${_blockAttributes(heading)}>'
            '${renderChildren(heading)}</$tag>';
      case final QuoteNode quote:
        return '<blockquote${_blockAttributes(quote)}>'
            '${renderChildren(quote)}</blockquote>';
      case final ListNode list:
        final tag = list.listType == ListType.number ? 'ol' : 'ul';
        final start = list.listType == ListType.number && list.start != 1
            ? ' start="${list.start}"'
            : '';
        return '<$tag$start>${renderChildren(list)}</$tag>';
      case final ListItemNode item:
        final checked = item.checked;
        // The checkbox is expressed with ARIA rather than an <input>, which is
        // what keeps the markup readable when pasted somewhere that has no
        // idea what a check list is.
        final aria = checked == null
            ? ''
            : ' role="checkbox" aria-checked="$checked"';
        return '<li$aria>${renderChildren(item)}</li>';
      case final LinkNode link:
        return '<a href="${escapeHtml(link.url)}"'
            '${_linkAttributes(link)}>${renderChildren(link)}</a>';
      case final ParagraphNode paragraph:
        if (paragraph.isEmpty) {
          // An empty paragraph with no content collapses to nothing in most
          // renderers; a break keeps the blank line the author put there.
          return '<p${_blockAttributes(paragraph)}><br></p>';
        }
        return '<p${_blockAttributes(paragraph)}>'
            '${renderChildren(paragraph)}</p>';
      case final ElementNode element when element.isInline:
        return '<span>${renderChildren(element)}</span>';
      case final ElementNode element:
        return '<div${_blockAttributes(element)}>'
            '${renderChildren(element)}</div>';
      default:
        return escapeHtml(node.getTextContent());
    }
  }

  String _renderText(TextNode node) {
    var html = escapeHtml(node.getTextContent());
    final style = node.getStyle();
    if (style.isNotEmpty) {
      html = '<span style="${escapeHtml(style)}">$html</span>';
    }
    // Innermost first, so nesting stays valid however many formats apply.
    const wrappers = <(TextFormat, String)>[
      (TextFormat.code, 'code'),
      (TextFormat.subscript, 'sub'),
      (TextFormat.superscript, 'sup'),
      (TextFormat.highlight, 'mark'),
      (TextFormat.underline, 'u'),
      (TextFormat.strikethrough, 's'),
      (TextFormat.italic, 'em'),
      (TextFormat.bold, 'strong'),
    ];
    for (final (format, tag) in wrappers) {
      if (node.hasFormat(format)) html = '<$tag>$html</$tag>';
    }
    return html;
  }

  String _blockAttributes(ElementNode node) {
    final parts = <String>[];
    final format = node.getFormat();
    if (format != ElementFormat.none) {
      parts.add('text-align: ${format.wire}');
    }
    final indent = node.getIndent();
    if (indent > 0) parts.add('padding-inline-start: ${indent * 40}px');
    final direction = node.getDirection();
    final dir = direction == null ? '' : ' dir="${direction.wire}"';
    if (parts.isEmpty) return dir;
    return '$dir style="${escapeHtml(parts.join('; '))}"';
  }

  String _linkAttributes(LinkNode link) {
    final buffer = StringBuffer();
    final target = link.target;
    if (target != null && target.isNotEmpty) {
      buffer.write(' target="${escapeHtml(target)}"');
    }
    final rel = link.rel;
    if (rel != null && rel.isNotEmpty) {
      buffer.write(' rel="${escapeHtml(rel)}"');
    }
    final title = link.title;
    if (title != null && title.isNotEmpty) {
      buffer.write(' title="${escapeHtml(title)}"');
    }
    return buffer.toString();
  }
}

/// Escapes the five characters that change how HTML parses.
///
/// Applied to every value that reaches the output, attributes included. It is
/// the one thing an HTML serializer must never get wrong: a document is
/// untrusted input, and a document containing `</p><script>` must come out as
/// text.
String escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Renders the active document as HTML.
///
/// Must be called inside a read or an update.
String $generateHtmlFromNodes({List<HtmlNodeExport> custom = const []}) =>
    HtmlExport(custom: custom).renderDocument();
