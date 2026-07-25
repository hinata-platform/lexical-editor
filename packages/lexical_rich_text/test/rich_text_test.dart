import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: richTextNodes);

void main() {
  test('heading tags map to levels', () {
    expect(HeadingTag.h1.level, 1);
    expect(HeadingTag.h6.level, 6);
    expect(HeadingTag.fromWire('h3'), HeadingTag.h3);
    expect(HeadingTag.fromWire('h9'), HeadingTag.h1);
  });

  test('a heading keeps its tag across an edit', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createHeadingNode(HeadingTag.h3)..append($createTextNode('Titel')),
      );
    }, discrete: true);

    editor.update(() {
      ($getRoot().getFirstChild()! as ElementNode).setIndent(1);
    }, discrete: true);

    editor.read(() {
      final heading = $getRoot().getFirstChild();
      expect(heading, isA<HeadingNode>());
      expect((heading! as HeadingNode).tag, HeadingTag.h3);
    });
  });

  test('setTag changes the level', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append($createHeadingNode()..setTag(HeadingTag.h5));
    }, discrete: true);
    expect(
      editor.read(() => ($getRoot().getFirstChild()! as HeadingNode).tag),
      HeadingTag.h5,
    );
  });

  test('a quote round-trips with only the element base shape', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append($createQuoteNode()..append($createTextNode('Zitat')));
    }, discrete: true);

    final json = editor.toJson();
    final quote = ((json['root']! as Map)['children']! as List).first as Map;
    expect(quote.keys.toSet(), {
      'children',
      'direction',
      'format',
      'indent',
      'type',
      'version',
    });
    expect(
      jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
      isNull,
    );
  });

  test('the package can be omitted without breaking the core', () {
    // A bare core editor still works; it simply does not know these types.
    final bare = LexicalEditor();
    expect(bare.registry.knows('heading'), isFalse);
    expect(bare.registry.knows('paragraph'), isTrue);
  });
}
