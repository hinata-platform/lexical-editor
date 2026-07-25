// Run it with:  dart run example/main.dart
//
// @mentions: the node, the trigger matching that decides when a picker opens,
// and the search controller that keeps typing smooth. All pure Dart — the
// popover is the only part that needs Flutter, and it lives in
// lexical_mention_flutter.
import 'dart:async';

import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_mention/lexical_mention.dart';

const triggers = [
  MentionTrigger(character: '@', mentionType: 'user'),
  MentionTrigger(character: '#', mentionType: 'issue', minQueryLength: 1),
];

Future<void> main() async {
  // 1. When does a picker open? -----------------------------------------
  // The scan walks backwards from the caret at most maxQueryLength
  // characters, so its cost does not grow with the paragraph.
  for (final line in [
    'Hallo @re',
    'Hallo @',
    'schreib an name@example.org',
    'siehe #42',
    'siehe #',
    'kein trigger hier',
  ]) {
    final match = matchMentionTrigger(line, line.length, triggers);
    final verdict = match == null
        ? 'no picker'
        : 'picker for ${match.trigger.mentionType}, query "${match.query}"';
    print('${line.padRight(28)} → $verdict');
  }
  print(
    '\n  name@example.org opens nothing: a trigger must start a word, or\n'
    '  every email address would open a people picker.',
  );

  // 2. Searching ---------------------------------------------------------
  // Debounced, with stale responses dropped and results cached — the three
  // things that decide whether typing stays smooth over a slow network.
  var calls = 0;
  final controller = MentionSearchController(
    triggers: triggers,
    debounce: const Duration(milliseconds: 20),
    source: CallbackMentionSource((query) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return [
        for (final name in ['Rebar', 'Rosa', 'Rune'])
          if (name.toLowerCase().startsWith(query.text.toLowerCase()))
            MentionSuggestion(
              id: name.toLowerCase(),
              label: name,
              mentionType: query.mentionType,
            ),
      ];
    }),
  );

  // Four keystrokes in quick succession, as a person actually types.
  for (final typed in ['Hallo @R', 'Hallo @Re', 'Hallo @Reb', 'Hallo @Reba']) {
    controller.onTextChanged(typed, typed.length);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 80));
  print('\nfour keystrokes cost $calls request(s)');
  print(
    'results: '
    '${controller.state.suggestions.map((item) => item.label).toList()}',
  );

  // Wandering off and coming back is answered from the cache rather than
  // from the network, which is the most common interaction there is.
  controller.onTextChanged('Hallo @Ro', 'Hallo @Ro'.length);
  await Future<void>.delayed(const Duration(milliseconds: 60));
  print('a different query: $calls request(s) in total');

  controller.onTextChanged('Hallo @Reba', 'Hallo @Reba'.length);
  await Future<void>.delayed(const Duration(milliseconds: 60));
  print('returning to the first one: still $calls — it came from the cache');
  controller.dispose();

  // 3. Inserting ---------------------------------------------------------
  final editor = LexicalEditor(nodes: mentionNodes);
  registerRichText(editor);
  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('Hallo '))
          ..append(
            $createMentionNode(
              text: '@Rebar',
              mentionType: 'user',
              mentionId: 'rebar',
            ),
          )
          ..append($createTextNode(', schau dir das an.')),
      );
  }, discrete: true);

  editor.read(() {
    final mention = $getRoot()
        .getAllTextNodes()
        .whereType<MentionNode>()
        .single;
    print(
      '\nmention: ${mention.mentionType}:${mention.mentionId} '
      '"${mention.getTextContent()}"',
    );
    // Token mode is what makes it behave as one thing: the caret steps over
    // it, and a backspace beside it removes all of it rather than a letter.
    print(
      'mode:    ${mention.getMode().wire}  (atomic — one span, not a widget)',
    );
  });
}
