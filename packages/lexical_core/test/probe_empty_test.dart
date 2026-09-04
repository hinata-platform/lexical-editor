import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _rt() {
  final e = LexicalEditor();
  registerRichText(e);
  return e;
}

List<String> _blocks(LexicalEditor e) =>
    e.read(() => $getRoot().children.map((n) => n.getTextContent()).toList());

void main() {
  test('probe: backspace in an empty paragraph between two others', () {
    final e = _rt();
    e.update(() {
      final root = $getRoot()..clear();
      root.append($createParagraphNode()..append($createTextNode('a')));
      root.append($createParagraphNode());            // the empty one
      root.append($createParagraphNode()..append($createTextNode('b')));
    }, discrete: true);
    print('PROBE before: ${_blocks(e)}');

    e.update(() {
      final empty = $getRoot().children.toList()[1] as ElementNode;
      empty.selectStart();
    }, discrete: true);
    print('PROBE selection: ${e.read(() => $getSelection())}');

    e.dispatchCommand(deleteCharacterCommand, true);
    print('PROBE after backspace: ${_blocks(e)}');
  });

  test('probe: backspace in a trailing empty paragraph', () {
    final e = _rt();
    e.update(() {
      final root = $getRoot()..clear();
      root.append($createParagraphNode()..append($createTextNode('a')));
      root.append($createParagraphNode());
    }, discrete: true);
    e.update(() {
      ($getRoot().children.toList()[1] as ElementNode).selectStart();
    }, discrete: true);
    e.dispatchCommand(deleteCharacterCommand, true);
    print('PROBE trailing after: ${_blocks(e)}');
  });

  test('probe: several empty paragraphs in a row', () {
    final e = _rt();
    e.update(() {
      final root = $getRoot()..clear();
      root.append($createParagraphNode()..append($createTextNode('a')));
      root.append($createParagraphNode());
      root.append($createParagraphNode());
      root.append($createParagraphNode());
    }, discrete: true);
    for (var i = 0; i < 3; i++) {
      e.update(() {
        ($getRoot().children.last as ElementNode).selectEnd();
      }, discrete: true);
      e.dispatchCommand(deleteCharacterCommand, true);
      print('PROBE run $i: ${_blocks(e)}');
    }
  });
}
