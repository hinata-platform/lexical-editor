/// HTML into nodes.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_layout/lexical_layout.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

/// Builds nodes from an element, or returns `null` to fall through.
typedef HtmlNodeImport =
    List<LexicalNode>? Function(dom.Element element, HtmlImport importer);

/// An `<img>` as the importer read it.
final class HtmlImage {
  /// Creates an image description.
  const HtmlImage({required this.src, this.alt = '', this.width, this.height});

  /// The `src` attribute, verbatim.
  final String src;

  /// The `alt` attribute.
  final String alt;

  /// Width in pixels, from the `width` attribute or CSS, if given.
  final double? width;

  /// Height in pixels, from the `height` attribute or CSS, if given.
  final double? height;
}

/// Creates the node for an image, or returns `null` to drop it.
///
/// Images are a decorator this package cannot depend on — the playground's
/// `image` node lives in `lexical_image`, next to its Flutter widget — so the
/// host supplies the node:
///
/// ```dart
/// import 'package:lexical_image/image_node.dart';
///
/// HtmlImport(
///   createImage: (image) => $createImageNode(
///     src: image.src,
///     altText: image.alt,
///     width: image.width ?? 0,
///     height: image.height ?? 0,
///   ),
/// )
/// ```
///
/// Without one an image contributes its `alt` text.
typedef HtmlImageFactory = LexicalNode? Function(HtmlImage image);

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

/// What an element hands down to its content: CSS inheritance, cut to what
/// the document keeps.
final class _Inherited {
  const _Inherited({
    this.format = 0,
    this.text = const {},
    this.align = ElementFormat.none,
  });

  static const _Inherited none = _Inherited();

  /// Text format bits — `<b>`, `<i>` and friends.
  final int format;

  /// Inherited text CSS, already filtered to the rendered properties.
  final Map<String, String> text;

  /// Inherited `text-align` / `align`, applied to blocks that set none.
  final ElementFormat align;

  _Inherited withFormat(int bit) =>
      _Inherited(format: format | bit, text: text, align: align);

  _Inherited withText(Map<String, String> more) => more.isEmpty
      ? this
      : _Inherited(format: format, text: {...text, ...more}, align: align);

  _Inherited withAlign(ElementFormat value) => value == ElementFormat.none
      ? this
      : _Inherited(format: format, text: text, align: value);
}

/// The text properties a renderer draws; everything else is dropped.
const Set<String> _textProperties = {
  'color',
  'background-color',
  'font-size',
  'font-family',
  'font-weight',
  'font-style',
  'line-height',
  'letter-spacing',
  'text-transform',
  'text-decoration',
};

/// `<font size>` 1–7 in pixels, as browsers map it.
const List<String> _fontSizes = [
  '10px',
  '13px',
  '16px',
  '18px',
  '24px',
  '32px',
  '48px',
];

/// The most columns one table row or MJML section becomes.
const int _maxColumns = 16;

/// Converts HTML into Lexical nodes.
///
/// Maps the tags a document actually arrives as — a paste from a browser, a
/// mail client, or a CMS — onto the node types this editor knows. Anything
/// unrecognized contributes its **text**, never nothing: dropping content
/// silently is the one outcome a paste must not have.
///
/// When the editor registers `layout-container` and `layout-item`
/// (`lexical_layout`), mail-shaped HTML keeps its shape: a table row of two
/// or more cells, or a run of MJML `mj-column-*` columns, becomes a layout;
/// a styled table, cell or `div` becomes a block style — background,
/// padding, border, width, centring — on the block it holds or on a
/// one-column layout around several; inline CSS on text becomes the text's
/// `style`. Only the properties a renderer draws are kept. Hidden elements
/// (`display:none`, `mso-hide:all`, collapsed preheaders, mobile-only
/// variants) and tracking pixels are dropped. Without the layout nodes the
/// same HTML imports as its blocks and text, as it always has.
final class HtmlImport {
  /// Creates an importer.
  HtmlImport({
    this.custom = const [],
    this.limits = HtmlImportLimits.defaults,
    this.createImage,
  });

  /// Rules tried before the built-in ones, so any of them can be overridden.
  final List<HtmlNodeImport> custom;

