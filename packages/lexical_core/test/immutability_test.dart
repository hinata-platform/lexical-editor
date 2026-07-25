import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('committed state is frozen', () {
    test('mutation outside update throws', () {
      final editor = LexicalEditor();
      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);

      final paragraph = editor.read(
        () => $getRoot().getFirstChild()! as ElementNode,
      );
      expect(() => paragraph.setIndent(2), throwsA(isA<LexicalStateError>()));
    });

    test('the committed node map is unmodifiable', () {
      final editor = LexicalEditor();
      expect(
        () => editor.editorState.nodeMap[const NodeKey('x')] =
            editor.editorState.root,
        throwsUnsupportedError,
      );
    });

    test('node construction outside an update throws', () {
      expect($createParagraphNode, throwsA(isA<LexicalStateError>()));
    });

    test('nested update throws', () {
      final editor = LexicalEditor();
      expect(
        () => editor.update(() {
          editor.update(() {}, discrete: true);
        }, discrete: true),
        throwsA(isA<LexicalStateError>()),
      );
    });
  });

  group('structural sharing', () {
    test('an untouched node is shared by reference between states', () {
      final editor = LexicalEditor();
      late NodeKey untouchedKey;
      editor.update(() {
        final root = $getRoot();
        final touched = $createParagraphNode()..append($createTextNode('a'));
        final untouched = $createParagraphNode()..append($createTextNode('b'));
        root
          ..append(touched)
          ..append(untouched);
        untouchedKey = untouched.key;
      }, discrete: true);

      final before = editor.editorState;
      final sharedBefore = before.nodeMap[untouchedKey];

      editor.update(() {
        final first = $getRoot().getFirstChild()! as ElementNode;
        (first.getFirstChild()! as TextNode).setTextContent('geändert');
      }, discrete: true);

      final after = editor.editorState;
      expect(
        identical(after.nodeMap[untouchedKey], sharedBefore),
        isTrue,
        reason: 'untouched nodes must be shared, not copied',
      );
      expect(identical(after, before), isFalse);
    });

    test('a stale node reference still reads the latest value', () {
      final editor = LexicalEditor();
      late TextNode stale;
      editor.update(() {
        final paragraph = $createParagraphNode();
        stale = $createTextNode('alt');
        paragraph.append(stale);
        $getRoot().append(paragraph);
      }, discrete: true);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getFirstChild()! as TextNode).setTextContent('neu');
      }, discrete: true);

      final text = editor.read(stale.getTextContent);
      expect(text, 'neu');
    });

    test('writing twice in one update reuses the same clone', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
      }, discrete: true);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final first = paragraph.setIndent(1);
        final second = paragraph.setIndent(2);
        expect(identical(first, second), isTrue);
      }, discrete: true);
    });
  });

  group('update batching', () {
    test('discrete commits before returning', () {
      final editor = LexicalEditor();
      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);
      expect(editor.pendingEditorState, isNull);
      expect(editor.read(() => $getRoot().childrenSize), 1);
    });

    test('a failed update discards its pending changes', () {
      final editor = LexicalEditor();
      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);
      final before = editor.editorState;

      expect(
        () => editor.update(() {
          $getRoot().append($createParagraphNode());
          throw StateError('boom');
        }, discrete: true),
        throwsStateError,
      );

      expect(identical(editor.editorState, before), isTrue);
      expect(editor.read(() => $getRoot().childrenSize), 1);
    });
  });

  group('garbage collection', () {
    test('a removed subtree leaves the node map', () {
      final editor = LexicalEditor();
      late NodeKey paragraphKey;
      late NodeKey textKey;
      editor.update(() {
        final paragraph = $createParagraphNode();
        final text = $createTextNode('weg');
        paragraph.append(text);
        $getRoot().append(paragraph);
        paragraphKey = paragraph.key;
        textKey = text.key;
      }, discrete: true);

      expect(editor.editorState.nodeMap.containsKey(textKey), isTrue);

      editor.update(() {
        $getRoot().getFirstChild()!.remove();
      }, discrete: true);

      expect(editor.editorState.nodeMap.containsKey(paragraphKey), isFalse);
      expect(
        editor.editorState.nodeMap.containsKey(textKey),
        isFalse,
        reason: 'children of a detached element must be collected too',
      );
      expect(editor.editorState.nodeMap.length, 1);
    });

    test('repeated edit cycles do not grow the node map', () {
      final editor = LexicalEditor();
      for (var i = 0; i < 50; i++) {
        editor.update(() {
          final root = $getRoot();
          if (root.childrenSize > 0) root.getFirstChild()!.remove();
          root.append($createParagraphNode()..append($createTextNode('$i')));
        }, discrete: true);
      }
      // root + one paragraph + one text.
      expect(editor.editorState.nodeMap.length, 3);
    });

    test('a node moved rather than removed survives', () {
      final editor = LexicalEditor();
      late NodeKey textKey;
      editor.update(() {
        final source = $createParagraphNode();
        final target = $createParagraphNode();
        final text = $createTextNode('wandern');
        source.append(text);
        $getRoot()
          ..append(source)
          ..append(target);
        textKey = text.key;
      }, discrete: true);

      editor.update(() {
        final target = $getRoot().getLastChild()! as ElementNode;
        final source = $getRoot().getFirstChild()! as ElementNode;
        target.append(source.getFirstChild()!);
      }, discrete: true);

      expect(editor.editorState.nodeMap.containsKey(textKey), isTrue);
    });
  });

  group('clone contract', () {
    test('clone preserves subclass type across an edit', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        paragraph.append($createTabNode());
        $getRoot().append(paragraph);
      }, discrete: true);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getFirstChild()! as TabNode).setStyle('color: red');
      }, discrete: true);

      final tab = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).getFirstChild(),
      );
      expect(tab, isA<TabNode>());
      expect(tab!.type, 'tab');
    });
  });
}
