import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_table/lexical_table.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: tableNodes);

void main() {
  group('header state', () {
    test('is a bitmask, so a corner cell can be both', () {
      expect(TableCellHeaderState.both, 3);
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createTableNodeWithDimensions(2, 3, includeHeaders: true),
        );
      }, discrete: true);

      editor.read(() {
        final table = $getRoot().getFirstChild()! as TableNode;
        final firstRow = table.getFirstChild()! as TableRowNode;
        final corner = firstRow.getFirstChild()! as TableCellNode;
        expect(corner.headerState, TableCellHeaderState.both);
        expect(corner.isRowHeader, isTrue);
        expect(corner.isColumnHeader, isTrue);

        final secondCell = firstRow.getChildAtIndex(1)! as TableCellNode;
        expect(secondCell.headerState, TableCellHeaderState.row);
        expect(secondCell.isColumnHeader, isFalse);

        final secondRow = table.getChildAtIndex(1)! as TableRowNode;
        final bodyCell = secondRow.getChildAtIndex(1)! as TableCellNode;
        expect(bodyCell.headerState, TableCellHeaderState.none);
      });
    });
  });

  group('optional fields', () {
    test('row height is omitted when unset', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append($createTableNode()..append($createTableRowNode()));
      }, discrete: true);

      final table =
          ((editor.toJson()['root']! as Map)['children']! as List).first as Map;
      final row = (table['children']! as List).first as Map;
      expect(row.containsKey('height'), isFalse);
      expect(table.containsKey('colWidths'), isFalse);
    });

    test('cell background is emitted even when null', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createTableNode()
            ..append($createTableRowNode()..append($createTableCellNode())),
        );
      }, discrete: true);

      final table =
          ((editor.toJson()['root']! as Map)['children']! as List).first as Map;
      final row = (table['children']! as List).first as Map;
      final cell = (row['children']! as List).first as Map;
      expect(cell.containsKey('backgroundColor'), isTrue);
      expect(cell['backgroundColor'], isNull);
    });

    test('set values appear on the wire', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createTableNode()
            ..setColWidths([100, 200])
            ..append(
              $createTableRowNode(48)..append(
                $createTableCellNode(colSpan: 2, backgroundColor: '#eee'),
              ),
            ),
        );
      }, discrete: true);

      final json = editor.toJson();
      final table = ((json['root']! as Map)['children']! as List).first as Map;
      final row = (table['children']! as List).first as Map;
      final cell = (row['children']! as List).first as Map;
      expect(table['colWidths'], [100, 200]);
      expect(row['height'], 48);
      expect(cell['colSpan'], 2);
      expect(cell['backgroundColor'], '#eee');
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });
  });

  test('cells are shadow roots, so traversal stops at them', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append($createTableNodeWithDimensions(1, 1));
    }, discrete: true);

    editor.read(() {
      final table = $getRoot().getFirstChild()! as TableNode;
      final row = table.getFirstChild()! as TableRowNode;
      final cell = row.getFirstChild()! as TableCellNode;
      expect(cell.isShadowRoot, isTrue);
      expect(table.isShadowRoot, isTrue);
      final paragraph = cell.getFirstChild()!;
      expect(paragraph.type, 'paragraph');
      // The whole table is the top-level block of the document.
      expect(paragraph.getTopLevelElement()?.key, table.key);
    });
  });

  test('a built table is structurally sound', () {
    final editor = _editor();
    editor.update(() {
      $getRoot().append(
        $createTableNodeWithDimensions(3, 4, includeHeaders: true),
      );
    }, discrete: true);
    expect(editor.read(() => assertTreeIntegrity($getRoot())), isTrue);
  });
}
