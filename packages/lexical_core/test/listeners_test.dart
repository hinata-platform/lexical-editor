import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('update listener', () {
    test('fires once per commit with both states', () {
      final editor = LexicalEditor();
      final updates = <EditorUpdate>[];
      editor.registerUpdateListener(updates.add);

      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);

      expect(updates, hasLength(1));
      expect(identical(updates.single.editorState, editor.editorState), isTrue);
      expect(
        identical(
          updates.single.previousEditorState,
          updates.single.editorState,
        ),
        isFalse,
      );
    });

    test('batches several updates into one commit', () async {
      final editor = LexicalEditor();
      var commits = 0;
      editor.registerUpdateListener((_) => commits++);

      editor
        ..update(() => $getRoot().append($createParagraphNode()))
        ..update(() => $getRoot().append($createParagraphNode()))
        ..update(() => $getRoot().append($createParagraphNode()));

      await Future<void>.delayed(Duration.zero);
      expect(commits, 1);
      expect(editor.read(() => $getRoot().childrenSize), 3);
    });

    test('carries update tags', () {
      final editor = LexicalEditor();
      Set<String>? seen;
      editor.registerUpdateListener((update) => seen = update.tags);

      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
        tags: {'history-push', 'meine-quelle'},
      );

      expect(seen, containsAll(<String>['history-push', 'meine-quelle']));
    });

    test('reports which nodes were dirty', () {
      final editor = LexicalEditor();
      late NodeKey untouched;
      editor.update(() {
        final first = $createParagraphNode()..append($createTextNode('a'));
        final second = $createParagraphNode()..append($createTextNode('b'));
        $getRoot()
          ..append(first)
          ..append(second);
        untouched = second.key;
      }, discrete: true);

      EditorUpdate? seen;
      editor.registerUpdateListener((update) => seen = update);
      editor.update(() {
        final first = $getRoot().getFirstChild()! as ElementNode;
        (first.getFirstChild()! as TextNode).setTextContent('geändert');
      }, discrete: true);

      expect(seen, isNotNull);
      expect(
        seen!.dirtyElements.containsKey(untouched),
        isFalse,
        reason: 'an untouched sibling must not be reported dirty',
      );
      expect(seen!.dirtyLeaves, isNotEmpty);
    });

    test('unsubscribing stops delivery', () {
      final editor = LexicalEditor();
      var calls = 0;
      final unsubscribe = editor.registerUpdateListener((_) => calls++);
      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
      );
      unsubscribe();
      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
      );
      expect(calls, 1);
    });
  });

  group('mutation listener', () {
    test('reports created, updated and destroyed per type', () {
      final editor = LexicalEditor();
      final seen = <Map<NodeKey, NodeMutation>>[];
      editor.registerMutationListener('paragraph', seen.add);

      late NodeKey key;
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        key = paragraph.key;
      }, discrete: true);
      expect(seen.last[key], NodeMutation.created);

      editor.update(() {
        ($getRoot().getFirstChild()! as ElementNode).setIndent(2);
      }, discrete: true);
      expect(seen.last[key], NodeMutation.updated);

      editor.update(() {
        $getRoot().getFirstChild()!.remove();
      }, discrete: true);
      expect(seen.last[key], NodeMutation.destroyed);
    });

    test('only reports the type it was registered for', () {
      final editor = LexicalEditor();
      final paragraphs = <Map<NodeKey, NodeMutation>>[];
      final texts = <Map<NodeKey, NodeMutation>>[];
      editor
        ..registerMutationListener('paragraph', paragraphs.add)
        ..registerMutationListener('text', texts.add);

      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('hallo')),
        );
      }, discrete: true);

      expect(paragraphs.single.values, everyElement(NodeMutation.created));
      expect(texts.single.values, everyElement(NodeMutation.created));
    });

    test('the root is never reported', () {
      final editor = LexicalEditor();
      final seen = <Map<NodeKey, NodeMutation>>[];
      editor.registerMutationListener('root', seen.add);
      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
      );
      expect(seen, isEmpty);
    });
  });

  group('text content listener', () {
    test('fires only when the text actually changes', () {
      final editor = LexicalEditor();
      final seen = <String>[];
      editor.registerTextContentListener(seen.add);

      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('hallo')),
        );
      }, discrete: true);
      expect(seen, ['hallo']);

      // A change that does not affect text content.
      editor.update(() {
        ($getRoot().getFirstChild()! as ElementNode).setIndent(3);
      }, discrete: true);
      expect(seen, ['hallo']);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getFirstChild()! as TextNode).setTextContent('tschüss');
      }, discrete: true);
      expect(seen, ['hallo', 'tschüss']);
    });
  });

  group('editable listener', () {
    test('fires on change only', () {
      final editor = LexicalEditor();
      final seen = <bool>[];
      editor.registerEditableListener(seen.add);

      editor.isEditable = true;
      expect(seen, isEmpty, reason: 'already editable');

      editor.isEditable = false;
      editor.isEditable = false;
      expect(seen, [false]);

      editor.isEditable = true;
      expect(seen, [false, true]);
    });
  });

  group('listener discipline', () {
    test('a listener may schedule its own update without recursing', () {
      final editor = LexicalEditor();
      var calls = 0;
      editor.registerUpdateListener((_) {
        calls++;
        if (calls == 1) {
          editor.update(
            () => $getRoot().append($createParagraphNode()),
            discrete: true,
          );
        }
      });

      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
      );

      expect(calls, 2);
      expect(editor.read(() => $getRoot().childrenSize), 2);
    });
  });
}
