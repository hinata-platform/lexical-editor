// Emoji from outside the app: a launcher's paste, the browser's paste, and the
// fallback font that has to arrive before an emoji can be drawn.
//
// Raycast's emoji picker — and Alfred, and any clipboard manager with a
// "paste into the front app" action — writes to the pasteboard, gives
// activation back and posts ⌘V straight away. Typing ⌘V by hand worked; the
// launcher's never did, for two reasons that each lose the key on their own.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_flutter/src/widgets/lexical_editable.dart'
    show browserPastesNatively;

const _emoji = '✅😊☀️❤️👨‍👩‍👧';

final _key = GlobalKey<LexicalEditableState>();

LexicalEditor _editor(String text) {
  final editor = LexicalEditor();
  registerRichText(editor);
  editor.update(() {
    final paragraph = $createParagraphNode()..append($createTextNode(text));
    $getRoot()
      ..clear()
      ..append(paragraph);
    paragraph.selectEnd();
  }, discrete: true);
  return editor;
}

String _text(LexicalEditor editor) =>
    editor.read(() => $getRoot().getTextContent());

/// Serves [text] to `Clipboard.getData` for the rest of the test.
void _clipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData' ? {'text': text} : null,
  );
}

Future<void> _pump(WidgetTester tester, LexicalEditor editor) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LexicalEditable(
          key: _key,
          editor: editor,
          autofocus: true,
          scrollable: false,
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
  testWidgets(
    'a key that lands before the framework hands focus back still pastes',
    (tester) async {
      // While the launcher's panel is up the application is inactive, and the
      // framework parks focus on the root scope. It gives it back on resume,
      // but only at its next focus update — and on macOS the posted ⌘V is
      // dispatched first. The key-down found nothing focused and went to the
      // input method as `noop:`; only the key-up reached the editor.
      final editor = _editor('ab');
      _clipboard(tester, _emoji);
      await _pump(tester, editor);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final manager = FocusManager.instance;
      expect(manager.primaryFocus, manager.rootScope, reason: 'parked');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(_text(editor), 'ab$_emoji');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_key.currentState!.mounted, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'keys typed while the view itself lost focus stay out of the document',
    (tester) async {
      // On the web the view loses focus whenever DOM focus moves to an element
      // outside it — an input in the host page, a password manager — and the
      // framework parks focus on the root scope just as for an inactive app.
      // The engine still hears every key typed there. None of them, not even
      // the first, may reach the editor or pull focus back into it.
      final editor = _editor('ab');
      _clipboard(tester, _emoji);
      await _pump(tester, editor);

      tester.binding.handleViewFocusChanged(
        ui.ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ui.ViewFocusState.unfocused,
          direction: ui.ViewFocusDirection.undefined,
        ),
      );
      await tester.pump();
      final manager = FocusManager.instance;
      expect(manager.primaryFocus, manager.rootScope, reason: 'parked');

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(_text(editor), 'ab');
      expect(manager.primaryFocus, manager.rootScope);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a key is not taken from whatever got focus in the meantime', (
    tester,
  ) async {
    final editor = _editor('ab');
    _clipboard(tester, _emoji);
    final other = FocusNode();
    addTearDown(other.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: other, child: const SizedBox(height: 10)),
              LexicalEditable(
                key: _key,
                editor: editor,
                autofocus: true,
                scrollable: false,
                cursorBlinkInterval: Duration.zero,
                theme: const LexicalTheme(
                  baseTextStyle: TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    other.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(_text(editor), 'ab');
    expect(other.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('⌘ that only the event itself carries still counts as ⌘', (
    tester,
  ) async {
    // A process that posts a key event with `kCGEventFlagMaskCommand` sets
    // the side-less command flag and neither the left nor the right one.
    // The macOS engine synthesizes modifier events from the sided bits only,
    // so HardwareKeyboard never hears of ⌘ and the event reads as plain V.
    // This sends the pair the engine sends for exactly that event: the key
    // data without a modifier, the raw message with flag 0x100000 alone.
    final editor = _editor('ab');
    _clipboard(tester, _emoji);
    await _pump(tester, editor);

    // The engine's own entry point. Deprecated for apps, and the only way
    // to hand the framework exactly the pair the engine hands it.
    // ignore: deprecated_member_use
    final manager = tester.binding.keyEventManager;
    Future<void> send(ui.KeyEventType type, String rawType) async {
      // ignore: deprecated_member_use
      manager.handleKeyData(
        ui.KeyData(
          timeStamp: Duration.zero,
          type: type,
          physical: PhysicalKeyboardKey.keyV.usbHidUsage,
          logical: LogicalKeyboardKey.keyV.keyId,
          character: type == ui.KeyEventType.down ? 'v' : null,
          synthesized: false,
        ),
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.keyEvent.name,
        SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
          'type': rawType,
          'keymap': 'macos',
          'keyCode': 9,
          'characters': 'v',
          'charactersIgnoringModifiers': 'v',
          'modifiers': 0x100000,
        }),
        (_) {},
      );
    }

    await send(ui.KeyEventType.down, 'keydown');
    expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
    await tester.pump();
    expect(_text(editor), 'ab$_emoji');
    await send(ui.KeyEventType.up, 'keyup');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'the caret lands after a pasted emoji and backspace takes it whole',
    (tester) async {
      final editor = _editor('ab');
      _clipboard(tester, _emoji);
      await _pump(tester, editor);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(_text(editor), 'ab$_emoji');

      // Offsets are UTF-16 code units on both sides of the channel.
      final state = tester.testTextInput.editingState!;
      expect(state['text'], 'ab$_emoji');
      expect(state['selectionBase'], 'ab$_emoji'.length);
      expect(state['selectionExtent'], 'ab$_emoji'.length);

      // The family is one grapheme of eight code units.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_text(editor), 'ab✅😊☀️❤️');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_text(editor), 'ab✅😊☀️');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('on the web the browser pastes, not a clipboard read', (
    tester,
  ) async {
    // Reading the clipboard from script needs a permission prompt in Chrome
    // and a "Paste" bubble per paste in Safari; a refused prompt pasted
    // nothing at all. The browser's own paste needs neither, so the key is
    // left unconsumed and the text comes back as an insertion delta.
    browserPastesNatively = true;
    addTearDown(() => browserPastesNatively = false);
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') reads++;
        return null;
      },
    );
    final editor = _editor('ab');
    await _pump(tester, editor);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(handled, isFalse, reason: 'left for the browser to perform');
    expect(reads, 0);

    final input = _key.currentState!.input;
    final before = input.lastKnownValue;
    input.applyDeltasForTesting([
      TextEditingDeltaInsertion(
        oldText: before.text,
        textInserted: _emoji,
        insertionOffset: before.selection.baseOffset,
        selection: TextSelection.collapsed(
          offset: before.selection.baseOffset + _emoji.length,
        ),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(_text(editor), 'ab$_emoji');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a block lays its text out again when new fonts arrive', (
    tester,
  ) async {
    // The web has no font for emoji until the engine fetches one, and lays
    // the glyph out as a missing-glyph box until then. When the font lands
    // the engine announces it; a block that did not listen kept its boxes.
    final editor = _editor('ab$_emoji');
    await _pump(tester, editor);
    final render = _key.currentState!.registry.blocks.single.render;
    expect(render.debugNeedsLayout, isFalse);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (_) {},
    );
    // The render tree answers in the next frame's transient callbacks; one
    // registered after the announcement runs right behind it.
    bool? relayoutRequested;
    tester.binding.scheduleFrameCallback(
      (_) => relayoutRequested = render.debugNeedsLayout,
    );
    await tester.pump();
    expect(relayoutRequested, isTrue);
    expect(render.debugNeedsLayout, isFalse);
  });
}
