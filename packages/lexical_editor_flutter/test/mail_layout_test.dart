// A transactional mail rebuilt from layout and block-style nodes, measured
// rather than screenshotted: geometry and colours come from the render tree,
// so the suite asserts the same numbers on every machine.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

const _red = Color(0xFFE60000);

/// Keys of the parts the tests measure.
final class _Mail {
  late NodeKey canvas;
  late NodeKey header;
  late NodeKey stepRow;
  late List<NodeKey> stepColumns;
  late NodeKey image;
  late NodeKey button;
}

ParagraphNode _text(String text, {String style = '', String block = ''}) {
  final paragraph = $createParagraphNode()
    ..append($createTextNode(text)..setStyle(style));
  if (block.isNotEmpty) $setBlockStyle(paragraph, block);
  return paragraph;
}

/// A 600 px centred canvas: red header, one image | text step row, a
/// centred call to action — the shape of an order confirmation.
_Mail _seedMail(LexicalEditor editor) {
  final mail = _Mail();
  editor.update(() {
    final header = _text(
      'Deine Bestellung',
      style: 'color:#ffffff;font-size:28px;font-weight:bold',
      block: 'background-color:#e60000;padding:24px',
    )..setFormat(ElementFormat.center);

    final image = $createImageNode(
      src: 'https://mail.example/step.png',
      altText: 'Schritt',
      width: 160,
      height: 100,
      maxWidth: 600,
    );
    final imageParagraph = $createParagraphNode()
      ..setFormat(ElementFormat.center)
      ..append(image);
    final stepRow = $createLayoutContainerNode('200px 1fr');
    final left = $createLayoutItemNode()..append(imageParagraph);
    final right = $createLayoutItemNode()
      ..append(
        _text(
          'Wir packen dein Paket.',
          style: 'color:#333333;font-size:14px;line-height:20px',
        ),
      );
    $setBlockStyle(left, 'padding:20px');
    $setBlockStyle(right, 'background-color:#f4f4f4;padding:20px');
    stepRow.appendAll([left, right]);

    final button = _text(
      'Sendung verfolgen',
      style: 'color:#ffffff;font-size:16px',
      block:
          'background-color:#e60000;padding:10px 25px;'
          'width:fit-content;margin:0 auto',
    )..setFormat(ElementFormat.center);

    final item = $createLayoutItemNode()..appendAll([header, stepRow, button]);
    final canvas = $createLayoutContainerNode('1fr')..append(item);
    $setBlockStyle(
      canvas,
      'max-width:600px;margin:0 auto;background-color:#ffffff',
    );
    $getRoot()
      ..clear()
      ..append(canvas);

    mail
      ..canvas = canvas.key
      ..header = header.key
      ..stepRow = stepRow.key
      ..stepColumns = [left.key, right.key]
      ..image = image.key
      ..button = button.key;
  }, discrete: true);
  return mail;
}

