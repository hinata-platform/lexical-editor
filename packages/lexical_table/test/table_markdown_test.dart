import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_markdown/lexical_markdown.dart';
import 'package:lexical_table/lexical_table.dart';
import 'package:test/test.dart';

final MarkdownTransformers _transformers = defaultMarkdownTransformers.extend(
  elements: [tableTransformer],
);

LexicalEditor _editor() => LexicalEditor(nodes: tableNodes);

void _import(LexicalEditor editor, String markdown) => editor.update(
  () => $convertFromMarkdown(markdown, transformers: _transformers),
  discrete: true,
);

String _export(LexicalEditor editor) =>
    editor.read(() => $convertToMarkdown(transformers: _transformers));

/// The table as `row -> cells`, which is the shape a table assertion is about.
List<List<String>> _cells(LexicalEditor editor) => editor.read(() {
  final table = $getRoot().children.whereType<TableNode>().single;
  final grid = $computeTableGrid(table);
  return [
    for (var row = 0; row < grid.rowCount; row++)
      [
        for (var column = 0; column < grid.columnCount; column++)
          grid.at(row, column)?.cell.getTextContent() ?? '·',
      ],
  ];
});

const _table = '''
| Paket | Was es kann |
| --- | --- |
| lexical_table | Zeilen und Spalten |
| lexical_embed | YouTube und Figma |''';

void main() {
  group('import', () {
    test('a run of rows becomes one table', () {
      final editor = _editor();
      _import(editor, _table);

      expect(_cells(editor), [
        ['Paket', 'Was es kann'],
        ['lexical_table', 'Zeilen und Spalten'],
        ['lexical_embed', 'YouTube und Figma'],
      ]);
    });

    test('the delimiter line marks the header and leaves nothing behind', () {
      final editor = _editor();
      _import(editor, _table);

      editor.read(() {
        final grid = $computeTableGrid(
          $getRoot().children.whereType<TableNode>().single,
        );
        // Three rows, not four: the `| --- |` line is not a row.
        expect(grid.rowCount, 3);
        for (final ref in grid.cellsInRow(0)) {
          expect(ref.cell.headerState & TableCellHeaderState.row, isNonZero);
        }
        for (final ref in grid.cellsInRow(1)) {
          expect(ref.cell.headerState & TableCellHeaderState.row, isZero);
        }
      });
    });

    test('a table without a delimiter line is still a table', () {
      // GitHub would refuse it; refusing it here would mean losing the rows.
      final editor = _editor();
      _import(editor, '| a | b |\n| c | d |');
      expect(_cells(editor), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('a short row is padded, so the table has no holes', () {
      final editor = _editor();
      _import(editor, '| a | b | c |\n| d |');
      expect(_cells(editor), [
        ['a', 'b', 'c'],
        ['d', '', ''],
      ]);
    });

    test('cell content is parsed as inline markdown', () {
      final editor = _editor();
      _import(editor, '| **fett** | [Link](https://x.dev) |');

      editor.read(() {
        final grid = $computeTableGrid(
          $getRoot().children.whereType<TableNode>().single,
        );
        final bold = grid.at(0, 0)!.cell.getFirstChild()! as ElementNode;
        expect(
          (bold.getFirstChild()! as TextNode).hasFormat(TextFormat.bold),
          isTrue,
        );
        expect(grid.at(0, 1)!.cell.getTextContent(), 'Link');
      });
    });

    test('an escaped pipe stays inside its cell', () {
      final editor = _editor();
      _import(editor, r'| a \| b | c |');
      expect(_cells(editor), [
        ['a | b', 'c'],
      ]);
    });

    test('paragraphs around a table stay separate blocks', () {
      final editor = _editor();
      _import(editor, 'davor\n\n| a | b |\n\ndanach');

      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph', 'table', 'paragraph'],
      );
    });
  });

  group('export', () {
    test('a table exports as a table, not as its cells', () {
      // The bug this rule exists for: without it every cell is its own line
      // and the result still reads like a document.
      final editor = _editor();
      _import(editor, _table);
      expect(_export(editor), _table);
    });

    test('markdown survives a round trip', () {
      final editor = _editor();
      _import(editor, _table);
      final once = _export(editor);

      final second = _editor();
      _import(second, once);
      expect(_export(second), once);
    });

    test('a pipe in a cell is escaped', () {
      final editor = _editor();
      editor.update(() {
        final table = $createTableNodeWithDimensions(1, 2);
        final grid = $computeTableGrid(table);
        (grid.at(0, 0)!.cell.getFirstChild()! as ElementNode).append(
          $createTextNode('a | b'),
        );
        $getRoot()
          ..clear()
          ..append(table);
      }, discrete: true);

      expect(_export(editor), r'| a \| b |  |');
      // And it reads back as one cell rather than two.
      final second = _editor();
      _import(second, _export(editor));
      expect(_cells(second).first.first, 'a | b');
    });

    test('a merged cell keeps the table rectangular', () {
      final editor = _editor();
      _import(editor, '| a | b |\n| c | d |');
      editor.update(() {
        final table = $getRoot().children.whereType<TableNode>().single;
        $mergeTableCells($computeTableGrid(table), TableCellRange(0, 0, 0, 1));
      }, discrete: true);

      // The slot the merge covers is written empty: every row still has two
      // cells, which is what keeps the markdown parseable.
      expect(_export(editor), '| a b |  |\n| c | d |');
    });

    test('an empty table exports to nothing rather than to a broken row', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createTableNode())
          ..append($createParagraphNode()..append($createTextNode('text')));
      }, discrete: true);

      // A row with no cells would be `|  |`, which reads back as a table of
      // one empty cell — a document growing a table it never had.
      expect(_export(editor), isNot(contains('|')));
      expect(_export(editor), contains('text'));
    });
  });
}
