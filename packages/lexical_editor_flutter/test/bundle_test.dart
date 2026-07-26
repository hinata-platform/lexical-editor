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
