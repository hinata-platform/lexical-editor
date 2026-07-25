import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('text normalization', () {
    test('adjacent identical runs merge', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph
          ..append($createTextNode('Hallo '))
          ..append($createTextNode('Welt'));
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 1);
        expect(paragraph.getTextContent(), 'Hallo Welt');
      });
    });

    test('runs with different formats do not merge', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph
          ..append($createTextNode('normal '))
          ..append($createTextNode('fett')..toggleFormat(TextFormat.bold));
      }, discrete: true);

      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).childrenSize,
        ),
        2,
      );
    });

    test('a tab is never absorbed by its neighbours', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph
          ..append($createTextNode('vor'))
          ..append($createTabNode())
          ..append($createTextNode('nach'));
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 3);
        expect(paragraph.getChildAtIndex(1), isA<TabNode>());
      });
    });

    test('empty text nodes are dropped', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph
          ..append($createTextNode('a'))
          ..append($createTextNode(''))
          ..append($createTextNode('b'));
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 1);
        expect(paragraph.getTextContent(), 'ab');
      });
    });

    test('newlines in a text node survive normalization', () {
      // Splitting them would be a reasonable editor behaviour but a wire
      // incompatibility: real Lexical keeps them, so the core keeps them too.
      // Editing paths that want line breaks build them explicitly.
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph.append($createTextNode('eins\nzwei\ndrei'));
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 1);
        expect(paragraph.getTextContent(), 'eins\nzwei\ndrei');
        expect(assertTreeIntegrity($getRoot()), isTrue);
      });
    });

    test('a merged document still round-trips as a fixed point', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        paragraph
          ..append($createTextNode('a'))
          ..append($createTextNode('b'))
          ..append($createTextNode('c'));
      }, discrete: true);

      final once = editor.toJson();
      final twice = editor.parseEditorState(once).toJson();
      expect(jsonFirstDifference(once, twice), isNull);
    });
  });

  group('registered transforms', () {
    test('run for dirty nodes of their type', () {
      final editor = LexicalEditor();
      editor.registerNodeTransform('text', (node) {
        final text = node as TextNode;
        if (!text.getTextContent().startsWith('!')) {
          text.setTextContent('!${text.getTextContent()}');
        }
      });

      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('hallo')),
        );
      }, discrete: true);

      expect(editor.read(() => $getRoot().getTextContent()), '!hallo');
    });

    test('apply to content that already exists when registered', () {
      final editor = LexicalEditor();
      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('hallo')),
        );
      }, discrete: true);

      editor.registerNodeTransform('text', (node) {
        final text = node as TextNode;
        if (!text.getTextContent().endsWith('!')) {
          text.setTextContent('${text.getTextContent()}!');
        }
      });

      expect(editor.read(() => $getRoot().getTextContent()), 'hallo!');
    });

    test('run to a fixed point, seeing each other\'s output', () {
      final editor = LexicalEditor();
      editor
        ..registerNodeTransform('text', (node) {
          final text = node as TextNode;
          if (text.getTextContent() == 'a') text.setTextContent('b');
        })
        ..registerNodeTransform('text', (node) {
          final text = node as TextNode;
          if (text.getTextContent() == 'b') text.setTextContent('c');
        });

      editor.update(() {
        $getRoot().append($createParagraphNode()..append($createTextNode('a')));
      }, discrete: true);

      expect(editor.read(() => $getRoot().getTextContent()), 'c');
    });

    test('a non-converging transform is caught rather than hanging', () {
      final editor = LexicalEditor();
      var flip = false;
      editor.registerNodeTransform('text', (node) {
        final text = node as TextNode;
        flip = !flip;
        text.setTextContent(flip ? 'ping' : 'pong');
      });

      expect(
        () => editor.update(() {
          $getRoot().append(
            $createParagraphNode()..append($createTextNode('start')),
          );
        }, discrete: true),
        throwsA(
          isA<LexicalStateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('did not converge'), contains('text')),
          ),
        ),
      );
    });

    test('the root transform runs last, as an update finalizer', () {
      final editor = LexicalEditor();
      final order = <String>[];
      editor
        ..registerNodeTransform('paragraph', (_) => order.add('paragraph'))
        ..registerNodeTransform('root', (_) => order.add('root'));

      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);

      expect(order.last, 'root');
      expect(order, contains('paragraph'));
    });

    test('a root transform can enforce a trailing paragraph', () {
      final editor = LexicalEditor();
      editor.registerNodeTransform('root', (node) {
        final root = node as ElementNode;
        final last = root.getLastChild();
        if (last == null || last.type != 'paragraph') {
          root.append($createParagraphNode());
        }
      });

      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('inhalt')),
        );
      }, discrete: true);
      editor.update(() {
        $getRoot().getLastChild()!.remove();
      }, discrete: true);

      expect(editor.read(() => $getRoot().getLastChild()?.type), 'paragraph');
    });

    test('registering for an unknown type is rejected', () {
      final editor = LexicalEditor();
      expect(
        () => editor.registerNodeTransform('gibt-es-nicht', (_) {}),
        throwsA(isA<LexicalStateError>()),
      );
    });

    test('unsubscribing stops the transform', () {
      final editor = LexicalEditor();
      final unsubscribe = editor.registerNodeTransform('text', (node) {
        (node as TextNode).setTextContent('ersetzt');
      });
      unsubscribe();

      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('original')),
        );
      }, discrete: true);

      expect(editor.read(() => $getRoot().getTextContent()), 'original');
    });
  });
}
