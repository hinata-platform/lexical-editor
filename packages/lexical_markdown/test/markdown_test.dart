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
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ListNode).childrenSize,
        ),
        2,
      );
      expect(_to(editor), '- eins\n  - eins-a\n- zwei');
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
