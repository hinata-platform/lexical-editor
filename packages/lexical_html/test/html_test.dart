import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_html/lexical_html.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(
  nodes: [...richTextNodes, ...listNodes, ...linkNodes, ...codeNodes],
);

/// Builds a document and returns its HTML.
String _html(LexicalEditor editor, void Function(ElementNode root) build) {
  editor.update(() => build($getRoot()..clear()), discrete: true);
  return editor.read($generateHtmlFromNodes);
}

/// Parses [html] into a document and returns the editor holding it.
LexicalEditor _parse(String html) {
  final editor = _editor();
  editor.update(() {
    $getRoot()
      ..clear()
      ..appendAll($generateNodesFromHtml(html));
  }, discrete: true);
  return editor;
}

List<String> _types(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

String _text(LexicalEditor editor) =>
    editor.read(() => $getRoot().getTextContent());

void main() {
  group('export', () {
    test('blocks become the tags everyone understands', () {
      final html = _html(_editor(), (root) {
        root
          ..append(
            $createHeadingNode(HeadingTag.h2)..append($createTextNode('Titel')),
          )
          ..append($createParagraphNode()..append($createTextNode('Absatz')))
          ..append($createQuoteNode()..append($createTextNode('Zitat')));
      });
      expect(html, '<h2>Titel</h2><p>Absatz</p><blockquote>Zitat</blockquote>');
    });

    test('formats nest as semantic tags', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createParagraphNode()..append(
            $createTextNode('beides')
              ..setFormat(TextFormat.bold.bit | TextFormat.italic.bit),
          ),
        );
      });
      expect(html, '<p><strong><em>beides</em></strong></p>');
    });

    test('a link keeps its attributes', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createParagraphNode()..append(
            $createLinkNode('https://example.org', title: 'Titel')
              ..append($createTextNode('hier')),
          ),
        );
      });
      expect(
        html,
        '<p><a href="https://example.org" title="Titel">hier</a></p>',
      );
    });

    test('lists carry their kind, and check lists their state', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createListNode(ListType.check)
            ..append($createListItemNode(true)..append($createTextNode('a')))
            ..append($createListItemNode(false)..append($createTextNode('b'))),
        );
      });
      expect(
        html,
        '<ul><li role="checkbox" aria-checked="true">a</li>'
        '<li role="checkbox" aria-checked="false">b</li></ul>',
      );
    });

    test('code keeps its language and its content', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createCodeNode('dart')..append($createTextNode('a < b && c > d')),
        );
      });
      expect(
        html,
        '<pre><code class="language-dart">a &lt; b &amp;&amp; c &gt; d'
        '</code></pre>',
      );
    });

    test('document content can never become markup', () {
      // The one thing an HTML serializer must not get wrong. A document is
      // untrusted input, and it may contain anything at all.
      final html = _html(_editor(), (root) {
        root.append(
          $createParagraphNode()
            ..append($createTextNode('</p><script>alert("x")</script>')),
        );
      });
      expect(html.contains('<script>'), isFalse);
      expect(
        html,
        '<p>&lt;/p&gt;&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;</p>',
      );
    });

    test('a style attribute is escaped too', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createParagraphNode()..append(
            $createTextNode('x')..setStyle('color: red" onload="alert(1)'),
          ),
        );
      });
      expect(html.contains('onload="alert'), isFalse);
    });

    test('alignment and direction survive', () {
      final html = _html(_editor(), (root) {
        root.append(
          $createParagraphNode()
            ..append($createTextNode('mitte'))
            ..setFormat(ElementFormat.center)
            ..setDirection(NodeDirection.rtl),
        );
      });
      expect(html, '<p dir="rtl" style="text-align: center">mitte</p>');
    });
  });

  group('import', () {
    test('maps the tags a paste actually arrives as', () {
      final editor = _parse(
        '<h1>Titel</h1><p>Ein <b>fetter</b> Absatz</p>'
        '<blockquote>Zitat</blockquote>',
      );
      expect(_types(editor), ['heading', 'paragraph', 'quote']);
      expect(
        editor.read(
          () => ($getRoot().getChildAtIndex(1)! as ElementNode).children
              .whereType<TextNode>()
              .map((node) => (node.getTextContent(), node.getFormat()))
              .toList(),
        ),
        [('Ein ', 0), ('fetter', TextFormat.bold.bit), (' Absatz', 0)],
      );
    });

    test('nested formatting combines', () {
      final editor = _parse('<p><strong><em>beides</em></strong></p>');
      editor.read(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        expect(node.getFormat(), TextFormat.bold.bit | TextFormat.italic.bit);
      });
    });

    test('lists come back as lists', () {
      final editor = _parse('<ol start="3"><li>eins</li><li>zwei</li></ol>');
      editor.read(() {
        final list = $getRoot().getFirstChild()! as ListNode;
        expect(list.listType, ListType.number);
        expect(list.start, 3);
        expect(
          list.children.cast<ListItemNode>().map((item) => item.value).toList(),
          [3, 4],
        );
      });
    });

    test('a check list is recognized by its ARIA state', () {
      final editor = _parse(
        '<ul><li role="checkbox" aria-checked="true">a</li>'
        '<li role="checkbox" aria-checked="false">b</li></ul>',
      );
      editor.read(() {
        final list = $getRoot().getFirstChild()! as ListNode;
        expect(list.listType, ListType.check);
        expect(
          list.children
              .cast<ListItemNode>()
              .map((item) => item.checked)
              .toList(),
          [true, false],
        );
      });
    });

    test('unknown tags contribute their text rather than nothing', () {
      // A paste that silently loses content is the outcome worth designing
      // against; an unknown wrapper is not a reason to drop what is inside it.
      final editor = _parse(
        '<p>vor <custom-thing>drin</custom-thing> nach</p>',
      );
      expect(_text(editor), 'vor drin nach');
    });

    test('script and style contribute nothing at all', () {
      final editor = _parse(
        '<p>sichtbar</p><script>alert(1)</script><style>p{}</style>',
      );
      expect(_text(editor), 'sichtbar');
    });

    test('bare inline content is wrapped in a paragraph', () {
      // A text node directly under the root is a structural error, so an
      // import that produced one would fail the integrity check on commit.
      final editor = _parse('nur <b>text</b>');
      expect(_types(editor), ['paragraph']);
      expect(_text(editor), 'nur text');
    });

    test('a URL is kept verbatim, not rewritten', () {
      final editor = _parse('<a href="javascript:void">klick</a>');
      editor.read(() {
        final link = ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<LinkNode>()
            .single;
        expect(link.url, 'javascript:void');
      });
      expect(isSafeUrl('javascript:void'), isFalse);
    });

    test('deep nesting is bounded rather than fatal', () {
      final deep = '${'<div>' * 500}tief${'</div>' * 500}';
      final editor = _parse(deep);
      // It parsed, it did not overflow, and nothing above the limit was kept.
      expect(editor.read(() => $getRoot().childrenSize), lessThanOrEqualTo(1));
    });

    test('an imported document is a valid Lexical document', () {
      final editor = _parse(
        '<h1>Titel</h1><p>Text mit <a href="https://x.test">Link</a></p>'
        '<ul><li>eins</li></ul><pre><code class="language-dart">x</code></pre>',
      );
      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });
  });

  group('both directions', () {
    test('export then import preserves the structure', () {
      final source = _editor();
      final html = _html(source, (root) {
        root
          ..append(
            $createHeadingNode(HeadingTag.h3)..append($createTextNode('Titel')),
          )
          ..append(
            $createParagraphNode()
              ..append($createTextNode('Text mit '))
              ..append($createTextNode('fett')..setFormat(TextFormat.bold.bit))
              ..append($createTextNode(' und '))
              ..append(
                $createLinkNode('https://example.org')
                  ..append($createTextNode('Link')),
              ),
          )
          ..append(
            $createListNode(ListType.bullet)
              ..append($createListItemNode()..append($createTextNode('eins')))
              ..append($createListItemNode()..append($createTextNode('zwei'))),
          );
      });

      final back = _parse(html);
      expect(_types(back), ['heading', 'paragraph', 'list']);
      expect(back.read($generateHtmlFromNodes), html);
    });
  });
}
