import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _richText() {
  final editor = LexicalEditor();
  registerRichText(editor);
  return editor;
}

void _seed(LexicalEditor editor, List<String> paragraphs) {
  editor.update(() {
    final root = $getRoot()..clear();
    for (final text in paragraphs) {
      root.append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
}

List<String> _blocks(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

/// A paragraph of `cc `, an atomic `@Rebar` token, and ` bitte`.
void _seedWithToken(LexicalEditor editor) {
  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('cc '))
          ..append($createTextNode('@Rebar')..setMode(TextMode.token))
          ..append($createTextNode(' bitte')),
      );
  }, discrete: true);
}

/// An inline element that does or does not take text at its edge — a link,
/// stripped down to the one property this file is about.
class _InlineWrapNode extends ElementNode {
  _InlineWrapNode({this.sealed = true});

  final bool sealed;

  @override
  String get type => 'inline-wrap';

  @override
  bool get isInline => true;

  @override
  bool get canInsertTextBefore => !sealed;

  @override
  bool get canInsertTextAfter => !sealed;

  @override
  _InlineWrapNode clone() => _InlineWrapNode(sealed: sealed);
}

/// A block-level decorator — a divider, in every editor that has one.
class _RuleNode extends DecoratorNode {
  @override
  String get type => 'rule';

  @override
  bool get isInline => false;

  @override
  _RuleNode clone() => _RuleNode();
}

/// A paragraph of `die `, an inline element wrapping `Doku`, and [tail].
LexicalEditor _sealedInline({bool sealed = true, String tail = ''}) {
  final editor = LexicalEditor(
    nodes: [
      NodeSpec<_InlineWrapNode>(
        type: 'inline-wrap',
        create: _InlineWrapNode.new,
      ),
      NodeSpec<_RuleNode>(type: 'rule', create: _RuleNode.new),
    ],
  );
  registerRichText(editor);
  editor.update(() {
    final paragraph = $createParagraphNode()
      ..append($createTextNode('die '))
      ..append(
        _InlineWrapNode(sealed: sealed)..append($createTextNode('Doku')),
      );
    if (tail.isNotEmpty) paragraph.append($createTextNode(tail));
    $getRoot()
      ..clear()
      ..append(paragraph);
  }, discrete: true);
  return editor;
}

/// A collapsed caret at [offset] inside the inline element's own text.
void _selectSealed(LexicalEditor editor, int offset) {
  editor.update(() {
    final paragraph = $getRoot().getFirstChild()! as ElementNode;
    final inside =
        (paragraph.getLastChild()! as ElementNode).getFirstChild()! as TextNode;
    $setSelection(
      RangeSelection(
        Point(inside.key, offset, PointType.text),
        Point(inside.key, offset, PointType.text),
      ),
    );
  }, discrete: true);
}

/// A collapsed caret in the text node at [index] of the first paragraph.
void _selectSibling(LexicalEditor editor, int index, int offset) {
  editor.update(() {
    final paragraph = $getRoot().getFirstChild()! as ElementNode;
    final text = paragraph.getChildAtIndex(index)! as TextNode;
    $setSelection(
      RangeSelection(
        Point(text.key, offset, PointType.text),
        Point(text.key, offset, PointType.text),
      ),
    );
  }, discrete: true);
}

/// The first paragraph's shape, with the inline element's text in `<>`.
String _shape(LexicalEditor editor) => editor.read(() {
  final buffer = StringBuffer();
  for (final child in ($getRoot().getFirstChild()! as ElementNode).children) {
    if (child is _InlineWrapNode) {
      buffer.write('<${child.getTextContent()}>');
    } else {
      buffer.write(child.getTextContent());
    }
  }
  return buffer.toString();
});

/// Puts a collapsed caret, or a range, into the text of block [block].
void _select(
  LexicalEditor editor,
  int block,
  int offset, {
  int? toBlock,
  int? toOffset,
}) {
  editor.update(() {
    final root = $getRoot();
    final from = root.getChildAtIndex(block)! as ElementNode;
    final fromText = from.getFirstChild()! as TextNode;
    final to = root.getChildAtIndex(toBlock ?? block)! as ElementNode;
    final toText = to.getFirstChild()! as TextNode;
    $setSelection(
      RangeSelection(
        Point(fromText.key, offset, PointType.text),
        Point(toText.key, toOffset ?? offset, PointType.text),
      ),
    );
  }, discrete: true);
}

