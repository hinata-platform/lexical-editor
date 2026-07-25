import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_table/lexical_table.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: tableNodes);

/// The table under test. Must be called inside a read or an update.
TableNode _table() => $getRoot().getFirstChild()! as TableNode;

/// A freshly resolved grid. Must be called inside a read or an update.
TableGrid _grid() => $computeTableGrid(_table());

/// Must be called inside a read or an update.
TableCellNode _cell(int row, int column) => _grid().at(row, column)!.cell;

/// Builds a table whose cells hold `a`, `b`, `c`… so that a grid assertion
/// reads as the table the user would see.
void _seed(
  LexicalEditor editor,
  int rows,
  int columns, {
  bool headers = false,
}) {
  editor.update(() {
    final table = $createTableNodeWithDimensions(
      rows,
      columns,
      includeHeaders: headers,
    );
    var index = 0;
    for (final row in table.children.cast<TableRowNode>()) {
      for (final cell in row.children.cast<TableCellNode>()) {
        (cell.getFirstChild()! as ElementNode).append(
          $createTextNode(String.fromCharCode('a'.codeUnitAt(0) + index++)),
        );
      }
    }
    $getRoot()
      ..clear()
      ..append(table)
      ..append($createParagraphNode());
  }, discrete: true);
}

/// The grid as text, one string per row: the shape, not the child lists.
///
/// A slot shows the content of the cell covering it, so a merged cell appears
/// once per slot it occupies — `_` for an empty cell, `·` for a hole. The
/// block separators a cell of several paragraphs produces are dropped, since
/// what is being asserted here is the shape rather than the content.
List<String> _shape(LexicalEditor editor) => editor.read(() {
  final grid = _grid();
  return [
    for (var row = 0; row < grid.rowCount; row++)
      [
        for (var column = 0; column < grid.columnCount; column++)
          switch (grid
              .at(row, column)
              ?.cell
              .getTextContent()
              .replaceAll('\n', '')) {
            null => '·',
            '' => '_',
            final text => text,
          },
      ].join(' '),
  ];
});

/// Merges a rectangle through the public operation, rather than by setting a
/// span by hand — half-applied spans are not a state the editor can produce.
void _merge(LexicalEditor editor, int rowA, int colA, int rowB, int colB) {
  editor.update(() {
    $mergeTableCells(_grid(), TableCellRange(rowA, colA, rowB, colB));
  }, discrete: true);
}