  /// Bounds applied while parsing.
  final HtmlImportLimits limits;

  /// Creates image nodes; see [HtmlImageFactory].
  final HtmlImageFactory? createImage;

  int _nodeCount = 0;
  bool _layouts = false;
  bool _rules = false;

  /// Parses [html] into block-level nodes.
  ///
  /// Must be called inside an update.
  List<LexicalNode> parse(String html) {
    _nodeCount = 0;
    final registry = $getActiveEditor().registry;
    _layouts =
        registry.knows('layout-container') && registry.knows('layout-item');
    _rules = registry.knows('horizontalrule');
    final document = html_parser.parseFragment(html);
    final produced = <LexicalNode>[];
    for (final child in document.nodes) {
      produced.addAll(_convert(child, _Inherited.none, depth: 0));
    }
    return _asBlocks(produced, _Inherited.none);
  }

  List<LexicalNode> _convert(
    dom.Node node,
    _Inherited inherited, {
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
      if (inherited.format != 0) textNode.setFormat(inherited.format);
      if (_layouts && inherited.text.isNotEmpty) {
        textNode.setStyle(getCssFromStyleObject(inherited.text));
      }
      return [textNode];
    }

    if (node is! dom.Element) return const [];

    for (final rule in custom) {
      final produced = rule(node, this);
      if (produced != null) return produced;
    }
    return _convertElement(node, inherited, depth: depth);
  }

  /// Converts [element]'s children, carrying [format] into their text.
  List<LexicalNode> convertChildren(
    dom.Element element, {
    int format = 0,
    int depth = 0,
  }) => _children(element, _Inherited(format: format), depth: depth);

  List<LexicalNode> _children(
    dom.Element element,
    _Inherited inherited, {
    required int depth,
  }) {
    final result = <LexicalNode>[];
    for (final child in element.nodes) {
      result.addAll(_convert(child, inherited, depth: depth + 1));
    }
    return result;
  }

  List<LexicalNode> _convertElement(
    dom.Element element,
    _Inherited parent, {
    required int depth,
  }) {
    final tag = element.localName?.toLowerCase() ?? '';
    final declarations = _declarations(element);
    if (_isHidden(element, declarations)) return const [];
    _nodeCount++;

    final inherited = parent
        .withText(_textCss(element, declarations))
        .withAlign(_alignOf(element, declarations));

    ElementNode block(ElementNode node) {
      node.appendAll(_trimmed(_children(element, inherited, depth: depth)));
      _applyBlockStyle(node, element, declarations, inherited);
      // An empty block is as tall as one line of its own font: a mail's
      // divider is an empty `<p>` with a border and `font-size:1px`. The
      // caret style is where an empty block keeps that font.
      if (_layouts && node.isEmpty && inherited.text.isNotEmpty) {
        node.setTextStyle(getCssFromStyleObject(inherited.text));
      }
      return node;
    }

    switch (tag) {
      case 'br':
        return [$createLineBreakNode()];

      case 'b' || 'strong':
        return _children(
          element,
          inherited.withFormat(TextFormat.bold.bit),
          depth: depth,
        );
      case 'i' || 'em':
        return _children(
          element,
          inherited.withFormat(TextFormat.italic.bit),
          depth: depth,
        );
      case 'u' || 'ins':
        return _children(
          element,
          inherited.withFormat(TextFormat.underline.bit),
          depth: depth,
        );
      case 's' || 'strike' || 'del':
        return _children(
          element,
          inherited.withFormat(TextFormat.strikethrough.bit),
          depth: depth,
        );
      case 'mark':
        return _children(
          element,
          inherited.withFormat(TextFormat.highlight.bit),
          depth: depth,
        );
      case 'sub':
        return _children(
          element,
          inherited.withFormat(TextFormat.subscript.bit),
          depth: depth,
        );
      case 'sup':
        return _children(
          element,
          inherited.withFormat(TextFormat.superscript.bit),
          depth: depth,
        );
      case 'code' when !_isInsidePre(element):
        return _children(
          element,
          inherited.withFormat(TextFormat.code.bit),
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
      case 'hr':
        return _rules ? [$createHorizontalRuleNode()] : const [];
      case 'img':
        return _image(element, declarations);

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
          list.append(_convertListItem(child, type, inherited, depth: depth));
        }
        if (list.isEmpty) return const [];
        renumberItems(list);
        return [list];
      case 'li':
        return [
          _convertListItem(element, ListType.bullet, inherited, depth: depth),
        ];

      case 'a':
        final href = element.attributes['href'];
        if (href == null || href.isEmpty) {
          return _children(element, inherited, depth: depth);
        }
        // The URL is kept verbatim; whether it may be opened is decided where
        // it is made tappable, not here.
        final link = $createLinkNode(
          href,
          title: element.attributes['title'],
          target: element.attributes['target'],
          rel: element.attributes['rel'],
        );
        final children = _children(
          element,
          inherited,
          depth: depth,
        ).where((node) => node.isInline).toList();
        if (children.isEmpty) {
          children.add($createTextNode(href));
        }
        return [link..appendAll(children)];

      case 'table':
        return _convertTable(element, declarations, inherited, depth: depth);
      case 'thead' || 'tbody' || 'tfoot' || 'tr' || 'td' || 'th':
        // Outside a table — a fragment of one pasted on its own.
        if (!_layouts) return _children(element, inherited, depth: depth);
        return _container(element, declarations, inherited, depth: depth);

      case 'script' ||
          'style' ||
          'head' ||
          'meta' ||
          'link' ||
          'title' ||
          'noscript':
        // Never text: the contents of these are code, not content.
        return const [];

      case 'div' ||
          'section' ||
          'article' ||
          'main' ||
          'body' ||
          'html' ||
          'center' ||
          'header' ||
          'footer':
        if (_layouts &&
            element.attributes['data-lexical-layout-container'] == 'true') {
          return _lexicalLayout(element, declarations, inherited, depth: depth);
        }
        return _container(element, declarations, inherited, depth: depth);

      default:
        return _children(element, inherited, depth: depth);
    }
  }

