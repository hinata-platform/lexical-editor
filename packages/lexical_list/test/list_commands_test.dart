import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:test/test.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: listNodes);
  registerRichText(editor);
  registerList(editor);
  return editor;
}

void _seed(LexicalEditor editor, List<String> items, {ListType? type}) {
  editor.update(() {
    final list = $createListNode(type ?? ListType.bullet);
    for (final text in items) {
      list.append($createListItemNode()..append($createTextNode(text)));
    }
    $getRoot()
      ..clear()
      ..append(list);
  }, discrete: true);
}

void _caretAtItem(LexicalEditor editor, int index, {int offset = 0}) {
  editor.update(() {
    final list = $getRoot().getFirstChild()! as ListNode;
    final item = list.getChildAtIndex(index)! as ListItemNode;
    final text = item.getFirstChild();
    if (text is TextNode) {
      text.select(offset, offset);
    } else {
      item.selectStart();
    }
  }, discrete: true);
}

/// The document as `type:text` pairs, one per top-level block.
List<String> _outline(LexicalEditor editor) => editor.read(
  () => $getRoot().children
      .map((node) => '${node.type}:${node.getTextContent()}')
      .toList(),
);

void main() {
  test('Enter in the middle of an item continues the list', () {
    final editor = _editor();
    _seed(editor, ['eins', 'zwei']);
    _caretAtItem(editor, 0, offset: 2);
    editor.dispatchCommand(insertParagraphCommand, null);
    expect(
      editor.read(() => ($getRoot().getFirstChild()! as ListNode).childrenSize),
      3,
    );
  });

  test('Enter on an empty item at the end leaves the list', () {
    final editor = _editor();
    _seed(editor, ['eins']);
    _caretAtItem(editor, 0, offset: 4);
    // First Enter adds an item; the second — on the now-empty item — is the
    // one that has to get the user out.
    editor
      ..dispatchCommand(insertParagraphCommand, null)
      ..dispatchCommand(insertParagraphCommand, null);
    expect(_outline(editor), ['list:eins', 'paragraph:']);
  });

  test('Enter on an empty item in the middle splits the list', () {
    final editor = _editor();
    _seed(editor, ['eins', '', 'drei']);
    _caretAtItem(editor, 1);
    editor.dispatchCommand(insertParagraphCommand, null);
    expect(_outline(editor), ['list:eins', 'paragraph:', 'list:drei']);
  });

  test('Enter on an empty nested item un-nests one level', () {
    final editor = _editor();
    _seed(editor, ['eins', 'zwei']);
    _caretAtItem(editor, 1);
    editor.dispatchCommand(indentContentCommand, null);
    // "zwei" is now nested inside "eins".
    expect(
      editor.read(() => ($getRoot().getFirstChild()! as ListNode).childrenSize),
      1,
    );

    editor.update(() {
      final outer = $getRoot().getFirstChild()! as ListNode;
      final holder = outer.getFirstChild()! as ListItemNode;
      final nested = holder.getLastChild()! as ListNode;
      final item = nested.getFirstChild()! as ListItemNode;
      (item.getFirstChild()! as TextNode).select(0, 4);
    }, discrete: true);
    editor
      ..dispatchCommand(removeTextCommand, null)
      ..dispatchCommand(insertParagraphCommand, null);

    expect(
      editor.read(() => ($getRoot().getFirstChild()! as ListNode).childrenSize),
      2,
    );
  });

  test('Tab nests an item under the one above it', () {
    final editor = _editor();
    _seed(editor, ['eins', 'zwei']);
    _caretAtItem(editor, 1);
    editor.dispatchCommand(indentContentCommand, null);

    editor.read(() {
      final outer = $getRoot().getFirstChild()! as ListNode;
      expect(outer.childrenSize, 1);
      final holder = outer.getFirstChild()! as ListItemNode;
      expect(holder.getLastChild(), isA<ListNode>());
      expect(holder.getTextContent(), 'einszwei');
    });
  });

  test('Shift-Tab promotes it back', () {
    final editor = _editor();
    _seed(editor, ['eins', 'zwei']);
    _caretAtItem(editor, 1);
    editor
      ..dispatchCommand(indentContentCommand, null)
      ..dispatchCommand(outdentContentCommand, null);
    expect(
      editor.read(() => ($getRoot().getFirstChild()! as ListNode).childrenSize),
      2,
    );
  });

  test('a new check-list item starts unticked', () {
    final editor = _editor();
    _seed(editor, ['erledigt'], type: ListType.check);
    editor.update(() {
      final list = $getRoot().getFirstChild()! as ListNode;
      (list.getFirstChild()! as ListItemNode).setChecked(true);
    }, discrete: true);
    _caretAtItem(editor, 0, offset: 8);
    editor.dispatchCommand(insertParagraphCommand, null);

    editor.read(() {
      final list = $getRoot().getFirstChild()! as ListNode;
      expect((list.getChildAtIndex(0)! as ListItemNode).checked, isTrue);
      expect((list.getChildAtIndex(1)! as ListItemNode).checked, isFalse);
    });
  });

  test('numbering follows the new item', () {
    final editor = _editor();
    _seed(editor, ['eins', 'zwei'], type: ListType.number);
    _caretAtItem(editor, 0, offset: 4);
    editor.dispatchCommand(insertParagraphCommand, null);
    expect(
      editor.read(
        () => ($getRoot().getFirstChild()! as ListNode).children
            .cast<ListItemNode>()
            .map((item) => item.value)
            .toList(),
      ),
      [1, 2, 3],
    );
  });
}
