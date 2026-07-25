import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: hashtagNodes);

void main() {
  test('a hashtag serializes as a text node with a different type', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append($createHashtagNode('#flutter')),
      );
    }, discrete: true);

    final paragraph =
        ((editor.toJson()['root']! as Map)['children']! as List).first as Map;
    final hashtag = (paragraph['children']! as List).first as Map;
    expect(hashtag['type'], 'hashtag');
    expect(hashtag['text'], '#flutter');
    expect(hashtag.keys.toSet(), {
      'detail',
      'format',
      'mode',
      'style',
      'text',
      'type',
      'version',
    });
  });

  test('a hashtag never merges into surrounding text', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..append($createTextNode('siehe '))
          ..append($createHashtagNode('#dart'))
          ..append($createTextNode(' dort')),
      );
    }, discrete: true);

    editor.read(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      expect(paragraph.childrenSize, 3);
      expect(paragraph.getChildAtIndex(1), isA<HashtagNode>());
    });
  });

  test('a hashtag stays a hashtag when cloned', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append($createHashtagNode('#a')),
      );
    }, discrete: true);

    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as HashtagNode).setTextContent('#b');
    }, discrete: true);

    editor.read(() {
      final tag = ($getRoot().getFirstChild()! as ElementNode).getFirstChild();
      expect(tag, isA<HashtagNode>());
      expect(tag!.getTextContent(), '#b');
    });
  });
}
