import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: linkNodes);

/// A document of one paragraph per entry, each holding one text node.
LexicalEditor _document(List<String> paragraphs) {
  final editor = _editor();
  editor.update(() {
    $getRoot().clear();
    for (final text in paragraphs) {
      $getRoot().append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
  return editor;
}

/// Selects [start]..[end] within the text node of paragraph [paragraph].
void _select(
  LexicalEditor editor,
  int start,
  int end, {
  int paragraph = 0,
  int? toParagraph,
}) {
  editor.update(() {
    final blocks = $getRoot().children.cast<ElementNode>().toList();
    final from = blocks[paragraph].getFirstChild()!;
    final to = blocks[toParagraph ?? paragraph].getLastChild()!;
    $setSelection(
      RangeSelection(
        Point(from.key, start, PointType.text),
        Point(to.key, end, PointType.text),
      ),
    );
  }, discrete: true);
}

/// The paragraph's shape: `[url]text` for a link, bare text otherwise.
String _shape(LexicalEditor editor, {int paragraph = 0}) => editor.read(() {
  final block = $getRoot().children.toList()[paragraph] as ElementNode;
  final buffer = StringBuffer();
  for (final child in block.children) {
    if (child is LinkNode) {
      buffer.write('[${child.url}]${child.getTextContent()}');
    } else {
      buffer.write(child.getTextContent());
    }
  }
  return buffer.toString();
});

List<LinkNode> _links(LexicalEditor editor) => editor.read(
  () => $getRoot().children
      .cast<ElementNode>()
      .expand((block) => block.children)
      .whereType<LinkNode>()
      .toList(),
);

void main() {
  group('making a link', () {
    test('wraps exactly what was selected', () {
      final editor = _document(['siehe die Doku dazu']);
      _select(editor, 10, 14); // "Doku"
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);

      expect(_shape(editor), 'siehe die [https://lexical.dev]Doku dazu');
      // The boundary text nodes were split, so the link took the word and not
      // the paragraph.
      // Read inside the editor: a node handle is only valid in a read.
      expect(editor.read(() => _links(editor).single.getTextContent()), 'Doku');
    });

    test('a whole text node needs no splitting', () {
      final editor = _document(['Doku']);
      _select(editor, 0, 4);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);

      expect(_shape(editor), '[https://lexical.dev]Doku');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).childrenSize,
        ),
        1,
      );
    });

    test('a collapsed caret links nothing', () {
      final editor = _document(['unverändert']);
      _select(editor, 3, 3);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);

      expect(_shape(editor), 'unverändert');
      expect(_links(editor), isEmpty);
    });

    test('a selection across paragraphs links each of them', () {
      // An element cannot span two parents. One link per paragraph is the
      // only faithful answer; linking just the first would lose half of it.
      final editor = _document(['erster Absatz', 'zweiter Absatz']);
      _select(editor, 7, 7, toParagraph: 1);
      editor.update(() => $toggleLink('https://example.org'), discrete: true);

      expect(_shape(editor), 'erster [https://example.org]Absatz');
      expect(
        _shape(editor, paragraph: 1),
        '[https://example.org]zweiter Absatz',
      );
    });

    test('the document stays structurally valid', () {
      final editor = _document(['ein Satz mit Wörtern']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);
      editor.read(() => assertTreeIntegrity($getRoot()));
    });

    test('a link round-trips as a fixed point', () {
      final editor = _document(['siehe die Doku dazu']);
      _select(editor, 10, 14);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);

      final json = editor.editorState.toJson();
      final restored = _editor();
      restored.setEditorState(restored.parseEditorState(json));
      expect(restored.editorState.toJson(), json);
    });
  });

  group('editing a link', () {
    test('a caret inside one retargets it rather than nesting', () {
      final editor = _document(['die Doku']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://old.example'), discrete: true);

      // Caret in the middle of the link text.
      editor.update(() {
        final link = _links(editor).single;
        (link.getFirstChild()! as TextNode).select(2, 2);
      }, discrete: true);
      editor.update(() => $toggleLink('https://new.example'), discrete: true);

      expect(_shape(editor), 'die [https://new.example]Doku');
      expect(_links(editor), hasLength(1));
    });

    test('part of a link retargets the whole link', () {
      // Splitting one link into two with different targets is never what
      // selecting three of its letters meant.
      final editor = _document(['Dokumentation']);
      _select(editor, 0, 13);
      editor.update(() => $toggleLink('https://old.example'), discrete: true);
      editor.update(() {
        (_links(editor).single.getFirstChild()! as TextNode).select(2, 5);
      }, discrete: true);
      editor.update(() => $toggleLink('https://new.example'), discrete: true);

      expect(_shape(editor), '[https://new.example]Dokumentation');
    });

    test(r'$getLinkAtSelection finds the link under a caret', () {
      final editor = _document(['die Doku']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);
      editor.update(() {
        (_links(editor).single.getFirstChild()! as TextNode).select(1, 1);
      }, discrete: true);

      expect(
        editor.read(() => $getLinkAtSelection()?.url),
        'https://lexical.dev',
      );
    });

    test(r'$getLinkAtSelection is null when the range leaves the link', () {
      final editor = _document(['die Doku dazu']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);
      // From inside the link out into the trailing text.
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final link = block.children.whereType<LinkNode>().single;
        final inside = link.getFirstChild()!;
        final after = block.getLastChild()!;
        $setSelection(
          RangeSelection(
            Point(inside.key, 1, PointType.text),
            Point(after.key, 3, PointType.text),
          ),
        );
      }, discrete: true);

      expect(editor.read($getLinkAtSelection), isNull);
    });
  });

  group('removing a link', () {
    test('unlinking keeps the text', () {
      final editor = _document(['die Doku dazu']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);
      editor.update(() {
        (_links(editor).single.getFirstChild()! as TextNode).select(1, 1);
      }, discrete: true);
      editor.update(() => $toggleLink(null), discrete: true);

      expect(_links(editor), isEmpty);
      expect(editor.read(() => $getRoot().getTextContent()), 'die Doku dazu');
    });

    test('a range covering several links removes all of them', () {
      final editor = _document(['eins zwei drei']);
      _select(editor, 0, 4);
      editor.update(() => $toggleLink('https://a.example'), discrete: true);
      _select(editor, 0, 4, paragraph: 0);
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final last = block.getLastChild()! as TextNode;
        // "drei" at the end of the trailing run.
        final text = last.getTextContent();
        last.select(text.length - 4, text.length);
      }, discrete: true);
      editor.update(() => $toggleLink('https://b.example'), discrete: true);
      expect(_links(editor), hasLength(2));

      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final first = block.getFirstChild()! as LinkNode;
        final last = block.getLastChild()! as LinkNode;
        $setSelection(
          RangeSelection(
            Point(first.getFirstChild()!.key, 0, PointType.text),
            Point(last.getLastChild()!.key, 4, PointType.text),
          ),
        );
      }, discrete: true);
      editor.update(() => $toggleLink(null), discrete: true);

      expect(_links(editor), isEmpty);
      expect(editor.read(() => $getRoot().getTextContent()), 'eins zwei drei');
    });
  });

  group('the command', () {
    test('registerLink wires the command to the operation', () {
      final editor = _document(['die Doku']);
      final unsubscribe = registerLink(editor);
      _select(editor, 4, 8);

      editor.dispatchCommand(toggleLinkCommand, 'https://lexical.dev');
      expect(_shape(editor), 'die [https://lexical.dev]Doku');

      editor.dispatchCommand(toggleLinkCommand, null);
      expect(_links(editor), isEmpty);
      unsubscribe();
    });
  });

  group('typing at a link', () {
    /// A paragraph of `die ` and a link around `Doku`, caret at [offset]
    /// inside the link's own text.
    LexicalEditor withCaret(int offset) {
      final editor = _document(['die Doku']);
      _select(editor, 4, 8);
      editor.update(() => $toggleLink('https://lexical.dev'), discrete: true);
      editor.update(() {
        (_links(editor).single.getFirstChild()! as TextNode).select(
          offset,
          offset,
        );
      }, discrete: true);
      return editor;
    }

    void type(LexicalEditor editor, String text) => editor.update(
      () => ($getSelection()! as RangeSelection).insertText(text),
      discrete: true,
    );

    test('its front writes in front of it, not into it', () {
      final editor = withCaret(0);
      type(editor, 'X');
      expect(_shape(editor), 'die X[https://lexical.dev]Doku');
      expect(editor.read(() => _links(editor).single.getTextContent()), 'Doku');
    });

    test('its end writes after it, so the link stops growing', () {
      final editor = withCaret(4);
      type(editor, 'X');
      expect(_shape(editor), 'die [https://lexical.dev]DokuX');
      expect(editor.read(() => _links(editor).single.getTextContent()), 'Doku');
    });

    test('inside it the text belongs to the link', () {
      final editor = withCaret(2);
      type(editor, 'X');
      expect(_shape(editor), 'die [https://lexical.dev]DoXku');
    });

    test('after Enter in front of it, the new line is not part of it', () {
      // How the bug was met in practice: Enter at the link's start pushes it
      // down and leaves the caret at the link's first letter, where every
      // character typed used to be absorbed by the anchor.
      final editor = withCaret(0);
      editor.update(
        () => ($getSelection()! as RangeSelection).insertParagraph(),
        discrete: true,
      );
      type(editor, 'Neu');

      expect(_shape(editor), 'die ');
      expect(_shape(editor, paragraph: 1), 'Neu[https://lexical.dev]Doku');
    });
  });

  group('an emptied link', () {
    test('removes itself rather than staying behind invisibly', () {
      // A link with no children renders nothing, so an anchor left over from
      // deleting the text inside it cannot be seen — it is saved, sent to
      // every other client and exported as `[](url)`, and one accumulates per
      // edit that emptied a link.
      final editor = _document(['die Doku']);
      final unsubscribe = registerLink(editor);
      addTearDown(unsubscribe);
      _select(editor, 4, 8);
      editor.dispatchCommand(toggleLinkCommand, 'https://lexical.dev');

      editor.update(() {
        final link = $getRoot().getLastDescendant()!.getParent()!;
        link.getFirstChild()!.remove();
      }, discrete: true);

      expect(_links(editor), isEmpty);
      expect(editor.read(() => $getRoot().getTextContent()), 'die ');
    });

    test('is gone the moment its last child is removed', () {
      // The other route to the same state, and the one the model handles by
      // itself: `canBeEmpty` is what the core consults when a removal leaves
      // a parent with nothing in it.
      final editor = _document(['die Doku']);
      _select(editor, 4, 8);
      editor.update(() {
        $toggleLink('https://lexical.dev');
      }, discrete: true);

      editor.update(() {
        final link = _links(editor).single;
        ($getNodeByKey(link.key)! as ElementNode).getFirstChild()!.remove();
      }, discrete: true);

      expect(_links(editor), isEmpty);
    });
  });
}
