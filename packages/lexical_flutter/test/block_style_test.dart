import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

import 'support/harness.dart';

/// One paragraph per entry: its text and its block style.
LexicalEditor _blocks(List<(String, String)> blocks, {String textStyle = ''}) {
  final editor = LexicalEditor();
  editor.update(() {
    for (final (text, css) in blocks) {
      final paragraph = $createParagraphNode()
        ..append($createTextNode(text)..setStyle(textStyle));
      $setBlockStyle(paragraph, css);
      $getRoot().append(paragraph);
    }
  }, discrete: true);
  return editor;
}

Future<void> _pump(WidgetTester tester, LexicalEditor editor) =>
    tester.pumpWidget(
      wrap(
        SizedBox(
          width: 800,
          height: 600,
          child: LexicalDocument(
            editor: editor,
            theme: testTheme,
            scrollable: false,
          ),
        ),
      ),
    );

Finder _block(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is LexicalInlineBlock && widget.span.toPlainText() == text,
);

/// The decorated box drawn for the block holding [text].
BoxDecoration _decorationOf(WidgetTester tester, String text) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: _block(text), matching: find.byType(DecoratedBox)).first,
  );
  return box.decoration as BoxDecoration;
}

void main() {
  testWidgets('a block draws its fill, border, radius and padding', (
    tester,
  ) async {
    final editor = _blocks([
      (
        'Knopf',
        'background-color:#e60000;padding:10px 25px;'
            'border:2px solid #000;border-radius:6px',
      ),
    ]);
    await _pump(tester, editor);

    final decoration = _decorationOf(tester, 'Knopf');
    expect(decoration.color, const Color(0xFFE60000));
    expect(decoration.borderRadius, BorderRadius.circular(6));

    final box = tester.getRect(
      find.ancestor(of: _block('Knopf'), matching: find.byType(DecoratedBox))
          .first,
    );
    final text = tester.getRect(_block('Knopf'));
    expect(text.left - box.left, 27);
    expect(text.top - box.top, 12);
  });

  testWidgets('max-width with auto margins centres the block', (tester) async {
    final editor = _blocks([
      ('Mitte', 'max-width:600px;margin:0 auto;background-color:#fff'),
      ('Links', 'width:300px;background-color:#fff'),
      ('Halb', 'width:50%;background-color:#fff'),
    ]);
    await _pump(tester, editor);

    Rect boxOf(String text) => tester.getRect(
      find.ancestor(of: _block(text), matching: find.byType(DecoratedBox))
          .first,
    );
    expect(boxOf('Mitte').left, 100);
    expect(boxOf('Mitte').width, 600);
    expect(boxOf('Links').left, 0);
    expect(boxOf('Links').width, 300);
    expect(boxOf('Halb').width, 400);
  });

  testWidgets('a width never pushes past the space available', (
    tester,
  ) async {
    final editor = _blocks([('Breit', 'width:2000px;background-color:#fff')]);
    await _pump(tester, editor);
    expect(
      tester
          .getRect(
            find
                .ancestor(of: _block('Breit'), matching: find.byType(DecoratedBox))
                .first,
          )
          .width,
      800,
    );
  });

  testWidgets('margins replace the theme spacing', (tester) async {
    final editor = _blocks([
      ('Eins', 'margin-bottom:30px'),
      ('Zwei', 'margin-top:5px'),
    ]);
    await _pump(tester, editor);
    final first = tester.getRect(_block('Eins'));
    final second = tester.getRect(_block('Zwei'));
    // 30 below the first; the second keeps its own 5 above, and the theme's
    // spacing (8) under the first is replaced, not added.
    expect(second.top - first.bottom, 35);
  });

  testWidgets('the block colour is the default for its text', (tester) async {
    final editor = _blocks([('Weiß', 'color:#ffffff;background-color:#333')]);
    await _pump(tester, editor);
    final span = tester.widget<LexicalInlineBlock>(_block('Weiß')).span;
    expect(span.style?.color, const Color(0xFFFFFFFF));
  });

  testWidgets('a text style colour still wins over the block colour', (
    tester,
  ) async {
    final editor = _blocks([
      ('Rot', 'color:#ffffff'),
    ], textStyle: 'color:#e60000');
    await _pump(tester, editor);
    final span = tester.widget<LexicalInlineBlock>(_block('Rot')).span;
    final run = (span as TextSpan).children!.single as TextSpan;
    expect(run.style?.color, const Color(0xFFE60000));
  });

  testWidgets('text-transform changes the drawn text, not the document', (
    tester,
  ) async {
    final editor = _blocks([
      ('laut', ''),
    ], textStyle: 'text-transform:uppercase');
    await _pump(tester, editor);
    expect(_block('LAUT'), findsOneWidget);
    expect(editor.read(() => $getRoot().getTextContent()), 'laut');
  });

  testWidgets('junk in a block style draws a plain block', (tester) async {
    final editor = _blocks([
      (
        'Text',
        'padding:-5px;width:auto;border-radius:nope;background:url(x)',
      ),
    ]);
    await _pump(tester, editor);
    expect(tester.takeException(), isNull);
    expect(_block('Text'), findsOneWidget);
  });

  testWidgets('an empty block is one line of its own font', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      final divider = $createParagraphNode()..setTextStyle('font-size:1px');
      $setBlockStyle(divider, 'border-top:1px solid #ccc;margin:0');
      $getRoot().append(divider);
    }, discrete: true);
    await _pump(tester, editor);
    final line = tester.getSize(find.byType(LexicalInlineBlock));
    expect(line.height, lessThan(3));
  });
}
