// The @mention typeahead.
//
//   cd packages/lexical_mention_flutter/example
//   flutter create .        # once, to add the platform folders
//   flutter run
//
// Type `@` for people or `#` for issues. The popover follows the caret, the
// arrow keys move through it, Enter accepts and Escape closes — and the
// search behind it is debounced, cached and drops stale answers, which is
// what keeps typing smooth when the list comes from a network.
import 'package:flutter/material.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_mention_flutter/lexical_mention_flutter.dart';

void main() => runApp(const ExampleApp());

/// Stands in for the directory an application would actually search.
const _people = [
  ('rebar', 'Rebar Ahmad', 'Wartung'),
  ('ada', 'Ada Lovelace', 'Analytik'),
  ('grace', 'Grace Hopper', 'Compiler'),
  ('alan', 'Alan Turing', 'Kryptografie'),
  ('katherine', 'Katherine Johnson', 'Flugbahnen'),
];

const _issues = [
  ('42', 'Caret springt beim Einfügen'),
  ('108', 'Tabellen: Spalte einfügen'),
  ('256', 'Kollaboration: zweiter Cursor'),
];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'lexical_mention_flutter',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF7C5CFF)),
    home: const MentionPage(),
  );
}

class MentionPage extends StatefulWidget {
  const MentionPage({super.key});

  @override
  State<MentionPage> createState() => _MentionPageState();
}

class _MentionPageState extends State<MentionPage> {
  final LexicalEditor editor = LexicalEditor(nodes: mentionNodes);

  @override
  void initState() {
    super.initState();
    registerRichText(editor);
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()
            ..append($createTextNode('Schreib @ für Personen oder # für ein '))
            ..append($createTextNode('Ticket. ')),
        );
    }, discrete: true);
  }

  /// A source with an artificial delay, so the debounce is visible.
  Future<List<MentionSuggestion>> _search(MentionQuery query) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final needle = query.text.toLowerCase();
    if (query.mentionType == 'issue') {
      return [
        for (final (id, title) in _issues)
          if (id.startsWith(needle) || title.toLowerCase().contains(needle))
            MentionSuggestion(
              id: id,
              label: '#$id',
              mentionType: 'issue',
              subtitle: title,
            ),
      ];
    }
    return [
      for (final (id, name, team) in _people)
        if (name.toLowerCase().contains(needle))
          MentionSuggestion(
            id: id,
            label: name,
            mentionType: 'user',
            subtitle: team,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('lexical_mention_flutter')),
    body: MentionScope(
      editor: editor,
      triggers: const [
        MentionTrigger(character: '@', mentionType: 'user'),
        MentionTrigger(character: '#', mentionType: 'issue'),
      ],
      source: CallbackMentionSource(_search),
      itemBuilder: (context, suggestion, selected) => Container(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              child: Text(suggestion.label.characters.first),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(suggestion.label),
                if (suggestion.subtitle != null)
                  Text(
                    suggestion.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
      builder: (context, key) => LexicalEditable(
        key: key,
        editor: editor,
        autofocus: true,
        padding: const EdgeInsets.all(20),
        theme: LexicalTheme(
          baseTextStyle: Theme.of(context).textTheme.bodyLarge!,
          blockStyles: {
            // A mention is a token: one atomic span, not a widget. The caret
            // steps over it, and a backspace beside it removes all of it.
            'mention': BlockStyle(
              textStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          },
        ),
      ),
    ),
  );
}
