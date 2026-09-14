import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

LexicalEditor _editor(String text) {
  final editor = LexicalEditor();
  registerRichText(editor);
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode(text)));
  }, discrete: true);
  return editor;
}

/// Pumps [editor] as a [size] box whose top left corner is at [offset].
Future<void> _pump(
  WidgetTester tester,
  LexicalEditor editor, {
  required FocusNode focusNode,
  Offset offset = const Offset(40, 60),
  Size size = const Size(300, 120),
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: offset.dx, top: offset.dy),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: LexicalEditable(
              editor: editor,
              focusNode: focusNode,
              scrollable: false,
              // A periodic blink would keep the frame loop spinning.
              cursorBlinkInterval: Duration.zero,
              theme: const LexicalTheme(
                baseTextStyle: TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Taps the first line of an editor pumped at the default offset.
///
/// Waits out the double-tap window afterwards, so the next tap is a tap of
/// its own rather than the second half of a double tap.
Future<void> _tapText(WidgetTester tester) async {
  await tester.tapAt(const Offset(60, 70));
  await tester.pump();
  await tester.pump(kDoubleTapTimeout);
}

/// The size and transform calls the platform received, oldest first.
List<Map<Object?, Object?>> _geometryCalls(WidgetTester tester) => [
  for (final call in tester.testTextInput.log)
    if (call.method == 'TextInput.setEditableSizeAndTransform')
      call.arguments! as Map<Object?, Object?>,
];

Offset _translation(Map<Object?, Object?> geometry) {
  final storage = (geometry['transform']! as List<Object?>).cast<num>();
  return Offset(storage[12].toDouble(), storage[13].toDouble());
}

void main() {
  // On the web the engine places its hidden input element where it is told
  // the editor is. Told nothing, the element sat in the corner of the page, a
  // click on the text reached the page rather than the element, and the
  // element lost focus. Safari never takes it back: typing stopped until the
  // page was reloaded, while backspace — which the editor handles itself —
  // went on working.
  group('the editor tells the platform where it is', () {
    testWidgets('before the input is shown', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await _pump(tester, _editor('Hallo'), focusNode: focusNode);
      tester.testTextInput.log.clear();

      await _tapText(tester);

      final methods = [
        for (final call in tester.testTextInput.log) call.method,
      ];
      final geometryAt = methods.indexOf(
        'TextInput.setEditableSizeAndTransform',
      );
      expect(geometryAt, isNot(-1));
      // Before `show`: the web engine places its element as editing starts.
      expect(methods.indexOf('TextInput.show'), greaterThan(geometryAt));

      final geometry = _geometryCalls(tester).first;
      expect(geometry['width'], 300);
      expect(geometry['height'], 120);
      expect(_translation(geometry), const Offset(40, 60));
    });

    testWidgets('and again once it has moved', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final editor = _editor('Hallo');
      await _pump(tester, editor, focusNode: focusNode);
      await _tapText(tester);
      tester.testTextInput.log.clear();

      await _pump(
        tester,
        editor,
        focusNode: focusNode,
        offset: const Offset(90, 140),
      );
      await tester.pump();

      final calls = _geometryCalls(tester);
      expect(calls, isNotEmpty);
      expect(_translation(calls.last), const Offset(90, 140));
    });

    testWidgets('but not once it has let go of the keyboard', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final editor = _editor('Hallo');
      await _pump(tester, editor, focusNode: focusNode);
      await _tapText(tester);

      focusNode.unfocus();
      await tester.pump();
      tester.testTextInput.log.clear();
      await _pump(
        tester,
        editor,
        focusNode: focusNode,
        offset: const Offset(90, 140),
      );
      await tester.pump();

      expect(_geometryCalls(tester), isEmpty);
    });
  });

  testWidgets('a closed connection gives up focus, and a tap opens a new one', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final editor = _editor('Hallo');
    await _pump(tester, editor, focusNode: focusNode);
    await _tapText(tester);
    expect(focusNode.hasFocus, isTrue);

    // What the web engine sends when the page loses focus to something
    // outside it.
    tester.testTextInput.closeConnection();
    await tester.pump();

    // Holding on to focus would leave a caret blinking in an editor that can
    // no longer receive a single character.
    expect(focusNode.hasFocus, isFalse);

    tester.testTextInput.log.clear();
    await _tapText(tester);

    expect(focusNode.hasFocus, isTrue);
    expect([
      for (final call in tester.testTextInput.log) call.method,
    ], contains('TextInput.setClient'));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Hallo!',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(editor.read(() => $getRoot().getTextContent()), 'Hallo!');
  });

  testWidgets('focus without a caret puts one at the end, so typing lands', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final editor = _editor('Hallo');
    await _pump(tester, editor, focusNode: focusNode);
    expect(editor.read($getSelection), isNull);

    // What an autofocused editor, or a host's own button handing focus back,
    // amounts to: focus, and no tap to put a caret anywhere.
    focusNode.requestFocus();
    await tester.pump();

    final caret = editor.read(() {
      final selection = $getSelection()! as RangeSelection;
      return (
        selection.isCollapsed,
        selection.focus.getNode()?.getTextContent(),
        selection.focus.offset,
      );
    });
    expect(caret, (true, 'Hallo', 5));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Hallo!',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(editor.read(() => $getRoot().getTextContent()), 'Hallo!');
  });
}