  // ---------------------------------------------------------------------
  // Blocks and their boxes
  // ---------------------------------------------------------------------

  /// A wrapper element — `div`, a lone table cell — as the blocks it holds,
  /// boxed by its own style.
  List<LexicalNode> _container(
    dom.Element element,
    Map<String, String> declarations,
    _Inherited inherited, {
    required int depth,
  }) {
    final columns = _layouts ? _mjmlColumns(element) : const <dom.Element>[];
    final List<LexicalNode> children;
    if (columns.length >= 2) {
      children = [
        for (final child in element.nodes)
          if (child is dom.Element && columns.first == child)
            _columnsLayout(columns, inherited, depth: depth)
          else if (!(child is dom.Element && columns.contains(child)))
            ..._convert(child, inherited, depth: depth + 1),
      ];
    } else {
      children = _children(element, inherited, depth: depth);
    }
    if (children.isEmpty) return const [];
    final css = _blockCss(element, declarations, withWidth: true);
    final hasBlocks = children.any(_isBlock);
    if (!hasBlocks && css.isEmpty && !_definesBlock(element)) {
      // Inline content in a wrapper that adds nothing: leave it inline, so a
      // `<td>` of text next to a `<td>` of text does not become two
      // paragraphs where a paste meant one line.
      return children;
    }
    return _box(_asBlocks(children, inherited), css);
  }

  /// Whether [element] starts a line of its own even without a style.
  static bool _definesBlock(dom.Element element) =>
      switch (element.localName?.toLowerCase()) {
        'div' ||
        'section' ||
        'article' ||
        'main' ||
        'center' ||
        'header' ||
        'footer' ||
        'td' ||
        'th' => true,
        _ => false,
      };

  /// Puts [css] on [blocks]: on the block itself when there is exactly one
  /// paragraph or heading without a style of its own, otherwise on a
  /// one-column layout around them.
  List<LexicalNode> _box(List<LexicalNode> blocks, String css) {
    if (css.isEmpty || blocks.isEmpty || !_layouts) return blocks;
    if (blocks.length == 1) {
      final only = blocks.single;
      if ((only is ParagraphNode || only is HeadingNode) &&
          $getBlockStyle(only).isEmpty) {
        $setBlockStyle(only, css);
        return blocks;
      }
    }
    if (!_layouts) return blocks;
    _nodeCount += 2;
    final container = $createLayoutContainerNode('1fr')
      ..append($createLayoutItemNode()..appendAll(blocks));
    $setBlockStyle(container, css);
    return [container];
  }

