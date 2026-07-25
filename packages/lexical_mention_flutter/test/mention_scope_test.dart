import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_mention_flutter/lexical_mention_flutter.dart';

const _people = [
  MentionSuggestion(id: 'u_1', label: 'Rebar Ahmad', mentionType: 'user'),
  MentionSuggestion(id: 'u_2', label: 'Rena Berg', mentionType: 'user'),
  MentionSuggestion(id: 'u_3', label: 'Robin Klein', mentionType: 'user'),
];

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: mentionNodes);
  registerRichText(editor);
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode('cc ')));
  }, discrete: true);
  editor.update(() {
    final paragraph = $getRoot().getFirstChild()! as ElementNode;
    (paragraph.getFirstChild()! as TextNode).selectEnd();
  }, discrete: true);
  return editor;
}

String _text(LexicalEditor editor) =>
    editor.read(() => $getRoot().getFirstChild()!.getTextContent());

final _scopeKey = GlobalKey<MentionScopeState>();

Future<void> _pump(
  WidgetTester tester,
  LexicalEditor editor, {
  List<MentionSuggestion> results = _people,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MentionScope(
          key: _scopeKey,
          editor: editor,
          debounce: Duration.zero,
          triggers: const [MentionTrigger(character: '@', mentionType: 'user')],
          source: CallbackMentionSource((query) async {
            final needle = query.text.toLowerCase();
            return results
                .where((s) => s.label.toLowerCase().contains(needle))
                .toList();
          }),
          itemBuilder: (context, suggestion, highlighted) => Container(
            key: ValueKey('row-${suggestion.id}'),
            color: highlighted ? const Color(0xFFEEEEEE) : null,
            padding: const EdgeInsets.all(8),
            child: Text(suggestion.label),
          ),
          builder: (context, key) => LexicalEditable(
            key: key,
            editor: editor,
            autofocus: true,
            scrollable: false,
            cursorBlinkInterval: Duration.zero,
            theme: const LexicalTheme(baseTextStyle: TextStyle(fontSize: 14)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('typing a trigger opens the picker with matches', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);

    editor.dispatchCommand(insertTextCommand, '@Re');
    await tester.pumpAndSettle();

    expect(_scopeKey.currentState!.isOpen, isTrue);
    expect(find.text('Rebar Ahmad'), findsOneWidget);
    expect(find.text('Rena Berg'), findsOneWidget);
    // "Robin Klein" does not contain "re".
    expect(find.text('Robin Klein'), findsNothing);
  });

  testWidgets('arrow keys move the highlight and Enter inserts', (
    tester,
  ) async {
    final editor = _editor();
    await _pump(tester, editor);

    editor.dispatchCommand(insertTextCommand, '@Re');
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.state.highlightedIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.state.highlightedIndex, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_text(editor), 'cc @Rena Berg ');
    expect(_scopeKey.currentState!.isOpen, isFalse);
  });

  testWidgets('the inserted mention is one atomic node', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Reb');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    editor.read(() {
      final children = ($getRoot().getFirstChild()! as ElementNode).children
          .toList();
      expect(children, hasLength(3));
      final mention = children[1];
      expect(mention, isA<MentionNode>());
      expect((mention as MentionNode).mentionId, 'u_1');
      expect(mention.mentionType, 'user');
      expect(mention.isToken, isTrue);
      expect(mention.getTextContent(), '@Rebar Ahmad');
      expect(children[2].getTextContent(), ' ');
    });
  });

  testWidgets('an arrow key still moves the caret when the picker is shut', (
    tester,
  ) async {
    final editor = _editor();
    await _pump(tester, editor);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      editor.read(() => ($getSelection()! as RangeSelection).focus.offset),
      2,
    );
  });

  testWidgets('Escape closes without inserting', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Re');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.isOpen, isFalse);
    expect(_text(editor), 'cc @Re');
  });

  testWidgets('tapping a row inserts it', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@R');
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('row-u_3'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'after tap open=${_scopeKey.currentState!.isOpen} '
      'match=${_scopeKey.currentState!.state.match}',
    );
    expect(_text(editor), 'cc @Robin Klein ');
  });

  testWidgets('a second trigger does not read the first mention', (
    tester,
  ) async {
    // The scan stops at a token, so "@Rebar Ahmad" is not part of the next
    // query — without that, every mention would poison the one after it.
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Reb');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    editor.dispatchCommand(insertTextCommand, '@Rena');
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.state.match?.query, 'Rena');
  });

  testWidgets('typing past the trigger closes the picker', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Re');
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.isOpen, isTrue);

    editor.dispatchCommand(insertTextCommand, ' und weiter');
    await tester.pumpAndSettle();
    expect(_scopeKey.currentState!.isOpen, isFalse);
  });

  testWidgets('inserting a mention is a single commit', (tester) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Reb');
    await tester.pumpAndSettle();

    var commits = 0;
    editor.registerUpdateListener((_) => commits++);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // One commit, so one undo step: an accepted suggestion comes back in a
    // single press rather than character by character.
    expect(commits, 1);
  });

  testWidgets('an edited document with mentions still round-trips', (
    tester,
  ) async {
    final editor = _editor();
    await _pump(tester, editor);
    editor.dispatchCommand(insertTextCommand, '@Reb');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    editor.dispatchCommand(insertTextCommand, 'bitte prüfen');
    await tester.pumpAndSettle();

    final json = editor.toJson();
    expect(
      jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
      isNull,
    );
  });
}
