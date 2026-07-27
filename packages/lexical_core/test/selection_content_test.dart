import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor();

/// Seeds one paragraph per entry of [paragraphs].
void _seed(LexicalEditor editor, List<String> paragraphs) {
  editor.update(() {
    final root = $getRoot()..clear();
    for (final text in paragraphs) {
      root.append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
}

/// The text node inside the paragraph at [index].
TextNode _textAt(LexicalEditor editor, int index) => editor.read(
  () =>
      ($getRoot().getChildAtIndex(index)! as ElementNode).getFirstChild()!
          as TextNode,
);

ElementNode _blockAt(LexicalEditor editor, int index) =>
    editor.read(() => $getRoot().getChildAtIndex(index)! as ElementNode);

List<String> _texts(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

void main() {
  group(r'$isAtNodeEnd', () {
    test('a text point is at the end past the last code unit', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);

      editor.read(() {
        expect($isAtNodeEnd(Point(text.key, 4, PointType.text)), isTrue);
        expect($isAtNodeEnd(Point(text.key, 3, PointType.text)), isFalse);
      });
    });

    test('an element point is at the end past the last child', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      final block = _blockAt(editor, 0);

      editor.read(() {
        expect($isAtNodeEnd(Point(block.key, 1, PointType.element)), isTrue);
        expect($isAtNodeEnd(Point(block.key, 0, PointType.element)), isFalse);
      });
    });

    test('a point whose node is gone is an error, not a false', () {
      // Silently answering "no" for a stale point hides the bug that made it
      // stale, in the one place a caret is about to be moved.
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);
      editor.update(() {
        $getNodeByKey(text.key)!.remove();
      }, discrete: true);

      editor.read(() {
        expect(
          () => $isAtNodeEnd(Point(text.key, 0, PointType.text)),
          throwsA(isA<LexicalStateError>()),
        );
      });
    });
  });

  group(r'$isAtStartOfNode / $isAtEndOfNode', () {
    test('a caret in a paragraph reports both of its edges', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);
      final block = _blockAt(editor, 0);

      editor.read(() {
        final start = Point(text.key, 0, PointType.text);
        final end = Point(text.key, 4, PointType.text);
        final middle = Point(text.key, 2, PointType.text);
        expect($isAtStartOfNode(start, block), isTrue);
        expect($isAtEndOfNode(start, block), isFalse);
        expect($isAtEndOfNode(end, block), isTrue);
        expect($isAtStartOfNode(end, block), isFalse);
        expect($isAtStartOfNode(middle, block), isFalse);
        expect($isAtEndOfNode(middle, block), isFalse);
      });
    });

    test('content between the point and the edge disqualifies it', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('eins')..setFormat(TextFormat.bold.bit))
              ..append($createTextNode('zwei')),
          );
      }, discrete: true);
      final block = _blockAt(editor, 0);

      editor.read(() {
        final first = block.getFirstChild()! as TextNode;
        final last = block.getLastChild()! as TextNode;
        final afterFirst = Point(first.key, 4, PointType.text);
        final afterLast = Point(last.key, 4, PointType.text);
        final beforeFirst = Point(first.key, 0, PointType.text);
        // The end of the first run is not the end of the paragraph.
        expect($isAtEndOfNode(afterFirst, block), isFalse);
        expect($isAtEndOfNode(afterLast, block), isTrue);
        expect($isAtStartOfNode(beforeFirst, block), isTrue);
      });
    });

    test('an empty element is at both of its edges', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode());
      }, discrete: true);
      final block = _blockAt(editor, 0);

      editor.read(() {
        final point = Point(block.key, 0, PointType.element);
        expect($isAtStartOfNode(point, block), isTrue);
        expect($isAtEndOfNode(point, block), isTrue);
      });
    });

    test('an element the point is not inside is never its edge', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei']);
      final text = _textAt(editor, 0);
      final other = _blockAt(editor, 1);

      editor.read(() {
        final start = Point(text.key, 0, PointType.text);
        final end = Point(text.key, 4, PointType.text);
        expect($isAtStartOfNode(start, other), isFalse);
        expect($isAtEndOfNode(end, other), isFalse);
      });
    });
  });

  group(r'$sliceSelectedTextContent', () {
    /// The text `slice` reports for [node] under a selection from [from] to
    /// [to] within [anchorIn]/[focusIn].
    String slice(
      LexicalEditor editor,
      TextNode node,
      TextNode anchorIn,
      int from,
      TextNode focusIn,
      int to,
    ) => editor.read(() {
      final selection = $createRangeSelection();
      selection.anchor.set(anchorIn.key, from, PointType.text);
      selection.focus.set(focusIn.key, to, PointType.text);
      return $sliceSelectedTextContent(
        selection,
        $getNodeByKey(node.key)! as TextNode,
      );
    });

    test('narrows a boundary node to the covered part', () {
      final editor = _editor();
      _seed(editor, ['einszwei']);
      final text = _textAt(editor, 0);

      expect(slice(editor, text, text, 4, text, 8), 'zwei');
      // The document is untouched: this is an export helper, not an edit.
      expect(_texts(editor), ['einszwei']);
    });

    test('a fully covered node comes back whole', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);

      expect(slice(editor, text, text, 0, text, 4), 'eins');
    });

    test('a backwards selection narrows the same way', () {
      final editor = _editor();
      _seed(editor, ['einszwei']);
      final text = _textAt(editor, 0);

      expect(slice(editor, text, text, 8, text, 4), 'zwei');
    });

    test('the first node keeps its tail, the last one keeps its head', () {
      final editor = _editor();
      _seed(editor, ['einszwei', 'dreivier']);
      final first = _textAt(editor, 0);
      final second = _textAt(editor, 1);

      expect(slice(editor, first, first, 4, second, 4), 'zwei');
      expect(slice(editor, second, first, 4, second, 4), 'drei');
    });

    test('a token node is never narrowed', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('@rebar')..setMode(TextMode.token)),
          );
      }, discrete: true);
      final token = _textAt(editor, 0);

      expect(slice(editor, token, token, 0, token, 3), '@rebar');
    });

    test('a node the selection does not reach comes back whole', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei']);
      final first = _textAt(editor, 0);
      final second = _textAt(editor, 1);

      expect(slice(editor, second, first, 0, first, 2), 'zwei');
    });
  });

  group(r'$trimTextContentFromAnchor', () {
    test('takes the overrun off the end of the anchored node', () {
      final editor = _editor();
      _seed(editor, ['einszwei']);
      final text = _textAt(editor, 0);

      editor.update(() {
        final anchor = Point(text.key, 8, PointType.text);
        $trimTextContentFromAnchor(editor, anchor, 4);
      }, discrete: true);

      expect(_texts(editor), ['eins']);
    });

    test('walks back out of the block, counting the boundary it crosses', () {
      // A block boundary is worth two characters in the text content the
      // limit was measured against, and an implementation that forgets that
      // deletes too much.
      final editor = _editor();
      _seed(editor, ['eins', 'zwei']);
      final second = _textAt(editor, 1);

      editor.update(() {
        final anchor = Point(second.key, 4, PointType.text);
        // "zwei" (4) + the boundary (2) + one character of "eins".
        $trimTextContentFromAnchor(editor, anchor, 7);
      }, discrete: true);

      expect(_texts(editor), ['ein']);
    });

    test('restores a node the same update had already changed', () {
      // A length limit rejects the edit that broke it; the writer gets back
      // exactly what they had rather than an arbitrary truncation of it.
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);

      editor.update(() {
        final node = $getNodeByKey(text.key)! as TextNode
          ..setTextContent('einszweidrei');
        $trimTextContentFromAnchor(
          editor,
          Point(node.key, 12, PointType.text),
          8,
        );
      }, discrete: true);

      expect(_texts(editor), ['eins']);
    });
  });

  group('getBlocks', () {
    test('reports every block between the ends, in document order', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei', 'drei', 'vier']);
      final first = _textAt(editor, 1);
      final last = _textAt(editor, 3);

      expect(
        editor.read(() {
          final selection = $createRangeSelection();
          selection.anchor.set(first.key, 1, PointType.text);
          selection.focus.set(last.key, 2, PointType.text);
          return selection.getBlocks().map((b) => b.getTextContent()).toList();
        }),
        ['zwei', 'drei', 'vier'],
      );
    });

    test('a backwards drag reports the same blocks, still in order', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei', 'drei']);
      final first = _textAt(editor, 0);
      final last = _textAt(editor, 2);

      expect(
        editor.read(() {
          final selection = $createRangeSelection();
          selection.anchor.set(last.key, 2, PointType.text);
          selection.focus.set(first.key, 1, PointType.text);
          return selection.getBlocks().map((b) => b.getTextContent()).toList();
        }),
        ['eins', 'zwei', 'drei'],
      );
    });

    test('a collapsed caret reports the one block it sits in', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei']);
      final text = _textAt(editor, 1);

      expect(
        editor.read(() {
          final selection = $createRangeSelection();
          selection.anchor.set(text.key, 2, PointType.text);
          selection.focus.set(text.key, 2, PointType.text);
          return selection.getBlocks().map((b) => b.getTextContent()).toList();
        }),
        ['zwei'],
      );
    });
  });

  group(r'$isParentRtl', () {
    test('reads the direction the model inferred, and inherits it', () {
      final editor = _editor();
      _seed(editor, ['שלום']);
      editor.update(() {
        ($getRoot().getFirstChild()! as ElementNode).setDirection(
          NodeDirection.rtl,
        );
      }, discrete: true);
      final text = _textAt(editor, 0);

      editor.read(() {
        expect($isParentRtl($getNodeByKey(text.key)!), isTrue);
        final selection = $createRangeSelection();
        selection.anchor.set(text.key, 0, PointType.text);
        selection.focus.set(text.key, 0, PointType.text);
        expect($isParentElementRtl(selection), isTrue);
      });
    });

    test('no declared direction anywhere reads as left-to-right', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      final text = _textAt(editor, 0);

      editor.read(() {
        expect($isParentRtl($getNodeByKey(text.key)!), isFalse);
      });
    });
  });
}
