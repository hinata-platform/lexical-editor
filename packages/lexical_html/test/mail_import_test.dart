import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_html/lexical_html.dart';
import 'package:lexical_image/image_node.dart';
import 'package:lexical_layout/lexical_layout.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor({bool layouts = true}) => LexicalEditor(
  nodes: [
    ...richTextNodes,
    ...listNodes,
    ...linkNodes,
    ...imageNodes,
    if (layouts) ...layoutNodes,
  ],
);

LexicalNode? _image(HtmlImage image) => $createImageNode(
  src: image.src,
  altText: image.alt,
  width: image.width ?? 0,
  height: image.height ?? 0,
);

LexicalEditor _import(String html, {bool layouts = true}) {
  final editor = _editor(layouts: layouts);
  editor.update(() {
    $getRoot()
      ..clear()
      ..appendAll($generateNodesFromHtml(html, createImage: _image));
  }, discrete: true);
  return editor;
}

/// The document as an outline: `type[style]{children}` per element, text in
/// quotes, images as `image WxH`.
String _outline(LexicalEditor editor) => editor.read(() {
  String walk(LexicalNode node) {
    if (node is ImageNode) {
      return 'image ${node.width.round()}x${node.height.round()}';
    }
    if (node is TextNode) return '"${node.getTextContent()}"';
    if (node is LineBreakNode) return 'br';
    if (node is! ElementNode) return node.type;
    final buffer = StringBuffer(node.type);
    if (node is LayoutContainerNode) buffer.write('(${node.templateColumns})');
    final format = node.getFormat();
    if (format != ElementFormat.none) buffer.write('<${format.wire}>');
    final css = $getBlockStyle(node);
    if (css.isNotEmpty) buffer.write('[$css]');
    buffer.write('{${node.children.map(walk).join(' ')}}');
    return buffer.toString();
  }

  return $getRoot().children.map(walk).join('\n');
});

