import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

import 'support/harness.dart';

LexicalEditor _multiParagraph(int count) {
  final editor = LexicalEditor();
  editor.update(() {
    for (var i = 0; i < count; i++) {
      $getRoot().append(
        $createParagraphNode()..append($createTextNode('Absatz $i')),
      );
    }
  }, discrete: true);
  return editor;
}

void main() {
  testWidgets('renders every top-level block', (tester) async {
    final editor = _multiParagraph(3);
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(editor: editor, theme: testTheme),
        ),
      ),
    );
    expect(find.byType(LexicalInlineBlock), findsNWidgets(3));
  });

  testWidgets('an edit rebuilds exactly one block', (tester) async {
    // The reconciler's whole purpose, asserted on the dirty-set path rather
    // than eyeballed in a profile.
    final editor = _multiParagraph(5);
    final stats = LexicalRenderStats();
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            stats: stats,
          ),
        ),
      ),
    );
    expect(stats.blocksBuilt, 5);

    stats.reset();
    editor.update(() {
      final third = $getRoot().getChildAtIndex(2)! as ElementNode;
      (third.getFirstChild()! as TextNode).setTextContent('geändert');
    }, discrete: true);
    await tester.pump();

    expect(
      stats.blocksBuilt,
      1,
      reason: 'only the edited block may be rebuilt',
    );
    expect(stats.blocksReused, 4);
  });

  testWidgets('untouched blocks are reused across unrelated commits', (
    tester,
  ) async {
    final editor = _multiParagraph(4);
    final stats = LexicalRenderStats();
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            stats: stats,
          ),
        ),
      ),
    );

    stats.reset();
    editor.update(() {
      $getRoot().append($createParagraphNode()..append($createTextNode('neu')));
    }, discrete: true);
    await tester.pump();

    // Two, not one: appending rewrites the previous last child's `next`
    // pointer, which clones it and gives it a new identity. That node really
    // did change, so rebuilding it is correct rather than wasteful — and the
    // other three are still reused by reference.
    expect(stats.blocksBuilt, 2);
    expect(stats.blocksReused, 3);
  });

  testWidgets('replacing the state rebuilds everything', (tester) async {
    final editor = _multiParagraph(3);
    final stats = LexicalRenderStats();
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            stats: stats,
          ),
        ),
      ),
    );

    stats.reset();
    final replacement = editor.parseEditorState(editor.toJson());
    editor.setEditorState(replacement);
    await tester.pump();

    expect(stats.blocksReused, 0, reason: 'nothing was diffed');
    expect(stats.blocksBuilt, 3);
  });

  testWidgets('a long document only builds what the viewport needs', (
    tester,
  ) async {
    final editor = _multiParagraph(2000);
    final stats = LexicalRenderStats();
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            stats: stats,
          ),
        ),
      ),
    );
    expect(
      stats.blocksBuilt,
      lessThan(100),
      reason: 'off-screen blocks must not be built',
    );
  });

  testWidgets('nested blocks recurse instead of flattening', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      final outer = $createParagraphNode();
      final inner = $createParagraphNode()..append($createTextNode('innen'));
      outer.append(inner);
      $getRoot().append(outer);
    }, discrete: true);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(editor: editor, theme: testTheme),
        ),
      ),
    );
    expect(find.byType(LexicalInlineBlock), findsOneWidget);
  });

  testWidgets('rtl blocks lay out right to left', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..setDirection(NodeDirection.rtl)
          ..append($createTextNode('سلاو دنیا')),
      );
    }, discrete: true);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 200,
          child: LexicalDocument(editor: editor, theme: testTheme),
        ),
      ),
    );

    final block = tester.widget<LexicalInlineBlock>(
      find.byType(LexicalInlineBlock),
    );
    expect(block.textDirection, TextDirection.rtl);
  });

  testWidgets('block alignment maps onto TextAlign', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot()
        ..append(
          $createParagraphNode()
            ..setFormat(ElementFormat.center)
            ..append($createTextNode('mittig')),
        )
        ..append(
          $createParagraphNode()
            ..setFormat(ElementFormat.end)
            ..append($createTextNode('logisch')),
        );
    }, discrete: true);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 400,
          child: LexicalDocument(editor: editor, theme: testTheme),
        ),
      ),
    );

    final blocks = tester
        .widgetList<LexicalInlineBlock>(find.byType(LexicalInlineBlock))
        .toList();
    expect(blocks[0].textAlign, TextAlign.center);
    expect(
      blocks[1].textAlign,
      TextAlign.end,
      reason: 'start and end are logical and resolve at render time',
    );
  });

  testWidgets('mounted blocks are discoverable for selection', (tester) async {
    final editor = _multiParagraph(2);
    final key = GlobalKey<LexicalDocumentState>();
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(key: key, editor: editor, theme: testTheme),
        ),
      ),
    );
    await tester.pump();

    final registry = key.currentState!.registry;
    expect(registry.blocks, hasLength(2));
    final textKey = editor.read(
      () => (($getRoot().getFirstChild()! as ElementNode).getFirstChild()!).key,
    );
    expect(registry.blockContaining(textKey), isNotNull);
  });

  testWidgets('an empty paragraph still occupies a line', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append($createParagraphNode());
    }, discrete: true);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 200,
          child: LexicalDocument(editor: editor, theme: testTheme),
        ),
      ),
    );

    final render = tester.renderObject<RenderLexicalBlock>(
      find.byType(LexicalInlineBlock),
    );
    expect(render.size.height, greaterThan(0));
  });
}
