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
    await tester.enterText(find.byType(TextField).last, 'Sollte klarer sein');
    await tester.tap(find.byIcon(Icons.send).last);
    await tester.pump();
    expect(find.text('Sollte klarer sein'), findsOneWidget);
    expect(_editorOf(tester).toJsonString(), before);

    // A reply joins the same thread.
    await tester.enterText(find.byType(TextField).last, 'Stimmt');
    await tester.tap(find.byIcon(Icons.send).last);
    await tester.pump();
    expect(find.text('Sollte klarer sein'), findsOneWidget);
    expect(find.text('Stimmt'), findsOneWidget);

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

    await tester.tap(find.text('Row below'));
    await tester.pump();
    expect(shape(), [4, 3]);

    await tester.tap(find.text('Column right'));
    await tester.pump();
    expect(shape(), [4, 4]);

    // Deleting the row the caret is in must not lose the selection — the
    // core refuses a selection pointing at nodes that no longer exist.
    await tester.tap(find.text('Delete row'));
    await tester.pump();
    expect(shape(), [3, 4]);
    expect(tester.takeException(), isNull);

    // And deleting the table itself leaves a caret behind. The bar scrolls;
    // the last button is past the right edge on this surface.
    await tester.ensureVisible(find.text('Delete table'));
    await tester.pump();
    await tester.tap(find.text('Delete table'));
    await tester.pump();
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
}
