import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  test('a replacement from an update that threw does not come back', () {
    final editor = LexicalEditor();
    registerRichText(editor);
    editor.update(() {
      $getRoot()
        ..clear()
        ..append($createParagraphNode()..append($createTextNode('old')));
    }, discrete: true);
    final old = editor.editorState;

    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      paragraph.append($createTextNode(' new'));
    }, discrete: true);
    expect(editor.read(() => $getRoot().getTextContent()), 'old new');

    expect(
      () => editor.update(() {
        editor.setEditorState(old);
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(editor.read(() => $getRoot().getTextContent()), 'old new');

    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      paragraph.append($createTextNode('!'));
    }, discrete: true);
    expect(editor.read(() => $getRoot().getTextContent()), 'old new!');
  });
}
