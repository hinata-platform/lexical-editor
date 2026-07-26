/// The markdown spelling of a table.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

import 'table_grid.dart';
import 'table_nodes.dart';

/// A line that is a table row: `| a | b |`.
final RegExp _rowPattern = RegExp(r'^\s*\|(.*)\|\s*$');

/// A row that only separates the header: `| --- | :--: |`.
final RegExp _delimiterCell = RegExp(r'^\s*:?-{1,}:?\s*$');

/// GitHub-flavoured tables, in both directions.
///
/// ```markdown
/// | Paket         | Was es kann         |
/// | ------------- | ------------------- |
/// | lexical_table | Zeilen und Spalten  |
/// ```
///
/// Like the image rule in `lexical_image` this is **not** part of
/// [defaultMarkdownTransformers], and neither is upstream's: `@lexical/markdown`
/// ships no table rule and the playground adds its own to the list it passes
/// in. Add it the same way, and put it before the rules that match a plain
/// line:
///
/// ```dart
/// final transformers = defaultMarkdownTransformers.extend(
///   elements: [tableTransformer],
/// );
/// ```
///
/// Without it a table still exports — as its cells, one per line, because
/// every block falls back to its text. That is worse than losing it: the
/// result reads like a document, so nobody notices the table is gone.
///
/// ## How a multi-line construct fits a line-based parser
///
/// Import is one line at a time, so a row cannot see the rows around it.
/// It does not have to: a row that follows a table **joins** it, and only the
/// first row of a run creates one. The delimiter line is not a row at all — it
/// marks the row above as the header and leaves nothing behind. Upstream
/// solves it the same way, and the shape is worth naming because it is how
/// every multi-line construct has to work here.
///
/// ## What markdown cannot carry
///
/// A merged cell has no markdown spelling. Rather than drop the columns it
/// covers — which would make the table ragged and unparseable — export writes
/// the merged content in its own slot and leaves the slots it covers empty, so
/// the table stays rectangular and reads correctly. Coming back it is a table
/// of ordinary cells: the merge itself is lost, as it is upstream.
///
/// Cell content is inline. A cell holding several paragraphs exports as one
/// line with the paragraphs joined by a space, because a markdown table row
/// cannot contain a line break. A `|` inside a cell is escaped.
final ElementTransformer tableTransformer = ElementTransformer(
  regExp: _rowPattern,
  exportsSubtree: true,
  replace: (block, children, match) {
    final cells = _splitRow(match.group(1)!);
    final previous = block.getPreviousSibling();

    // A delimiter line describes the row above it and is not a row itself.
    if (cells.every(_delimiterCell.hasMatch)) {
      if (previous is TableNode) {
        final first = previous.getFirstChild();
        if (first is TableRowNode) {
          for (final cell in first.children.whereType<TableCellNode>()) {
            cell.setHeaderState(cell.headerState | TableCellHeaderState.row);
          }
        }
      }
      block.remove();
      return;
    }

    final row = $createTableRowNode()
      ..appendAll([for (final cell in cells) _cell(cell)]);

    if (previous is TableNode) {
      previous.append(row);
      _squareOff(previous);
      block.remove();
      return;
    }
    block.replace($createTableNode()..append(row));
  },
  export: (node, exportChildren) {
    if (node is! TableNode) return null;
    final grid = $computeTableGrid(node);
    if (grid.rowCount == 0 || grid.columnCount == 0) return null;

    final lines = <String>[];
    for (var row = 0; row < grid.rowCount; row++) {
      final cells = <String>[];
      var isHeader = false;
      for (var column = 0; column < grid.columnCount; column++) {
        final ref = grid.at(row, column);
        // A slot a merged cell reaches into is written empty: its content
        // already appeared in the cell's own slot, one row or one column
        // back, and repeating it would read as duplicated data.
        if (ref == null || ref.row != row || ref.column != column) {
          cells.add('');
          continue;
        }
        cells.add(_cellText(ref.cell, exportChildren));
        if ((ref.cell.headerState & TableCellHeaderState.row) != 0) {
          isHeader = true;
        }
      }
      lines.add('| ${cells.join(' | ')} |');
      if (isHeader) {
        lines.add('| ${cells.map((_) => '---').join(' | ')} |');
      }
    }
    return lines.join('\n');
  },
);

/// Splits `a | b` into its cells, respecting `\|`.
List<String> _splitRow(String body) {
  final cells = <String>[];
  final buffer = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final character = body[i];
    if (character == r'\' && i + 1 < body.length && body[i + 1] == '|') {
      buffer.write('|');
      i++;
      continue;
    }
    if (character == '|') {
      cells.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(character);
  }
  cells.add(buffer.toString().trim());
  return cells;
}

TableCellNode _cell(String markdown, {int headerState = 0}) =>
    $createTableCellNode(headerState: headerState)..append(
      $createParagraphNode()
        ..appendAll($parseMarkdownInline(markdown, transformers: _inline)),
    );

/// The rules a cell's content is parsed with.
///
/// The defaults minus the block rules, since a cell holds one line: `# ` in a
/// cell is a hash, not a heading.
final MarkdownTransformers _inline = MarkdownTransformers(
  textFormats: defaultMarkdownTransformers.textFormats,
  textMatches: defaultMarkdownTransformers.textMatches,
);

/// Pads every row of [table] to the width of its widest.
///
/// A markdown table may have a short row, and a table with holes in it is not
/// something the grid, the commands or the layout should have to carry
/// around: the hole is filled once, here, at the edge where it arrives.
void _squareOff(TableNode table) {
  final rows = table.children.whereType<TableRowNode>().toList();
  var widest = 0;
  for (final row in rows) {
    final width = row.children.whereType<TableCellNode>().length;
    if (width > widest) widest = width;
  }
  for (final row in rows) {
    final cells = row.children.whereType<TableCellNode>().toList();
    final headerState = cells.isEmpty
        ? TableCellHeaderState.none
        : cells.first.headerState & TableCellHeaderState.row;
    for (var i = cells.length; i < widest; i++) {
      row.append(_cell('', headerState: headerState));
    }
  }
}

String _cellText(TableCellNode cell, ExportChildren exportChildren) {
  final parts = <String>[
    for (final child in cell.children)
      if (child is ElementNode) exportChildren(child),
  ];
  return parts
      .where((part) => part.isNotEmpty)
      .join(' ')
      .replaceAll('|', r'\|')
      .replaceAll('\n', ' ');
}
