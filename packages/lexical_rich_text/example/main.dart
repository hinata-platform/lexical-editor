// Run it with:  dart run example/main.dart
//
// Headings and quotes, plus the behaviour that makes them feel right: Enter
// at the end of a heading gives you a *paragraph*, because continuing a
// heading is almost never what anyone meant.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

List<String> blocks(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

void main() {
  final editor = LexicalEditor(nodes: richTextNodes);
  registerRichText(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createHeadingNode(HeadingTag.h1)..append($createTextNode('Title')),
      )
      ..append($createQuoteNode()..append($createTextNode('A quotation.')));
  }, discrete: true);

  print('blocks:            ${blocks(editor)}');

  // Enter at the end of the heading.
  editor.update(() {
    final heading = $getRoot().getFirstChild()! as HeadingNode;
    (heading.getLastChild()! as TextNode).selectEnd();
  }, discrete: true);
  editor.dispatchCommand(insertParagraphCommand, null);

  print('after Enter:       ${blocks(editor)}');
  print('  — the new block is a paragraph, not a second heading.');

  // Alignment and indentation belong to the element, not to its text.
  editor.update(() {
    ($getRoot().getLastChild()! as ElementNode)
      ..setFormat(ElementFormat.center)
      ..setIndent(1);
  }, discrete: true);
  editor.read(() {
    final last = $getRoot().getLastChild()! as ElementNode;
    print(
      'last block:        align=${last.getFormat().wire} '
      'indent=${last.getIndent()}',
    );
  });

  // Text formats are a bitmask, so several apply at once.
  editor.update(() {
    final title =
        ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
            as TextNode;
    title.setFormat(TextFormat.bold.bit | TextFormat.italic.bit);
  }, discrete: true);
  editor.read(() {
    final text =
        ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
            as TextNode;
    print(
      'title formats:     bold=${text.hasFormat(TextFormat.bold)} '
      'italic=${text.hasFormat(TextFormat.italic)}',
    );
  });

  print(
    '\nheading level survives the wire format: '
    '${editor.toJsonString().contains('"tag":"h1"')}',
  );
}
