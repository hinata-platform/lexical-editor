import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_markdown/lexical_markdown.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(
  nodes: [...richTextNodes, ...listNodes, ...linkNodes, ...codeNodes],
);

/// Imports [markdown] and returns the resulting document.
LexicalEditor _from(String markdown) {
  final editor = _editor();
  editor.update(() {
    $convertFromMarkdown(markdown, transformers: defaultMarkdownTransformers);
  }, discrete: true);
  return editor;
}

String _to(LexicalEditor editor) => editor.read(
  () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
);

/// Import then export, which is the property that actually matters.
String _roundTrip(String markdown) => _to(_from(markdown));

List<String> _types(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

void main() {
  group('blocks', () {
    test('headings keep their level', () {
      final editor = _from('# Eins\n\n### Drei');
      expect(_types(editor), ['heading', 'heading']);
      expect(
        editor.read(
          () => $getRoot().children
              .cast<HeadingNode>()
              .map((node) => node.tag)
              .toList(),
        ),
        [HeadingTag.h1, HeadingTag.h3],
      );
      expect(_to(editor), '# Eins\n\n### Drei');
    });

    test('quotes round-trip, including their line breaks', () {
      expect(_roundTrip('> Ein Zitat'), '> Ein Zitat');
      final editor = _from('> Ein Zitat');
      expect(_types(editor), ['quote']);
    });

    test('paragraphs are separated by a blank line', () {
      expect(_roundTrip('Erster\n\nZweiter'), 'Erster\n\nZweiter');
    });

    test('every spelling of a thematic break is one', () {
      // `***` and `___` are the interesting ones: they are ambiguous with
      // emphasis, and an inline rule that sees them first turns the line into
      // a stray asterisk rather than a break.
      for (final marker in ['---', '***', '___', '-----', '  ---  ']) {
        expect(_types(_from('davor\n\n$marker\n\ndanach')), [
          'paragraph',
          'horizontalrule',
          'paragraph',
        ], reason: '$marker did not become a break');
      }
    });

    test('a break exports to one spelling, and reads back the same', () {
      expect(_roundTrip('davor\n\n***\n\ndanach'), 'davor\n\n---\n\ndanach');
      expect(_roundTrip('davor\n\n---\n\ndanach'), 'davor\n\n---\n\ndanach');
    });

    test('dashes inside a fence stay content', () {
      // A fence is consumed before the line rules run, and it has to stay that
      // way: `---` in a code sample is text the writer typed.
      const source = '```\n---\n```';
      expect(_types(_from(source)), ['code']);
      expect(_roundTrip(source), source);
    });

    test('a setext underline does not swallow the line above it', () {
      // `Titel\n---` is an h2 in CommonMark. This importer is line-based and
      // has no setext rule, so the honest outcome is a paragraph and a break —
      // not a break that ate the title.
      expect(_types(_from('Titel\n---')), ['paragraph', 'horizontalrule']);
      expect(
        _from('Titel\n---').read(() => $getRoot().getTextContent()),
        contains('Titel'),
      );
    });

    test('a fenced code block keeps its language and its content verbatim', () {
      const source = '```dart\nvoid main() {\n  print("*hi*");\n}\n```';
      final editor = _from(source);
      expect(_types(editor), ['code']);
      expect(
        editor.read(() => ($getRoot().getFirstChild()! as CodeNode).language),
        'dart',
      );
      // Nothing inside a fence is parsed: those asterisks are asterisks.
      expect(
        editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
        'void main() {\n  print("*hi*");\n}',
      );
      expect(_to(editor), source);
    });

    test('a fence with no language round-trips too', () {
      expect(_roundTrip('```\nnur text\n```'), '```\nnur text\n```');
    });
  });

  group('lists', () {
    test('consecutive bullets become one list', () {
      final editor = _from('- eins\n- zwei\n- drei');
      expect(_types(editor), ['list']);
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ListNode).childrenSize,
        ),
        3,
      );
      expect(_to(editor), '- eins\n- zwei\n- drei');
    });

    test('ordered lists keep their numbering', () {
      expect(_roundTrip('1. eins\n2. zwei'), '1. eins\n2. zwei');
      final editor = _from('1. eins\n2. zwei');
      expect(
        editor.read(() => ($getRoot().getFirstChild()! as ListNode).listType),
        ListType.number,
      );
    });

    test('check lists keep their ticks', () {
      final editor = _from('- [x] erledigt\n- [ ] offen');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ListNode).children
              .cast<ListItemNode>()
              .map((item) => item.checked)
              .toList(),
        ),
        [true, false],
      );
      expect(_to(editor), '- [x] erledigt\n- [ ] offen');
    });

    test('a check list is not read as a bullet list', () {
      // Both rules match the same line; order is what decides, which is why
      // the check rule is declared first.
      final editor = _from('- [ ] offen');
      expect(
        editor.read(() => ($getRoot().getFirstChild()! as ListNode).listType),
        ListType.check,
      );
    });

    test('indentation nests, and comes back out', () {
      final editor = _from('- eins\n  - eins-a\n- zwei');
      // Three items, not two: the nested list is held by an item of its own,
      // between the two that carry text.
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ListNode).childrenSize,
        ),
        3,
      );
      expect(_to(editor), '- eins\n  - eins-a\n- zwei');
    });

    test('a nested list is a sibling of the item it sits under', () {
      // The shape Lexical itself writes. The other one — the nested list as a
      // child of the item holding the parent's text — carries the same words,
      // which is why it survives reading the output. It is a different
      // document to anything that walks structure.
      final editor = _from('- außen\n  - innen');
      final shape = editor.read(() {
        final list = $getRoot().getFirstChild()! as ListNode;
        return list.children
            .cast<ListItemNode>()
            .map(
              (item) => (
                // Joined rather than kept as a list: a record compares its
                // fields with `==`, and two equal lists are not `==`.
                item.children.map((child) => child.type).join(','),
                item.isNestedListHolder,
              ),
            )
            .toList();
      });

      expect(shape, [('text', false), ('list', true)]);
    });

    test('an item carries the nesting depth of the list it belongs to', () {
      // `indent` is what tells a renderer, an exporter and Lexical web how deep
      // an item sits. Leaving every item at 0 makes a three-level list render
      // flat everywhere except in the importer that built it.
      final editor = _from('- außen\n  - innen\n    - ganz innen\n- zurück');
      final indents = editor.read(() {
        final out = <(String, int)>[];
        void walk(ListNode list) {
          for (final item in list.children.cast<ListItemNode>()) {
            final nested = item.getFirstChild();
            if (nested is ListNode) {
              out.add(('<holder>', item.getIndent()));
              walk(nested);
            } else {
              out.add((item.getTextContent(), item.getIndent()));
            }
          }
        }

        walk($getRoot().getFirstChild()! as ListNode);
        return out;
      });

      expect(indents, [
        ('außen', 0),
        ('<holder>', 0),
        ('innen', 1),
        ('<holder>', 1),
        ('ganz innen', 2),
        ('zurück', 0),
      ]);
    });

    test('numbering counts holders, so a nested list does not restart it', () {
      final editor = _from('1. eins\n   1. eins-a\n1. zwei');
      final values = editor.read(
        () => ($getRoot().getFirstChild()! as ListNode).children
            .cast<ListItemNode>()
            .map((item) => item.value)
            .toList(),
      );

      expect(values, [1, 2, 3]);
      expect(_to(editor), '1. eins\n  1. eins-a\n3. zwei');
    });

    test('three levels round-trip without losing a level', () {
      const source = '- außen\n  - innen\n    - ganz innen\n- zurück';
      expect(_roundTrip(source), source);
    });
  });

  group('inline formatting', () {
    test('bold, italic, strikethrough and code', () {
      final editor = _from('**fett** *kursiv* ~~weg~~ `code`');
      final formats = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .where((node) => node.getFormat() != 0)
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList(),
      );
      expect(formats, [
        ('fett', TextFormat.bold.bit),
        ('kursiv', TextFormat.italic.bit),
        ('weg', TextFormat.strikethrough.bit),
        ('code', TextFormat.code.bit),
      ]);
      expect(_to(editor), '**fett** *kursiv* ~~weg~~ `code`');
    });

    test('nested delimiters produce both formats', () {
      // The case a naive tokenizer gets wrong: the closing run has to be
      // matched from its end, or the inner emphasis loses an asterisk.
      final editor = _from('***beides***');
      editor.read(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        expect(node.getTextContent(), 'beides');
        expect(node.getFormat(), TextFormat.bold.bit | TextFormat.italic.bit);
      });
    });

    test('a code span is taken exactly as written', () {
      // In markdown the content of a code span is characters, not syntax.
      // Parsing emphasis in there invents formatting nobody wrote — and
      // exports as `` `a `**`b`** ``, which no longer says the same thing.
      final editor = _from('ein `code mit **stern**` darin');
      final runs = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList(),
      );
      expect(runs, [
        ('ein ', 0),
        ('code mit **stern**', TextFormat.code.bit),
        (' darin', 0),
      ]);
      expect(_to(editor), 'ein `code mit **stern**` darin');
    });

    test('an escaped delimiter is a character, not a delimiter', () {
      // `\*` is how an author writes an asterisk. Treating it as emphasis
      // loses the asterisks and leaves the backslashes stranded in the text.
      final editor = _from(r'ein \*kein Stern\* mehr');
      final runs = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList(),
      );
      expect(runs, [(r'ein \*kein Stern\* mehr', 0)]);
      expect(_to(editor), r'ein \*kein Stern\* mehr');
    });

    test('an unpaired delimiter is literal text', () {
      final editor = _from('2 * 3 = 6');
      expect(
        editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
        '2 * 3 = 6',
      );
    });

    test('underscores work as well as asterisks', () {
      final editor = _from('__fett__ und _kursiv_');
      final formats = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => node.getFormat())
            .toList(),
      );
      expect(formats.contains(TextFormat.bold.bit), isTrue);
      expect(formats.contains(TextFormat.italic.bit), isTrue);
    });
  });

  group('links', () {
    test('a label is markdown, not characters', () {
      // CommonMark resolves emphasis inside a link label. Keeping the
      // asterisks would show a reader the syntax rather than the formatting,
      // and would disagree with every CommonMark parser a document travels to.
      final editor = _from('[ein *kursiver* Link](https://x.de)');
      final runs = editor.read(() {
        final link =
            ($getRoot().getFirstChild()! as ElementNode).children
                    .whereType<LinkNode>()
                    .first
                as ElementNode;
        return link.children
            .cast<TextNode>()
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList();
      });

      expect(runs, [
        ('ein ', 0),
        ('kursiver', TextFormat.italic.bit),
        (' Link', 0),
      ]);
      expect(_to(editor), '[ein *kursiver* Link](https://x.de)');
    });

    test('a label inside emphasis keeps the emphasis around it', () {
      // The rule put the outer bold on the label it made; re-parsing has to add
      // to that rather than trade it for the inner format.
      final editor = _from('**[ein *kursiver* Link](https://x.de)**');
      final runs = editor.read(() {
        final link =
            ($getRoot().getFirstChild()! as ElementNode).children
                    .whereType<LinkNode>()
                    .first
                as ElementNode;
        return link.children
            .cast<TextNode>()
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList();
      });

      expect(runs, [
        ('ein ', TextFormat.bold.bit),
        ('kursiver', TextFormat.bold.bit | TextFormat.italic.bit),
        (' Link', TextFormat.bold.bit),
      ]);
    });

    test('a plain label is left as the one node the rule made', () {
      final editor = _from('[die Doku](https://example.org)');
      expect(
        editor.read(() {
          final link =
              ($getRoot().getFirstChild()! as ElementNode).children
                      .whereType<LinkNode>()
                      .first
                  as ElementNode;
          return link.childrenSize;
        }),
        1,
      );
    });

    test('round-trip', () {
      final editor = _from('siehe [die Doku](https://example.org) dort');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).children
              .whereType<LinkNode>()
              .map((node) => node.url)
              .toList(),
        ),
        ['https://example.org'],
      );
      expect(_to(editor), 'siehe [die Doku](https://example.org) dort');
    });

    test('a title survives', () {
      expect(
        _roundTrip('[x](https://example.org "Titel")'),
        '[x](https://example.org "Titel")',
      );
    });

    test('a dangerous scheme is preserved, not rewritten', () {
      // Validation belongs where the link is made tappable. Rewriting it here
      // would silently change the document.
      final editor = _from('[klick](javascript:void)');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).children
              .whereType<LinkNode>()
              .single
              .url,
        ),
        'javascript:void',
      );
      expect(isSafeUrl('javascript:void'), isFalse);
    });
  });

  group('the whole thing', () {
    const source = '''
# Titel

Ein Absatz mit **fett**, *kursiv* und [einem Link](https://example.org).

> Ein Zitat

- eins
- zwei

1. erstens
2. zweitens

- [x] erledigt
- [ ] offen

```dart
void main() {}
```''';

    test('round-trips as a fixed point', () {
      final once = _roundTrip(source);
      // The second pass must not change anything further; that is what makes
      // the conversion safe to run repeatedly.
      expect(_roundTrip(once), once);
    });

    test('produces the blocks it should', () {
      expect(_types(_from(source)), [
        'heading',
        'paragraph',
        'quote',
        'list',
        'list',
        'list',
        'code',
      ]);
    });

    test('the imported document is a valid Lexical document', () {
      final editor = _from(source);
      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });

    test('empty input still leaves somewhere to type', () {
      expect(_types(_from('')), ['paragraph']);
    });
  });
}
