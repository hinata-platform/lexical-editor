import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: codeNodes);
  registerRichText(editor);
  registerCode(editor);
  return editor;
}

void _seedCode(LexicalEditor editor, String source) {
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createCodeNode('dart')..append($createTextNode(source)));
  }, discrete: true);
}

void _caretAtEnd(LexicalEditor editor) {
  editor.update(() {
    final code = $getRoot().getFirstChild()! as ElementNode;
    (code.getFirstChild()! as TextNode).selectEnd();
  }, discrete: true);
}

void main() {
  test('Enter inserts a newline instead of splitting the block', () {
    // The canonical fixture keeps a code block's line breaks inside one text
    // node, so this is the wire format's behaviour, not a preference.
    final editor = _editor();
    _seedCode(editor, 'void main() {');
    _caretAtEnd(editor);
    editor.dispatchCommand(insertParagraphCommand, null);
    expect(editor.read(() => $getRoot().childrenSize), 1);
    expect(
      editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
      'void main() {\n',
    );
  });

  test('Tab indents rather than moving focus', () {
    final editor = _editor();
    _seedCode(editor, 'void main() {\n');
    _caretAtEnd(editor);
    editor
      ..dispatchCommand(insertTabCommand, null)
      ..dispatchCommand(insertTextCommand, 'print(1);');
    expect(
      editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
      'void main() {\n  print(1);',
    );
  });

  test('outside a code block nothing changes', () {
    final editor = _editor();
    editor.update(() {
      $getRoot()
        ..clear()
        ..append($createParagraphNode()..append($createTextNode('Hallo')));
    }, discrete: true);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).selectEnd();
    }, discrete: true);
    editor.dispatchCommand(insertParagraphCommand, null);
    expect(editor.read(() => $getRoot().childrenSize), 2);
  });

  test('an edited code block still round-trips', () {
    final editor = _editor();
    _seedCode(editor, 'void main() {');
    _caretAtEnd(editor);
    editor
      ..dispatchCommand(insertParagraphCommand, null)
      ..dispatchCommand(insertTabCommand, null)
      ..dispatchCommand(insertTextCommand, r'print("hi");')
      ..dispatchCommand(insertParagraphCommand, null)
      ..dispatchCommand(insertTextCommand, '}');
    final json = editor.toJson();
    expect(
      jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
      isNull,
    );
    expect(
      editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
      'void main() {\n  print("hi");\n}',
    );
  });
}
