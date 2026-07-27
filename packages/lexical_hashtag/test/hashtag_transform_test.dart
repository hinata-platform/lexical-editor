import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';
import 'package:test/test.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: hashtagNodes);
  registerHashtag(editor);
  return editor;
}

/// The document as `type:text` pairs, which is what a tag being found or not
/// actually looks like.
List<String> _runs(LexicalEditor editor) => editor.read(
  () => [
    for (final block in $getRoot().children.whereType<ElementNode>())
      for (final child in block.children)
        '${child.type}:${child.getTextContent()}',
  ],
);

void _write(LexicalEditor editor, String text) {
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode(text)));
  }, discrete: true);
}

void main() {
  group('finding one', () {
    test('a tag on its own becomes a hashtag', () {
      final editor = _editor();
      _write(editor, '#flutter');
      expect(_runs(editor), ['hashtag:#flutter']);
    });

    test('a tag inside a sentence keeps the text around it', () {
      final editor = _editor();
      _write(editor, 'siehe #flutter dazu');
      expect(_runs(editor), ['text:siehe ', 'hashtag:#flutter', 'text: dazu']);
    });

    test('letters outside ASCII count', () {
      final editor = _editor();
      _write(editor, '#Grüße und #مرحبا');
      expect(_runs(editor), ['hashtag:#Grüße', 'text: und ', 'hashtag:#مرحبا']);
    });

    test('a hash that does not start a word is not a tag', () {
      // Otherwise every URL fragment and every `a#b` would become one.
      for (final line in ['a#b', 'https://x.dev/page#top', '##', '# ']) {
        final editor = _editor();
        _write(editor, line);
        expect(
          _runs(editor).where((run) => run.startsWith('hashtag')),
          isEmpty,
          reason: line,
        );
      }
    });

    test('code is left alone', () {
      // `#include` is not a tag, and a code block is where that is decided.
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(_FakeCode()..append($createTextNode('#include <stdio.h>')));
      }, discrete: true);
      expect(_runs(editor), ['text:#include <stdio.h>']);
    });
  });

  group('losing one', () {
    test('deleting the hash turns it back into text', () {
      final editor = _editor();
      _write(editor, '#flutter');
      expect(_runs(editor), ['hashtag:#flutter']);

      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final tag = block.getFirstChild()! as TextNode;
        tag.setTextContent('flutter');
      }, discrete: true);

      expect(_runs(editor), ['text:flutter']);
    });

    test('typing a space after a tag splits it, keeping the tag', () {
      final editor = _editor();
      _write(editor, '#flutter');
      editor.update(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        final tag = block.getFirstChild()! as TextNode;
        tag.setTextContent('#flutter ist gut');
      }, discrete: true);

      expect(_runs(editor), ['hashtag:#flutter', 'text: ist gut']);
    });
  });

  group('typed one character at a time', () {
    /// Typing goes through the editing commands, so this editor has them.
    LexicalEditor typing() {
      final editor = LexicalEditor(nodes: hashtagNodes);
      registerRichText(editor);
      registerHashtag(editor);
      return editor;
    }

    // The way a tag is actually written, and the case a whole-line test cannot
    // see: the transform replaces the run *under the caret*, so the caret has
    // to survive that and stay in the tag. It did not, and everything typed
    // after the first letter went into the text before the tag instead.
    test('grows with each keystroke, and the caret stays in it', () {
      final editor = typing();
      _write(editor, 'los ');
      editor.update(() {
        (($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode)
            .select(4, 4);
      }, discrete: true);

      for (final char in ['#', 'f', 'l', 'u']) {
        editor.dispatchCommand(insertTextCommand, char);
      }
      expect(_runs(editor), ['text:los ', 'hashtag:#flu']);

      final caret = editor.read(() {
        final selection = $getSelection()! as RangeSelection;
        return (
          text: selection.anchor.getNode()!.getTextContent(),
          offset: selection.anchor.offset,
        );
      });
      expect(caret.text, '#flu');
      expect(caret.offset, 4);
    });

    test('a space ends the tag and the text after it is ordinary', () {
      final editor = typing();
      _write(editor, 'los ');
      editor.update(() {
        (($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode)
            .select(4, 4);
      }, discrete: true);

      for (final char in ['#', 'a', 'b', ' ', 'c']) {
        editor.dispatchCommand(insertTextCommand, char);
      }
      expect(_runs(editor), ['text:los ', 'hashtag:#ab', 'text: c']);
    });
  });

  test('a document with hashtags still round-trips', () {
    final editor = _editor();
    _write(editor, 'siehe #flutter');
    final json = editor.editorState.toJson();

    final reopened = LexicalEditor(nodes: hashtagNodes);
    reopened.setEditorState(reopened.parseEditorState(json));
    expect(reopened.editorState.toJson(), json);
  });
}

/// Stands in for a `CodeNode` without depending on `lexical_code`.
class _FakeCode extends ElementNode {
  @override
  String get type => 'code';

  @override
  _FakeCode clone() => _FakeCode();
}
