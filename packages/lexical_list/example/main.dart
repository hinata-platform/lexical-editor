// Run it with:  dart run example/main.dart
//
// Lists, and the two behaviours that make them usable: Enter on an empty item
// leaves the list, and Tab nests. Without the first there is no way out of a
// list except the mouse, and the second Enter — the one everybody presses —
// silently adds another blank bullet.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_list/lexical_list.dart';

void show(LexicalEditor editor, String label) {
  print('\n$label');
  editor.read(() {
    void walk(ElementNode node, int depth) {
      for (final child in node.children) {
        final indent = '  ' * (depth + 1);
        if (child is ListNode) {
          print('$indent<${child.listType.wire}>');
          walk(child, depth + 1);
        } else if (child is ListItemNode) {
          final tick = switch (child.checked) {
            null => '•',
            true => '[x]',
            false => '[ ]',
          };
          final own = child.children
              .where((node) => node is! ListNode)
              .map((node) => node.getTextContent())
              .join();
          if (own.isNotEmpty || child.childrenSize == 0) {
            print('$indent$tick $own');
          }
          // Only nested lists are walked: an item's own inline children are
          // its text, and they were just printed.
          for (final nested in child.children.whereType<ListNode>()) {
            print('$indent  <${nested.listType.wire}>');
            walk(nested, depth + 2);
          }
        } else {
          print('$indent¶ ${child.getTextContent()}');
        }
      }
    }

    walk($getRoot(), 0);
  });
}

void main() {
  final editor = LexicalEditor(nodes: listNodes);
  registerRichText(editor);
  registerList(editor);

  editor.update(() {
    final list = $createListNode(ListType.bullet)
      ..append($createListItemNode()..append($createTextNode('eins')))
      ..append($createListItemNode()..append($createTextNode('zwei')));
    $getRoot()
      ..clear()
      ..append(list);
    (list.getLastChild()! as ListItemNode).selectEnd();
  }, discrete: true);
  show(editor, 'a bullet list');

  // Tab nests the item the caret is in.
  editor.dispatchCommand(indentContentCommand, null);
  show(editor, 'after Tab on the second item');

  // Enter opens a new item; Enter again on the empty one un-nests it, and
  // once more leaves the list altogether.
  editor.dispatchCommand(insertParagraphCommand, null);
  editor.dispatchCommand(insertParagraphCommand, null);
  editor.dispatchCommand(insertParagraphCommand, null);
  show(editor, 'after Enter on the empty item, twice');

  // Numbering is derived from position, so it never has to be maintained.
  editor.update(() {
    $getRoot().append(
      $createListNode(ListType.number, 3)
        ..append($createListItemNode()..append($createTextNode('drittens')))
        ..append($createListItemNode()..append($createTextNode('viertens'))),
    );
  }, discrete: true);
  editor.read(() {
    final list = $getRoot().getLastChild()! as ListNode;
    final values = list.children
        .cast<ListItemNode>()
        .map((item) => item.value)
        .toList();
    print('\nordered list starting at ${list.start}, values: $values');
  });

  // A check list is the same node with a different type, and its items carry
  // a tri-state: null means "not a check list item at all".
  editor.update(() {
    $getRoot().append(
      $createListNode(ListType.check)
        ..append($createListItemNode(true)..append($createTextNode('erledigt')))
        ..append($createListItemNode(false)..append($createTextNode('offen'))),
    );
  }, discrete: true);
  show(editor, 'a check list');
}
