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

  testWidgets('a text node is styled by its type, not only by its formats', (
    tester,
  ) async {
    // A mention and a hashtag are TextNode subclasses that look different
    // from ordinary text without carrying a format bit or a style string.
    // Their theme entry has to reach them, or it silently does nothing.
    final editor = LexicalEditor(
      nodes: [NodeSpec<_Badge>(type: 'badge', create: _Badge.new)],
    );
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()
            ..append($createTextNode('normal '))
            ..append($applyNodeReplacement(_Badge('@rebar'))),
        );
    }, discrete: true);

    const theme = LexicalTheme(
      baseTextStyle: TextStyle(fontSize: 14),
      blockStyles: {
        'badge': BlockStyle(textStyle: TextStyle(color: Color(0xFFFF0000))),
      },
    );
    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(theme: theme, context: context).buildBlock(block);
      });
      final spans = (built.span as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.style!.color, isNot(const Color(0xFFFF0000)));
      expect(spans.last.style!.color, const Color(0xFFFF0000));
    });
  });
  testWidgets('a token text node can render as a widget', (tester) async {
    // The chip case: a mention wants padding and a rounded corner, and no
    // TextStyle can express either.
    final editor = LexicalEditor(
      nodes: [NodeSpec<_Badge>(type: 'badge', create: _Badge.new)],
    );
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()
            ..append($createTextNode('hallo '))
            ..append($applyNodeReplacement(_Badge('@Ada Lovelace')))
            ..append($createTextNode('!')),
        );
    }, discrete: true);

    final theme = LexicalTheme(
      baseTextStyle: const TextStyle(fontSize: 14),
      tokenBuilders: {
        'badge': (context, node, style) =>
            Text(node.getTextContent(), style: style),
      },
    );
    await withContext(tester, (context) {
      final built = editor.read(() {
        final block = $getRoot().getFirstChild()! as ElementNode;
        return SpanBuilder(theme: theme, context: context).buildBlock(block);
      });
      expect(built.hasDecorators, isTrue);
      final spans = (built.span as TextSpan).children!;
      expect(spans[1], isA<WidgetSpan>());

      // One flat position for the whole label, and the surrounding text keeps
      // laying out around it.
      expect(built.offsets.flatText, 'hallo ￼!');
      final segment = built.offsets.segments[1];
      expect(segment.flatLength, 1);
      expect(segment.modelLength, '@Ada Lovelace'.length);
      expect(segment.isIdentity, isFalse);

      // The caret can only land on the chip's edges — the same rule token mode
      // enforces in the model. Past its end it addresses the whole label.
      expect(
        built.offsets.pointFor(7),
        ResolvedPoint(segment.key, segment.modelLength, PointType.text),
      );
      // And a model offset anywhere inside the label maps to an edge rather
      // than to some arbitrary point inside a widget.
      expect(built.offsets.flatOffsetFor(segment.key, 0, PointType.text), 6);
      expect(built.offsets.flatOffsetFor(segment.key, 5, PointType.text), 7);
      expect(built.offsets.flatOffsetFor(segment.key, 13, PointType.text), 7);
      expect(built.offsets.segments.last.flatStart, 7);
    });
  });

  testWidgets('a builder for an editable text node is refused', (tester) async {
    // Its widget would occupy one position while the node holds many
    // characters, so every offset after it in the block would be wrong. In
    // debug that is an assertion naming the type; in release the builder is
    // dropped and the node renders as styled text, which loses the least.
    final editor = LexicalEditor(
      nodes: [NodeSpec<_Loose>(type: 'loose', create: _Loose.new)],
    );
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()..append($applyNodeReplacement(_Loose('frei'))),
        );
    }, discrete: true);

    final theme = LexicalTheme(
      baseTextStyle: const TextStyle(fontSize: 14),
      tokenBuilders: {
        'loose': (context, node, style) => const SizedBox.shrink(),
      },
    );
    await withContext(tester, (context) {
      expect(
        () => editor.read(() {
          final block = $getRoot().getFirstChild()! as ElementNode;
          return SpanBuilder(theme: theme, context: context).buildBlock(block);
        }),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            contains('token-mode'),
          ),
        ),
      );
    });
  });
}

/// A text node with its own type, standing in for a mention or a hashtag.
class _Badge extends TextNode {
  _Badge([String text = '']) : super(text, TextMode.token);

  @override
  String get type => 'badge';

  @override
  _Badge clone() => _Badge(getTextContent());
}

/// A typed text node that stayed editable — the case a token builder refuses.
class _Loose extends TextNode {
  _Loose([super.text]);

  @override
  String get type => 'loose';

  @override
  _Loose clone() => _Loose(getTextContent());
}
