import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

final _key = GlobalKey<LexicalEditableState>();

LexicalEditableState get _state => _key.currentState!;

Future<void> _pump(
  WidgetTester tester,
  LexicalEditor editor, {
  List<RemoteSelection> remote = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LexicalEditable(
          key: _key,
          editor: editor,
          autofocus: true,
          scrollable: false,
          remoteSelections: remote,
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

/// The first block's render object.
MountedBlock _block(int index) => _state.registry.blocks.toList()[index];

/// Selects [from]..[to] of the first paragraph's text node.
void _select(LexicalEditor editor, int from, int to) {
  editor.update(() {
    final text =
        ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
            as TextNode;
    text.select(from, to);
  }, discrete: true);
}

void main() {
  group('the caret', () {
    testWidgets('a trailing space does not shrink it or lift it off the '
        'line', (tester) async {
      // `getFullHeightForCaret` reports the *glyph run* at the position, and
      // for trailing whitespace the engine reports it without the style's
      // height multiplier — 14 where the line is 19.6. The caret shrank and
      // rode up to the top of the line the moment a space was typed at the end
      // of it, which reads as the space having broken something.
      final editor = _editor(['adsasda']);
      await _pump(tester, editor);

      final before = _block(0).render.caretRect(7);

      editor.update(() {
        final text =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        text.setTextContent('adsasda ');
        text.select(8, 8);
      }, discrete: true);
      await tester.pump();

      final after = _block(0).render.caretRect(8);

      expect(after.height, before.height);
      expect(after.top, before.top);
      // It did move along by the width of the space, which is the one thing
      // that should have changed.
      expect(after.left, greaterThan(before.left));
    });
  });

  group('handles', () {
    testWidgets(
      'a long press selects a word and raises the handles',
      (tester) async {
        final editor = _editor(['Hallo schöne Welt']);
        await _pump(tester, editor);

        final origin = _block(0).render.localToGlobal(Offset.zero);
        final gesture = await tester.startGesture(origin + const Offset(45, 6));
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pump();

        expect(_state.selectionEndpoints, isNotNull);
        expect(_state.selectionEndpoints!.isCollapsed, isFalse);
        // Two handles, one per end of the selection.
        expect(find.byType(CustomPaint, skipOffstage: false), findsWidgets);
        expect(_state.toolbarVisible, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'the toolbar offers what the selection allows',
      (tester) async {
        final editor = _editor(['Hallo Welt']);
        await _pump(tester, editor);

        _select(editor, 0, 5);
        await tester.pump();
        final withRange = _state.contextMenuButtonItems
            .map((item) => item.type)
            .toList();
        expect(withRange, contains(ContextMenuButtonType.copy));
        expect(withRange, contains(ContextMenuButtonType.cut));
        expect(withRange, isNot(contains(ContextMenuButtonType.selectAll)));

        _select(editor, 2, 2);
        await tester.pump();
        final collapsed = _state.contextMenuButtonItems
            .map((item) => item.type)
            .toList();
        // Nothing is selected, so Cut and Copy are left out rather than shown
        // greyed — which is what every platform's own menu does.
        expect(collapsed, isNot(contains(ContextMenuButtonType.copy)));
        expect(collapsed, contains(ContextMenuButtonType.selectAll));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'the toolbar shows the platform menu and a tap dismisses it',
      (tester) async {
        final editor = _editor(['Hallo Welt']);
        await _pump(tester, editor);

        _select(editor, 0, 5);
        await tester.pump();
        _state.showToolbar();
        await tester.pump();
        expect(find.text('Copy'), findsOneWidget);

        await tester.tapAt(_block(0).render.localToGlobal(const Offset(4, 6)));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_state.toolbarVisible, isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'dragging an end of the selection moves only that end',
      (tester) async {
        final editor = _editor(['Hallo schöne Welt']);
        await _pump(tester, editor);

        _select(editor, 0, 5);
        await tester.pump();
        final before = editor.read(
          () => ($getSelection()! as RangeSelection).orderedPoints.$1.offset,
        );

        final render = _block(0).render;
        _state.extendSelectionTo(
          render.localToGlobal(const Offset(80, 6)),
          movingStart: false,
        );
        await tester.pump();

        final (start, end) = editor.read(
          () => ($getSelection()! as RangeSelection).orderedPoints,
        );
        expect(start.offset, before);
        expect(end.offset, greaterThan(5));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('endpoints', () {
    testWidgets('a collapsed selection reports one point', (tester) async {
      final editor = _editor(['Hallo Welt']);
      await _pump(tester, editor);
      _select(editor, 3, 3);
      await tester.pump();

      final endpoints = _state.selectionEndpoints!;
      expect(endpoints.isCollapsed, isTrue);
      expect(endpoints.startHeight, greaterThan(0));
    });

    testWidgets('a range reports its left and right edges, in order', (
      tester,
    ) async {
      final editor = _editor(['Hallo Welt']);
      await _pump(tester, editor);
      _select(editor, 1, 8);
      await tester.pump();

      final endpoints = _state.selectionEndpoints!;
      expect(endpoints.isCollapsed, isFalse);
      expect(endpoints.start.dx, lessThan(endpoints.end.dx));
    });

    testWidgets('a backwards drag still reports left before right', (
      tester,
    ) async {
      final editor = _editor(['Hallo Welt']);
      await _pump(tester, editor);
      // Anchor after focus: the user dragged right to left.
      _select(editor, 8, 1);
      await tester.pump();

      final endpoints = _state.selectionEndpoints!;
      expect(endpoints.start.dx, lessThan(endpoints.end.dx));
    });
  });

  group('other people', () {
    testWidgets('a peer\'s range and caret reach the block that holds them', (
      tester,
    ) async {
      final editor = _editor(['Hallo Welt', 'Zweiter Absatz']);
      await _pump(tester, editor);

      final keys = editor.read(
        () => $getRoot().children
            .map((node) => (node as ElementNode).getFirstChild()!.key)
            .toList(),
      );
      await _pump(
        tester,
        editor,
        remote: [
          RemoteSelection(
            anchor: Point(keys[1], 0, PointType.text),
            focus: Point(keys[1], 7, PointType.text),
            color: const Color(0xFFFF0000),
            label: 'Rebar',
          ),
        ],
      );
      await tester.pump();

      expect(_block(0).render.foreignSelections, isEmpty);
      final second = _block(1).render.foreignSelections;
      expect(second, hasLength(1));
      expect(second.single.color, const Color(0xFFFF0000));
      expect(second.single.range!.start, 0);
      expect(second.single.range!.end, 7);
      expect(second.single.caretOffset, 7);
    });

    testWidgets('their caret rectangle is exposed for a name label', (
      tester,
    ) async {
      final editor = _editor(['Hallo Welt']);
      await _pump(tester, editor);
      final key = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!.key,
      );
      await _pump(
        tester,
        editor,
        remote: [
          RemoteSelection(
            anchor: Point(key, 4, PointType.text),
            focus: Point(key, 4, PointType.text),
            color: const Color(0xFF00FF00),
          ),
        ],
      );
      await tester.pump();

      final rects = _state.remoteCaretRects;
      expect(rects.keys, [0]);
      expect(rects[0]!.height, greaterThan(0));
      // A collapsed peer selection is a caret and nothing else.
      expect(_block(0).render.foreignSelections.single.range, isNull);
    });

    testWidgets('a peer in a node that no longer exists is simply absent', (
      tester,
    ) async {
      final editor = _editor(['Hallo Welt']);
      await _pump(
        tester,
        editor,
        remote: [
          RemoteSelection(
            anchor: Point(const NodeKey('does-not-exist'), 0, PointType.text),
            focus: Point(const NodeKey('does-not-exist'), 1, PointType.text),
            color: const Color(0xFF0000FF),
          ),
        ],
      );
      await tester.pump();
      expect(_state.remoteCaretRects, isEmpty);
      expect(_block(0).render.foreignSelections, isEmpty);
    });
  });

  group('dragging out a selection', () {
    /// Reports the anchor and the focus, in that order — which end is which is
    /// the whole point here, so they are never put in document order.
    (int, int) points(LexicalEditor editor) => editor.read(() {
      final selection = $getSelection()! as RangeSelection;
      return (selection.anchor.offset, selection.focus.offset);
    });

    /// Hands the value back the way a platform with no notion of direction
    /// does: iOS and macOS both carry the selection as a location and a
    /// length, so what comes back has its ends in document order.
    void echoWithoutDirection(WidgetTester tester) {
      final state = tester.testTextInput.editingState;
      if (state == null) return;
      final base = state['selectionBase'] as int;
      final extent = state['selectionExtent'] as int;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: state['text'] as String,
          selection: TextSelection(
            baseOffset: base < extent ? base : extent,
            extentOffset: base < extent ? extent : base,
          ),
        ),
      );
    }

    /// Drags with the mouse and reports the anchor after every move, so a
    /// drag that re-anchors on itself is visible rather than only its result.
    Future<List<int>> mouseDrag(
      WidgetTester tester,
      LexicalEditor editor,
      Offset from,
      Offset to, {
      bool echo = false,
    }) async {
      final anchors = <int>[];
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 20));
      for (var step = 1; step <= 8; step++) {
        await gesture.moveTo(Offset.lerp(from, to, step / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
        if (echo) {
          echoWithoutDirection(tester);
          await tester.pump();
        }
        anchors.add(points(editor).$1);
      }
      await gesture.up();
      await tester.pump();
      return anchors;
    }

    testWidgets('left to right leaves the anchor where it began', (
      tester,
    ) async {
      final editor = _editor(['Hallo schöne weite Welt']);
      await _pump(tester, editor);
      final render = _block(0).render;
      final anchors = await mouseDrag(
        tester,
        editor,
        render.localToGlobal(const Offset(4, 6)),
        render.localToGlobal(const Offset(110, 6)),
        echo: true,
      );

      final (anchor, focus) = points(editor);
      expect(anchors.toSet(), hasLength(1));
      expect(anchor, lessThan(focus));
      expect(focus - anchor, greaterThan(4));
    });

    testWidgets('right to left survives a platform without a direction', (
      tester,
    ) async {
      // The regression this pins: every echo swapped the anchor and the
      // focus, so each move re-anchored on the previous one and the selection
      // never grew past the single character between two pointer positions.
      final editor = _editor(['Hallo schöne weite Welt']);
      await _pump(tester, editor);
      final render = _block(0).render;
      final anchors = await mouseDrag(
        tester,
        editor,
        render.localToGlobal(const Offset(110, 6)),
        render.localToGlobal(const Offset(4, 6)),
        echo: true,
      );

      final (anchor, focus) = points(editor);
      expect(anchors.toSet(), hasLength(1));
      expect(focus, lessThan(anchor));
      expect(anchor - focus, greaterThan(4));
    });

    testWidgets('right to left reaches back over an earlier block', (
      tester,
    ) async {
      final editor = _editor(['Erster Absatz hier', 'Zweiter Absatz hier']);
      await _pump(tester, editor);
      await mouseDrag(
        tester,
        editor,
        _block(1).render.localToGlobal(const Offset(90, 6)),
        _block(0).render.localToGlobal(const Offset(10, 6)),
        echo: true,
      );

      final selection = editor.read($resolveDocumentSelection);
      expect(selection!.spans, hasLength(2));
    });

    testWidgets(
      'a long press keeps its word while the finger passes either side',
      (tester) async {
        final editor = _editor(['Hallo schöne weite Welt']);
        await _pump(tester, editor);
        final render = _block(0).render;
        // Inside "schöne", so there is a word on both sides of it. The test
        // font draws one glyph per font size, so this is the tenth character.
        final onWord = render.localToGlobal(const Offset(9 * 14 + 4, 6));

        final gesture = await tester.startGesture(onWord);
        await tester.pump(const Duration(milliseconds: 600));
        final (wordStart, wordEnd) = editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          final (start, end) = selection.orderedPoints;
          return (start.offset, end.offset);
        });
        expect(wordEnd, greaterThan(wordStart));

        // Left of the word: the word's far end is the one that stands still.
        await gesture.moveTo(render.localToGlobal(const Offset(1 * 14 + 4, 6)));
        await tester.pump();
        echoWithoutDirection(tester);
        await tester.pump();
        var (anchor, focus) = points(editor);
        expect(anchor, wordEnd);
        expect(focus, lessThan(wordStart));

        // Back to the right of it, and the near end takes over again.
        await gesture.moveTo(
          render.localToGlobal(const Offset(20 * 14 + 4, 6)),
        );
        await tester.pump();
        echoWithoutDirection(tester);
        await tester.pump();
        (anchor, focus) = points(editor);
        expect(anchor, wordStart);
        expect(focus, greaterThan(wordEnd));

        await gesture.up();
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
