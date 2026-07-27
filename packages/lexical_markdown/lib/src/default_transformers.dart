/// The rules that make up ordinary markdown.
library;

import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

import 'transformers.dart';

/// `# ` through `###### `.
final ElementTransformer headingTransformer = ElementTransformer(
  regExp: RegExp(r'^(#{1,6})\s+(.*)$'),
  replace: (block, children, match) {
    final level = match.group(1)!.length;
    block.replace(
      $createHeadingNode(HeadingTag.values[level - 1])..appendAll(children),
    );
  },
  export: (node, exportChildren) {
    if (node is! HeadingNode) return null;
    return '${'#' * node.tag.level} ${exportChildren(node)}';
  },
);

/// `---`, `***` and `___` on a line of their own.
///
/// All three spellings mean the same break, and all three have to be here: the
/// inline rules claim the other two otherwise — by the time a `***` line
/// reaches a block rule it has already become an empty emphasis run and a
/// stray asterisk. Matching the line before anything inline sees it is what
/// makes the spelling irrelevant, which is what CommonMark says it is.
///
/// Declared **before** [quoteTransformer] and the list rules for the same
/// reason a check list is declared before a bullet: `---` also matches nothing
/// else here, but `***` and `___` are ambiguous with emphasis and the earliest
/// rule wins.
final ElementTransformer horizontalRuleTransformer = ElementTransformer(
  regExp: RegExp(r'^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$'),
  replace: (block, children, match) {
    block.replace($createHorizontalRuleNode());
  },
  export: (node, exportChildren) => $isHorizontalRuleNode(node) ? '---' : null,
);

/// `> `.
final ElementTransformer quoteTransformer = ElementTransformer(
  regExp: RegExp(r'^>\s?(.*)$'),
  replace: (block, children, match) {
    block.replace($createQuoteNode()..appendAll(children));
  },
  export: (node, exportChildren) {
    if (node is! QuoteNode) return null;
    // Every line gets its own marker: a quote holding a line break would
    // otherwise export to something that reads back as a quote followed by a
    // paragraph.
    return exportChildren(node).split('\n').map((line) => '> $line').join('\n');
  },
);

/// `- [ ] ` and `- [x] `, tried before the plain bullet rule.
final ElementTransformer checkListTransformer = ElementTransformer(
  regExp: RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$'),
  replace: (block, children, match) {
    final checked = match.group(2)!.toLowerCase() == 'x';
    _appendItem(
      block,
      children,
      indent: match.group(1)!.length ~/ 2,
      listType: ListType.check,
      checked: checked,
    );
  },
  export: (node, exportChildren) {
    if (node is! ListItemNode) return null;
    final list = node.getParent();
    if (list is! ListNode || list.listType != ListType.check) return null;
    final mark = (node.checked ?? false) ? 'x' : ' ';
    return '${'  ' * _depthOf(node)}- [$mark] ${exportChildren(node)}';
  },
);

/// `- `, `* ` and `+ `.
final ElementTransformer bulletListTransformer = ElementTransformer(
  regExp: RegExp(r'^(\s*)[-*+]\s+(.*)$'),
  replace: (block, children, match) => _appendItem(
    block,
    children,
    indent: match.group(1)!.length ~/ 2,
    listType: ListType.bullet,
  ),
  export: (node, exportChildren) {
    if (node is! ListItemNode) return null;
    final list = node.getParent();
    if (list is! ListNode || list.listType != ListType.bullet) return null;
    if (node.isNestedListHolder) return '';
    return '${'  ' * _depthOf(node)}- ${exportChildren(node)}';
  },
);

/// `1. `, `2. ` and so on.
final ElementTransformer orderedListTransformer = ElementTransformer(
  regExp: RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$'),
  replace: (block, children, match) => _appendItem(
    block,
    children,
    indent: match.group(1)!.length ~/ 2,
    listType: ListType.number,
    start: int.tryParse(match.group(2)!) ?? 1,
  ),
  export: (node, exportChildren) {
    if (node is! ListItemNode) return null;
    final list = node.getParent();
    if (list is! ListNode || list.listType != ListType.number) return null;
    if (node.isNestedListHolder) return '';
    return '${'  ' * _depthOf(node)}${node.value}. ${exportChildren(node)}';
  },
);

/// A code block, exported as a fence. Import is handled before the line rules.
final ElementTransformer codeTransformer = ElementTransformer(
  // Never matches: a fence spans lines and is consumed by the importer
  // itself. The rule exists so that export stays declared in the same place
  // as every other block's.
  regExp: RegExp(r'^￿$'),
  replace: (block, children, match) {},
  export: (node, exportChildren) {
    if (node is! CodeNode) return null;
    return '```${node.language ?? ''}\n${node.getTextContent()}\n```';
  },
);

