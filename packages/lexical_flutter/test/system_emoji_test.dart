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
    show debugBrowserPastesNativelyOverride;

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
/// Serves [text] to `Clipboard.getData` and returns how often it was read.
int Function() _clipboard(WidgetTester tester, String text) {
  var reads = 0;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method != 'Clipboard.getData') return null;
      reads++;
      return {'text': text};
    },
  );
  return () => reads;
}

/// Sends one V event exactly as the macOS engine hands it over — key data,
/// then the raw message carrying the event's [modifiers] — without yielding,
/// so nothing scheduled before it gets to run first.
void _sendV(WidgetTester tester, {required int modifiers, bool down = true}) {
  // The engine's own entry point. Deprecated for apps, and the only way to
  // hand the framework exactly the pair the engine hands it.
  // ignore: deprecated_member_use
  tester.binding.keyEventManager.handleKeyData(
    ui.KeyData(
      timeStamp: Duration.zero,
      type: down ? ui.KeyEventType.down : ui.KeyEventType.up,
      physical: PhysicalKeyboardKey.keyV.usbHidUsage,
      logical: LogicalKeyboardKey.keyV.keyId,
      character: down ? 'v' : null,
      synthesized: false,
    ),
  );
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
      'type': down ? 'keydown' : 'keyup',
      'keymap': 'macos',
      'keyCode': 9,
      'characters': 'v',
      'charactersIgnoringModifiers': 'v',
      'modifiers': modifiers,
    }),
    (_) {},
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
      final reads = _clipboard(tester, _emoji);
      await _pump(tester, editor);
      final state = _key.currentState!;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final manager = FocusManager.instance;
      expect(manager.primaryFocus, manager.rootScope, reason: 'parked');
      expect(state.debugTakesParkedKeys, isTrue);

      // Resume and the key in one turn, as they arrive from the engine: the
      // framework has asked for focus back but not applied it yet. The event
      // carries the side-less command flag only, as Raycast sends it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(manager.primaryFocus, manager.rootScope, reason: 'still parked');
      _sendV(tester, modifiers: 0x100000);
      _sendV(tester, modifiers: 0x100000, down: false);
      await tester.pump();
      await tester.pump();

      expect(_text(editor), 'ab$_emoji');
      expect(reads(), 1);
      expect(manager.primaryFocus, isNot(manager.rootScope));
      expect(
        manager.primaryFocus?.context
            ?.findAncestorStateOfType<LexicalEditableState>(),
        same(state),
      );
      expect(state.debugTakesParkedKeys, isFalse);
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

  testWidgets(
    'a key for a field inside the document does not land in the body',
    (tester) async {
      // An image caption is a text field of its own, inside the editor. The
      // editor's node reports focus while the caption has it, and a paste
      // meant for the caption must not go into the body.
      final editor = _editor('ab');
      _clipboard(tester, _emoji);
      final editorFocus = FocusNode();
      final caption = FocusNode();
      addTearDown(editorFocus.dispose);
      addTearDown(caption.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LexicalEditable(
              key: _key,
              editor: editor,
              focusNode: editorFocus,
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
      final attachment = caption.attach(_key.currentContext);
      addTearDown(attachment.detach);
      attachment.reparent(parent: editorFocus);
      caption.requestFocus();
      await tester.pump();
      expect(editorFocus.hasFocus, isTrue);
      expect(editorFocus.hasPrimaryFocus, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();

      expect(_text(editor), 'ab');
      expect(editorFocus.hasPrimaryFocus, isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'focus that lands elsewhere while the app is inactive ends the claim',
    (tester) async {
      // Focus moved on while the app was inactive; when it is parked again
      // later, the editor has no claim on what is typed.
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
      final state = _key.currentState!;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(state.debugTakesParkedKeys, isTrue);

      other.requestFocus();
      await tester.pump();
      expect(state.debugTakesParkedKeys, isFalse);

      FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(_text(editor), 'ab');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('an editor disposed while parked lets go of the keyboard', (
    tester,
  ) async {
    final editor = _editor('ab');
    _clipboard(tester, _emoji);
    await _pump(tester, editor);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final state = _key.currentState!;
    expect(state.debugTakesParkedKeys, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(state.mounted, isFalse);
    expect(state.debugTakesParkedKeys, isFalse, reason: 'released on dispose');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(_text(editor), 'ab');
    expect(tester.takeException(), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a key the editor does not take does not pull focus in', (
    tester,
  ) async {
    final editor = _editor('ab');
    await _pump(tester, editor);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final manager = FocusManager.instance;
    expect(manager.primaryFocus, manager.rootScope);
    expect(_key.currentState!.debugTakesParkedKeys, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a resume does not end a claim made after it', (tester) async {
    // Resume, focus back, inactive again — all before the frame in which the
    // resume would end its claim. The new claim is not the resume's to end.
    final editor = _editor('ab');
    await _pump(tester, editor);
    final state = _key.currentState!;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(state.debugTakesParkedKeys, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.value(); // focus comes back, no frame yet
    expect(state.debugTakesParkedKeys, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(state.debugTakesParkedKeys, isTrue);

    await tester.pump();
    expect(state.debugTakesParkedKeys, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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

    _sendV(tester, modifiers: 0x100000);
    expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
    await tester.pump();
    expect(_text(editor), 'ab$_emoji');
    _sendV(tester, modifiers: 0x100000, down: false);
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
    debugBrowserPastesNativelyOverride = true;
    addTearDown(() => debugBrowserPastesNativelyOverride = null);
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

  testWidgets('on the web a pasteCommand handler still runs first', (
    tester,
  ) async {
    // Leaving ⌘V to the browser must not bypass a host's own paste.
    debugBrowserPastesNativelyOverride = true;
    addTearDown(() => debugBrowserPastesNativelyOverride = null);
    final reads = _clipboard(tester, _emoji);
    final editor = _editor('ab');
    var pastes = 0;
    final unregister = editor.registerCommand(pasteCommand, (_) {
      pastes++;
      return true;
    }, CommandPriority.editor);
    addTearDown(unregister);
    await _pump(tester, editor);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(pastes, 1);
    expect(handled, isTrue, reason: 'the handler took it, not the browser');
    expect(reads(), 0);
    expect(_text(editor), 'ab');
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
