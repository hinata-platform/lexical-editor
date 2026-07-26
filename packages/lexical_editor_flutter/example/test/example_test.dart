import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_editor_flutter_example/brand_header.dart';
import 'package:lexical_editor_flutter_example/main.dart';

/// The editor behind the mounted example page.
LexicalEditor _editorOf(WidgetTester tester) =>
    tester.widget<LexicalEditorField>(find.byType(LexicalEditorField)).editor;

/// Selects [word] wherever it first appears in the document.
Future<void> _select(WidgetTester tester, String word) async {
  _editorOf(tester).update(() {
    for (final block in $getRoot().children.whereType<ElementNode>()) {
      for (final child in block.children.whereType<TextNode>()) {
        final start = child.getTextContent().indexOf(word);
        if (start < 0) continue;
        child.select(start, start + word.length);
        return;
      }
    }
    throw StateError('no "$word" in the document');
  }, discrete: true);
  // The toolbar reads geometry, so it can only appear a frame later.
  await tester.pump();
  await tester.pump();
}

List<LinkNode> _links(WidgetTester tester) => _editorOf(tester).read(
  () => $getRoot().children
      .whereType<ElementNode>()
      .expand((block) => block.children)
      .whereType<LinkNode>()
      .toList(),
);

void main() {
  testWidgets('the example mounts and renders its document as markdown', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('lexical_editor_flutter'), findsOneWidget);
    // The inspector shows the same document the editor holds.
    expect(find.textContaining('# Lexical, on Flutter'), findsOneWidget);
  });

  testWidgets('the floating toolbar follows a selection', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    // Nothing selected, nothing floating. The page toolbar has its own bold
    // button, so count: one before, two while a selection exists.
    expect(find.byIcon(Icons.format_bold), findsOneWidget);

    await _select(tester, 'Type');
    expect(find.byIcon(Icons.format_bold), findsNWidgets(2));

    // And it sits over the selected text, not somewhere on the page.
    final editable = tester.state<LexicalEditableState>(
      find.byType(LexicalEditable),
    );
    final selected = editable.selectionRects.first;
    final toolbar = tester.getRect(find.byIcon(Icons.link));
    expect((toolbar.center.dx - selected.center.dx).abs(), lessThan(220));
    expect(toolbar.bottom, lessThanOrEqualTo(selected.top));

    // Collapsing the selection takes it away again.
    _editorOf(tester).update(() {
      final selection = $getSelection()! as RangeSelection;
      selection.focus.set(
        selection.anchor.key,
        selection.anchor.offset,
        selection.anchor.type,
      );
    }, discrete: true);
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
  });

  testWidgets('the platform cut/copy/paste menu stays away', (tester) async {
    // Two overlays on one gesture: the floating toolbar and the platform's
    // own selection menu, one over the other. The example draws its own, so
    // the built-in one is suppressed.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    tester
        .state<LexicalEditableState>(find.byType(LexicalEditable))
        .showToolbar();
    await tester.pump();

    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    // Ours is still there.
    expect(find.byIcon(Icons.format_bold), findsNWidgets(2));
  });

  testWidgets('its bold button formats the selection', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    await tester.tap(find.byIcon(Icons.format_bold).last);
    await tester.pump();

    final bold = _editorOf(tester).read(() {
      final selection = $getSelection()! as RangeSelection;
      final texts = selection.getNodes().whereType<TextNode>();
      return texts.isNotEmpty &&
          texts.every((node) => node.hasFormat(TextFormat.bold));
    });
    expect(bold, isTrue);
  });

  testWidgets('the link button opens an editor and links the selection', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    await tester.tap(find.byIcon(Icons.link));
    await tester.pump();

    // A field, prefilled with the scheme rather than empty.
    expect(find.widgetWithText(TextField, 'https://'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://lexical.dev');
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    final links = _links(tester);
    expect(links, hasLength(1));
    expect(
      _editorOf(tester).read(() => _links(tester).single.url),
      'https://lexical.dev',
    );
    expect(
      _editorOf(tester).read(() => _links(tester).single.getTextContent()),
      'Type',
    );
  });

  testWidgets('commenting marks the text and opens a thread', (tester) async {
    // A desktop-sized window: below 900 logical pixels the example stacks the
    // panel under the editor, where the default 800x600 test surface leaves
    // the composer off screen.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pump();

    // The document records only the mark; the panel quotes what it covers.
    final ids = _editorOf(tester).read($getMarkIdsAtSelection);
    expect(ids, hasLength(1));
    expect(_editorOf(tester).read(() => $getMarkedText(ids.single)), 'Type');
    expect(find.text('Type'), findsWidgets);

    // Writing the comment does not touch the document.
    final before = _editorOf(tester).toJsonString();
    await tester.enterText(find.byType(TextField).last, 'Should be clearer');
    await tester.tap(find.byIcon(Icons.send).last);
    await tester.pump();
    expect(find.text('Should be clearer'), findsOneWidget);
    expect(_editorOf(tester).toJsonString(), before);

    // A reply joins the same thread.
    await tester.enterText(find.byType(TextField).last, 'Agreed');
    await tester.tap(find.byIcon(Icons.send).last);
    await tester.pump();
    expect(find.text('Should be clearer'), findsOneWidget);
    expect(find.text('Agreed'), findsOneWidget);

    // Resolving takes the mark back out, leaving the text.
    await tester.tap(find.byIcon(Icons.check).last);
    await tester.pump();
    expect(_editorOf(tester).read(() => $getMarkedText(ids.single)), isEmpty);
    expect(
      _editorOf(tester).read(() => $getRoot().getTextContent()),
      contains('Type here'),
    );
  });

  testWidgets('the toolbar button inserts a table', (tester) async {
    // It used to do nothing at all: the bundle registered the table nodes
    // but never their behaviour, so the command found no handler.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    final before = _editorOf(
      tester,
    ).read(() => $getRoot().children.whereType<TableNode>().length);

    await tester.tap(find.byIcon(Icons.grid_on));
    await tester.pump();

    _editorOf(tester).read(() {
      final tables = $getRoot().children.whereType<TableNode>().toList();
      expect(tables, hasLength(before + 1));
      assertTreeIntegrity($getRoot());
    });
  });

  testWidgets('the table bar appears with the caret and edits the table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    // Nothing while the caret is in ordinary text.
    expect(find.text('Table'), findsNothing);

    // Into the first cell of the seeded table.
    _editorOf(tester).update(() {
      final table = $getRoot().children.whereType<TableNode>().first;
      final cell = (table.getFirstChild()! as ElementNode).getFirstChild()!;
      ((cell as ElementNode).getFirstChild()! as ElementNode).selectStart();
    }, discrete: true);
    await tester.pump();

    expect(find.text('Table'), findsOneWidget);

    List<int> shape() => _editorOf(tester).read(() {
      final table = $getRoot().children.whereType<TableNode>().first;
      final rows = table.children.whereType<TableRowNode>().toList();
      return [rows.length, rows.first.children.length];
    });
    expect(shape(), [3, 3]);

    // The bar scrolls: inside the editor's card only the first few buttons
    // are on screen, so each one is brought into view before it is pressed.
    Future<void> press(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
      await tester.tap(find.text(label));
      await tester.pump();
    }

    await press('Row below');
    expect(shape(), [4, 3]);

    await press('Column right');
    expect(shape(), [4, 4]);

    // Deleting the row the caret is in must not lose the selection — the
    // core refuses a selection pointing at nodes that no longer exist.
    await press('Delete row');
    expect(shape(), [3, 4]);
    expect(tester.takeException(), isNull);

    // And deleting the table itself leaves a caret behind.
    await press('Delete table');
    expect(tester.takeException(), isNull);
    expect(find.text('Table'), findsNothing);
  });

  testWidgets('the link editor refuses a script URL', (tester) async {
    // A stored `javascript:` URL is an XSS waiting for a tap. The model keeps
    // what it is given so documents round-trip; refusing belongs here, where
    // the link is created.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    await tester.tap(find.byIcon(Icons.link));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    expect(find.text('Scheme not allowed'), findsOneWidget);
    expect(_links(tester), isEmpty);
  });

  testWidgets('the header carries the mark, and the mark loads', (
    tester,
  ) async {
    // The example is also the published demo, so its header is the first
    // thing a visitor sees. An asset that is declared in the wrong place
    // fails only at runtime — in the browser, as a broken image.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.byType(BrandAppBar), findsOneWidget);
    expect(find.text('lexical_editor_flutter'), findsOneWidget);

    final logo = tester.widget<Image>(
      find.descendant(
        of: find.byType(BrandAppBar),
        matching: find.byType(Image),
      ),
    );
    expect((logo.image as AssetImage).assetName, 'assets/logo.png');
    await tester.runAsync(
      () => (logo.image as AssetImage).obtainKey(ImageConfiguration.empty),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the block menu names the block the caret is in', (tester) async {
    // The toolbar reads the document rather than remembering what was
    // pressed, which is the difference between a toolbar and a row of
    // buttons — and the only way it survives undo.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    void caretIn(String word) {
      _editorOf(tester).update(() {
        for (final block in $getRoot().children.whereType<ElementNode>()) {
          for (final text in block.children.whereType<TextNode>()) {
            if (!text.getTextContent().contains(word)) continue;
            text.selectEnd();
            return;
          }
        }
        throw StateError('no "$word" in the document');
      }, discrete: true);
    }

    caretIn('Lexical, on Flutter');
    await tester.pump();
    expect(find.text('Heading 1'), findsOneWidget);

    caretIn('Type here');
    await tester.pump();
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Heading 1'), findsNothing);
  });

  testWidgets('the block menu turns a paragraph into a list', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await _select(tester, 'Type');

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bullet list').last);
    await tester.pumpAndSettle();

    // The text moved into the item, not beside it: a list holding a bare
    // paragraph is a shape no Lexical client knows what to do with.
    _editorOf(tester).read(() {
      final list = $getRoot().children.whereType<ListNode>().first;
      expect(list.listType, ListType.bullet);
      final item = list.getFirstChild()! as ListItemNode;
      expect(item.getTextContent(), contains('Type here'));
    });
    expect(find.text('Bullet list'), findsOneWidget);
  });

  testWidgets('the sample code block comes up highlighted', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    final blocks = _editorOf(tester).read(
      () => [
        for (final code in $getRoot().children.whereType<CodeNode>())
          (
            code.language,
            code.children
                .whereType<CodeHighlightNode>()
                .map((run) => run.highlightType)
                .whereType<String>()
                .toSet(),
          ),
      ],
    );

    expect(blocks, isNotEmpty, reason: 'the demo lost its code block');
    for (final (language, types) in blocks) {
      expect(
        types,
        containsAll(['keyword', 'function', 'comment']),
        reason: '$language came up with nothing classified',
      );
    }
  });

  testWidgets('the code bar switches the language and the colours follow', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    /// What each run of the first code block is classified as, by its text.
    Map<String, String?> classified() => _editorOf(tester).read(() {
      final code = $getRoot().children.whereType<CodeNode>().first;
      return {
        for (final run in code.children.whereType<CodeHighlightNode>())
          if (run.highlightType != null)
            run.getTextContent(): run.highlightType,
      };
    });

    // Nothing to say until the caret is in a code block.
    expect(find.text('Code'), findsNothing);
    final asDart = classified();

    _editorOf(tester).update(() {
      final code = $getRoot().children.whereType<CodeNode>().first;
      (code.getFirstChild()! as TextNode).selectEnd();
    }, discrete: true);
    await tester.pump();

    expect(find.text('Code'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);

    await tester.tap(find.text('dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('python').last);
    await tester.pumpAndSettle();

    expect(
      _editorOf(
        tester,
      ).read(() => $getRoot().children.whereType<CodeNode>().first.language),
      'python',
    );
    // The same text, read by different rules: `void` is a keyword in Dart and
    // an ordinary word in Python. Nothing is cached and nothing is stale.
    final asPython = classified();
    expect(asDart['void'], 'keyword');
    expect(asPython['void'], isNull);
    expect(asPython, isNotEmpty);
    expect(find.text('python'), findsOneWidget);
  });

  testWidgets('the placeholder shows only while the document is empty', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('Enter some text…'), findsNothing);

    _editorOf(tester).update(() {
      $getRoot()
        ..clear()
        ..append($createParagraphNode());
    }, discrete: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Enter some text…'), findsOneWidget);
  });
}
