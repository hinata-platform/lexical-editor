import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_mark/lexical_mark.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: markNodes);

void main() {
  test('a mark carries its ids and is inline', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append(
          $createMarkNode(['comment-1', 'comment-2'])
            ..append($createTextNode('markiert')),
        ),
      );
    }, discrete: true);

    editor.read(() {
      final mark =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as MarkNode;
      expect(mark.isInline, isTrue);
      expect(mark.ids, ['comment-1', 'comment-2']);
      expect(mark.hasId('comment-2'), isTrue);
    });
  });

  test('ids are added and removed without duplicates', () {
    final editor = _editor();
    editor.update(() {
      final mark = $createMarkNode(['a']);
      $getRoot().append($createParagraphNode()..append(mark));
      mark
        ..addId('b')
        ..addId('a')
        ..removeId('a');
    }, discrete: true);

    editor.read(() {
      final mark =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as MarkNode;
      expect(mark.ids, ['b']);
    });
  });

  test('the id list is not modifiable through the getter', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append($createParagraphNode()..append($createMarkNode(['a'])));
    }, discrete: true);

    editor.read(() {
      final mark =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as MarkNode;
      expect(() => mark.ids.add('b'), throwsUnsupportedError);
    });
  });

  test('ids survive cloning', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append($createMarkNode(['a', 'b'])),
      );
    }, discrete: true);

    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as MarkNode).setIndent(1);
    }, discrete: true);

    editor.read(() {
      final mark =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as MarkNode;
      expect(mark.ids, ['a', 'b']);
    });
  });
}
