import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

LexicalEditor _editor(List<String> paragraphs) {
  final editor = LexicalEditor();
  registerRichText(editor);
  editor.update(() {
    final root = $getRoot()..clear();
    for (final text in paragraphs) {
      root.append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
  return editor;
}

List<String> _blocks(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

(int, int) _selectionOffsets(LexicalEditor editor) => editor.read(() {
  final selection = $getSelection()! as RangeSelection;
  return (selection.anchor.offset, selection.focus.offset);
});

final _key = GlobalKey<LexicalEditableState>();

Future<void> _pumpEditable(
  WidgetTester tester,
  LexicalEditor editor, {
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LexicalEditable(
          key: _key,
          editor: editor,
          readOnly: readOnly,
          autofocus: true,
          scrollable: false,
          // A periodic blink would keep pumpAndSettle spinning forever.
          cursorBlinkInterval: Duration.zero,
          theme: const LexicalTheme(
            baseTextStyle: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('keys the editor does not handle', () {
    testWidgets('space is claimed rather than left to travel up the tree', (
      tester,
    ) async {
      // `DefaultTextEditingShortcuts`, which `WidgetsApp` installs over the
      // whole application, binds space to a text intent that only
      // `EditableText` supplies an action for. Unhandled, the
      // binding falls through and the key carries on up the tree; what is above
      // an editor is a scrollable, so finishing a word threw the page a screen
      // down. Asserted as "the intent resolves from the focused context",
      // because that is the fix: a key that no longer travels is what it buys,
      // and a widget test has no browser to show it in.
      final editor = _editor(['Hallo']);
      await _pumpEditable(tester, editor);

      final focused = FocusManager.instance.primaryFocus!.context!;
      final action = Actions.maybeFind<Intent>(
        focused,
        intent: const DoNothingAndStopPropagationTextIntent(),
      );

      expect(action, isA<DoNothingAction>());
      // Not consumed: the intent is handled so the key stops travelling, while
      // the key itself still reaches the input method and types its character.
      expect(
        action!.consumesKey(const DoNothingAndStopPropagationTextIntent()),
        isFalse,
      );
    });
  });

  testWidgets('a tap places the caret where it landed', (tester) async {
    final editor = _editor(['Hallo Welt', 'Zweiter Absatz']);
    await _pumpEditable(tester, editor);

    final blocks = _key.currentState!.registry.blocks.toList();
    expect(blocks, hasLength(2));

    // Tap into the second block, a little way along its first line.
    final second = blocks.firstWhere(
      (block) => block.offsets.flatText == 'Zweiter Absatz',
    );
    final topLeft = second.render.localToGlobal(Offset.zero);
    await tester.tapAt(topLeft + const Offset(20, 6));
    // The double-tap recognizer shares the arena, so the caret lands on the
    // press deadline rather than on the raw pointer-down.
    await tester.pump(const Duration(milliseconds: 300));

    final caretText = editor.read(
      () => ($getSelection()! as RangeSelection).focus
          .getNode()
          ?.getTextContent(),
    );
    expect(caretText, 'Zweiter Absatz');
  });

  testWidgets('arrow keys move the caret, shift extends it', (tester) async {
    final editor = _editor(['Hallo Welt']);
    await _pumpEditable(tester, editor);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).select(0, 0);
    }, discrete: true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(_selectionOffsets(editor), (2, 2));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(_selectionOffsets(editor), (2, 3));
  });

  testWidgets('backspace deletes and Enter splits', (tester) async {
    final editor = _editor(['Hallo']);
    await _pumpEditable(tester, editor);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).selectEnd();
    }, discrete: true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(_blocks(editor), ['Hall']);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(_blocks(editor), ['Hall', '']);
  });

  testWidgets('a caret is painted only in the block that has it', (
    tester,
  ) async {
    final editor = _editor(['Hallo', 'Welt']);
    await _pumpEditable(tester, editor);
    editor.update(() {
      final second = $getRoot().getChildAtIndex(1)! as ElementNode;
      (second.getFirstChild()! as TextNode).select(2, 2);
    }, discrete: true);
    await tester.pump();

    final withCaret = _key.currentState!.registry.blocks
        .where((block) => block.render.caret != null)
        .toList();
    expect(withCaret, hasLength(1));
    expect(withCaret.single.offsets.flatText, 'Welt');
    expect(withCaret.single.render.caret!.offset, 2);
  });

  testWidgets('a selection across blocks highlights each of them', (
    tester,
  ) async {
    final editor = _editor(['Hallo Welt', 'Zweiter', 'Dritter']);
    await _pumpEditable(tester, editor);
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
    await tester.pump();

    final painted = {
      for (final block in _key.currentState!.registry.blocks)
        if (block.render.selections.isNotEmpty)
          block.offsets.flatText: block.render.selections.single,
    };
    expect(painted.keys, hasLength(3));
    expect(
      painted['Hallo Welt'],
      const TextSelection(baseOffset: 6, extentOffset: 10),
    );
    // A block wholly inside the range is highlighted end to end.
    expect(
      painted['Zweiter'],
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    expect(
      painted['Dritter'],
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    // And no caret is painted while a range is selected.
    expect(
      _key.currentState!.registry.blocks.every(
        (block) => block.render.caret == null,
      ),
      isTrue,
    );
  });

  testWidgets('the caret rectangle is available for a host toolbar', (
    tester,
  ) async {
    final editor = _editor(['Hallo Welt']);
    await _pumpEditable(tester, editor);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).select(5, 5);
    }, discrete: true);
    await tester.pump();

    final rect = _key.currentState!.caretRect;
    expect(rect, isNotNull);
    expect(rect!.width, 2);
    expect(rect.height, greaterThan(0));
  });

  testWidgets('read-only allows selection but refuses edits', (tester) async {
    final editor = _editor(['Hallo']);
    await _pumpEditable(tester, editor, readOnly: true);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).selectEnd();
    }, discrete: true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(_blocks(editor), ['Hallo']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(_selectionOffsets(editor), (4, 4));
  });

  testWidgets('a host can claim a key before the defaults see it', (
    tester,
  ) async {
    final editor = _editor(['Hallo']);
    await _pumpEditable(tester, editor);
    editor.update(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      (paragraph.getFirstChild()! as TextNode).selectEnd();
    }, discrete: true);
    await tester.pump();

    var seen = 0;
    editor.registerCommand<KeyEvent>(keyDownCommand, (event) {
      if (event.logicalKey != LogicalKeyboardKey.backspace) return false;
      seen++;
      return true;
    }, CommandPriority.high);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(seen, 1);
    expect(_blocks(editor), ['Hallo']);
  });
}
