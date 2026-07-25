import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: codeNodes);

void main() {
  test('a code block keeps its language across an edit', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createCodeNode('dart')..append($createTextNode('void main() {}')),
      );
    }, discrete: true);

    editor.update(() {
      ($getRoot().getFirstChild()! as ElementNode).setIndent(1);
    }, discrete: true);

    expect(
      editor.read(() => ($getRoot().getFirstChild()! as CodeNode).language),
      'dart',
    );
  });

  test('language is emitted even when null', () {
    final editor = _editor();
    editor.update(() => $getRoot().append($createCodeNode()), discrete: true);
    final code =
        ((editor.toJson()['root']! as Map)['children']! as List).first as Map;
    expect(code.containsKey('language'), isTrue);
    expect(code['language'], isNull);
  });

  test('newlines inside a code block survive the round trip', () {
    // A code block authored by appending a multi-line text node keeps the
    // newlines inside that node. Real Lexical preserves them, so splitting
    // them here would break compatibility with documents it produces.
    const source = 'void main() {\n  print("hi");\n}';
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createCodeNode('dart')..append($createTextNode(source)),
      );
    }, discrete: true);

    final json = editor.toJson();
    final code = ((json['root']! as Map)['children']! as List).first as Map;
    final text = (code['children']! as List).first as Map;
    expect(text['text'], source);
    expect(
      jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
      isNull,
    );
  });

  test('a highlight run never merges with plain text', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createCodeNode('dart')
          ..append($createCodeHighlightNode('void', 'keyword'))
          ..append($createTextNode(' main')),
      );
    }, discrete: true);

    editor.read(() {
      final code = $getRoot().getFirstChild()! as CodeNode;
      expect(
        code.childrenSize,
        2,
        reason: 'merging requires equal types, which keeps runs addressable',
      );
      expect(code.getFirstChild(), isA<CodeHighlightNode>());
    });
  });

  test('a highlight run keeps its type and classification when cloned', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createCodeNode()..append($createCodeHighlightNode('const', 'keyword')),
      );
    }, discrete: true);

    editor.update(() {
      final code = $getRoot().getFirstChild()! as CodeNode;
      (code.getFirstChild()! as CodeHighlightNode).setStyle('color: red');
    }, discrete: true);

    editor.read(() {
      final run = ($getRoot().getFirstChild()! as CodeNode).getFirstChild();
      expect(run, isA<CodeHighlightNode>());
      expect((run! as CodeHighlightNode).highlightType, 'keyword');
      expect(run.getTextContent(), 'const');
    });
  });
}