  /// [nodes] with every run of inline content wrapped in a paragraph.
  List<LexicalNode> _asBlocks(List<LexicalNode> nodes, _Inherited inherited) {
    final blocks = <LexicalNode>[];
    final run = <LexicalNode>[];
    void flush() {
      if (run.isEmpty) return;
      // A run of nothing but spaces between two blocks is source formatting.
      final blank = run.every(
        (node) => node is TextNode && node.getTextContent().trim().isEmpty,
      );
      if (blank) {
        run.clear();
        return;
      }
      final content = _trimmed(run);
      run.clear();
      if (content.isEmpty) return;
      final paragraph = $createParagraphNode()..appendAll(content);
      if (inherited.align != ElementFormat.none) {
        paragraph.setFormat(inherited.align);
      }
      blocks.add(paragraph);
    }

    for (final node in nodes) {
      if (_isBlock(node)) {
        flush();
        blocks.add(node);
      } else {
        run.add(node);
      }
    }
    flush();
    return blocks;
  }

  /// [nodes] without the whitespace a browser drops at the edges of a line
  /// box: source indentation before the first word and after the last.
  static List<LexicalNode> _trimmed(List<LexicalNode> nodes) {
    final result = List<LexicalNode>.of(nodes);
    while (result.isNotEmpty) {
      final first = result.first;
      if (first is! TextNode || first.isToken) break;
      final text = first.getTextContent().trimLeft();
      if (text.isNotEmpty) {
        if (text.length != first.getTextContentSize()) {
          first.setTextContent(text);
        }
        break;
      }
      result.removeAt(0);
      first.remove();
    }
    while (result.isNotEmpty) {
      final last = result.last;
      if (last is! TextNode || last.isToken) break;
      final text = last.getTextContent().trimRight();
      if (text.isNotEmpty) {
        if (text.length != last.getTextContentSize()) last.setTextContent(text);
        break;
      }
      result.removeLast();
      last.remove();
    }
    return result;
  }

  static bool _isBlock(LexicalNode node) =>
      (node is ElementNode || node is DecoratorNode) && !node.isInline;

  void _applyBlockStyle(
    ElementNode node,
    dom.Element element,
    Map<String, String> declarations,
    _Inherited inherited,
  ) {
    final direction = element.attributes['dir']?.toLowerCase();
    if (direction == 'rtl') {
      node.setDirection(NodeDirection.rtl);
    } else if (direction == 'ltr') {
      node.setDirection(NodeDirection.ltr);
    }
    if (inherited.align != ElementFormat.none) node.setFormat(inherited.align);
    if (!_layouts) return;
    final css = _blockCss(element, declarations, withWidth: true);
    if (css.isNotEmpty) $setBlockStyle(node, css);
  }

  // ---------------------------------------------------------------------
  // Tables
  // ---------------------------------------------------------------------

