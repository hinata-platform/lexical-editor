// Run it with:  dart run example/main.dart
//
// HTML in and out — for text that has to leave the editor, and for text
// pasted in from a browser, a mail client or a CMS.
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_html/lexical_html.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

LexicalEditor makeEditor() => LexicalEditor(
  nodes: [...richTextNodes, ...listNodes, ...linkNodes, ...codeNodes],
);

void main() {
  // 1. Export ------------------------------------------------------------
  // The tags everything understands — <strong>, not <span class="lx-bold">.
  // That is the whole point: text leaving this editor has to be readable by
  // things that have never heard of it.
  final editor = makeEditor();
  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createHeadingNode(HeadingTag.h2)..append($createTextNode('Title')),
      )
      ..append(
        $createParagraphNode()
          ..append($createTextNode('Text with '))
          ..append($createTextNode('bold')..setFormat(TextFormat.bold.bit))
          ..append($createTextNode(' and '))
          ..append(
            $createLinkNode('https://example.org')
              ..append($createTextNode('a link')),
          ),
      )
      ..append(
        $createListNode(ListType.check)
          ..append($createListItemNode(true)..append($createTextNode('done')))
          ..append($createListItemNode(false)..append($createTextNode('open'))),
      );
  }, discrete: true);

  final html = editor.read($generateHtmlFromNodes);
  print('exported:\n$html\n');

  // 2. Escaping ----------------------------------------------------------
  // The one thing an HTML serializer must never get wrong. A document is
  // untrusted input and may contain anything at all.
  final hostile = makeEditor();
  hostile.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('</p><script>alert("x")</script>')),
      );
  }, discrete: true);
  final escaped = hostile.read($generateHtmlFromNodes);
  print('a document containing markup comes out as text:');
  print('  $escaped');
  print('  contains a live <script>: ${escaped.contains('<script>')}\n');

  // 3. Import ------------------------------------------------------------
  final pasted = makeEditor();
  pasted.update(() {
    $getRoot()
      ..clear()
      ..appendAll(
        $generateNodesFromHtml(
          '<h1>From the browser</h1>'
          '<p>A <b>bold</b> paragraph and <custom-thing>something foreign</custom-thing>.</p>'
          '<ol start="3"><li>three</li><li>four</li></ol>'
          '<script>alert(1)</script>',
        ),
      );
  }, discrete: true);

  print(
    'imported blocks: '
    '${pasted.read(() => $getRoot().children.map((n) => n.type).toList())}',
  );
  final pastedText = pasted.read(() => $getRoot().getTextContent());
  print('text: ${pastedText.replaceAll('\n', ' ⏎ ')}');
  print('\n  An unknown wrapper contributed its text rather than nothing —');
  print('  a paste that silently loses content is the outcome to design');
  print('  against. <script> contributed nothing at all: that is code.');

  // 4. Bounded -----------------------------------------------------------
  // Pasted markup is untrusted input, so nesting is capped rather than fatal.
  final deep = makeEditor();
  deep.update(() {
    $getRoot()
      ..clear()
      ..appendAll(
        $generateNodesFromHtml('${'<div>' * 500}tief${'</div>' * 500}'),
      );
  }, discrete: true);
  print(
    '\n500 levels of nesting parsed without overflowing the stack: '
    '${deep.read(() => $getRoot().childrenSize)} block(s) kept',
  );
}
