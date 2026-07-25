import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: richTextNodes);
  registerRichText(editor);
  return editor;
}

List<String> _types(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

List<String> _texts(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

void _caretAt(LexicalEditor editor, int block, int offset) {
  editor.update(() {
    final element = $getRoot().getChildAtIndex(block)! as ElementNode;
    (element.getFirstChild()! as TextNode).select(offset, offset);
  }, discrete: true);
}

void main() {
  group('heading', () {
    test('Enter at the end starts a paragraph', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createHeadingNode(HeadingTag.h2)..append($createTextNode('Titel')),
          );
      }, discrete: true);
      _caretAt(editor, 0, 5);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_types(editor), ['heading', 'paragraph']);
    });

    test('Enter in the middle splits into two headings of the same level', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createHeadingNode(HeadingTag.h3)
              ..append($createTextNode('Erster Teil')),
          );
      }, discrete: true);
      _caretAt(editor, 0, 6);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_types(editor), ['heading', 'heading']);
      expect(_texts(editor), ['Erster', ' Teil']);
      expect(
        editor.read(() => ($getRoot().getChildAtIndex(1)! as HeadingNode).tag),
        HeadingTag.h3,
      );
    });
  });

  group('quote', () {
    test('Enter leaves the quote, as it does on Lexical web', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createQuoteNode()..append($createTextNode('Zitat')));
      }, discrete: true);
      _caretAt(editor, 0, 5);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_types(editor), ['quote', 'paragraph']);
    });

    test('Shift-Enter continues it', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createQuoteNode()..append($createTextNode('Zitat')));
      }, discrete: true);
      _caretAt(editor, 0, 5);
      editor.dispatchCommand(insertLineBreakCommand, false);
      expect(_types(editor), ['quote']);
      expect(_texts(editor), ['Zitat\n']);
    });
  });
}
