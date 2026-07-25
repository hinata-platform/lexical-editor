import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: listNodes);

/// The item numbers of the first list, materialized inside the read context.
///
/// Node accessors resolve through the *active* editor state, so a lazy
/// `Iterable` built inside `read` and consumed outside it fails — the list
/// must be realized before the context closes.
List<int> _values(LexicalEditor editor) => editor.read(() {
  final list = $getRoot().getFirstChild()! as ListNode;
  return list.children
      .whereType<ListItemNode>()
      .map((item) => item.value)
      .toList();
});

void main() {
  group('wire shape', () {
    test('tag is derived from the list type, including for check lists', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..append($createListNode())
          ..append($createListNode(ListType.number))
          ..append($createListNode(ListType.check));
      }, discrete: true);

      final children = ((editor.toJson()['root']! as Map)['children']! as List)
          .cast<Map<String, Object?>>();
      expect(children.map((node) => node['tag']).toList(), ['ul', 'ol', 'ul']);
      expect(children.map((node) => node['listType']).toList(), [
        'bullet',
        'number',
        'check',
      ]);
    });

    test('checked is omitted outside a check list, present inside one', () {
      final editor = _editor();
      editor.update(() {
        final plain = $createListNode()..append($createListItemNode());
        final check = $createListNode(ListType.check)
          ..append($createListItemNode(false));
        $getRoot()
          ..append(plain)
          ..append(check);
      }, discrete: true);

      final lists = ((editor.toJson()['root']! as Map)['children']! as List)
          .cast<Map<String, Object?>>();
      final plainItem = (lists[0]['children']! as List).first as Map;
      final checkItem = (lists[1]['children']! as List).first as Map;

      expect(
        plainItem.containsKey('checked'),
        isFalse,
        reason: 'absent is a different wire value from present-and-null',
      );
      expect(checkItem['checked'], false);
    });
  });

  group('numbering', () {
    test('items are renumbered from the list start', () {
      final editor = _editor();
      registerListNumbering(editor);
      editor.update(() {
        final list = $createListNode(ListType.number, 5)
          ..append($createListItemNode())
          ..append($createListItemNode())
          ..append($createListItemNode());
        $getRoot().append(list);
      }, discrete: true);

      expect(_values(editor), [5, 6, 7]);
    });

    test('removing an item renumbers the rest', () {
      final editor = _editor();
      registerListNumbering(editor);
      editor.update(() {
        final list = $createListNode()
          ..append($createListItemNode())
          ..append($createListItemNode())
          ..append($createListItemNode());
        $getRoot().append(list);
      }, discrete: true);

      editor.update(() {
        final list = $getRoot().getFirstChild()! as ListNode;
        list.getFirstChild()!.remove();
      }, discrete: true);

      expect(_values(editor), [1, 2]);
    });

    test('changing the start renumbers immediately', () {
      final editor = _editor();
      editor.update(() {
        final list = $createListNode(ListType.number)
          ..append($createListItemNode())
          ..append($createListItemNode());
        $getRoot().append(list);
      }, discrete: true);

      editor.update(() {
        ($getRoot().getFirstChild()! as ListNode).setStart(10);
      }, discrete: true);

      expect(_values(editor), [10, 11]);
    });

    test('import stays verbatim even when values disagree', () {
      // Renumbering is a transform, and import does not run transforms — so
      // a document whose values are inconsistent is preserved rather than
      // silently rewritten, which is what keeps the round-trip a fixed point.
      final editor = _editor();
      registerListNumbering(editor);
      final document = {
        'root': {
          'children': [
            {
              'children': [
                {
                  'children': <Object?>[],
                  'direction': null,
                  'format': '',
                  'indent': 0,
                  'type': 'listitem',
                  'version': 1,
                  'value': 99,
                },
              ],
              'direction': null,
              'format': '',
              'indent': 0,
              'type': 'list',
              'version': 1,
              'listType': 'bullet',
              'start': 1,
              'tag': 'ul',
            },
          ],
          'direction': null,
          'format': '',
          'indent': 0,
          'type': 'root',
          'version': 1,
        },
      };
      final encoded = editor.parseEditorState(document).toJson();
      expect(jsonFirstDifference(document, encoded), isNull);
    });
  });

  group('check lists', () {
    test('toggling treats an unticked item as false', () {
      final editor = _editor();
      editor.update(() {
        final item = $createListItemNode();
        $getRoot().append($createListNode(ListType.check)..append(item));
        expect(item.checked, isNull);
        item.toggleChecked();
      }, discrete: true);

      editor.read(() {
        final item = ($getRoot().getFirstChild()! as ListNode).getFirstChild();
        expect((item! as ListItemNode).checked, isTrue);
      });
    });
  });

  test('nesting is represented as a list inside an item', () {
    final editor = _editor();
    editor.update(() {
      final inner = $createListNode()
        ..append($createListItemNode()..append($createTextNode('innen')));
      final holder = $createListItemNode()..append(inner);
      $getRoot().append($createListNode()..append(holder));
    }, discrete: true);

    editor.read(() {
      final outer = $getRoot().getFirstChild()! as ListNode;
      final holder = outer.getFirstChild()! as ListItemNode;
      expect(holder.isNestedListHolder, isTrue);
      expect(assertTreeIntegrity($getRoot()), isTrue);
    });
  });
}
