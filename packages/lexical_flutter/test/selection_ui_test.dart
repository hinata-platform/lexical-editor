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
}