  List<LexicalNode> _convertTable(
    dom.Element table,
    Map<String, String> declarations,
    _Inherited inherited, {
    required int depth,
  }) {
    final rows = _rowsOf(table);
    if (!_layouts || _isDataTable(table, rows)) {
      // A table of data stays its text: reproducing a browser's table model
      // — colspan, rowspan, implied sections — in a paste path is a large
      // amount of code that fails in ways nobody can predict from a
      // screenshot. The content survives; the grid does not.
      return _children(table, inherited, depth: depth);
    }

    final padding = _cellPadding(table);
    final tableCss = _blockCss(table, declarations, withWidth: true);
    // A table that is one cell — a button, a banner — is that cell: its box
    // and the table's merge onto the content rather than nesting.
    final isOneCell =
        rows.length == 1 && rows.single.children.where(_hasContent).length == 1;
    final blocks = <LexicalNode>[];
    for (final row in rows) {
      if (_nodeCount >= limits.maxNodes) break;
      final rowDeclarations = _declarations(row);
      if (_isHidden(row, rowDeclarations)) continue;
      final rowInherited = inherited
          .withText(_textCss(row, rowDeclarations))
          .withAlign(_alignOf(row, rowDeclarations));
      final cells = [
        for (final cell in row.children)
          if (cell.localName == 'td' || cell.localName == 'th')
            if (!_isHidden(cell, _declarations(cell))) cell,
      ].take(_maxColumns).toList();
      if (cells.isEmpty) continue;

      final withContent = cells.where(_hasContent).length;
      if (withContent >= 2) {
        final container = $createLayoutContainerNode(
          cells.map(_track).join(' '),
        );
        _nodeCount++;
        for (final cell in cells) {
          final cellDeclarations = _declarations(cell);
          final cellInherited = rowInherited
              .withText(_textCss(cell, cellDeclarations))
              .withAlign(_alignOf(cell, cellDeclarations));
          final content = _asBlocks(
            _children(cell, cellInherited, depth: depth + 1),
            cellInherited,
          );
          final item = $createLayoutItemNode()
            ..appendAll(content.isEmpty ? [$createParagraphNode()] : content);
          _nodeCount++;
          final css = _blockCss(
            cell,
            cellDeclarations,
            withWidth: false,
            padding: padding,
          );
          if (css.isNotEmpty) $setBlockStyle(item, css);
          container.append(item);
        }
        final rowCss = _blockCss(row, rowDeclarations, withWidth: false);
        if (rowCss.isNotEmpty) $setBlockStyle(container, rowCss);
        blocks.add(container);
        continue;
      }

      // One cell with content: the row is a wrapper, and so is the cell.
      for (final cell in cells.where(_hasContent)) {
        final cellDeclarations = _declarations(cell);
        final cellInherited = rowInherited
            .withText(_textCss(cell, cellDeclarations))
            .withAlign(_alignOf(cell, cellDeclarations));
        final content = _asBlocks(
          _children(cell, cellInherited, depth: depth + 1),
          cellInherited,
        );
        final css = _mergeCss(
          _mergeCss(
            isOneCell ? tableCss : '',
            _blockCss(row, rowDeclarations, withWidth: false),
          ),
          _blockCss(cell, cellDeclarations, withWidth: true, padding: padding),
        );
        blocks.addAll(_box(content, css));
      }
    }
    return isOneCell ? blocks : _box(blocks, tableCss);
  }

