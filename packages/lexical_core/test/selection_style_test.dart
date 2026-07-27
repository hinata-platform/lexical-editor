import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

/// A text node that renders something other than its own characters, so
/// restyling it would change what it means rather than how it looks.
class _StampNode extends TextNode {
  _StampNode([super.text = '']);

  @override
  String get type => 'stamp';

  @override
  bool get canHaveFormat => false;

  @override
  _StampNode clone() => _StampNode(textInternal);
}

LexicalEditor _editor() => LexicalEditor(
  nodes: [NodeSpec<_StampNode>(type: 'stamp', create: _StampNode.new)],
);

/// Seeds one paragraph holding the text nodes [build] creates.
///
/// The nodes are built inside the update because constructing one allocates a
/// key, which only an update may do.
List<TextNode> _seed(LexicalEditor editor, List<TextNode> Function() build) {
  late List<TextNode> runs;
  editor.update(() {
    runs = build();
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..appendAll(runs));
  }, discrete: true);
  return runs;
}

List<(String, String)> _runs(LexicalEditor editor) => editor.read(
  () => ($getRoot().getFirstChild()! as ElementNode).children
      .cast<TextNode>()
      .map((node) => (node.getTextContent(), node.getStyle()))
      .toList(),
);

/// A text node that will not be merged into its neighbour.
///
/// Adjacent runs with identical formatting are one run as far as the model is
/// concerned, and normalization merges them on commit. A test that needs two
/// of them has to say so.
TextNode _run(String text) =>
    $createTextNode(text)..setDetail(TextDetail.unmergeable.bit);

/// Selects [from] in [start] through [to] in [end].
void _select(
  LexicalEditor editor,
  TextNode start,
  int from,
  TextNode end,
  int to,
) {
  editor.update(() {
    final selection = $createRangeSelection();
    selection.anchor.set(start.key, from, PointType.text);
    selection.focus.set(end.key, to, PointType.text);
    $setSelection(selection);
  }, discrete: true);
}

void _patch(LexicalEditor editor, StylePatch patch) {
  editor.update(() {
    $patchStyleText($getSelection(), patch);
  }, discrete: true);
}

