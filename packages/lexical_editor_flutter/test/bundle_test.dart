import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

const _base = TextStyle(fontSize: 16, height: 1.4);

Future<void> _pump(WidgetTester tester, LexicalEditor editor) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LexicalEditorField(
          editor: editor,
          baseTextStyle: _base,
          autofocus: true,
          scrollable: false,
        ),
      ),
    ),
  );
  await tester.pump();
}

List<String> _types(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

void main() {
  group('registration', () {
    test('every fixture node type is understood', () {
      final editor = createLexicalEditor();
      for (final type in [
        'heading',
        'quote',
        'list',
        'listitem',
        'link',
        'autolink',
        'code',
        'code-highlight',
        'table',
        'tablerow',
        'tablecell',
        'mark',
        'hashtag',
        'mention',
        'image',
        'youtube',
        'tweet',
        'figma',
      ]) {
        expect(
          editor.registry.knows(type),
          isTrue,
          reason: '$type is not registered',
        );
      }
    });

    test('an unknown type is still refused loudly', () {
      // The bundle is wide, not permissive: a version skew must not be
      // mistaken for a document that simply lost a node.
      final editor = createLexicalEditor();
      expect(
        () => editor.parseEditorState({
          'root': {
            'children': [
              {'type': 'from-the-future', 'version': 1},
            ],
            'direction': null,
            'format': '',
            'indent': 0,
            'type': 'root',
            'version': 1,
          },
        }),
        throwsA(isA<UnknownNodeTypeException>()),
      );
    });

    test('registerLexical unregisters everything it installed', () {
      final editor = createLexicalEditor();
      final unsubscribe = registerLexical(editor);
      editor
        ..ensureNonEmpty()
        ..update(() {
          final paragraph = $getRoot().getFirstChild()! as ElementNode;
          paragraph.selectStart();
        }, discrete: true);
      expect(editor.dispatchCommand(insertTextCommand, 'x'), isTrue);
      unsubscribe();
      expect(editor.dispatchCommand(insertTextCommand, 'y'), isFalse);
    });
  });

  group('the default theme', () {
    test('sizes headings by their level', () {
      final theme = defaultLexicalTheme(baseTextStyle: _base);
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createHeadingNode(HeadingTag.h1))
          ..append($createHeadingNode(HeadingTag.h4));
      }, discrete: true);

      final sizes = editor.read(
        () => $getRoot().children
            .cast<ElementNode>()
            .map((node) => theme.blockStyleForNode(node).textStyle?.fontSize)
            .toList(),
      );
      expect(sizes[0], 32);
      expect(sizes[1], greaterThan(16));
      expect(sizes[0]! > sizes[1]!, isTrue);
    });

    test('gives every bundled block type its own presentation', () {
      final theme = defaultLexicalTheme(baseTextStyle: _base);
      for (final type in [
        'heading',
        'quote',
        'code',
        'list',
        'listitem',
        'table',
        'tablecell',
      ]) {
        expect(
          theme.blockStyles.containsKey(type),
          isTrue,
          reason: '$type has no block style',
        );
      }
      expect(theme.linkStyle, isNotNull);
      expect(theme.markerBuilders.containsKey('listitem'), isTrue);
    });

    test('colours a code run by what the tokenizer called it', () {
      final theme = defaultLexicalTheme(baseTextStyle: _base);
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createCodeNode('dart')
              ..append($createCodeHighlightNode('void', 'keyword'))
              ..append($createCodeHighlightNode(' name', null))
              // What a block highlighted by @lexical/code-shiki looks like:
              // no classification at all, the colour baked into the style.
              ..append(
                $createCodeHighlightNode('shiki')..setStyle('color: #ff0000'),
              ),
          );
      }, discrete: true);

      final styles = editor.read(() {
        final code = $getRoot().getFirstChild()! as ElementNode;
        return [
          for (final run in code.children.cast<TextNode>())
            theme
                .resolveTextStyle(
                  base: theme.textStyleResolver!(run, theme.baseTextStyle),
                  format: run.getFormat(),
                  style: run.getStyle(),
                )
                .color,
        ];
      });

      expect(styles[0], isNot(styles[1]), reason: 'a keyword looks like text');
      expect(styles[1], theme.baseTextStyle.color);
      expect(styles[2], const Color(0xFFFF0000));
    });

    test('a dark palette changes the colours, not the metrics', () {
      final light = defaultLexicalTheme(baseTextStyle: _base);
      final dark = defaultLexicalTheme(
        baseTextStyle: _base,
        palette: const LexicalPalette.dark(),
      );
      expect(dark.baseTextStyle.color, isNot(light.baseTextStyle.color));
      expect(dark.baseTextStyle.fontSize, light.baseTextStyle.fontSize);
    });
  });

  group('the field', () {
    testWidgets('starts with somewhere to type', (tester) async {
      final editor = createLexicalEditor();
      await _pump(tester, editor);
      expect(_types(editor), ['paragraph']);
    });

    testWidgets('renders a list with its markers', (tester) async {
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createListNode(ListType.number)
              ..append($createListItemNode()..append($createTextNode('eins')))
              ..append($createListItemNode()..append($createTextNode('zwei'))),
          );
      }, discrete: true);
      await _pump(tester, editor);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('a check list renders checkboxes, not numbers', (tester) async {
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createListNode(ListType.check)
              ..append(
                $createListItemNode(true)..append($createTextNode('erledigt')),
              )
              ..append(
                $createListItemNode(false)..append($createTextNode('offen')),
              ),
          );
      }, discrete: true);
      await _pump(tester, editor);

      expect(find.text('1.'), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('editing works end to end, and undo comes back', (
      tester,
    ) async {
      final editor = createLexicalEditor();
      await _pump(tester, editor);
      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        paragraph.selectStart();
      }, discrete: true);
      await tester.pump();

      editor.dispatchCommand(insertTextCommand, 'Hallo Welt');
      await tester.pump();
      expect(editor.read(() => $getRoot().getTextContent()), 'Hallo Welt');

      editor.dispatchCommand(insertParagraphCommand, null);
      await tester.pump();
      expect(_types(editor), ['paragraph', 'paragraph']);

      editor.dispatchCommand(undoCommand, null);
      await tester.pump();
      expect(_types(editor), ['paragraph']);
    });

    testWidgets('a document written by the bundle round-trips', (tester) async {
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createHeadingNode(HeadingTag.h2)..append($createTextNode('Titel')),
          )
          ..append(
            $createParagraphNode()
              ..append($createTextNode('Text mit '))
              ..append(
                $createLinkNode('https://example.org')
                  ..append($createTextNode('Link')),
              )
              ..append($createTextNode(' und '))
              ..append(
                $createMentionNode(
                  text: '@Rebar',
                  mentionType: 'user',
                  mentionId: 'u_1',
                ),
              ),
          )
          ..append($createQuoteNode()..append($createTextNode('Zitat')))
          ..append(
            $createCodeNode('dart')..append($createTextNode('void main() {}')),
          );
      }, discrete: true);
      await _pump(tester, editor);

      final json = editor.toJson();
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('tables', () {
    testWidgets('the insert command actually inserts one', (tester) async {
      // The bundle registered the table *nodes* but never `registerTable`,
      // so every table command dispatched into nothing and the toolbar
      // button did visibly nothing. Nodes without their behaviour is the
      // failure mode a bundle exists to prevent.
      final editor = createLexicalEditor();
      await _pump(tester, editor);

      final handled = editor.dispatchCommand(
        insertTableCommand,
        const TableShape(rows: 2, columns: 3),
      );

      expect(handled, isTrue, reason: 'no handler claimed the command');
      editor.read(() {
        final table = $getRoot().children.whereType<TableNode>().single;
        expect(table.children.whereType<TableRowNode>().length, 2);
        final row = table.getFirstChild()! as ElementNode;
        expect(row.children.whereType<TableCellNode>().length, 3);
        assertTreeIntegrity($getRoot());
      });
    });

    testWidgets('rows and columns can be added and removed', (tester) async {
      final editor = createLexicalEditor();
      await _pump(tester, editor);
      editor
        ..dispatchCommand(
          insertTableCommand,
          const TableShape(rows: 2, columns: 2),
        )
        ..dispatchCommand(insertTableRowCommand, true)
        ..dispatchCommand(insertTableColumnCommand, true);

      List<int> shape() => editor.read(() {
        final table = $getRoot().children.whereType<TableNode>().single;
        final rows = table.children.whereType<TableRowNode>().toList();
        return [rows.length, rows.first.children.length];
      });

      expect(shape(), [3, 3]);

      editor
        ..dispatchCommand(deleteTableRowCommand, null)
        ..dispatchCommand(deleteTableColumnCommand, null);
      expect(shape(), [2, 2]);

      editor.dispatchCommand(deleteTableCommand, null);
      editor.read(() {
        expect($getRoot().children.whereType<TableNode>(), isEmpty);
      });
    });
  });

  group('table layout', () {
    // The reported bug, and it was never in the commands: a table drawn as
    // ordinary nested blocks is a vertical list of every cell, so inserting
    // one row looks like three lines appearing and inserting a column looks
    // like rows sprouting all over the table.
    Future<LexicalEditor> pumpTable(
      WidgetTester tester, {
      int rows = 2,
      int columns = 3,
    }) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createTableNodeWithDimensions(rows, columns))
          ..append($createParagraphNode());
      }, discrete: true);

      await _pump(tester, editor);
      return editor;
    }

    /// Where the cell at [row], [column] was drawn.
    ///
    /// Found by node key: the document is drawn with render objects rather
    /// than `Text` widgets, so there is no string to look for.
    Rect cellRect(WidgetTester tester, LexicalEditor editor, int row, int col) {
      final key = editor.read(() {
        final table = $getRoot().getFirstChild()! as TableNode;
        return $computeTableGrid(table).at(row, col)!.cell.key.value;
      });
      return tester.getRect(find.byKey(ValueKey<String>('lexical-cell-$key')));
    }

    void placeCaret(LexicalEditor editor, int row, int col) {
      editor.update(() {
        final table = $getRoot().getFirstChild()! as TableNode;
        final cell = $computeTableGrid(table).at(row, col)!.cell;
        (cell.getFirstChild()! as ElementNode).selectStart();
      }, discrete: true);
    }

    testWidgets('cells of a row share a top edge, side by side', (
      tester,
    ) async {
      final editor = await pumpTable(tester);

      final first = cellRect(tester, editor, 0, 0);
      final second = cellRect(tester, editor, 0, 1);
      final third = cellRect(tester, editor, 0, 2);
      expect(second.left, greaterThan(first.left));
      expect(third.left, greaterThan(second.left));
      expect(second.top, first.top);
      expect(third.top, first.top);

      // And the second row is below the first, not beside it.
      final below = cellRect(tester, editor, 1, 0);
      expect(below.top, greaterThanOrEqualTo(first.bottom));
      expect(below.left, first.left);
    });

    testWidgets('inserting one row adds one row, not one line per cell', (
      tester,
    ) async {
      final editor = await pumpTable(tester);
      final rowHeight =
          cellRect(tester, editor, 1, 0).top -
          cellRect(tester, editor, 0, 0).top;

      placeCaret(editor, 0, 0);
      editor.dispatchCommand(insertTableRowCommand, true);
      await tester.pump();

      // Three cells arrived and they are one row: what used to be the second
      // row is now the third, one row lower — not three lines lower.
      expect(
        cellRect(tester, editor, 2, 0).top - cellRect(tester, editor, 0, 0).top,
        closeTo(rowHeight * 2, 1),
      );
      expect(
        cellRect(tester, editor, 1, 1).top,
        cellRect(tester, editor, 1, 0).top,
      );
    });

    testWidgets('inserting a column widens the table instead of stacking', (
      tester,
    ) async {
      final editor = await pumpTable(tester);
      final widthBefore = cellRect(tester, editor, 0, 0).width;

      placeCaret(editor, 0, 0);
      editor.dispatchCommand(insertTableColumnCommand, true);
      await tester.pump();

      // Four columns now share the width, and every row still has one top
      // edge — nothing dropped into a line of its own.
      expect(cellRect(tester, editor, 0, 0).width, lessThan(widthBefore));
      expect(
        cellRect(tester, editor, 0, 3).top,
        cellRect(tester, editor, 0, 0).top,
      );
      expect(
        cellRect(tester, editor, 1, 3).top,
        cellRect(tester, editor, 1, 0).top,
      );
    });

    testWidgets('a merged cell covers the columns it spans', (tester) async {
      final editor = await pumpTable(tester);
      final single = cellRect(tester, editor, 0, 0).width;

      editor.update(() {
        final table = $getRoot().getFirstChild()! as TableNode;
        final grid = $computeTableGrid(table);
        $mergeTableCells(grid, TableCellRange(0, 0, 0, 1));
      }, discrete: true);
      await tester.pump();

      expect(cellRect(tester, editor, 0, 0).width, greaterThan(single * 1.5));
      // The row below is untouched and still starts at the left edge.
      expect(
        cellRect(tester, editor, 1, 0).left,
        closeTo(cellRect(tester, editor, 0, 0).left, 1),
      );
    });

    group('selecting cells', () {
      // The reported bug, and the cause was nowhere near the table: a cell is
      // taller than the line of text in it — padding, and a cell stretched to
      // its row — and a press on that part of it used to resolve to no block
      // at all. Doing nothing is not neutral here, because the selection
      // keeps the anchor it already had: the next drag then spans from
      // wherever the user last clicked, and a merge swallows rows they never
      // pointed at.
      Future<LexicalEditor> pumpFilled(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final editor = createLexicalEditor();
        editor.update(() {
          const text = [
            ['Paket', 'Was es kann', 'Rein Dart'],
            ['lexical_table', 'Zeilen und Spalten', 'ja'],
            ['lexical_embed', 'YouTube und Figma', 'nein'],
          ];
          final table = $createTableNodeWithDimensions(
            3,
            3,
            includeHeaders: true,
          );
          final grid = $computeTableGrid(table);
          for (var row = 0; row < 3; row++) {
            for (var column = 0; column < 3; column++) {
              (grid.at(row, column)!.cell.getFirstChild()! as ElementNode)
                  .append($createTextNode(text[row][column]));
            }
          }
          $getRoot()
            ..clear()
            ..append(table)
            ..append($createParagraphNode());
        }, discrete: true);

        await _pump(tester, editor);
        return editor;
      }

      /// The cells the selection resolves to, by their text.
      List<String> selectedCells(LexicalEditor editor) => editor.read(() {
        final selection = $tableSelectionOf();
        return selection == null
            ? const <String>[]
            : selection.cells.map((cell) => cell.getTextContent()).toList();
      });

      testWidgets("a drag starting in a cell's padding selects that cell", (
        tester,
      ) async {
        final editor = await pumpFilled(tester);

        // The caret is somewhere else entirely to begin with.
        await tester.tapAt(cellRect(tester, editor, 2, 1).center);
        await tester.pump(const Duration(milliseconds: 400));

        // Press below the text of a header cell — inside the cell, outside
        // its line — and drag to the cell beside it.
        final head = cellRect(tester, editor, 0, 1);
        final press = Offset(head.center.dx, head.bottom - 2);
        final gesture = await tester.startGesture(
          press,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 30));
        await gesture.moveTo(Offset(press.dx + 20, press.dy));
        await tester.pump();
        await gesture.moveTo(cellRect(tester, editor, 0, 2).center);
        await tester.pump();
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));

        expect(selectedCells(editor), ['Was es kann', 'Rein Dart']);

        // And merging takes exactly those two: one row, two columns.
        editor.dispatchCommand(mergeTableCellsCommand, null);
        await tester.pump();
        await tester.pump();

        editor.read(() {
          final grid = $computeTableGrid(
            $getRoot().getFirstChild()! as TableNode,
          );
          final merged = grid.at(0, 1)!;
          expect(merged.rowSpan, 1);
          expect(merged.colSpan, 2);
          expect(grid.rowCount, 3);
          // The row below kept its own three cells.
          expect(grid.cellsInRow(1).length, 3);
        });
      });

      testWidgets('a press below the last block still places the caret', (
        tester,
      ) async {
        // The same rule, outside a table: the empty area under a document
        // belongs to the document.
        final editor = await pumpFilled(tester);
        final table = tester.getRect(find.byType(LexicalGrid));

        await tester.tapAt(Offset(table.center.dx, table.bottom + 40));
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          editor.read($getSelection),
          isA<RangeSelection>(),
          reason: 'a tap in the document must always land somewhere',
        );
      });

      testWidgets('the cells that would be merged are tinted', (tester) async {
        final editor = await pumpFilled(tester);

        /// Whether the cell at [row], [column] draws the selection tint.
        bool tinted(int row, int column) {
          final key = editor.read(() {
            final grid = $computeTableGrid(
              $getRoot().getFirstChild()! as TableNode,
            );
            return grid.at(row, column)!.cell.key.value;
          });
          final boxes = tester.widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(ValueKey<String>('lexical-cell-$key')),
              matching: find.byType(DecoratedBox),
              matchRoot: true,
            ),
          );
          return boxes.any(
            (box) =>
                box.position == DecorationPosition.foreground &&
                (box.decoration as BoxDecoration).color != null,
          );
        }

        expect(tinted(0, 1), isFalse);

        editor.update(() {
          final grid = $computeTableGrid(
            $getRoot().getFirstChild()! as TableNode,
          );
          $selectTableCells(grid.at(0, 1)!.cell, grid.at(0, 2)!.cell);
        }, discrete: true);
        await tester.pump();
        await tester.pump();

        expect(tinted(0, 1), isTrue);
        expect(tinted(0, 2), isTrue);
        expect(tinted(0, 0), isFalse);
        expect(tinted(1, 1), isFalse);
      });
    });
  });

  group('media', () {
    // The inline image is the part worth pinning: upstream's ImageNode is an
    // inline decorator inside a paragraph, so it renders as a WidgetSpan in
    // the middle of a text run rather than as a block of its own. Getting
    // that wrong produces either a layout error or a document shape no other
    // Lexical client writes.
    const transparentPixel =
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAAB'
        'AAEAAAIBRAA7';

    Future<void> pumpMedia(WidgetTester tester, LexicalEditor editor) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LexicalEditorField(
              editor: editor,
              baseTextStyle: _base,
              scrollable: false,
              decoratorBuilders: lexicalDecoratorBuilders(
                editor: editor,
                // A thumbnail would be an HTTP request the test binding
                // refuses; the card is the thing under test either way.
                embedThumbnails: (kind, id) => null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an image and a video render without a layout error', (
      tester,
    ) async {
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('davor '))
              ..append(
                $createImageNode(
                  src: transparentPixel,
                  altText: 'Ein Bild',
                  width: 160,
                  height: 120,
                )..setCaptionText('Eine Unterschrift'),
              )
              ..append($createTextNode(' danach')),
          )
          ..append($createYouTubeNode('dQw4w9WgXcQ'))
          ..append($createParagraphNode());
      }, discrete: true);

      await pumpMedia(tester, editor);

      expect(tester.takeException(), isNull);
      expect(find.byType(LexicalImageView), findsOneWidget);
      expect(find.byType(LexicalEmbedView), findsOneWidget);
      expect(find.text('Eine Unterschrift'), findsOneWidget);
    });

    testWidgets('an image resizes by its handle inside the editable', (
      tester,
    ) async {
      // The image is a WidgetSpan in the middle of a text run, inside a
      // scrollable that has drag recognizers of its own. If the editor won
      // that arena the handle would never see the drag, and resizing would
      // be dead in exactly the place it matters.
      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('davor '))
              ..append(
                $createImageNode(
                  src: transparentPixel,
                  width: 200,
                  height: 100,
                ),
              ),
          );
      }, discrete: true);

      await pumpMedia(tester, editor);

      final image = tester.getRect(find.byType(Image));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: image.center);
      addTearDown(mouse.removePointer);
      await tester.pump();

      final drag = await tester.startGesture(
        image.centerRight - const Offset(2, 0),
      );
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.up();
      // The editable's double-tap recognizer starts a countdown on every
      // pointer down; letting it expire is what keeps the test from ending
      // with a timer still pending.
      await tester.pump(const Duration(milliseconds: 400));

      final width = editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        return paragraph.children.whereType<ImageNode>().single.width;
      });
      expect(width, 260);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow viewport does not overflow', (tester) async {
      // An image wider than the column is the ordinary case, not an edge one.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final editor = createLexicalEditor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()..append(
              $createImageNode(src: transparentPixel, width: 900, height: 600),
            ),
          )
          ..append($createYouTubeNode('dQw4w9WgXcQ'));
      }, discrete: true);

      await pumpMedia(tester, editor);
      expect(tester.takeException(), isNull);
    });
  });
}