  /// The rows of [table] itself, not of tables nested in its cells.
  static List<dom.Element> _rowsOf(dom.Element table) => [
    for (final child in table.children)
      if (child.localName == 'tr')
        child
      else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName))
        ...child.children.where((row) => row.localName == 'tr'),
  ];

  /// A table that holds data rather than layout: it has header cells, or a
  /// visible grid of three or more columns.
  static bool _isDataTable(dom.Element table, List<dom.Element> rows) {
    for (final row in rows) {
      if (row.children.any((cell) => cell.localName == 'th')) return true;
    }
    final border = int.tryParse(table.attributes['border'] ?? '') ?? 0;
    if (border > 0 && rows.length >= 2) {
      return rows.every(
        (row) =>
            row.children.where((cell) => cell.localName == 'td').length >= 3,
      );
    }
    return false;
  }

  static bool _hasContent(dom.Element cell) =>
      cell.text.trim().isNotEmpty ||
      cell.querySelector('img') != null ||
      cell.querySelector('hr') != null;

  /// The grid track a cell's width asks for.
  static String _track(dom.Element cell) {
    final declared =
        _declarations(cell)['width'] ?? cell.attributes['width'] ?? '';
    final length = CssLength.parse(declared);
    if (length == null || length.value <= 0) return '1fr';
    return length.unit == CssLengthUnit.px
        ? '${_number(length.value)}px'
        : '${_number(length.value)}%';
  }

  static String? _cellPadding(dom.Element table) {
    final value = int.tryParse(table.attributes['cellpadding'] ?? '');
    return value == null || value <= 0 ? null : '${value.clamp(0, 200)}px';
  }

  // ---------------------------------------------------------------------
  // MJML and Lexical layouts
  // ---------------------------------------------------------------------

  /// The MJML columns among [element]'s children: `div.mj-column-per-NN`
  /// and `div.mj-column-px-NN`, which MJML lays side by side as inline
  /// blocks.
  static List<dom.Element> _mjmlColumns(dom.Element element) => [
    for (final child in element.children)
      if (child.localName == 'div' && _mjmlTrack(child) != null) child,
  ].take(_maxColumns).toList();

  static String? _mjmlTrack(dom.Element column) {
    for (final name in column.classes) {
      final match = RegExp(
        r'^mj-column-(per|px)-(\d{1,4})(?:-(\d{1,2}))?$',
      ).firstMatch(name);
      if (match == null) continue;
      final whole = match.group(2)!;
      final fraction = match.group(3);
      final amount = fraction == null ? whole : '$whole.$fraction';
      return match.group(1) == 'per' ? '$amount%' : '${amount}px';
    }
    return null;
  }

  LexicalNode _columnsLayout(
    List<dom.Element> columns,
    _Inherited inherited, {
    required int depth,
  }) {
    final container = $createLayoutContainerNode(
      columns.map((column) => _mjmlTrack(column)!).join(' '),
    );
    _nodeCount++;
    for (final column in columns) {
      final declarations = _declarations(column);
      final columnInherited = inherited
          .withText(_textCss(column, declarations))
          .withAlign(_alignOf(column, declarations));
      final content = _asBlocks(
        _children(column, columnInherited, depth: depth + 1),
        columnInherited,
      );
      final item = $createLayoutItemNode()
        ..appendAll(content.isEmpty ? [$createParagraphNode()] : content);
      _nodeCount++;
      final css = _blockCss(column, declarations, withWidth: false);
      if (css.isNotEmpty) $setBlockStyle(item, css);
      container.append(item);
    }
    return container;
  }

  /// A layout exported by Lexical web or by this package: the playground's
  /// `data-lexical-layout-container` markup.
  List<LexicalNode> _lexicalLayout(
    dom.Element element,
    Map<String, String> declarations,
    _Inherited inherited, {
    required int depth,
  }) {
    final template = declarations['grid-template-columns'] ?? '';
    final container = $createLayoutContainerNode(
      template.length > maxTemplateLength ? '' : template,
    );
    _nodeCount++;
    for (final child in element.children.take(_maxColumns)) {
      if (child.attributes['data-lexical-layout-item'] != 'true') continue;
      final childDeclarations = _declarations(child);
      final content = _asBlocks(
        _children(child, inherited, depth: depth + 1),
        inherited,
      );
      final item = $createLayoutItemNode()
        ..appendAll(content.isEmpty ? [$createParagraphNode()] : content);
      _nodeCount++;
      final css = _blockCss(child, childDeclarations, withWidth: true);
      if (css.isNotEmpty) $setBlockStyle(item, css);
      container.append(item);
    }
    if (container.isEmpty) {
      container.append($createLayoutItemNode()..append($createParagraphNode()));
    }
    final css = _blockCss(element, declarations, withWidth: true);
    if (css.isNotEmpty) $setBlockStyle(container, css);
    return [container];
  }

  // ---------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------

  List<LexicalNode> _image(
    dom.Element element,
    Map<String, String> declarations,
  ) {
    final src = element.attributes['src']?.trim() ?? '';
    final alt = element.attributes['alt'] ?? '';
    final width = _pixels(declarations['width'] ?? element.attributes['width']);
    final height = _pixels(
      declarations['height'] ?? element.attributes['height'],
    );
    // A tracking pixel draws nothing and reports the reader.
    if ((width != null && width <= 2) || (height != null && height <= 2)) {
      return const [];
    }
    final factory = createImage;
    if (factory == null || src.isEmpty) {
      return alt.trim().isEmpty ? const [] : [$createTextNode(alt)];
    }
    final node = factory(
      HtmlImage(src: src, alt: alt, width: width, height: height),
    );
    if (node == null) return const [];
    _nodeCount++;
    return [node];
  }

  static double? _pixels(String? value) {
    if (value == null) return null;
    return parseCssPixels(value.trim());
  }

  // ---------------------------------------------------------------------
  // CSS
  // ---------------------------------------------------------------------

  /// An element's inline style, lower-cased names, bounded.
  static Map<String, String> _declarations(dom.Element element) {
    final style = element.attributes['style'];
    if (style == null || style.isEmpty || style.length > 4096) return const {};
    final result = <String, String>{};
    for (final entry in getStyleObjectFromCss(style).entries) {
      result[entry.key.toLowerCase()] = entry.value
          .replaceAll(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
          .trim();
    }
    return result;
  }

  /// Whether [element] is not shown, or is the mobile half of a pair.
  static bool _isHidden(dom.Element element, Map<String, String> css) {
    if (element.attributes.containsKey('hidden')) return true;
    final display = css['display']?.toLowerCase();
    if (display == 'none') return true;
    if (css['mso-hide']?.toLowerCase() == 'all') return true;
    if (css['visibility']?.toLowerCase() == 'hidden') return true;
    // The preheader: text a mail client shows in the inbox list, collapsed
    // to nothing in the message itself.
    final maxHeight = css['max-height'];
    if (maxHeight != null &&
        parseCssPixels(maxHeight) == 0 &&
        css['overflow']?.toLowerCase() == 'hidden') {
      return true;
    }
    // Responsive mails carry a mobile and a desktop variant; the desktop one
    // is kept, because the layout reflows to a phone on its own.
    final names = [...element.classes, if (element.id.isNotEmpty) element.id];
    return names.any(
      (name) => RegExp(
        r'^(mob|mobile)([-_]?(only|show|version|view))?$|'
        r'^(show|only|visible)[-_](on[-_])?(mob|mobile)$',
        caseSensitive: false,
      ).hasMatch(name),
    );
  }

  /// The text CSS [element] adds for its content, legacy attributes included.
  static Map<String, String> _textCss(
    dom.Element element,
    Map<String, String> declarations,
  ) {
    final result = <String, String>{};
    if (element.localName == 'font') {
      final color = element.attributes['color'];
      if (color != null && parseCssColorValue(color) != null) {
        result['color'] = color.trim();
      }
      final face = element.attributes['face'];
      if (face != null && face.trim().isNotEmpty && face.length <= 128) {
        result['font-family'] = face.trim();
      }
      final size = int.tryParse(element.attributes['size']?.trim() ?? '');
      if (size != null && size >= 1 && size <= 7) {
        result['font-size'] = _fontSizes[size - 1];
      }
    }
    for (final entry in declarations.entries) {
      if (!_textProperties.contains(entry.key)) continue;
      final value = entry.value;
      if (value.isEmpty || value.length > 128) continue;
      if (value.contains('(') && !value.startsWith('rgb')) continue;
      result[entry.key] = value;
    }
    return result;
  }

  /// [element]'s alignment: `text-align`, the `align` attribute, `<center>`.
  static ElementFormat _alignOf(
    dom.Element element,
    Map<String, String> declarations,
  ) {
    if (element.localName == 'center') return ElementFormat.center;
    final value =
        (declarations['text-align'] ??
                // On a table `align` positions the table, not its text.
                (element.localName == 'table'
                    ? null
                    : element.attributes['align']))
            ?.trim()
            .toLowerCase();
    return switch (value) {
      'left' ||
      'center' ||
      'right' ||
      'justify' => ElementFormat.fromWire(value),
      'middle' => ElementFormat.center,
      _ => ElementFormat.none,
    };
  }

  /// [element]'s block style as canonical CSS, legacy attributes included.
  ///
  /// [withWidth] keeps a width — off for a cell in a row, whose width is its
  /// grid track instead. [padding] is a table's `cellpadding`, applied when
  /// the cell sets none of its own.
  static String _blockCss(
    dom.Element element,
    Map<String, String> declarations, {
    required bool withWidth,
    String? padding,
  }) {
    final legacy = <String>[];
    final bgcolor = element.attributes['bgcolor'];
    if (bgcolor != null && parseCssColorValue(bgcolor) != null) {
      legacy.add('background-color:${bgcolor.trim()}');
    }
    if (padding != null) legacy.add('padding:$padding');
    if (withWidth) {
      final width = element.attributes['width'];
      if (width != null) {
        final length = CssLength.parse(width.trim());
        if (length != null) legacy.add('width:$length');
      }
    }
    if (element.localName == 'table' &&
        element.attributes['align']?.toLowerCase() == 'center') {
      legacy.add('margin-left:auto;margin-right:auto');
    }
    // As wide as its content: a table without a width shrinks to fit, and
    // an inline block is as wide as what is in it — a mail's button, both
    // ways it is written. A declared width, which comes after, still wins.
    if (withWidth &&
        ((element.localName == 'table' &&
                element.attributes['width'] == null) ||
            declarations['display']?.toLowerCase() == 'inline-block')) {
      legacy.add('width:fit-content');
    }
    final declared = <String>[
      for (final entry in declarations.entries)
        if (withWidth || entry.key != 'width') '${entry.key}:${entry.value}',
    ];
    // Declared CSS after the legacy attributes, so it wins as it does in a
    // browser.
    final source = [...legacy, ...declared].join(';');
    if (source.isEmpty || source.length > 4096) return '';
    var css = BlockCss.parse(
      source.length > maxBlockStyleLength ? _trimDeclarations(source) : source,
    );
    // A width in pixels on a centred table is its max-width: it shrinks on a
    // phone the way a mail's media query makes it.
    if (withWidth &&
        css.width?.unit == CssLengthUnit.px &&
        css.centered &&
        css.maxWidth == null) {
      css = BlockCss.parse('${css.toCss()};max-width:${css.width};width:auto');
    }
    // `width:100%` is what a block does anyway.
    if (css.width == const CssLength(100, CssLengthUnit.percent)) {
      css = BlockCss.parse('${css.toCss()};width:auto');
    }
    final text = css.toCss();
    return text.length > maxBlockStyleLength ? '' : text;
  }

  /// The declarations of [source] a block style keeps, so that a long inline
  /// style full of properties nobody draws still yields the few that matter.
  static String _trimDeclarations(String source) {
    const kept = {
      'background-color',
      'background',
      'color',
      'padding',
      'padding-top',
      'padding-right',
      'padding-bottom',
      'padding-left',
      'margin',
      'margin-top',
      'margin-bottom',
      'margin-left',
      'margin-right',
      'max-width',
      'width',
      'border-radius',
      'border',
      'border-top',
      'border-right',
      'border-bottom',
      'border-left',
    };
    final parts = <String>[];
    for (final entry in getStyleObjectFromCss(source).entries) {
      if (kept.contains(entry.key.toLowerCase())) {
        parts.add('${entry.key}:${entry.value}');
      }
    }
    final joined = parts.join(';');
    return joined.length > maxBlockStyleLength ? '' : joined;
  }

  /// [outer] and [inner] merged, [inner] winning.
  static String _mergeCss(String outer, String inner) {
    if (outer.isEmpty) return inner;
    if (inner.isEmpty) return outer;
    final merged = BlockCss.parse('$outer;$inner').toCss();
    return merged.length > maxBlockStyleLength ? inner : merged;
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  // ---------------------------------------------------------------------
  // Lists and code
  // ---------------------------------------------------------------------

  ListItemNode _convertListItem(
    dom.Element element,
    ListType type,
    _Inherited inherited, {
    required int depth,
  }) {
    final checked = element.attributes['aria-checked'];
    final item = $createListItemNode(
      type == ListType.check ? checked == 'true' : null,
    );
    final itemInherited = inherited.withText(
      _textCss(element, _declarations(element)),
    );
    for (final child in element.nodes) {
      item.appendAll(
        _convert(
          child,
          _Inherited(format: 0, text: itemInherited.text),
          depth: depth + 1,
        ),
      );
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
}

/// Parses [html] into block-level nodes ready to be inserted.
///
/// Must be called inside an update.
List<LexicalNode> $generateNodesFromHtml(
  String html, {
  List<HtmlNodeImport> custom = const [],
  HtmlImportLimits limits = HtmlImportLimits.defaults,
  HtmlImageFactory? createImage,
}) => HtmlImport(
  custom: custom,
  limits: limits,
  createImage: createImage,
).parse(html);