void main() {
  group('a transactional mail', () {
    const mail = '''
<html><head><style>.x{color:red}</style><title>t</title></head><body>
<div style="display:none;max-height:0;overflow:hidden">Vorschautext</div>
<table width="100%" bgcolor="#eeeeee"><tr><td align="center">
  <table width="600" align="center" cellpadding="0" bgcolor="#ffffff">
    <tr><td bgcolor="#e60000" style="padding:24px" align="center">
      <font color="#ffffff" size="6"><b>Deine Bestellung</b></font>
    </td></tr>
    <tr>
      <td width="200" style="padding:20px"><img src="https://m.example/a.png" width="160" height="100" alt="Schritt"></td>
      <td style="padding:20px;color:#333333;font-size:14px">Wir <span style="color:#e60000">packen</span> dein Paket.</td>
    </tr>
    <tr><td align="center">
      <table align="center"><tr><td bgcolor="#e60000" style="padding:10px 25px">
        <a href="https://m.example/track" style="color:#ffffff;text-decoration:none">Sendung verfolgen</a>
      </td></tr></table>
    </td></tr>
  </table>
</td></tr></table>
<img src="https://t.example/open.gif" width="1" height="1">
</body></html>''';

    test('keeps its shape', () {
      final outline = _outline(_import(mail));
      // The outer 100 % table is a grey band around a centred 600 px canvas.
      expect(
        outline,
        startsWith('layout-container(1fr)[background-color:#eeeeee]'),
      );
      expect(
        outline,
        contains(
          'layout-container(1fr)'
          '[background-color:#ffffff;margin-left:auto;margin-right:auto;'
          'max-width:600px]',
        ),
      );
      // The header cell's box lands on the paragraph it holds.
      expect(
        outline,
        contains(
          'paragraph<center>[background-color:#e60000;'
          'padding:24px 24px 24px 24px]',
        ),
      );
      // Two cells with content: a row of columns, widths from the cells.
      expect(outline, contains('layout-container(200px 1fr)'));
      expect(outline, contains('image 160x100'));
      // The button: a cell with a fill around a link.
      expect(
        outline,
        contains(
          'paragraph<center>[background-color:#e60000;'
          'padding:10px 25px 10px 25px;margin-left:auto;margin-right:auto;'
          'width:fit-content]{link{"Sendung verfolgen"}}',
        ),
      );
    });

    test('drops what is not shown', () {
      final editor = _import(mail);
      final text = editor.read(() => $getRoot().getTextContent());
      expect(text, isNot(contains('Vorschautext')));
      expect(text, isNot(contains('color:red')));
      expect(_outline(editor), isNot(contains('image 1x1')));
    });

    test('inline CSS becomes text style, inherited the way CSS inherits', () {
      final editor = _import(mail);
      final styles = editor.read(
        () => {
          for (final node in $getRoot().getAllTextNodes())
            if (node is TextNode && node.getTextContent().trim().isNotEmpty)
              node.getTextContent().trim(): node.getStyle(),
        },
      );
      expect(styles['Deine Bestellung'], contains('color: #ffffff'));
      expect(styles['Deine Bestellung'], contains('font-size: 32px'));
      expect(styles['packen'], contains('color: #e60000'));
      expect(styles['packen'], contains('font-size: 14px'));
      expect(styles['Wir'], contains('color: #333333'));
      expect(
        editor.read(
          () => $getRoot()
              .getAllTextNodes()
              .whereType<TextNode>()
              .firstWhere((node) => node.getTextContent() == 'Deine Bestellung')
              .hasFormat(TextFormat.bold),
        ),
        isTrue,
      );
    });

    test('is a valid document that round-trips', () {
      final editor = _import(mail);
      expect(editor.read(() => assertTreeIntegrity($getRoot())), isTrue);
      final json = editor.toJson();
      final again = _editor().parseEditorState(json).toJson();
      expect(jsonFirstDifference(json, again), isNull);
    });
  });

  test('MJML columns become a layout with their widths', () {
    final outline = _outline(
      _import('''
<div style="margin:0px auto;max-width:600px;">
  <!--[if mso | IE]><table><tr><td><![endif]-->
  <div class="mj-column-per-50 mj-outlook-group-fix" style="display:inline-block;width:100%;">
    <img src="https://m.example/b.png" width="300" height="200">
  </div>
  <div class="mj-column-per-50 mj-outlook-group-fix" style="display:inline-block;width:100%;">
    <p style="font-size:14px">Rechts</p>
  </div>
</div>'''),
    );
    expect(
      outline,
      'layout-container(1fr)[margin-top:0px;margin-bottom:0px;'
      'margin-left:auto;margin-right:auto;max-width:600px]'
      '{layout-item{layout-container(50% 50%)[--stack-below:480px]{'
      'layout-item{paragraph{image 300x200}} '
      'layout-item{paragraph{"Rechts"}}}}}',
    );
  });

  test('the columns of an mj-group stay side by side', () {
    final outline = _outline(
      _import('''
<div class="mj-column-per-100 mj-outlook-group-fix" style="width:100%;">
  <div class="mj-column-per-25 mj-outlook-group-fix"><p>A</p></div>
  <div class="mj-column-per-25 mj-outlook-group-fix"><p>B</p></div>
  <div class="mj-column-per-25 mj-outlook-group-fix"><p>C</p></div>
  <div class="mj-column-per-25 mj-outlook-group-fix"><p>D</p></div>
</div>'''),
    );
    expect(outline, contains('layout-container(25% 25% 25% 25%){'));
    expect(outline, isNot(contains('stack-below')));
  });

  test('a divider keeps its border and its one-pixel line', () {
    final editor = _import(
      '<p style="border-top:solid 1px #cccccc;font-size:1px;'
      'margin:0px auto;width:100%"></p>',
    );
    expect(
      _outline(editor),
      'paragraph[margin-top:0px;margin-bottom:0px;margin-left:auto;'
      'margin-right:auto;border-top:1px solid #cccccc]{}',
    );
    expect(
      editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).getTextStyle(),
      ),
      'font-size: 1px;',
    );
  });

  test('an inline block is as wide as its content', () {
    expect(
      _outline(
        _import(
          '<div style="display:inline-block;background:#e60000;'
          'padding:10px 25px">Los</div>',
        ),
      ),
      'paragraph[background-color:#e60000;padding:10px 25px 10px 25px;'
      'width:fit-content]{"Los"}',
    );
  });

  test('a mobile variant is dropped, the desktop one kept', () {
    final text = _import('''
<div class="mobile-only">Klein</div>
<div class="desktop">Groß</div>''').read(() => $getRoot().getTextContent());
    expect(text, 'Groß');
  });

  test('a data table stays text', () {
    final editor = _import(
      '<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>',
    );
    expect(_outline(editor), isNot(contains('layout-container')));
    expect(editor.read(() => $getRoot().getTextContent()), contains('A'));
  });

  test('without the layout nodes a mail imports as blocks and text', () {
    final editor = _import(
      '<table width="600" align="center"><tr>'
      '<td style="background:#e60000">Links</td><td>Rechts</td></tr></table>',
      layouts: false,
    );
    expect(_outline(editor), isNot(contains('layout')));
    expect(_outline(editor), isNot(contains('[')));
    expect(editor.read(() => $getRoot().getTextContent()), 'LinksRechts');
  });

  test('a Lexical layout survives export and import', () {
    final editor = _editor();
    editor.update(() {
      final container = $createLayoutContainerNode('200px 1fr');
      $setBlockStyle(container, 'max-width:600px;margin:0 auto');
      final left = $createLayoutItemNode()
        ..append($createParagraphNode()..append($createTextNode('A')));
      $setBlockStyle(left, 'background-color:#f4f4f4');
      container
        ..append(left)
        ..append(
          $createLayoutItemNode()
            ..append($createParagraphNode()..append($createTextNode('B'))),
        );
      $getRoot()
        ..clear()
        ..append(container);
    }, discrete: true);
    final html = editor.read($generateHtmlFromNodes);
    expect(html, contains('data-lexical-layout-container="true"'));
    expect(html, contains('grid-template-columns: 200px 1fr'));

    final back = _outline(_import(html));
    expect(
      back,
      'layout-container(200px 1fr)'
      '[margin-top:0px;margin-bottom:0px;margin-left:auto;margin-right:auto;'
      'max-width:600px]'
      '{layout-item[background-color:#f4f4f4]{paragraph{"A"}} '
      'layout-item{paragraph{"B"}}}',
    );
  });

  test('a template that is not a template is not exported', () {
    final editor = _editor();
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createLayoutContainerNode('1fr;background:url(x)')
            ..append($createLayoutItemNode()..append($createParagraphNode())),
        );
    }, discrete: true);
    expect(editor.read($generateHtmlFromNodes), isNot(contains('url(')));
  });

  test('deeply nested tables are bounded, not fatal', () {
    final html = '${'<table><tr><td>' * 400}tief${'</td></tr></table>' * 400}';
    expect(() => _import(html), returnsNormally);
  });

  test('style values that are not CSS values are dropped', () {
    final editor = _import(
      '<p><span style="color:expression(alert(1));font-family:url(x)">a</span></p>',
    );
    expect(
      editor.read(
        () => ($getRoot().getAllTextNodes().single as TextNode).getStyle(),
      ),
      isEmpty,
    );
  });
}
