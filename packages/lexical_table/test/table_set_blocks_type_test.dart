import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:lexical_table/lexical_table.dart';
import 'package:test/test.dart';

LexicalEditor _editor() =>
    LexicalEditor(nodes: [...tableNodes, ...richTextNodes]);

/// A 2×2 table holding `a`…`d`, and a paragraph after it.
void _seed(LexicalEditor editor) {
  editor.update(() {
    final table = $createTableNodeWithDimensions(2, 2);
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
      ..append($createParagraphNode()..append($createTextNode('danach')));
  }, discrete: true);
}

/// Puts a caret in the first cell's paragraph.
void _caretInFirstCell(LexicalEditor editor) {
  editor.update(() {
    final table = $getRoot().getFirstChild()! as TableNode;
    final row = table.getFirstChild()! as TableRowNode;
    final cell = row.getFirstChild()! as TableCellNode;
    ((cell.getFirstChild()! as ElementNode).getFirstChild()! as TextNode)
        .select(0, 0);
  }, discrete: true);
}

void main() {
  group('a table meets a block conversion', () {
    test('the table survives, and the cell converts', () {
      // The failure worth a test of its own: replacing the table with the
      // pressed kind runs every cell's text together into one element and
      // drops the rows. Every word is still present afterwards, so a text
      // projection, a search index and a round trip all report success.
      final editor = _editor();
      _seed(editor);
      final before = editor.read(() => $getRoot().getTextContent());
      _caretInFirstCell(editor);

      editor.update(() {
        $setBlocksType(
          $getSelection(),
          () => $createHeadingNode(HeadingTag.h1),
        );
      }, discrete: true);

      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['table', 'paragraph'],
      );
      expect(editor.read(() => $getRoot().getTextContent()), before);
      expect(editor.read(() => assertTreeIntegrity($getRoot())), isTrue);
    });

    test('the paragraph in the cell is what became the heading', () {
      final editor = _editor();
      _seed(editor);
      _caretInFirstCell(editor);

      editor.update(() {
        $setBlocksType(
          $getSelection(),
          () => $createHeadingNode(HeadingTag.h1),
        );
      }, discrete: true);

      expect(
        editor.read(() {
          final table = $getRoot().getFirstChild()! as TableNode;
          final row = table.getFirstChild()! as TableRowNode;
          final cell = row.getFirstChild()! as TableCellNode;
          return cell.children.map((node) => node.type).toList();
        }),
        ['heading'],
      );
    });

    test('a row and a cell are containers, not blocks', () {
      final editor = _editor();
      _seed(editor);

      editor.read(() {
        final table = $getRoot().getFirstChild()! as TableNode;
        final row = table.getFirstChild()! as TableRowNode;
        final cell = row.getFirstChild()! as TableCellNode;

        expect($isBlock(table), isFalse);
        expect($isBlock(row), isFalse);
        // A cell holds a paragraph, so it is a container too — the paragraph
        // inside it is the block a caret is actually in.
        expect($isBlock(cell), isFalse);
        expect($isBlock(cell.getFirstChild()), isTrue);
      });
    });
  });
}
