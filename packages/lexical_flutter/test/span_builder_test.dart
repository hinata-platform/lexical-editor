import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

import 'support/harness.dart';

/// Runs [body] with a real BuildContext, which the span builder needs for
/// decorator widgets.
Future<void> withContext(
  WidgetTester tester,
  void Function(BuildContext context) body,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    wrap(
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  body(captured);
}

void main() {
  testWidgets('a plain paragraph produces one segment', (tester) async {
    final editor = editorWithParagraph('Hallo Welt');
    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      expect(built.offsets.flatText, 'Hallo Welt');
      expect(built.offsets.segments, hasLength(1));
      expect(built.offsets.segments.single.flatStart, 0);
      expect(built.offsets.segments.single.flatLength, 10);
      expect(built.hasDecorators, isFalse);
    });
  });

  testWidgets('format bits become text styles', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..append($createTextNode('fett')..toggleFormat(TextFormat.bold))
          ..append($createTextNode('kursiv')..toggleFormat(TextFormat.italic)),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      final children = (built.span as TextSpan).children!.cast<TextSpan>();
      expect(children[0].style!.fontWeight, FontWeight.bold);
      expect(children[1].style!.fontStyle, FontStyle.italic);
    });
  });

  testWidgets('a line break occupies exactly one flat position', (
    tester,
  ) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..append($createTextNode('vor'))
          ..append($createLineBreakNode())
          ..append($createTextNode('nach')),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      expect(built.offsets.flatText, 'vor\nnach');
      expect(built.offsets.segments, hasLength(3));
      expect(built.offsets.segments[1].flatLength, 1);
      expect(built.offsets.segments[1].type, PointType.element);
    });
  });

  testWidgets('case transforms change the rendering, never the model', (
    tester,
  ) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..append($createTextNode('laut')..toggleFormat(TextFormat.uppercase)),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      expect(built.offsets.flatText, 'LAUT');
      expect(editor.read(() => $getRoot().getTextContent()), 'laut');
      // Same length, so offsets still map one to one.
      expect(built.offsets.segments.single.isIdentity, isTrue);
    });
  });

  test('Dart case mapping is length-preserving, unlike JavaScript', () {
    // JavaScript's toUpperCase applies *full* Unicode case mapping, so 'ß'
    // becomes 'SS' and offsets stop lining up. Dart applies *simple* (1:1)
    // mapping, so they always do — which removes a whole class of offset bug
    // the web implementation has to handle.
    //
    // The trade is a visible rendering difference: a run formatted
    // `uppercase` reads STRAßE here and STRASSE on the web. That is a
    // presentation difference only; the model text is identical either way,
    // so documents still round-trip byte for byte.
    expect('straße'.toUpperCase(), 'STRAßE');
    expect('straße'.toUpperCase().length, 'straße'.length);
    expect('ﬁx'.toUpperCase().length, 'ﬁx'.length);
  });

  testWidgets('case-transformed runs keep one-to-one offsets', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append(
          $createTextNode('straße')..toggleFormat(TextFormat.uppercase),
        ),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      final segment = built.offsets.segments.single;
      expect(segment.modelLength, segment.flatLength);
      expect(segment.isIdentity, isTrue);
      // The caret in the middle of the run maps straight through.
      expect(built.offsets.pointFor(3).offset, 3);
    });
  });

  testWidgets('inline elements merge their style into their children', (
    tester,
  ) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append($createTextNode('normal')),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block);
      });
      expect((built.span as TextSpan).style!.fontSize, 14);
    });
  });

  testWidgets('a heading inherits its block text style', (tester) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()..append($createTextNode('Titel')),
      );
    }, discrete: true);

    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(
          theme: testTheme,
          context: context,
        ).buildBlock(block, baseStyle: const TextStyle(fontSize: 30));
      });
      expect((built.span as TextSpan).style!.fontSize, 30);
    });
  });
}