({String key, int offset}) _caret(LexicalEditor editor) => editor.read(() {
  final selection = $getSelection()! as RangeSelection;
  return (key: selection.focus.key.value, offset: selection.focus.offset);
});

String _caretText(LexicalEditor editor) => editor.read(() {
  final selection = $getSelection()! as RangeSelection;
  return selection.focus.getNode()?.getTextContent() ?? '';
});

void main() {
  group('insertText', () {
    test('types into an existing run', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 5);
      editor.dispatchCommand(insertTextCommand, ',');
      expect(_blocks(editor), ['Hallo, Welt']);
      expect(_caret(editor).offset, 6);
    });

    test('replaces a range inside one run as a single operation', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 6, toOffset: 10);
      editor.dispatchCommand(replaceTextCommand, 'Hinata');
      expect(_blocks(editor), ['Hallo Hinata']);
    });

    test('replaces a range spanning several runs in one block', () {
      final editor = _richText();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('eins '))
              ..append($createTextNode('zwei ')..setFormat(TextFormat.bold.bit))
              ..append($createTextNode('drei')),
          );
      }, discrete: true);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final first = paragraph.getChildAtIndex(0)! as TextNode;
        final last = paragraph.getChildAtIndex(2)! as TextNode;
        $setSelection(
          RangeSelection(
            Point(first.key, 2, PointType.text),
            Point(last.key, 2, PointType.text),
          ),
        );
      }, discrete: true);

      editor.dispatchCommand(insertTextCommand, 'X');
      expect(_blocks(editor), ['eiXei']);
    });

    test('replaces a range spanning blocks and merges them', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt', 'Zweiter Absatz', 'Dritter']);
      _select(editor, 0, 6, toBlock: 2, toOffset: 4);
      editor.dispatchCommand(insertTextCommand, '— ');
      expect(_blocks(editor), ['Hallo — ter']);
    });

    test('a backwards selection deletes the same range', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      // Focus before anchor: a drag from right to left.
      _select(editor, 0, 10, toOffset: 6);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final text = paragraph.getFirstChild()! as TextNode;
        $setSelection(
          RangeSelection(
            Point(text.key, 10, PointType.text),
            Point(text.key, 6, PointType.text),
          ),
        );
      }, discrete: true);
      editor.dispatchCommand(removeTextCommand, null);
      expect(_blocks(editor), ['Hallo ']);
    });

    test('at an inline element that refuses text, writes beside it', () {
      // What `canInsertTextBefore`/`canInsertTextAfter` are for. A link's text
      // is its label, so a character typed against either end is new text next
      // to the link — not a silent extension of what the anchor covers.
      for (final atEnd in [false, true]) {
        final editor = _sealedInline();
        _selectSealed(editor, atEnd ? 4 : 0);
        editor.dispatchCommand(insertTextCommand, 'X');
        expect(_shape(editor), atEnd ? 'die <Doku>X' : 'die X<Doku>');

        // The caret came along, so the next keystroke continues the new run
        // instead of dropping back inside the element.
        editor.dispatchCommand(insertTextCommand, 'Y');
        expect(_shape(editor), atEnd ? 'die <Doku>XY' : 'die XY<Doku>');
      }
    });

    test('inside the element it is ordinary text', () {
      // The rule is about the element's outer edge only; between two of its
      // own letters the character is plainly part of the label.
      final editor = _sealedInline();
      _selectSealed(editor, 2);
      editor.dispatchCommand(insertTextCommand, 'X');
      expect(_shape(editor), 'die <DoXku>');
    });

    test('an inline element that accepts text keeps it', () {
      final editor = _sealedInline(sealed: false);
      _selectSealed(editor, 0);
      editor.dispatchCommand(insertTextCommand, 'X');
      expect(_shape(editor), 'die <XDoku>');
    });

    test('the run beside it merges with the text already there', () {
      // Normalization does this, which is why escaping the element may create
      // a fresh run without fragmenting the document.
      final editor = _sealedInline();
      _selectSealed(editor, 0);
      editor.dispatchCommand(insertTextCommand, 'X');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).childrenSize,
        ),
        2,
      );
      expect(_blocks(editor), ['die XDoku']);
    });

    test('newlines are inserted verbatim', () {
      // Text nodes may contain newlines — the canonical code-block fixture
      // does. Turning them into blocks is the clipboard layer's job, not this
      // one's; Enter arrives as insertParagraphCommand.
      final editor = _richText();
      _seed(editor, ['a']);
      _select(editor, 0, 1);
      editor.dispatchCommand(insertTextCommand, '\nb');
      expect(_blocks(editor), ['a\nb']);
    });
  });

  group('deleteCharacter', () {
    test('removes one character backwards', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 5);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['Hall']);
      expect(_caret(editor).offset, 4);
    });

    test('removes one character forwards', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0);
      editor.dispatchCommand(deleteCharacterCommand, false);
      expect(_blocks(editor), ['allo']);
    });

    test('deletes an emoji as one press, not four', () {
      // The whole reason movement is by grapheme cluster. A skin-toned emoji
      // is several code units; removing one leaves a broken pair on screen.
      const emoji = '\u{1F44B}\u{1F3FC}';
      final editor = _richText();
      _seed(editor, ['hi $emoji']);
      _select(editor, 0, 'hi $emoji'.length);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['hi ']);
    });

    test('merges with the previous block at its start', () {
      final editor = _richText();
      _seed(editor, ['Erster', 'Zweiter']);
      _select(editor, 1, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['ErsterZweiter']);
      // The caret sits at the junction, so typing continues where the user
      // was rather than jumping to an end.
      expect(_caret(editor).offset, 6);
    });

    test('merges with the next block at its end', () {
      final editor = _richText();
      _seed(editor, ['Erster', 'Zweiter']);
      _select(editor, 0, 6);
      editor.dispatchCommand(deleteCharacterCommand, false);
      expect(_blocks(editor), ['ErsterZweiter']);
    });

    test('does nothing at the very start of the document', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['Hallo']);
    });

    test('backspace at the end of a token removes all of it', () {
      // A mention is a token: editing it character by character would leave a
      // label that no longer matches the entity it names.
      final editor = _richText();
      _seedWithToken(editor);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getChildAtIndex(1)! as TextNode).selectEnd();
      }, discrete: true);

      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['cc  bitte']);
    });

    test('backspace just after a token removes all of it', () {
      final editor = _richText();
      _seedWithToken(editor);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getChildAtIndex(2)! as TextNode).selectStart();
      }, discrete: true);

      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['cc  bitte']);
    });

    test('backspace just before a token leaves it alone', () {
      // The character before the token goes, not the token: the caret was
      // not on it.
      final editor = _richText();
      _seedWithToken(editor);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getChildAtIndex(1)! as TextNode).selectStart();
      }, discrete: true);

      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['cc@Rebar bitte']);
    });

    test('forward delete at the start of a token removes all of it', () {
      final editor = _richText();
      _seedWithToken(editor);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getChildAtIndex(1)! as TextNode).selectStart();
      }, discrete: true);

      editor.dispatchCommand(deleteCharacterCommand, false);
      expect(_blocks(editor), ['cc  bitte']);
    });
  });

  group('crossing an inline element', () {
    // Its outer edge and the position beside it are one place on screen, so a
    // keypress that only crosses that edge appears to do nothing at all.
    test('backspace after one deletes its last character', () {
      final editor = _sealedInline(sealed: false, tail: ' dazu');
      _selectSibling(editor, 2, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_shape(editor), 'die <Dok> dazu');
    });

    test('forward delete before one deletes its first character', () {
      final editor = _sealedInline(sealed: false, tail: ' dazu');
      _selectSibling(editor, 0, 4);
      editor.dispatchCommand(deleteCharacterCommand, false);
      expect(_shape(editor), 'die <oku> dazu');
    });

    test('an arrow steps into it rather than over it', () {
      final editor = _sealedInline(sealed: false, tail: ' dazu');
      _selectSibling(editor, 0, 4);
      editor.update(() {
        expect(
          ($getSelection()! as RangeSelection).moveCaret(backwards: false),
          isTrue,
        );
      }, discrete: true);
      expect(_caretText(editor), 'Doku');
      expect(_caret(editor).offset, 1);
    });

    test('the whole element is not skipped in one press', () {
      // Reaching the element's own text is the only way its last character can
      // ever be deleted.
      final editor = _sealedInline(sealed: false, tail: ' dazu');
      _selectSibling(editor, 2, 0);
      editor.update(() {
        ($getSelection()! as RangeSelection).moveCaret(backwards: true);
      }, discrete: true);
      expect(_caretText(editor), 'Doku');
      expect(_caret(editor).offset, 3);
    });
  });

  group('block decorators', () {
    LexicalEditor divided() {
      final editor = _sealedInline();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('davor')))
          ..append(_RuleNode())
          ..append($createParagraphNode()..append($createTextNode('danach')));
      }, discrete: true);
      return editor;
    }

    List<String> types(LexicalEditor editor) =>
        editor.read(() => $getRoot().children.map((n) => n.type).toList());

    test('backspace under one removes it', () {
      // It holds no text, so there is no character to delete and without this
      // the key does nothing: a divider could be inserted and never removed.
      final editor = divided();
      _select(editor, 2, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(types(editor), ['paragraph', 'paragraph']);
      expect(_blocks(editor), ['davor', 'danach']);
    });

    test('forward delete above one removes it', () {
      final editor = divided();
      _select(editor, 0, 5);
      editor.dispatchCommand(deleteCharacterCommand, false);
      expect(types(editor), ['paragraph', 'paragraph']);
    });

    test('an arrow steps across it', () {
      final editor = divided();
      _select(editor, 0, 5);
      editor.update(() {
        ($getSelection()! as RangeSelection).moveCaret(backwards: false);
      }, discrete: true);
      expect(types(editor), ['paragraph', 'rule', 'paragraph']);
      expect(_caretText(editor), 'danach');
    });
  });

  group('collapsing at the start', () {
    test('an empty first line goes, and the caret moves on', () {
      final editor = _richText();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode())
          ..append($createParagraphNode()..append($createTextNode('Text')));
      }, discrete: true);
      editor.update(() {
        ($getRoot().getFirstChild()! as ElementNode).select(0, 0);
      }, discrete: true);
      editor.dispatchCommand(deleteCharacterCommand, true);

      expect(_blocks(editor), ['Text']);
      expect(_caretText(editor), 'Text');
    });

    test('a first line with words in it stays', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_blocks(editor), ['Hallo']);
    });
  });

  group('segmented runs', () {
    LexicalEditor place() {
      final editor = _richText();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()..append(
              $createTextNode('New York')..setMode(TextMode.segmented),
            ),
          );
      }, discrete: true);
      return editor;
    }

    TextMode modeOf(LexicalEditor editor) => editor.read(
      () =>
          (($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                  as TextNode)
              .getMode(),
    );

    test('typing inside one makes it ordinary text', () {
      // It was completed as a unit; from the moment it is edited by hand,
      // deleting a whole word at a time is no longer what its content means.
      final editor = place();
      _select(editor, 0, 3);
      editor.dispatchCommand(insertTextCommand, 'X');

      expect(_blocks(editor), ['NewX York']);
      expect(modeOf(editor), TextMode.normal);
    });

    test('typing at its end leaves it as it was', () {
      final editor = place();
      _select(editor, 0, 8);
      editor.dispatchCommand(insertTextCommand, '!');

      expect(_blocks(editor), ['New York!']);
      expect(modeOf(editor), TextMode.segmented);
    });

    test('backspace still takes a whole segment', () {
      final editor = place();
      _select(editor, 0, 8);
      editor.dispatchCommand(deleteCharacterCommand, true);

      expect(_blocks(editor), ['New ']);
      expect(modeOf(editor), TextMode.segmented);
    });
  });

  group('deleteWord', () {
    test('removes the preceding word', () {
      final editor = _richText();
      _seed(editor, ['Hallo schöne Welt']);
      _select(editor, 0, 17);
      editor.dispatchCommand(deleteWordCommand, true);
      expect(_blocks(editor), ['Hallo schöne ']);
    });

    test('removes the following word', () {
      final editor = _richText();
      _seed(editor, ['Hallo schöne Welt']);
      _select(editor, 0, 0);
      editor.dispatchCommand(deleteWordCommand, false);
      expect(_blocks(editor), [' schöne Welt']);
    });
  });

  group('deleteLine', () {
    test('removes to the start of the block', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt', 'Zweiter']);
      _select(editor, 1, 4);
      editor.dispatchCommand(deleteLineCommand, true);
      expect(_blocks(editor), ['Hallo Welt', 'ter']);
    });
  });

  group('insertParagraph', () {
    test('splits a block at the caret', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 5);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_blocks(editor), ['Hallo', ' Welt']);
      expect(_caretText(editor), ' Welt');
    });

    test('at the end starts an empty block', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 5);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_blocks(editor), ['Hallo', '']);
      editor.dispatchCommand(insertTextCommand, 'Welt');
      expect(_blocks(editor), ['Hallo', 'Welt']);
    });

    test('at the start leaves an empty block above', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_blocks(editor), ['', 'Hallo']);
    });

    test('replaces the selection first', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 5, toOffset: 10);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_blocks(editor), ['Hallo', '']);
    });

    test('plain text inserts a line break instead', () {
      final editor = LexicalEditor();
      registerPlainText(editor);
      _seed(editor, ['Hallo']);
      _select(editor, 0, 5);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(editor.read(() => $getRoot().childrenSize), 1);
      expect(_blocks(editor), ['Hallo\n']);
    });
  });

  group('insertNodes', () {
    test('splices inline nodes into the run at the caret', () {
      final editor = _richText();
      _seed(editor, ['cc  bitte']);
      _select(editor, 0, 3);
      editor.update(() {
        final selection = $getSelection()! as RangeSelection;
        selection.insertNodes([
          $createTextNode('@Rebar')..setMode(TextMode.token),
        ]);
      }, discrete: true);
      expect(_blocks(editor), ['cc @Rebar bitte']);
      // The caret lands after the inserted token, which is what lets the next
      // keystroke continue the sentence.
      expect(_caretText(editor), '@Rebar');
      expect(_caret(editor).offset, 6);
    });

    test('a token stays its own node rather than merging', () {
      final editor = _richText();
      _seed(editor, ['cc ']);
      _select(editor, 0, 3);
      editor.update(() {
        final selection = $getSelection()! as RangeSelection;
        selection.insertNodes([
          $createTextNode('@Rebar')..setMode(TextMode.token),
        ]);
      }, discrete: true);
      editor.dispatchCommand(insertTextCommand, ' bitte');
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).childrenSize,
        ),
        3,
      );
      expect(_blocks(editor), ['cc @Rebar bitte']);
    });

    test('block nodes split the current block', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 5);
      editor.update(() {
        final selection = $getSelection()! as RangeSelection;
        selection.insertNodes([
          $createParagraphNode()..append($createTextNode('MITTE')),
        ]);
      }, discrete: true);
      expect(_blocks(editor), ['Hallo', 'MITTE', ' Welt']);
    });
  });

  group('formatText', () {
    test('a collapsed caret records a pending format', () {
      final editor = _richText();
      _seed(editor, ['Hallo ']);
      _select(editor, 0, 6);
      editor.dispatchCommand(formatTextCommand, TextFormat.bold);
      editor.dispatchCommand(insertTextCommand, 'fett');
      final formats = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => node.getFormat())
            .toList(),
      );
      expect(formats, [0, TextFormat.bold.bit]);
    });

    test('a range splits the run and formats exactly it', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt']);
      _select(editor, 0, 6, toOffset: 10);
      editor.dispatchCommand(formatTextCommand, TextFormat.italic);
      final runs = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => (node.getTextContent(), node.getFormat()))
            .toList(),
      );
      expect(runs, [('Hallo ', 0), ('Welt', TextFormat.italic.bit)]);
    });

    test('formatting an already formatted range removes it', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0, toOffset: 5);
      editor
        ..dispatchCommand(formatTextCommand, TextFormat.bold)
        ..dispatchCommand(formatTextCommand, TextFormat.bold);
      final formats = editor.read(
        () => ($getRoot().getFirstChild()! as ElementNode).children
            .whereType<TextNode>()
            .map((node) => node.getFormat())
            .toList(),
      );
      expect(formats, [0]);
    });

    test('formats across blocks', () {
      final editor = _richText();
      _seed(editor, ['Erster', 'Zweiter']);
      _select(editor, 0, 2, toBlock: 1, toOffset: 3);
      editor.dispatchCommand(formatTextCommand, TextFormat.bold);
      final runs = editor.read(
        () => $getRoot().children
            .cast<ElementNode>()
            .expand(
              (block) => block.children.whereType<TextNode>().map(
                (node) => (node.getTextContent(), node.getFormat()),
              ),
            )
            .toList(),
      );
      expect(runs, [
        ('Er', 0),
        ('ster', TextFormat.bold.bit),
        ('Zwe', TextFormat.bold.bit),
        ('iter', 0),
      ]);
    });
  });

  group('blocks', () {
    test('indent and outdent stay within bounds', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 0);
      for (var i = 0; i < maxIndent + 3; i++) {
        editor.dispatchCommand(indentContentCommand, null);
      }
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).getIndent(),
        ),
        maxIndent,
      );
      for (var i = 0; i < maxIndent + 3; i++) {
        editor.dispatchCommand(outdentContentCommand, null);
      }
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).getIndent(),
        ),
        0,
      );
    });

    test('alignment applies to every touched block', () {
      final editor = _richText();
      _seed(editor, ['Erster', 'Zweiter']);
      _select(editor, 0, 1, toBlock: 1, toOffset: 1);
      editor.dispatchCommand(formatElementCommand, ElementFormat.center);
      expect(
        editor.read(
          () => $getRoot().children
              .cast<ElementNode>()
              .map((block) => block.getFormat())
              .toList(),
        ),
        [ElementFormat.center, ElementFormat.center],
      );
    });
  });

  group('document invariants', () {
    test('the document is never left without a block', () {
      final editor = _richText();
      _seed(editor, ['Hallo', 'Welt']);
      editor.dispatchCommand(clearEditorCommand, null);
      expect(editor.read(() => $getRoot().childrenSize), 1);
      expect(_blocks(editor), ['']);
      // And the caret has somewhere to go.
      editor.dispatchCommand(insertTextCommand, 'neu');
      expect(_blocks(editor), ['neu']);
    });

    test('removing every block restores a paragraph', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      editor.update(() {
        $getRoot().clear();
      }, discrete: true);
      expect(editor.read(() => $getRoot().childrenSize), 1);
    });

    test('select all then delete leaves an empty editable document', () {
      final editor = _richText();
      _seed(editor, ['Erster', 'Zweiter', 'Dritter']);
      editor
        ..dispatchCommand(selectAllCommand, null)
        ..dispatchCommand(removeTextCommand, null);
      expect(_blocks(editor), ['']);
      editor.dispatchCommand(insertTextCommand, 'neu');
      expect(_blocks(editor), ['neu']);
    });

    test('an edited document still round-trips', () {
      final editor = _richText();
      _seed(editor, ['Hallo Welt', 'Zweiter']);
      _select(editor, 0, 5);
      editor
        ..dispatchCommand(insertTextCommand, ',')
        ..dispatchCommand(insertParagraphCommand, null)
        ..dispatchCommand(formatTextCommand, TextFormat.bold)
        ..dispatchCommand(insertTextCommand, 'fett');
      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });
  });

  group('overriding', () {
    test('a higher-priority handler wins', () {
      final editor = _richText();
      _seed(editor, ['Hallo']);
      _select(editor, 0, 5);
      var seen = '';
      final unsubscribe = editor.registerCommand<String>(insertTextCommand, (
        text,
      ) {
        seen = text;
        return true;
      }, CommandPriority.beforeEditor);
      editor.dispatchCommand(insertTextCommand, 'X');
      expect(seen, 'X');
      expect(_blocks(editor), ['Hallo']);
      unsubscribe();
      editor.dispatchCommand(insertTextCommand, 'Y');
      expect(_blocks(editor), ['HalloY']);
    });

    test('unregistering removes every handler it installed', () {
      final editor = LexicalEditor();
      final unsubscribe = registerRichText(editor);
      _seed(editor, ['Hallo']);
      _select(editor, 0, 5);
      unsubscribe();
      expect(editor.dispatchCommand(insertTextCommand, 'X'), isFalse);
      expect(_blocks(editor), ['Hallo']);
    });
  });
}