Future<void> _pumpDocument(
  WidgetTester tester,
  LexicalEditor editor, {
  required double width,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: LexicalDocument(
          editor: editor,
          theme: defaultLexicalTheme(
            baseTextStyle: const TextStyle(fontSize: 14, color: Colors.black),
          ),
          scrollable: false,
          decoratorBuilders: lexicalDecoratorBuilders(
            editor: editor,
            editable: false,
            // Blocked: a mail's remote images are not loaded until the
            // reader allows it, and the placeholder holds their exact size.
            imageResolver: (_) => null,
            imagePlaceholderBuilder: (context, src) =>
                const ColoredBox(color: Color(0xFFDDDDDD)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _node(NodeKey key) =>
    find.byKey(ValueKey<String>('lexical-block-${key.value}'));

/// The block-style box drawn for [key]: the outermost decorated box under it.
Finder _box(NodeKey key) =>
    find.descendant(of: _node(key), matching: find.byType(DecoratedBox)).first;

Color? _fill(WidgetTester tester, NodeKey key) =>
    (tester.widget<DecoratedBox>(_box(key)).decoration as BoxDecoration).color;

void main() {
  testWidgets('a 600 px mail at 800 px: centred, columns, sizes, colours', (
    tester,
  ) async {
    final editor = createLexicalEditor();
    final mail = _seedMail(editor);
    await _pumpDocument(tester, editor, width: 800);

    final canvas = tester.getRect(_box(mail.canvas));
    expect(canvas.width, 600);
    expect(canvas.left, 100, reason: 'centred by its auto margins');
    expect(_fill(tester, mail.canvas), const Color(0xFFFFFFFF));

    final header = tester.getRect(_box(mail.header));
    expect(header.left, canvas.left);
    expect(header.width, 600);
    expect(_fill(tester, mail.header), _red);

    final left = tester.getRect(_node(mail.stepColumns[0]));
    final right = tester.getRect(_node(mail.stepColumns[1]));
    expect(left.width, 200);
    expect(right.width, 400);
    expect(left.left, canvas.left);
    expect(right.left, left.right, reason: 'no gap between columns');
    expect(left.top, right.top);
    expect(left.height, right.height, reason: 'columns share the row height');
    expect(_fill(tester, mail.stepColumns[1]), const Color(0xFFF4F4F4));

    final image = tester.getRect(
      find.descendant(
        of: find.byType(LexicalImageView),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(image.size, const Size(160, 100));
    // Centred in its column by the paragraph's format: 20 px padding each
    // side of a 160 px content box.
    expect(image.left - left.left, 20);

    // As wide as its text plus its padding, and centred: a mail's button.
    final button = tester.getRect(_box(mail.button));
    final label = tester.getRect(
      find.descendant(
        of: _node(mail.button),
        matching: find.byType(LexicalInlineBlock),
      ),
    );
    expect(label.width, greaterThan(0));
    expect(button.width, closeTo(label.width + 50, 0.01));
    expect(button.width, lessThan(600), reason: 'not the canvas width');
    expect(label.left - button.left, 25);
    expect(button.center.dx, closeTo(400, 0.5), reason: 'centred');
    expect(_fill(tester, mail.button), _red);

    final buttonSpan =
        tester
                .widget<LexicalInlineBlock>(
                  find.descendant(
                    of: _node(mail.button),
                    matching: find.byType(LexicalInlineBlock),
                  ),
                )
                .span
            as TextSpan;
    final run = buttonSpan.children!.single as TextSpan;
    expect(run.style?.color, const Color(0xFFFFFFFF));
    expect(run.style?.fontSize, 16);
  });

  testWidgets('at phone width the fixed columns stack', (tester) async {
    final editor = createLexicalEditor();
    final mail = _seedMail(editor);
    await _pumpDocument(tester, editor, width: 180);

    final canvas = tester.getRect(_box(mail.canvas));
    expect(canvas.width, 180);
    final left = tester.getRect(_node(mail.stepColumns[0]));
    final right = tester.getRect(_node(mail.stepColumns[1]));
    expect(left.width, 180);
    expect(right.width, 180);
    expect(right.top, greaterThanOrEqualTo(left.bottom));

    // 180 wide minus 20 px padding each side leaves 140 for a 160 px image:
    // it shrinks, keeping its shape.
    final image = tester.getRect(
      find.descendant(
        of: find.byType(LexicalImageView),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(image.width, 140);
    expect(image.height, closeTo(87.5, 0.01));
  });

  group('editing in columns', () {
    final key = GlobalKey<LexicalEditableState>();

    Future<LexicalEditor> pumpEditable(WidgetTester tester) async {
      final editor = createLexicalEditor();
      registerLexical(editor);
      editor.update(() {
        final row = $createLayoutContainerNode('1fr 1fr')
          ..appendAll([
            $createLayoutItemNode()..append(_text('links')),
            $createLayoutItemNode()..append(_text('rechts')),
          ]);
        $getRoot()
          ..clear()
          ..append(row)
          ..append(_text('danach'));
      }, discrete: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LexicalEditable(
              key: key,
              editor: editor,
              autofocus: true,
              scrollable: false,
              cursorBlinkInterval: Duration.zero,
              theme: defaultLexicalTheme(
                baseTextStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return editor;
    }

    String? caretBlock(LexicalEditor editor) => editor.read(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return null;
      return $getNearestBlock(selection.focus.getNode()!).getTextContent();
    });

    testWidgets('a tap in a column puts the caret there', (tester) async {
      final editor = await pumpEditable(tester);
      final right = key.currentState!.registry.blocks.firstWhere(
        (block) => block.offsets.flatText == 'rechts',
      );
      await tester.tapAt(right.render.localToGlobal(const Offset(10, 6)));
      await tester.pump();
      expect(caretBlock(editor), 'rechts');
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('typing, Enter and arrows inside columns', (tester) async {
      final editor = await pumpEditable(tester);
      editor.update(() {
        final row = $getRoot().getFirstChild()! as LayoutContainerNode;
        final first = row.getFirstChild()! as ElementNode;
        ((first.getFirstChild()! as ElementNode).getFirstChild()! as TextNode)
            .selectEnd();
      }, discrete: true);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      final columns = editor.read(
        () => ($getRoot().getFirstChild()! as LayoutContainerNode).items
            .map((item) => item.childrenSize)
            .toList(),
      );
      expect(columns, [2, 1], reason: 'Enter stays inside the column');

      // From the empty new line at the end of column one, right goes on to
      // the start of column two: reading order.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(caretBlock(editor), 'rechts');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(
        editor.read(() => $getRoot().getFirstChild()!.getTextContent()),
        startsWith('links'),
      );
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as LayoutContainerNode).items
              .map((item) => item.getTextContent())
              .toList(),
        ),
        ['links', 'rechts'],
        reason: 'backspace removed the empty line, not a column',
      );
    });
  });
}
