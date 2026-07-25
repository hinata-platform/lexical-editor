import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('sibling pointers', () {
    test('append maintains first, last and size', () {
      final editor = LexicalEditor();
      editor.update(() {
        final root = $getRoot();
        final a = $createParagraphNode();
        final b = $createParagraphNode();
        final c = $createParagraphNode();
        root
          ..append(a)
          ..append(b)
          ..append(c);

        expect(root.childrenSize, 3);
        expect(root.getFirstChild()!.key, a.key);
        expect(root.getLastChild()!.key, c.key);
        expect(a.getNextSibling()!.key, b.key);
        expect(b.getPreviousSibling()!.key, a.key);
        expect(a.getPreviousSibling(), isNull);
        expect(c.getNextSibling(), isNull);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('removing a middle child relinks its neighbours', () {
      final editor = LexicalEditor();
      late NodeKey aKey;
      late NodeKey cKey;
      editor.update(() {
        final root = $getRoot();
        final a = $createParagraphNode();
        final b = $createParagraphNode();
        final c = $createParagraphNode();
        root
          ..append(a)
          ..append(b)
          ..append(c);
        aKey = a.key;
        cKey = c.key;
        b.remove();

        expect(root.childrenSize, 2);
        expect(root.getFirstChild()!.key, aKey);
        expect(root.getLastChild()!.key, cKey);
        expect(a.getNextSibling()!.key, cKey);
        expect(c.getPreviousSibling()!.key, aKey);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('insertBefore and insertAfter keep the chain consistent', () {
      final editor = LexicalEditor();
      editor.update(() {
        final root = $getRoot();
        final middle = $createParagraphNode();
        root.append(middle);
        final before = $createParagraphNode();
        final after = $createParagraphNode();
        middle
          ..insertBefore(before)
          ..insertAfter(after);

        expect(root.childrenSize, 3);
        expect(root.children.map((node) => node.key).toList(), [
          before.key,
          middle.key,
          after.key,
        ]);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('moving a node between parents leaves both consistent', () {
      final editor = LexicalEditor();
      editor.update(() {
        final root = $getRoot();
        final source = $createParagraphNode();
        final target = $createParagraphNode();
        final text = $createTextNode('wandern');
        source.append(text);
        root
          ..append(source)
          ..append(target);

        target.append(text);

        expect(source.childrenSize, 0);
        expect(source.getFirstChild(), isNull);
        expect(target.childrenSize, 1);
        expect(text.getParent()!.key, target.key);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('splice replaces a range', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final one = $createTextNode('one');
        final two = $createTextNode('two');
        final three = $createTextNode('three');
        paragraph.appendAll([one, two, three]);

        final replacement = $createTextNode('zwei');
        paragraph.splice(1, 1, [replacement]);

        expect(
          paragraph.children.map((node) => node.getTextContent()).toList(),
          ['one', 'zwei', 'three'],
        );
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('clear empties an element', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('a'))
          ..append($createTextNode('b'));
        $getRoot().append(paragraph);
        paragraph.clear();

        expect(paragraph.childrenSize, 0);
        expect(paragraph.getFirstChild(), isNull);
        expect(paragraph.getLastChild(), isNull);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });
  });

  group('traversal', () {
    test('getChildAtIndex walks from the nearer end', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        for (var i = 0; i < 10; i++) {
          paragraph.append($createTextNode('$i'));
        }
        expect(paragraph.getChildAtIndex(0)!.getTextContent(), '0');
        expect(paragraph.getChildAtIndex(9)!.getTextContent(), '9');
        expect(paragraph.getChildAtIndex(4)!.getTextContent(), '4');
        expect(paragraph.getChildAtIndex(-1)!.getTextContent(), '9');
        expect(paragraph.getChildAtIndex(10), isNull);
      }, discrete: true);
    });

    test('isBefore orders across subtrees', () {
      final editor = LexicalEditor();
      editor.update(() {
        final first = $createParagraphNode();
        final second = $createParagraphNode();
        final a = $createTextNode('a');
        final b = $createTextNode('b');
        first.append(a);
        second.append(b);
        $getRoot()
          ..append(first)
          ..append(second);

        expect(a.isBefore(b), isTrue);
        expect(b.isBefore(a), isFalse);
        expect(first.isBefore(second), isTrue);
      }, discrete: true);
    });

    test('getNodesBetween covers the inclusive range in order', () {
      final editor = LexicalEditor();
      editor.update(() {
        final first = $createParagraphNode();
        final second = $createParagraphNode();
        final a = $createTextNode('a');
        final b = $createTextNode('b');
        final c = $createTextNode('c');
        first
          ..append(a)
          ..append(b);
        second.append(c);
        $getRoot()
          ..append(first)
          ..append(second);

        final texts = a
            .getNodesBetween(c)
            .map((node) => node.getTextContent())
            .where((text) => text.isNotEmpty)
            .toList();
        expect(texts, containsAllInOrder(['a', 'b', 'c']));
      }, discrete: true);
    });

    test('indexWithinParent reflects position', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final a = $createTextNode('a');
        final b = $createTextNode('b');
        paragraph
          ..append(a)
          ..append(b);
        expect(a.indexWithinParent, 0);
        expect(b.indexWithinParent, 1);
      }, discrete: true);
    });
  });

  group('structural rules', () {
    test('a text node cannot be a direct child of the root', () {
      final editor = LexicalEditor();
      expect(
        () => editor.update(() {
          $getRoot().append($createTextNode('nein'));
        }, discrete: true),
        throwsA(isA<LexicalTreeError>()),
      );
    });

    test('the root cannot be removed or re-parented', () {
      final editor = LexicalEditor();
      editor.update(() {
        expect($getRoot().remove, throwsA(isA<LexicalTreeError>()));
        expect(
          () => $getRoot().insertAfter($createParagraphNode()),
          throwsA(isA<LexicalTreeError>()),
        );
      }, discrete: true);
    });

    test('appending an ancestor into its own descendant is rejected', () {
      final editor = LexicalEditor();
      expect(
        () => editor.update(() {
          final outer = $createParagraphNode();
          final inner = $createParagraphNode();
          outer.append(inner);
          $getRoot().append(outer);
          inner.append(outer);
        }, discrete: true),
        throwsA(isA<LexicalTreeError>()),
      );
    });
  });
}
