import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor();
  registerRichText(editor);
  return editor;
}

void _seed(LexicalEditor editor, List<String> paragraphs) {
  editor.update(() {
    final root = $getRoot()..clear();
    for (final text in paragraphs) {
      root.append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
}

void _caret(LexicalEditor editor, int block, int offset, {int? toOffset}) {
  editor.update(() {
    final element = $getRoot().getChildAtIndex(block)! as ElementNode;
    final text = element.getFirstChild();
    if (text is TextNode) {
      text.select(offset, toOffset ?? offset);
    } else {
      // An empty paragraph has no text child: normalization removes empty
      // runs, so the caret sits on the element itself.
      element.selectStart();
    }
  }, discrete: true);
}

List<String> _blocks(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

/// An input primed against the editor's current selection.
LexicalInput _primed(LexicalEditor editor) =>
    LexicalInput(editor: editor)..primeForTesting();

TextEditingDeltaInsertion _insert(LexicalInput input, String text, int at) =>
    TextEditingDeltaInsertion(
      oldText: input.lastKnownValue.text,
      textInserted: text,
      insertionOffset: at,
      selection: TextSelection.collapsed(offset: at + text.length),
      composing: TextRange.empty,
    );

TextEditingDeltaDeletion _delete(LexicalInput input, int start, int end) =>
    TextEditingDeltaDeletion(
      oldText: input.lastKnownValue.text,
      deletedRange: TextRange(start: start, end: end),
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );

TextEditingDeltaReplacement _replace(
  LexicalInput input,
  int start,
  int end,
  String text,
) => TextEditingDeltaReplacement(
  oldText: input.lastKnownValue.text,
  replacementText: text,
  replacedRange: TextRange(start: start, end: end),
  selection: TextSelection.collapsed(offset: start + text.length),
  composing: TextRange.empty,
);

void main() {
  group('the value the platform is given', () {
    test('is the block under the caret, not the document', () {
      final editor = _editor();
      _seed(editor, ['Erster', 'Zweiter', 'Dritter']);
      _caret(editor, 1, 3);
      final input = _primed(editor);
      // Newlines stand in for the two block boundaries, so a delete at either
      // edge has something to remove.
      expect(input.lastKnownValue.text, '\nZweiter\n');
      expect(
        input.lastKnownValue.selection,
        const TextSelection.collapsed(offset: 4),
      );
    });

    test('omits the sentinel at the document edges', () {
      final editor = _editor();
      _seed(editor, ['nur einer']);
      _caret(editor, 0, 0);
      expect(_primed(editor).lastKnownValue.text, 'nur einer');
    });

    test('is bounded for a very long block', () {
      final editor = _editor();
      _seed(editor, ['x' * 200000]);
      _caret(editor, 0, 100000);
      final input = LexicalInput(editor: editor, windowRadius: 512)
        ..primeForTesting();
      expect(input.lastKnownValue.text.length, 1024);
      // The caret still lands where the model says it is, in window terms.
      expect(input.lastKnownValue.selection.baseOffset, 512);
    });
  });

  group('typing', () {
    test('inserts at the caret and the two sides agree afterwards', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 5);
      final input = _primed(editor);
      input.applyDeltasForTesting([_insert(input, ',', 5)]);
      expect(_blocks(editor), ['Hallo, Welt']);
      // Agreement is what keeps the connection silent while typing: a value
      // is only pushed when the model and the platform have diverged.
      expect(input.lastKnownValue.text, 'Hallo, Welt');
      expect(input.lastKnownValue.selection.baseOffset, 6);
    });

    test('a replacement is one commit, not a delete and an insert', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 6, toOffset: 10);
      final input = _primed(editor);
      var commits = 0;
      editor.registerUpdateListener((_) => commits++);
      input.applyDeltasForTesting([_replace(input, 6, 10, 'Hinata')]);
      expect(_blocks(editor), ['Hallo Hinata']);
      expect(commits, 1);
    });

    test('a newline splits the block', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 5);
      final input = _primed(editor);
      input.applyDeltasForTesting([_insert(input, '\n', 5)]);
      expect(_blocks(editor), ['Hallo', ' Welt']);
    });

    test('pasted multi-line text becomes blocks', () {
      final editor = _editor();
      _seed(editor, ['']);
      _caret(editor, 0, 0);
      final input = _primed(editor);
      input.applyDeltasForTesting([_insert(input, 'eins\nzwei\ndrei', 0)]);
      expect(_blocks(editor), ['eins', 'zwei', 'drei']);
    });
  });

  group('deleting', () {
    test('removes the range the platform named', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 10);
      final input = _primed(editor);
      input.applyDeltasForTesting([_delete(input, 9, 10)]);
      expect(_blocks(editor), ['Hallo Wel']);
    });

    test('backspace at a block start merges with the previous block', () {
      // The whole reason the value carries a leading newline: without it the
      // platform has nothing to delete here and sends no delta at all.
      final editor = _editor();
      _seed(editor, ['Erster', 'Zweiter']);
      _caret(editor, 1, 0);
      final input = _primed(editor);
      expect(input.lastKnownValue.text, '\nZweiter');
      input.applyDeltasForTesting([_delete(input, 0, 1)]);
      expect(_blocks(editor), ['ErsterZweiter']);
    });

    test('forward delete at a block end merges with the next block', () {
      final editor = _editor();
      _seed(editor, ['Erster', 'Zweiter']);
      _caret(editor, 0, 6);
      final input = _primed(editor);
      expect(input.lastKnownValue.text, 'Erster\n');
      input.applyDeltasForTesting([_delete(input, 6, 7)]);
      expect(_blocks(editor), ['ErsterZweiter']);
    });

    test('deleting one character of a token removes the whole token', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('cc '))
              ..append($createTextNode('@Rebar')..setMode(TextMode.token))
              ..append($createTextNode(' bitte')),
          );
      }, discrete: true);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getChildAtIndex(1)! as TextNode).selectEnd();
      }, discrete: true);

      final input = _primed(editor);
      expect(input.lastKnownValue.text, 'cc @Rebar bitte');
      // The platform believes it removed one character.
      input.applyDeltasForTesting([_delete(input, 8, 9)]);
      expect(_blocks(editor), ['cc  bitte']);
      // ...so it has to be told what really happened, or the next delta is
      // computed against text that no longer exists.
      expect(input.lastKnownValue.text, 'cc  bitte');
      expect(input.lastKnownValue.selection.baseOffset, 3);
    });

    test('a selection spanning blocks is deleted whole', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt', 'Zweiter', 'Dritter']);
      editor.update(() {
        final root = $getRoot();
        final first =
            (root.getChildAtIndex(0)! as ElementNode).getFirstChild()!
                as TextNode;
        final last =
            (root.getChildAtIndex(2)! as ElementNode).getFirstChild()!
                as TextNode;
        $setSelection(
          RangeSelection(
            Point(first.key, 6, PointType.text),
            Point(last.key, 4, PointType.text),
          ),
        );
      }, discrete: true);

      final input = _primed(editor);
      // The window can only describe the focus block, so the reported
      // selection is clamped — and a delete over exactly that reported range
      // means "the selection", which the model still holds in full.
      final reported = input.lastKnownValue.selection;
      input.applyDeltasForTesting([
        _delete(input, reported.start, reported.end),
      ]);
      expect(_blocks(editor), ['Hallo ter']);
    });
  });

  group('robustness', () {
    test('a delta computed against a stale value is refused', () {
      final editor = _editor();
      _seed(editor, ['Hallo']);
      _caret(editor, 0, 5);
      final input = _primed(editor);
      const stale = TextEditingDeltaInsertion(
        oldText: 'etwas ganz anderes',
        textInserted: 'X',
        insertionOffset: 3,
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange.empty,
      );
      input.applyDeltasForTesting([stale]);
      // The document is untouched and our idea of the platform's value has
      // been re-stated rather than left to drift further.
      expect(_blocks(editor), ['Hallo']);
      expect(input.lastKnownValue.text, 'Hallo');
    });

    test('a non-text update only moves the selection', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 0);
      final input = _primed(editor);
      input.applyDeltasForTesting([
        TextEditingDeltaNonTextUpdate(
          oldText: input.lastKnownValue.text,
          selection: const TextSelection(baseOffset: 6, extentOffset: 10),
          composing: TextRange.empty,
        ),
      ]);
      expect(_blocks(editor), ['Hallo Welt']);
      expect(
        editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          return (selection.anchor.offset, selection.focus.offset);
        }),
        (6, 10),
      );
    });

    test('a platform without a direction cannot flip the selection', () {
      // iOS and macOS hold the selection as a location and a length, so a
      // backwards range comes back with its ends in document order. Believing
      // it swaps the anchor and the focus, and the next extend then moves the
      // end that was meant to stand still — which is what made selecting from
      // right to left impossible.
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 8, toOffset: 2);
      final input = _primed(editor);
      expect(
        input.lastKnownValue.selection,
        const TextSelection(baseOffset: 8, extentOffset: 2),
      );

      input.applyDeltasForTesting([
        TextEditingDeltaNonTextUpdate(
          oldText: input.lastKnownValue.text,
          selection: const TextSelection(baseOffset: 2, extentOffset: 8),
          composing: TextRange.empty,
        ),
      ]);

      expect(
        editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          return (selection.anchor.offset, selection.focus.offset);
        }),
        (8, 2),
      );
    });

    test('a direction the platform dropped is not pushed at it again', () {
      // The other half of the same story: re-stating our direction on every
      // echo is a conversation that never ends, and no `NSRange` can hold the
      // answer. What the platform is told is the range.
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 8, toOffset: 2);
      final input = _primed(editor);

      input.applyDeltasForTesting([
        TextEditingDeltaNonTextUpdate(
          oldText: input.lastKnownValue.text,
          selection: const TextSelection(baseOffset: 2, extentOffset: 8),
          composing: TextRange.empty,
        ),
      ]);

      expect(input.lastKnownValue.selection.start, 2);
      expect(input.lastKnownValue.selection.end, 8);
      expect(input.lastKnownValue.selection.baseOffset, 2);
    });

    test('a selection the platform really did move is applied', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 8, toOffset: 2);
      final input = _primed(editor);

      input.applyDeltasForTesting([
        TextEditingDeltaNonTextUpdate(
          oldText: input.lastKnownValue.text,
          selection: const TextSelection(baseOffset: 3, extentOffset: 9),
          composing: TextRange.empty,
        ),
      ]);

      expect(
        editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          return (selection.anchor.offset, selection.focus.offset);
        }),
        (3, 9),
      );
    });

    test('the composing region stays out of the editor state', () {
      final editor = _editor();
      _seed(editor, ['']);
      _caret(editor, 0, 0);
      final input = _primed(editor);
      input.applyDeltasForTesting([
        TextEditingDeltaInsertion(
          oldText: input.lastKnownValue.text,
          textInserted: 'にほん',
          insertionOffset: 0,
          selection: const TextSelection.collapsed(offset: 3),
          composing: const TextRange(start: 0, end: 3),
        ),
      ]);
      expect(_blocks(editor), ['にほん']);
      // Visible to the renderer...
      expect(input.composingRange, const TextRange(start: 0, end: 3));
      // ...and absent from the document, which is what makes undo and
      // serialization see only committed text.
      final json = editor.toJson();
      expect(json.keys, ['root']);
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });

    test('an edited document still round-trips', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt', 'Zweiter']);
      _caret(editor, 0, 5);
      final input = _primed(editor);
      input
        ..applyDeltasForTesting([_insert(input, ',', 5)])
        ..applyDeltasForTesting([_insert(input, '\n', 6)]);
      // After the split the caret is at the start of the new block, which in
      // window terms sits just past the boundary sentinel.
      final caret = input.lastKnownValue.selection.baseOffset;
      expect(caret, 1);
      input.applyDeltasForTesting([_insert(input, 'neu', caret)]);
      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
      expect(_blocks(editor), ['Hallo,', 'neu Welt', 'Zweiter']);
    });
  });

  group('the editing window', () {
    test('reuses an offset map for the block it already describes', () {
      // Rebuilding it walks the block and rebuilds its flat text. On a
      // selection drag that is once per pointer move, for a block whose text
      // by definition did not change.
      final editor = _editor();
      _seed(editor, ['Hallo Welt']);
      _caret(editor, 0, 5);

      final (first, reused, rebuilt) = editor.read(() {
        final first = $buildEditingWindow()!;
        return (
          first,
          $buildEditingWindow(reuseOffsets: first.offsets)!,
          $buildEditingWindow()!,
        );
      });

      // The map handed in is the one used, and a fresh build is a fresh map:
      // without both halves this asserts nothing.
      expect(identical(reused.offsets, first.offsets), isTrue);
      expect(identical(rebuilt.offsets, first.offsets), isFalse);
      // Reusing it changes nothing about what the platform is told.
      expect(reused.value, rebuilt.value);
    });

    test('rebuilds when the caret has moved to another block', () {
      final editor = _editor();
      _seed(editor, ['Hallo Welt', 'Zweiter']);
      _caret(editor, 0, 5);
      final stale = editor.read(() => $buildEditingWindow()!.offsets);
      _caret(editor, 1, 3);

      final window = editor.read(
        () => $buildEditingWindow(reuseOffsets: stale)!,
      );

      expect(window.blockKey, isNot(stale.blockKey));
      expect(window.offsets.flatText, 'Zweiter');
    });
  });
}
