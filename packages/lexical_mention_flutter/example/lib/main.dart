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

/// A source with an artificial delay, so the debounce is visible.
///
/// Top level rather than a method, so a test can call it: a suggestion's label
/// must not repeat the trigger character, and that is easy to get wrong and
/// invisible until someone reads `##108` on screen.
Future<List<MentionSuggestion>> searchDemoDirectory(MentionQuery query) async {
  await Future<void>.delayed(const Duration(milliseconds: 120));
  final needle = query.text.toLowerCase();
  if (query.mentionType == 'issue') {
    return [
      for (final (id, title) in _issues)
        if (id.startsWith(needle) || title.toLowerCase().contains(needle))
          // No `#` in the label: the trigger character is prepended when the
          // mention is inserted, so putting it here inserts it twice.
          MentionSuggestion(
            id: id,
            label: id,
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
        // Two mentions from the start, so the chips are on screen before
        // anything is typed — and so the smoke test walks the same path.
        ..append(
          $createParagraphNode()
            ..append($createTextNode('Schreib '))
            ..append(
              $createMentionNode(
                text: '@Ada Lovelace',
                mentionType: 'user',
                mentionId: 'ada',
              ),
            )
            ..append($createTextNode(' für Personen oder '))
            ..append(
              $createMentionNode(
                text: '#108',
                mentionType: 'issue',
                mentionId: '108',
                trigger: '#',
              ),
            )
            ..append($createTextNode(' für ein Ticket. ')),
        );
    }, discrete: true);
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
      source: CallbackMentionSource(searchDemoDirectory),
      itemBuilder: (context, suggestion, selected) => Container(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              child: Text(
                suggestion.mentionType == 'issue'
                    ? '#'
                    : suggestion.label.characters.first,
              ),
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
            // The cheap way to style a mention: it stays one span of text, so
            // a thousand of them cost a thousand spans and nothing else.
            // Delete the tokenBuilders entry below and this is what you get.
            'mention': BlockStyle(
              textStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          },
          tokenBuilders: {
            // The other way: a real widget, which is what padding and a
            // rounded corner need. It costs a placeholder layout and a render
            // object per mention — worth it for a handful, not for a document
            // full of them. The style above still reaches it, so the two
            // compose rather than compete.
            //
            // This runs inside the editor's read, which is where the node is
            // readable. Take what the chip needs here; the widget itself gets
            // values, never the node.
            'mention': (context, node, style) => _MentionChip(
              label: node.getTextContent(),
              // What a theme entry cannot express: `mention` is one type
              // string, but an issue should not look like a person.
              mentionType: (node as MentionNode).mentionType,
              style: style,
            ),
          },
        ),
      ),
    ),
  );
}

/// A mention drawn as a rounded chip.
///
/// The node is still a token `TextNode` — this changes how it is drawn, not
/// what it is. It serializes as text, a Lexical web client that never heard of
/// chips reads it, and the caret still steps over it as one unit.
///
/// Note what this takes: a label and a kind, **not** the node. The builder runs
/// inside the editor's read; this widget's `build` runs whenever Flutter feels
/// like it, and a node accessor there has no editor state to resolve against.
/// Reading the node in the builder and passing plain values is the rule, and it
/// is also the better Flutter widget.
class _MentionChip extends StatelessWidget {
  const _MentionChip({
    required this.label,
    required this.mentionType,
    required this.style,
  });

  final String label;

  final String mentionType;

  /// The style the mention would have been drawn with, formats and theme
  /// already resolved. Inheriting it is what keeps the chip in step with the
  /// document's font size and the platform's text scale.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final issue = mentionType == 'issue';
    final color = issue ? scheme.tertiary : (style.color ?? scheme.primary);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: style.copyWith(color: color)),
    );
  }
}