/// `[label](url)`.
///
/// The label is markdown in its own right — CommonMark reads
/// `[ein *kursiver* Link](url)` as a link holding emphasis — so it is parsed
/// rather than taken as characters.
final TextMatchTransformer linkTransformer = TextMatchTransformer(
  regExp: RegExp(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)'),
  parsesInlineContent: true,
  replace: (match, format) {
    final url = match.group(2)!;
    // Scheme validation happens where the link is made tappable, not here:
    // rewriting it would break the round trip, and a document is allowed to
    // contain a link this application will refuse to open.
    final link = $createLinkNode(url, title: match.group(3));
    final label = $createTextNode(match.group(1)!);
    if (format != 0) label.setFormat(format);
    return link..append(label);
  },
  export: (node, exportChildren) {
    if (node is! LinkNode) return null;
    final title = node.title;
    final suffix = title == null || title.isEmpty ? '' : ' "$title"';
    return '[${exportChildren(node)}](${node.url}$suffix)';
  },
);

/// Bold, italic, strikethrough and inline code.
///
/// Ordered longest-delimiter-first: `**` has to be tried before `*`, or bold
/// parses as two empty italics.
const List<TextFormatTransformer> defaultTextFormatTransformers = [
  TextFormatTransformer(tag: '**', format: TextFormat.bold),
  TextFormatTransformer(tag: '__', format: TextFormat.bold),
  TextFormatTransformer(tag: '~~', format: TextFormat.strikethrough),
  TextFormatTransformer(tag: '*', format: TextFormat.italic),
  TextFormatTransformer(tag: '_', format: TextFormat.italic),
  TextFormatTransformer(tag: '`', format: TextFormat.code, literal: true),
];

/// Ordinary markdown: headings, quotes, lists, code, links and formatting.
///
/// The order of [MarkdownTransformers.elements] is the order they are tried
/// in, and it matters: a check-list item also matches the bullet rule, so it
/// has to come first.
MarkdownTransformers get defaultMarkdownTransformers => MarkdownTransformers(
  elements: [
    horizontalRuleTransformer,
    headingTransformer,
    quoteTransformer,
    codeTransformer,
    checkListTransformer,
    orderedListTransformer,
    bulletListTransformer,
  ],
  textFormats: defaultTextFormatTransformers,
  textMatches: [linkTransformer],
);

/// Appends an item to the list above, or starts a new one.
void _appendItem(
  ElementNode block,
  List<LexicalNode> children, {
  required int indent,
  required ListType listType,
  bool? checked,
  int start = 1,
}) {
  final item = $createListItemNode(
    listType == ListType.check ? (checked ?? false) : null,
  )..appendAll(children);

  final previous = block.getPreviousSibling();
  // Continuing the list above rather than starting a new one for every line
  // is what makes three bullets one list instead of three.
  if (previous is ListNode && previous.listType == listType) {
    final container = _placeAtIndent(previous, item, indent);
    block.remove(preserveEmptyParent: true);
    // Numbering is derived from position, and import must produce a
    // well-formed document whether or not the numbering transform happens to
    // be registered on this editor. Every list on the path is renumbered, not
    // just the outer one: placing an item deeper also inserts the holder that
    // shifts the numbering of the list it was inserted into.
    for (LexicalNode? node = container; node != null; node = node.getParent()) {
      if (node is ListNode) renumberItems(node);
    }
    return;
  }
  block.replace($createListNode(listType, start)..append(item));
}

/// Puts [item] at nesting depth [indent] inside [list], and returns the list it
/// ended up in.
///
/// A nested list is a sibling of the item it sits under, held by an item of its
/// own — not a child of that item. Both shapes carry the same words, which is
/// why the wrong one survives casual inspection, but only this one matches what
/// Lexical itself writes, what `ListItemNode.isNestedListHolder` describes, and
/// what the indent of an item means. Anything reading structure rather than
/// text — an exporter, an outline, a document authored on another platform —
/// sees two different documents otherwise.
///
/// The depth is carried by the items, never by the list element: an item's
/// `indent` is the nesting level of the list it belongs to.
ListNode _placeAtIndent(ListNode list, ListItemNode item, int indent) {
  var container = list;
  var depth = 0;
  while (depth < indent) {
    final last = container.getLastChild();
    if (last is! ListItemNode) break;
    // A holder is an item whose only child is the nested list — so descending
    // looks at the first child, not the last.
    final nested = last.getFirstChild();
    if (nested is ListNode) {
      container = nested;
      depth++;
      continue;
    }
    final fresh = $createListNode(list.listType);
    last.insertAfter(
      $createListItemNode()
        ..setIndent(depth)
        ..append(fresh),
    );
    container = fresh;
    depth++;
  }
  item.setIndent(depth);
  container.append(item);
  return container;
}

int _depthOf(ListItemNode item) {
  var depth = 0;
  var parent = item.getParent();
  while (parent != null) {
    if (parent is ListNode) depth++;
    parent = parent.getParent();
  }
  return depth - 1;
}
