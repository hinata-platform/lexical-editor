import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('format bitmask', () {
    test('bit values match the wire format', () {
      expect(TextFormat.bold.bit, 1);
      expect(TextFormat.italic.bit, 2);
      expect(TextFormat.strikethrough.bit, 4);
      expect(TextFormat.underline.bit, 8);
      expect(TextFormat.code.bit, 16);
      expect(TextFormat.subscript.bit, 32);
      expect(TextFormat.superscript.bit, 64);
      expect(TextFormat.highlight.bit, 128);
      expect(TextFormat.lowercase.bit, 256);
      expect(TextFormat.uppercase.bit, 512);
      expect(TextFormat.capitalize.bit, 1024);
    });

    test('formats combine by OR', () {
      final editor = LexicalEditor();
      editor.update(() {
        final text = $createTextNode('x')
          ..toggleFormat(TextFormat.bold)
          ..toggleFormat(TextFormat.italic);
        expect(text.getFormat(), 3);
        text.toggleFormat(TextFormat.strikethrough);
        expect(text.getFormat(), 7);
        text.toggleFormat(TextFormat.italic);
        expect(text.getFormat(), 5);
      }, discrete: true);
    });

    test('case transforms are mutually exclusive', () {
      final editor = LexicalEditor();
      editor.update(() {
        final text = $createTextNode('x')..toggleFormat(TextFormat.uppercase);
        expect(text.hasFormat(TextFormat.uppercase), isTrue);
        text.toggleFormat(TextFormat.lowercase);
        expect(text.hasFormat(TextFormat.lowercase), isTrue);
        expect(text.hasFormat(TextFormat.uppercase), isFalse);
      }, discrete: true);
    });
  });

  group('merge rules', () {
    test('identical simple runs may merge', () {
      final editor = LexicalEditor();
      editor.update(() {
        final a = $createTextNode('a')..toggleFormat(TextFormat.bold);
        final b = $createTextNode('b')..toggleFormat(TextFormat.bold);
        expect(a.canMergeWith(b), isTrue);
      }, discrete: true);
    });

    test('runs with different formats do not merge', () {
      final editor = LexicalEditor();
      editor.update(() {
        final a = $createTextNode('a')..toggleFormat(TextFormat.bold);
        final b = $createTextNode('b');
        expect(a.canMergeWith(b), isFalse);
      }, discrete: true);
    });

    test('a tab never merges', () {
      final editor = LexicalEditor();
      editor.update(() {
        final tab = $createTabNode();
        final text = $createTextNode('\t');
        expect(tab.isUnmergeable, isTrue);
        expect(text.canMergeWith(tab), isFalse);
        expect(tab.canMergeWith(text), isFalse);
      }, discrete: true);
    });

    test('token nodes are not simple text', () {
      final editor = LexicalEditor();
      editor.update(() {
        final token = $createTextNode('@name')..setMode(TextMode.token);
        expect(token.isToken, isTrue);
        expect(token.isSimpleText, isFalse);
      }, discrete: true);
    });
  });

  group('splitText', () {
    test('splits at code-unit offsets and keeps formatting', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abcdef')
          ..toggleFormat(TextFormat.bold)
          ..setStyle('color: red');
        paragraph.append(text);

        final parts = text.splitText([2, 4]);
        expect(parts.map((node) => node.getTextContent()).toList(), [
          'ab',
          'cd',
          'ef',
        ]);
        for (final part in parts) {
          expect(part.hasFormat(TextFormat.bold), isTrue);
          expect(part.getStyle(), 'color: red');
        }
        expect(paragraph.childrenSize, 3);
        expect(assertTreeIntegrity($getRoot()), isTrue);
      }, discrete: true);
    });

    test('the caret comes along into the part it now belongs to', () {
      // Otherwise it keeps naming this node at an offset longer than the node
      // now is, and the next keystroke lands in the run before the split —
      // which is what a hashtag being typed used to do with the characters
      // after its first.
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abcdef');
        paragraph.append(text);
        text.select(5, 5);

        final parts = text.splitText([2]);
        final selection = $getSelection()! as RangeSelection;
        expect(selection.anchor.key, parts[1].key);
        expect(selection.anchor.offset, 3);
        expect(selection.focus.key, parts[1].key);
        expect(selection.focus.offset, 3);
      }, discrete: true);
    });

    test('a range across the split keeps both of its ends', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abcdef');
        paragraph.append(text);
        text.select(1, 5);

        final parts = text.splitText([3]);
        final selection = $getSelection()! as RangeSelection;
        expect(selection.anchor.key, parts[0].key);
        expect(selection.anchor.offset, 1);
        expect(selection.focus.key, parts[1].key);
        expect(selection.focus.offset, 2);
      }, discrete: true);
    });

    test('a backwards range keeps its direction', () {
      // anchor after focus is a right-to-left drag, and the direction is part
      // of the selection's meaning — not something to normalize away.
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abcdef');
        paragraph.append(text);
        text.select(5, 1);

        final parts = text.splitText([3]);
        final selection = $getSelection()! as RangeSelection;
        expect(selection.anchor.key, parts[1].key);
        expect(selection.anchor.offset, 2);
        expect(selection.focus.key, parts[0].key);
        expect(selection.focus.offset, 1);
      }, discrete: true);
    });

    test('a caret exactly on the split lands at the end of the first part', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abcdef');
        paragraph.append(text);
        text.select(3, 3);

        final parts = text.splitText([3]);
        final selection = $getSelection()! as RangeSelection;
        expect(selection.anchor.key, parts[0].key);
        expect(selection.anchor.offset, 3);
      }, discrete: true);
    });

    test('offsets at the edges are ignored', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot().append(paragraph);
        final text = $createTextNode('abc');
        paragraph.append(text);
        final parts = text.splitText([0, 3, 99]);
        expect(parts, hasLength(1));
        expect(paragraph.childrenSize, 1);
      }, discrete: true);
    });
  });

  group('unicode', () {
    test('offsets count UTF-16 code units, not graphemes', () {
      final editor = LexicalEditor();
      editor.update(() {
        // A woman-technologist ZWJ sequence is one grapheme, five code units.
        const emoji = '\u{1F469}‍\u{1F4BB}';
        final text = $createTextNode(emoji);
        expect(text.getTextContentSize(), 5);
      }, discrete: true);
    });

    test('text content is preserved byte for byte', () {
      final editor = LexicalEditor();
      const combining = 'é vs é';
      editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode(combining));
        $getRoot().append(paragraph);
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      final text = (paragraph['children']! as List).first as Map;
      expect(text['text'], combining);
    });
  });

  group('tab node', () {
    test('is always a single tab with the unmergeable detail', () {
      final editor = LexicalEditor();
      editor.update(() {
        final tab = $createTabNode()..setTextContent('etwas anderes');
        expect(tab.getTextContent(), '\t');
        expect(tab.getDetail(), TextDetail.unmergeable.bit);
        expect(tab.type, 'tab');
      }, discrete: true);
    });
  });

  group('paragraph derived fields', () {
    test('textFormat is derived from the first text child on export', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        final plain = $createTextNode('plain ');
        final bold = $createTextNode('bold')..toggleFormat(TextFormat.bold);
        paragraph
          ..append(plain)
          ..append(bold);
        $getRoot().append(paragraph);
        // Claim something contradictory; export must ignore it.
        paragraph.setTextFormat(999);
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      expect(paragraph['textFormat'], 0);
      expect(paragraph['textStyle'], '');
    });

    test('an empty paragraph keeps its own textFormat', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode()
          ..setTextFormat(TextFormat.bold.bit)
          ..setTextStyle('color: red');
        $getRoot().append(paragraph);
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      expect(paragraph['textFormat'], 1);
      expect(paragraph['textStyle'], 'color: red');
    });
  });
}