void main() {
  group(r'$patchStyleText', () {
    test('changes the named property and leaves the rest alone', () {
      // The failure this rules out: a colour picker that also silently drops
      // the font size the writer set a minute ago.
      final editor = _editor();
      final [text] = _seed(
        editor,
        () => [
          $createTextNode('eins')..setStyle('color: #000;font-size: 12px;'),
        ],
      );
      _select(editor, text, 0, text, 4);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(_runs(editor), [('eins', 'color: #f00;font-size: 12px;')]);
    });

    test('unset removes the declaration rather than emptying it', () {
      final editor = _editor();
      final [text] = _seed(
        editor,
        () => [
          $createTextNode('eins')..setStyle('color: #000;font-size: 12px;'),
        ],
      );
      _select(editor, text, 0, text, 4);

      _patch(editor, {'color': const StyleValue.unset()});

      expect(_runs(editor), [('eins', 'font-size: 12px;')]);
    });

    test('derived sees the value the node currently has', () {
      final editor = _editor();
      final [text] = _seed(
        editor,
        () => [$createTextNode('eins')..setStyle('font-size: 12px;')],
      );
      _select(editor, text, 0, text, 4);

      final seen = <String?>[];
      _patch(editor, {
        'font-size': StyleValue.derived((current) {
          seen.add(current);
          return '16px';
        }),
        'color': StyleValue.derived((current) {
          seen.add(current);
          return '#f00';
        }),
      });

      expect(seen, ['12px', null]);
      expect(_runs(editor), [('eins', 'font-size: 16px;color: #f00;')]);
    });

    test('a partially covered node is split, and only the run styles', () {
      // The opposite data-loss shape: styling the whole node because
      // splitting was easier to skip.
      final editor = _editor();
      final [text] = _seed(editor, () => [$createTextNode('einszwei')]);
      _select(editor, text, 4, text, 8);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(_runs(editor), [('eins', ''), ('zwei', 'color: #f00;')]);
    });

    test('the selection follows the run it split out', () {
      // A split leaves the points addressing a node whose text no longer
      // reaches the offset they name, and every later edit reads them.
      final editor = _editor();
      final [text] = _seed(editor, () => [$createTextNode('einszwei')]);
      _select(editor, text, 4, text, 8);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(
        editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          return (
            selection.anchor.getNode()!.getTextContent(),
            selection.anchor.offset,
            selection.focus.offset,
          );
        }),
        ('zwei', 0, 4),
      );
    });

    test('a node the selection only touches the edge of is left alone', () {
      final editor = _editor();
      final [first, second] = _seed(editor, () => [_run('eins'), _run('zwei')]);
      // Starts at the very end of "eins", so it covers none of it.
      _select(editor, first, 4, second, 4);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(_runs(editor), [('eins', ''), ('zwei', 'color: #f00;')]);
    });

    test('a collapsed selection styles what is typed next', () {
      final editor = _editor();
      final [text] = _seed(editor, () => [$createTextNode('eins')]);
      _select(editor, text, 2, text, 2);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(
        editor.read(() => ($getSelection()! as RangeSelection).style),
        'color: #f00;',
      );
      // Nothing existing changed — there was nothing selected to change.
      expect(_runs(editor), [('eins', '')]);
    });

    test('an empty block keeps the style for its first character', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode());
        ($getRoot().getFirstChild()! as ElementNode).select(0, 0);
        $patchStyleText($getSelection(), {'color': const StyleValue('#f00')});
      }, discrete: true);

      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).getTextStyle(),
        ),
        'color: #f00;',
      );
    });

    test('a token node is styled whole or not at all', () {
      // Half a mention chip is not a smaller mention chip.
      final editor = _editor();
      final [token] = _seed(
        editor,
        () => [$createTextNode('@rebar')..setMode(TextMode.token)],
      );
      _select(editor, token, 2, token, 4);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(_runs(editor), [('@rebar', 'color: #f00;')]);
    });

    test('a node that declines formatting is skipped', () {
      final editor = _editor();
      final [stamp, text] = _seed(
        editor,
        () => [_StampNode('2026-07-27'), _run(' eins')],
      );
      _select(editor, stamp, 0, text, 5);

      _patch(editor, {'color': const StyleValue('#f00')});

      expect(_runs(editor), [('2026-07-27', ''), (' eins', 'color: #f00;')]);
    });

    test('a null selection does nothing rather than throwing', () {
      final editor = _editor();
      _seed(editor, () => [$createTextNode('eins')]);

      editor.update(() {
        $setSelection(null);
        $patchStyleText($getSelection(), {'color': const StyleValue('#f00')});
      }, discrete: true);

      expect(_runs(editor), [('eins', '')]);
    });
  });

  group(r'$getSelectionStyleValueForProperty', () {
    String read(LexicalEditor editor, [String fallback = '']) => editor.read(
      () => $getSelectionStyleValueForProperty(
        $getSelection()!,
        'color',
        fallback,
      ),
    );

    test('the shared value, when every covered node agrees', () {
      final editor = _editor();
      final [first, second] = _seed(
        editor,
        () => [
          _run('eins')..setStyle('color: #f00;'),
          _run('zwei')..setStyle('color: #f00;'),
        ],
      );
      _select(editor, first, 0, second, 4);

      expect(read(editor), '#f00');
    });

    test('the empty string when they disagree, which is not "unset"', () {
      final editor = _editor();
      final [first, second] = _seed(
        editor,
        () => [
          _run('eins')..setStyle('color: #f00;'),
          _run('zwei')..setStyle('color: #00f;'),
        ],
      );
      _select(editor, first, 0, second, 4);

      expect(read(editor, '#000'), '');
    });

    test('the default when nothing sets the property', () {
      final editor = _editor();
      final [text] = _seed(editor, () => [$createTextNode('eins')]);
      _select(editor, text, 0, text, 4);

      expect(read(editor, '#000'), '#000');
    });

    test('a node touched only at its edge does not make it "mixed"', () {
      // Selecting from the very end of a red run into a blue one is a
      // selection of blue text, and a picker showing "mixed" there is wrong.
      final editor = _editor();
      final [first, second] = _seed(
        editor,
        () => [
          _run('eins')..setStyle('color: #f00;'),
          _run('zwei')..setStyle('color: #00f;'),
        ],
      );
      _select(editor, first, 4, second, 4);

      expect(read(editor), '#00f');
    });

    test('a collapsed selection answers from its pending style', () {
      final editor = _editor();
      final [text] = _seed(
        editor,
        () => [$createTextNode('eins')..setStyle('color: #f00;')],
      );
      _select(editor, text, 2, text, 2);

      _patch(editor, {'color': const StyleValue('#0f0')});

      expect(read(editor), '#0f0');
    });
  });

  group(r'$forEachSelectedTextNode', () {
    test('runs over the covered runs, in document order', () {
      final editor = _editor();
      final [first, second] = _seed(editor, () => [_run('eins'), _run('zwei')]);
      _select(editor, first, 2, second, 2);

      final seen = <String>[];
      editor.update(() {
        $forEachSelectedTextNode((node) => seen.add(node.getTextContent()));
      }, discrete: true);

      expect(seen, ['ns', 'zw']);
    });

    test('works against a selection the editor does not hold', () {
      final editor = _editor();
      final [_, second] = _seed(editor, () => [_run('eins'), _run('zwei')]);

      final seen = <String>[];
      editor.update(() {
        final selection = $createRangeSelection();
        selection.anchor.set(second.key, 0, PointType.text);
        selection.focus.set(second.key, 4, PointType.text);
        $forEachSelectedTextNode(
          (node) => seen.add(node.getTextContent()),
          selection: selection,
        );
      }, discrete: true);

      expect(seen, ['zwei']);
    });
  });

  group(r'$ensureForwardRangeSelection', () {
    test('a backwards drag is swapped, and a forward one is untouched', () {
      final editor = _editor();
      final [text] = _seed(editor, () => [$createTextNode('eins')]);

      (int, int) normalized(int anchor, int focus) => editor.read(() {
        final selection = $createRangeSelection();
        selection.anchor.set(text.key, anchor, PointType.text);
        selection.focus.set(text.key, focus, PointType.text);
        $ensureForwardRangeSelection(selection);
        return (selection.anchor.offset, selection.focus.offset);
      });

      expect(normalized(4, 1), (1, 4));
      expect(normalized(1, 4), (1, 4));
    });
  });
}
