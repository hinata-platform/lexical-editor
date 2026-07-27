// Editing where two packages meet.
//
// Each package tests its own nodes, and each of those tests passes while the
// editor is still awkward to use, because the awkward cases live between
// packages: a caret against a link, a divider between two paragraphs, a list
// that starts the document. This file drives the real bundle — every node type
// registered, every behaviour registered — over exactly those seams.
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: lexicalNodes);
  registerRichText(editor);
  registerList(editor);
  registerLink(editor);
  return editor;
}

/// The document as `type:text` per top-level block, links in brackets.
List<String> _outline(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((block) {
    if (block is! ElementNode) return block.type;
    final buffer = StringBuffer('${block.type}:');
    for (final child in block.children) {
      if (child is LinkNode) {
        buffer.write('[${child.getTextContent()}]');
      } else if (child is DecoratorNode) {
        buffer.write('<${child.type}>');
      } else {
        buffer.write(child.getTextContent());
      }
    }
    return buffer.toString();
  }).toList(),
);

void _run(LexicalEditor editor, void Function() body) =>
    editor.update(body, discrete: true);

RangeSelection _selection() => $getSelection()! as RangeSelection;

void main() {
  group('a link and the text around it', () {
    LexicalEditor linked() {
      final editor = _editor();
      _run(editor, () {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('die '))
              ..append(
                LinkNode('https://x.test')..append($createTextNode('Doku')),
              )
              ..append($createTextNode(' dazu')),
          );
      });
      return editor;
    }

    void caretInLink(LexicalEditor editor, int offset) => _run(editor, () {
      final link = ($getRoot().getFirstChild()! as ElementNode).children
          .whereType<LinkNode>()
          .single;
      (link.getFirstChild()! as TextNode).select(offset, offset);
    });

    test('typing in front of it writes in front of it', () {
      final editor = linked();
      caretInLink(editor, 0);
      editor.dispatchCommand(insertTextCommand, 'X');
      expect(_outline(editor), ['paragraph:die X[Doku] dazu']);
    });

    test('backspace from just behind it takes one character of it', () {
      final editor = linked();
      _run(editor, () {
        final block = $getRoot().getFirstChild()! as ElementNode;
        (block.getLastChild()! as TextNode).select(0, 0);
      });
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_outline(editor), ['paragraph:die [Dok] dazu']);
    });

    test('Enter in the middle of it leaves two links, not one torn one', () {
      final editor = linked();
      caretInLink(editor, 2);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_outline(editor), ['paragraph:die [Do]', 'paragraph:[ku] dazu']);
    });
  });

  group('a divider between two paragraphs', () {
    LexicalEditor divided() {
      final editor = _editor();
      _run(editor, () {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('davor')))
          ..append($createHorizontalRuleNode())
          ..append($createParagraphNode()..append($createTextNode('danach')));
      });
      return editor;
    }

    test('backspace under it removes it', () {
      final editor = divided();
      _run(editor, () {
        final block = $getRoot().getLastChild()! as ElementNode;
        (block.getFirstChild()! as TextNode).select(0, 0);
      });
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_outline(editor), ['paragraph:davor', 'paragraph:danach']);
    });

    test('an arrow steps across it instead of stopping at it', () {
      final editor = divided();
      _run(editor, () {
        final block = $getRoot().getFirstChild()! as ElementNode;
        (block.getFirstChild()! as TextNode).select(5, 5);
        expect(_selection().moveCaret(backwards: false), isTrue);
      });
      expect(_outline(editor), [
        'paragraph:davor',
        'horizontalrule',
        'paragraph:danach',
      ]);
      expect(
        editor.read(() => _selection().focus.getNode()?.getTextContent()),
        'danach',
      );
    });
  });

  group('a list at the top of the document', () {
    test('backspace in its first item is the way out of it', () {
      final editor = _editor();
      _run(editor, () {
        $getRoot()
          ..clear()
          ..append(
            $createListNode(ListType.bullet)
              ..append($createListItemNode()..append($createTextNode('eins')))
              ..append($createListItemNode()..append($createTextNode('zwei'))),
          );
      });
      _run(editor, () {
        final list = $getRoot().getFirstChild()! as ElementNode;
        final item = list.getFirstChild()! as ElementNode;
        (item.getFirstChild()! as TextNode).select(0, 0);
      });
      editor.dispatchCommand(deleteCharacterCommand, true);

      expect(_outline(editor).first, 'paragraph:eins');
    });
  });

  group('an image inside a paragraph', () {
    test('backspace behind it removes the image, not the line', () {
      final editor = _editor();
      _run(editor, () {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append(ImageNode(src: 'a.png'))
              ..append($createTextNode('Bildtext')),
          );
      });
      _run(editor, () {
        final block = $getRoot().getFirstChild()! as ElementNode;
        (block.getLastChild()! as TextNode).select(0, 0);
      });
      editor.dispatchCommand(deleteCharacterCommand, true);

      expect(_outline(editor), ['paragraph:Bildtext']);
    });
  });
}
