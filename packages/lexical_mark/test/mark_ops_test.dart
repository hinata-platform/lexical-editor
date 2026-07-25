import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_mark/lexical_mark.dart';
import 'package:test/test.dart';

LexicalEditor _document(String text) {
  final editor = LexicalEditor(nodes: markNodes);
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode(text)));
  }, discrete: true);
  return editor;
}

/// Every text node in the document, in order — marks included.
List<TextNode> _texts(ElementNode element) => [
  for (final child in element.children)
    if (child is TextNode)
      child
    else if (child is ElementNode)
      ..._texts(child),
];

/// Selects [word] wherever it is.
///
/// By content rather than by offset, because marking splits text nodes: after
/// the first mark the paragraph is three nodes, and an offset into "the first
/// one" no longer means what it did.
void _select(LexicalEditor editor, String word) {
  editor.update(() {
    for (final text in _texts($getRoot())) {
      final start = text.getTextContent().indexOf(word);
      if (start < 0) continue;
      text.select(start, start + word.length);
      return;
    }
    throw StateError('no "$word" in the document');
  }, discrete: true);
}

/// The paragraph's shape: `{ids}text` for a mark, bare text otherwise.
String _shape(LexicalEditor editor) => editor.read(() {
  final buffer = StringBuffer();
  void walk(ElementNode element) {
    for (final child in element.children) {
      if (child is MarkNode) {
        buffer.write('{${child.ids.join(',')}}');
        walk(child);
        buffer.write('{/}');
      } else if (child is ElementNode) {
        walk(child);
      } else {
        buffer.write(child.getTextContent());
      }
    }
  }

  walk($getRoot().getFirstChild()! as ElementNode);
  return buffer.toString();
});

void main() {
  group('marking', () {
    test('wraps exactly what was selected', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);

      expect(_shape(editor), 'ein {c1}markierter{/} Satz');
      expect(editor.read(() => $getMarkedText('c1')), 'markierter');
    });

    test('a collapsed caret marks nothing', () {
      final editor = _document('unverändert');
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        (block.getFirstChild()! as TextNode).select(3, 3);
      }, discrete: true);
      editor.update(() => $markSelection('c1'), discrete: true);
      expect(_shape(editor), 'unverändert');
    });

    test('the same range twice carries both ids on one mark', () {
      // Two people commenting on the same sentence should not nest two
      // elements deep; the mark already there just learns a second id.
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c2'), discrete: true);

      expect(_shape(editor), 'ein {c1,c2}markierter{/} Satz');
    });

    test('an overlapping range nests, because a node has one parent', () {
      final editor = _document('eins zwei drei');
      _select(editor, 'eins zwei');
      editor.update(() => $markSelection('c1'), discrete: true);
      // "zwei drei" now spans the mark's text node and the one after it.
      editor.update(() {
        final texts = _texts($getRoot());
        final inMark = texts.firstWhere(
          (text) => text.getTextContent().contains('zwei'),
        );
        final after = texts.last;
        $setSelection(
          RangeSelection(
            Point(inMark.key, 5, PointType.text),
            Point(after.key, after.getTextContentSize(), PointType.text),
          ),
        );
      }, discrete: true);
      editor.update(() => $markSelection('c2'), discrete: true);

      // The overlap sits inside both marks; the text is untouched.
      expect(editor.read(() => $getRoot().getTextContent()), 'eins zwei drei');
      expect(editor.read(() => $getMarkedText('c1')), contains('zwei'));
      expect(editor.read(() => $getMarkedText('c2')), contains('zwei'));
      expect(_shape(editor), contains('{c2}'));
    });

    test('the document stays structurally valid', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      editor.read(() => assertTreeIntegrity($getRoot()));
    });

    test('a mark round-trips as a fixed point', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);

      final json = editor.editorState.toJson();
      final restored = LexicalEditor(nodes: markNodes);
      restored.setEditorState(restored.parseEditorState(json));
      expect(restored.editorState.toJson(), json);
    });
  });

  group('resolving', () {
    test('removing the last id unwraps the mark', () {
      // An annotation nobody refers to is invisible; leaving it behind would
      // grow the document by one element per resolved comment forever.
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      editor.update(() => $removeMark('c1'), discrete: true);

      expect(_shape(editor), 'ein markierter Satz');
      expect(editor.read(() => $getMarkedText('c1')), isEmpty);
    });

    test('removing one of two ids keeps the mark', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c2'), discrete: true);
      editor.update(() => $removeMark('c1'), discrete: true);

      expect(_shape(editor), 'ein {c2}markierter{/} Satz');
    });

    test('removing an unknown id changes nothing', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      editor.update(() => $removeMark('anderes'), discrete: true);
      expect(_shape(editor), 'ein {c1}markierter{/} Satz');
    });
  });

  group('reading', () {
    test('the ids under the caret are reported', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      // Caret inside the marked run.
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final mark = block.children.whereType<MarkNode>().single;
        (mark.getFirstChild()! as TextNode).select(2, 2);
      }, discrete: true);

      expect(editor.read($getMarkIdsAtSelection), {'c1'});
    });

    test('a caret outside every mark reports nothing', () {
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      editor.update(() {
        _texts($getRoot()).first.select(0, 0);
      }, discrete: true);
      expect(editor.read($getMarkIdsAtSelection), isEmpty);
    });

    test('the quoted text follows the document as it is edited', () {
      // The sidebar quotes what the mark covers *now*, not what it covered
      // when the comment was written.
      final editor = _document('ein markierter Satz');
      _select(editor, 'markierter');
      editor.update(() => $markSelection('c1'), discrete: true);
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final mark = block.children.whereType<MarkNode>().single;
        (mark.getFirstChild()! as TextNode).setTextContent('geänderter');
      }, discrete: true);

      expect(editor.read(() => $getMarkedText('c1')), 'geänderter');
    });
  });

  group('the commands', () {
    test('registerMark wires both of them', () {
      final editor = _document('ein markierter Satz');
      final unsubscribe = registerMark(editor);
      _select(editor, 'markierter');

      editor.dispatchCommand(addMarkCommand, 'c1');
      expect(_shape(editor), 'ein {c1}markierter{/} Satz');

      editor.dispatchCommand(removeMarkCommand, 'c1');
      expect(_shape(editor), 'ein markierter Satz');
      unsubscribe();
    });
  });
}
