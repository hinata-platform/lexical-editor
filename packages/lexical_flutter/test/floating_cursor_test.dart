import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

// The test font draws every glyph as a square as wide as the font size, so at
// 14px a character is 14px wide and positions can be stated exactly.
const double _glyph = 14;

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

/// Pumps [editor] as a 300×120 box whose top left corner is at (40, 60).
Future<void> _pump(WidgetTester tester, LexicalEditor editor) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 40, top: 60),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 120,
                child: LexicalEditable(
                  editor: editor,
                  scrollable: false,
                  // A periodic blink would keep the frame loop spinning.
                  cursorBlinkInterval: Duration.zero,
                  theme: const LexicalTheme(
                    baseTextStyle: TextStyle(fontSize: _glyph, height: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// Taps in front of the first character, which puts the caret at offset zero
/// and opens the input connection.
Future<void> _tapStart(WidgetTester tester) async {
  await tester.tapAt(const Offset(41, 65));
  await tester.pump();
  await tester.pump(kDoubleTapTimeout);
}

/// Sends what iOS sends while the space bar is held and dragged: a start, then
/// each position as a distance from where the drag began, then an end.
Future<void> _floatingCursor(
  WidgetTester tester,
  FloatingCursorDragState state, [
  Offset distance = Offset.zero,
]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateFloatingCursor', <Object?>[
            // Debug builds route -1 to whichever client is attached.
            -1,
            'FloatingCursorDragState.${state.name.toLowerCase()}',
            <String, Object?>{'X': distance.dx, 'Y': distance.dy},
          ]),
        ),
        (_) {},
      );
  await tester.pump();
}

({String text, int anchor, int focus}) _selection(LexicalEditor editor) =>
    editor.read(() {
      final selection = $getSelection()! as RangeSelection;
      return (
        text: selection.focus.getNode()!.getTextContent(),
        anchor: selection.anchor.offset,
        focus: selection.focus.offset,
      );
    });

void main() {
  // The space bar held down turns the iOS keyboard into a trackpad. The editor
  // received the drag and dropped it, so the caret never moved.
  testWidgets('the keyboard trackpad moves the caret along the line', (
    tester,
  ) async {
    final editor = _editor(['Hallo Welt']);
    await _pump(tester, editor);
    await _tapStart(tester);
    expect(_selection(editor), (text: 'Hallo Welt', anchor: 0, focus: 0));

    await _floatingCursor(tester, FloatingCursorDragState.Start);
    await _floatingCursor(
      tester,
      FloatingCursorDragState.Update,
      const Offset(5 * _glyph, 0),
    );
    expect(_selection(editor), (text: 'Hallo Welt', anchor: 5, focus: 5));

    // Past the end of the editor the caret stops at the end of the text
    // rather than going nowhere.
    await _floatingCursor(
      tester,
      FloatingCursorDragState.Update,
      const Offset(1000, 0),
    );
    expect(_selection(editor), (text: 'Hallo Welt', anchor: 10, focus: 10));

    await _floatingCursor(tester, FloatingCursorDragState.End);
    expect(_selection(editor), (text: 'Hallo Welt', anchor: 10, focus: 10));
  });

  testWidgets('the keyboard trackpad moves the caret into the next block', (
    tester,
  ) async {
    final editor = _editor(['Hallo', 'Welt']);
    await _pump(tester, editor);
    await _tapStart(tester);

    await _floatingCursor(tester, FloatingCursorDragState.Start);
    await _floatingCursor(
      tester,
      FloatingCursorDragState.Update,
      const Offset(2 * _glyph, 60),
    );

    expect(_selection(editor), (text: 'Welt', anchor: 2, focus: 2));
  });

  testWidgets('a selection made with two fingers is left to the platform', (
    tester,
  ) async {
    final editor = _editor(['Hallo Welt']);
    await _pump(tester, editor);
    await _tapStart(tester);
    // Two fingers on the keyboard select: the platform extends the range, and
    // the trackpad's moves arrive alongside.
    editor.update(() {
      final text = ($getRoot().getFirstChild()! as ElementNode).getFirstChild();
      (text! as TextNode).select(0, 5);
    }, discrete: true);

    await _floatingCursor(tester, FloatingCursorDragState.Start);
    await _floatingCursor(
      tester,
      FloatingCursorDragState.Update,
      const Offset(2 * _glyph, 0),
    );

    expect(_selection(editor), (text: 'Hallo Welt', anchor: 0, focus: 5));
  });
}
