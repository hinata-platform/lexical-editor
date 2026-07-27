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

  testWidgets('each block paints on its own layer', (tester) async {
    // The caret blinks by marking one block needs-paint, twice a second,
    // forever. Without a boundary per block that repaints the whole document
    // — and so does every keystroke. The scrolling path gets these from
    // `ListView`; this is the path that has to ask.
    final editor = _multiParagraph(3);
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 600,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            scrollable: false,
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(LexicalDocument),
        matching: find.byType(RepaintBoundary),
      ),
      findsNWidgets(3),
    );
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

  testWidgets('a token builder puts a real widget in the line', (tester) async {
    // A chip is laid out by the text as a placeholder, so it sits on the same
    // line as the words around it rather than becoming its own block.
    final editor = LexicalEditor(
      nodes: [NodeSpec<_Chip>(type: 'chip', create: _Chip.new)],
    );
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()
            ..append($createTextNode('hallo '))
            ..append($applyNodeReplacement(_Chip('@Ada'))),
        );
    }, discrete: true);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 200,
          child: LexicalDocument(
            editor: editor,
            theme: LexicalTheme(
              baseTextStyle: testTheme.baseTextStyle,
              tokenBuilders: {
                'chip': (context, node, style) => DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFFEEEEEE)),
                  child: Text(node.getTextContent(), style: style),
                ),
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('@Ada'), findsOneWidget);
    final chip = tester.getRect(find.text('@Ada'));
    final block = tester.getRect(find.byType(LexicalInlineBlock));
    expect(chip.left, greaterThan(block.left));
    expect(block.contains(chip.center), isTrue);
  });

  testWidgets('a token builder runs inside a read; its widget does not', (
    tester,
  ) async {
    // The contract, pinned rather than asserted in prose. A builder is called
    // while the document is being read, so it can ask the node anything. The
    // widget it returns is built later, by Flutter, with no editor state
    // around it — so a widget that kept the node instead of its values throws
    // on the first frame. Take what you need in the builder.
    final editor = LexicalEditor(
      nodes: [NodeSpec<_Chip>(type: 'chip', create: _Chip.new)],
    );
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()..append($applyNodeReplacement(_Chip('@Ada'))),
        );
    }, discrete: true);

    bool? readableInBuilder;
    bool? readableInWidget;
    bool canRead(TextNode node) {
      try {
        node.getTextContent();
        return true;
      } on LexicalStateError {
        return false;
      }
    }

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          height: 200,
          child: LexicalDocument(
            editor: editor,
            theme: LexicalTheme(
              baseTextStyle: testTheme.baseTextStyle,
              tokenBuilders: {
                'chip': (context, node, style) {
                  readableInBuilder = canRead(node);
                  return Builder(
                    builder: (context) {
                      readableInWidget = canRead(node);
                      return const SizedBox(width: 10, height: 10);
                    },
                  );
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(readableInBuilder, isTrue);
    expect(readableInWidget, isFalse);
  });
}

/// A token text node standing in for a mention.
class _Chip extends TextNode {
  _Chip([String text = '']) : super(text, TextMode.token);

  @override
  String get type => 'chip';

  @override
  _Chip clone() => _Chip(getTextContent());
}