void main() {
  group('grid', () {
    test('resolves spans into slots, not into child indices', () {
      final editor = _editor();
      _seed(editor, 3, 3);
      _merge(editor, 0, 0, 1, 1);

      // The merged cell covers four slots while being one child of one row,
      // which is exactly the case an index-based implementation gets wrong.
      expect(_shape(editor), ['abde abde c', 'abde abde f', 'g h i']);
      editor.read(() {
        final grid = _grid();
        expect(grid.rowCount, 3);
        expect(grid.columnCount, 3);
        expect(grid.at(1, 1)!.cell.key, grid.at(0, 0)!.cell.key);
        expect(grid.rows[1].childrenSize, 1);
        expect(grid.childIndexForColumn(1, 2), 0);
      });
    });

    test('a rowSpan reaching past the last row is clamped, not trusted', () {
      final editor = _editor();
      _seed(editor, 2, 1);
      editor.update(() => _cell(0, 0).setRowSpan(9), discrete: true);
      editor.read(() => expect(_grid().at(0, 0)!.rowSpan, 2));
    });
  });

  group('rows', () {
    test('insert below adds a row of the same shape', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      editor.update(
        () => $insertTableRows(_grid(), atRow: 0, below: true),
        discrete: true,
      );
      expect(_shape(editor), ['a b', '_ _', 'c d']);
    });

    test('a cell spanning the insertion line grows instead of splitting', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      _merge(editor, 0, 0, 1, 0);
      expect(_shape(editor), ['ac b', 'ac d']);

      editor.update(
        () => $insertTableRows(_grid(), atRow: 0, below: true),
        discrete: true,
      );
      // The merged cell reaches over the new row; only the second column
      // gains a cell, and nothing was un-merged behind the user's back.
      expect(_shape(editor), ['ac b', 'ac _', 'ac d']);
    });

    test('delete keeps a cell that reaches past the deleted band', () {
      final editor = _editor();
      _seed(editor, 3, 2);
      _merge(editor, 0, 0, 1, 0);
      expect(_shape(editor), ['ac b', 'ac d', 'e f']);

      editor.update(
        () => expect($deleteTableRows(_grid(), 0), isTrue),
        discrete: true,
      );
      // The cell survived, re-anchored to the first surviving row, and it is
      // now a child of that row rather than of the row that went.
      expect(_shape(editor), ['ac d', 'e f']);
      editor.read(() {
        final grid = _grid();
        expect(grid.at(0, 0)!.rowSpan, 1);
        expect(grid.rows.first.childrenSize, 2);
      });
    });

    test('deleting every row is refused, not silently obeyed', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      editor.update(
        () => expect($deleteTableRows(_grid(), 0, 2), isFalse),
        discrete: true,
      );
      expect(_shape(editor), ['a b', 'c d']);
    });
  });

  group('columns', () {
    test('insert right adds one cell per row', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      editor.update(
        () => $insertTableColumns(_grid(), atColumn: 0, after: true),
        discrete: true,
      );
      expect(_shape(editor), ['a _ b', 'c _ d']);
    });

    test('a cell spanning the insertion line grows once, not per row', () {
      final editor = _editor();
      _seed(editor, 2, 3);
      _merge(editor, 0, 0, 1, 1);

      editor.update(
        () => $insertTableColumns(_grid(), atColumn: 0, after: true),
        discrete: true,
      );
      editor.read(() => expect(_grid().at(0, 0)!.colSpan, 3));
      expect(_shape(editor), ['abde abde abde c', 'abde abde abde f']);
    });

    test('delete removes the cells and shrinks the ones that overlap', () {
      final editor = _editor();
      _seed(editor, 2, 3);
      _merge(editor, 0, 0, 0, 1);
      expect(_shape(editor), ['ab ab c', 'd e f']);

      editor.update(
        () => expect($deleteTableColumns(_grid(), 1), isTrue),
        discrete: true,
      );
      expect(_shape(editor), ['ab c', 'd f']);
    });

    test('deleting every column is refused', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      editor.update(
        () => expect($deleteTableColumns(_grid(), 0, 2), isFalse),
        discrete: true,
      );
      expect(_shape(editor), ['a b', 'c d']);
    });
  });

  group('merge and unmerge', () {
    test('merging moves content rather than dropping it', () {
      final editor = _editor();
      _seed(editor, 2, 2);
      _merge(editor, 0, 0, 1, 1);

      editor.read(() {
        final ref = _grid().at(0, 0)!;
        expect(ref.rowSpan, 2);
        expect(ref.colSpan, 2);
        // Every cell's content is still in the document, each as its own
        // paragraph inside the surviving cell.
        expect(ref.cell.childrenSize, 4);
        expect(ref.cell.getTextContent().replaceAll('\n', ''), 'abcd');
        expect(_grid().rows[1].childrenSize, 0);
      });
    });

    test('unmerging fills the freed slots back in', () {
      final editor = _editor();
      _seed(editor, 3, 3);
      _merge(editor, 0, 1, 1, 2);
      editor.update(
        () => $unmergeTableCell(_grid(), _cell(0, 1)),
        discrete: true,
      );

      editor.read(() {
        final grid = _grid();
        expect(grid.rowCount, 3);
        expect(grid.columnCount, 3);
        for (var row = 0; row < 3; row++) {
          for (var column = 0; column < 3; column++) {
            final ref = grid.at(row, column)!;
            expect(ref.rowSpan, 1);
            expect(ref.colSpan, 1);
            expect(ref.row, row);
            expect(ref.column, column);
          }
        }
      });
    });

    test('a rectangle clipping a merged cell grows to hold all of it', () {
      final editor = _editor();
      _seed(editor, 3, 3);
      _merge(editor, 1, 1, 2, 2);

      editor.read(() {
        // Half of a merged cell is not a rectangle anything can act on.
        expect(
          _grid().expand(TableCellRange(0, 0, 1, 1)),
          TableCellRange(0, 0, 2, 2),
        );
      });
    });
  });

  group('headers', () {
    test('toggling a row switches the whole band both ways', () {
      final editor = _editor();
      _seed(editor, 2, 3);
      editor.update(() => $toggleTableRowHeader(_grid(), 0), discrete: true);
      editor.read(() {
        expect(
          _grid().cellsInRow(0).every((ref) => ref.cell.isRowHeader),
          isTrue,
        );
      });

      editor.update(() => $toggleTableRowHeader(_grid(), 0), discrete: true);
      editor.read(() {
        expect(
          _grid().cellsInRow(0).any((ref) => ref.cell.isRowHeader),
          isFalse,
        );
      });
    });

    test('a corner cell keeps both roles', () {
      final editor = _editor();
      _seed(editor, 2, 2, headers: true);
      editor.update(() => $toggleTableColumnHeader(_grid(), 1), discrete: true);
      editor.read(() {
        final grid = _grid();
        expect(grid.at(0, 0)!.cell.headerState, TableCellHeaderState.both);
        expect(grid.at(0, 1)!.cell.headerState, TableCellHeaderState.both);
        expect(grid.at(1, 1)!.cell.headerState, TableCellHeaderState.column);
      });
    });
  });

  group('selection', () {
    test('a range across two cells reads as the rectangle between them', () {
      final editor = _editor();
      _seed(editor, 3, 3);
      editor.update(() {
        (_cell(0, 0).getFirstChild()! as ElementNode).selectStart();
        final target = _cell(1, 1).getFirstChild()! as ElementNode;
        ($getSelection()! as RangeSelection).moveTo(
          target.key,
          0,
          PointType.element,
          extend: true,
        );

        final table = $tableSelectionOf()!;
        expect(table.range, TableCellRange(0, 0, 1, 1));
        expect(table.cells.length, 4);
      }, discrete: true);
    });

    test('selecting cells sets a node selection over exactly them', () {
      final editor = _editor();
      _seed(editor, 3, 3);
      editor.update(() {
        final resolved = $selectTableCells(_cell(0, 0), _cell(1, 1));
        expect(resolved!.cells.length, 4);
        expect(($getSelection()! as NodeSelection).keys.length, 4);
        expect($tableSelectionOf()!.range, TableCellRange(0, 0, 1, 1));
      }, discrete: true);
    });
  });

  group('commands', () {
    test('Tab walks the cells in reading order and stops at the end', () {
      final editor = _editor();
      registerTable(editor);
      _seed(editor, 2, 2);
      editor.update(() => $selectTableCellStart(_cell(0, 0)), discrete: true);

      for (final expected in ['b', 'c', 'd']) {
        expect(editor.dispatchCommand(moveTableCellCommand, false), isTrue);
        editor.read(() {
          final cell = $getTableCellForNode(
            ($getSelection()! as RangeSelection).focus.getNode(),
          );
          expect(cell!.getTextContent(), expected);
        });
      }
      // Past the last cell it declines, so the host's own Tab handling —
      // focus traversal, indentation — still gets its turn.
      expect(editor.dispatchCommand(moveTableCellCommand, false), isFalse);
    });

    test('Delete over selected cells empties them and keeps the shape', () {
      final editor = _editor();
      registerTable(editor);
      _seed(editor, 2, 2);
      editor.update(
        () => $selectTableCells(_cell(0, 0), _cell(1, 1)),
        discrete: true,
      );

      expect(editor.dispatchCommand(deleteCharacterCommand, true), isTrue);
      expect(_shape(editor), ['_ _', '_ _']);
      editor.read(() {
        expect(_grid().rowCount, 2);
        expect(_grid().columnCount, 2);
      });
    });

    test('inserting a table leaves somewhere to type after it', () {
      final editor = _editor();
      registerTable(editor);
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode());
        ($getRoot().getFirstChild()! as ElementNode).selectStart();
      }, discrete: true);

      expect(
        editor.dispatchCommand(
          insertTableCommand,
          const TableShape(rows: 2, columns: 2),
        ),
        isTrue,
      );
      editor.read(() {
        expect($getRoot().children.map((node) => node.type).toList(), [
          'table',
          'paragraph',
        ]);
        // The caret lands in the first cell, not after the table.
        final selection = $getSelection()! as RangeSelection;
        expect($getTableCellForNode(selection.focus.getNode()), isNotNull);
      });
    });

    test('a row command run from a cell selection covers the whole band', () {
      final editor = _editor();
      registerTable(editor);
      _seed(editor, 3, 2);
      editor.update(
        () => $selectTableCells(_cell(0, 0), _cell(1, 0)),
        discrete: true,
      );

      expect(editor.dispatchCommand(deleteTableRowCommand, null), isTrue);
      expect(_shape(editor), ['e f']);
    });
  });

  group('the document stays valid', () {
    test('a table with merged cells round-trips as a fixed point', () {
      final editor = _editor();
      _seed(editor, 3, 3, headers: true);
      _merge(editor, 1, 1, 2, 2);

      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
      editor.read(() => expect(assertTreeIntegrity($getRoot()), isTrue));
    });
  });
}
