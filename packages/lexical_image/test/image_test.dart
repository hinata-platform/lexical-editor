import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_image/lexical_image.dart';

LexicalEditor _editor() => LexicalEditor(nodes: imageNodes);

/// One image, exactly as the Lexical playground writes it.
///
/// Transcribed from `lexical-playground/src/nodes/ImageNode.tsx` rather than
/// generated: `image` is not in any published `@lexical/*` package, so
/// `gen_fixtures.mjs` cannot produce it. Writing it out in full is what makes
/// a drift in either direction visible.
///
/// Note where the image sits. `DecoratorNode.isInline()` is `true` upstream
/// and `ImageNode` does not override it, so the playground's insert wraps the
/// image in a paragraph. `root > image` is not a shape Lexical writes.
const Map<String, Object?> _playgroundImage = <String, Object?>{
  'root': <String, Object?>{
    'children': <Object?>[
      <String, Object?>{
        'children': <Object?>[
          {
            'altText': 'Ringelblumen',
            'caption': {
              'editorState': {
                'root': {
                  'children': [
                    {
                      'children': [
                        {
                          'detail': 0,
                          'format': 0,
                          'mode': 'normal',
                          'style': '',
                          'text': 'Aufgenommen im Juli',
                          'type': 'text',
                          'version': 1,
                        },
                      ],
                      'direction': 'ltr',
                      'format': '',
                      'indent': 0,
                      'type': 'paragraph',
                      'version': 1,
                      'textFormat': 0,
                      'textStyle': '',
                    },
                  ],
                  'direction': 'ltr',
                  'format': '',
                  'indent': 0,
                  'type': 'root',
                  'version': 1,
                },
              },
            },
            'height': 320,
            'maxWidth': 500,
            'showCaption': true,
            'src': 'https://example.org/flowers.jpg',
            'type': 'image',
            'version': 1,
            'width': 480,
          },
        ],
        'direction': null,
        'format': '',
        'indent': 0,
        'type': 'paragraph',
        'version': 1,
        'textFormat': 0,
        'textStyle': '',
      },
    ],
    'direction': null,
    'format': '',
    'indent': 0,
    'type': 'root',
    'version': 1,
  },
};

void main() {
  group('the wire format', () {
    test('a playground image round-trips as a fixed point', () {
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      expect(editor.editorState.toJson(), _playgroundImage);
    });

    test('its fields arrive where they belong', () {
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      editor.read(() {
        final image = _theImage();
        expect(image.src, 'https://example.org/flowers.jpg');
        expect(image.altText, 'Ringelblumen');
        expect(image.width, 480);
        expect(image.height, 320);
        expect(image.maxWidth, 500);
        expect(image.showCaption, isTrue);
        expect(image.captionText, 'Aufgenommen im Juli');
      });
    });

    test('a caption written on the web survives untouched', () {
      // The caption is a nested editor this port cannot edit. Keeping the map
      // verbatim is what lets a formatted caption come back out unchanged —
      // here across an edit to a different field.
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      editor.update(() {
        _theImage().setSize(240, 160);
      }, discrete: true);

      expect(
        _imageJson(editor.editorState.toJson())['caption'],
        _imageJson(_playgroundImage)['caption'],
      );
    });

    test('an unsized image writes zero, the way upstream does', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()..append($createImageNode(src: 'a.png')),
          );
      }, discrete: true);

      final image = _imageJson(editor.editorState.toJson());
      expect(image['width'], 0);
      expect(image['height'], 0);
      expect(image['maxWidth'], 500);
      expect(image['showCaption'], false);
      // Even with no caption the key is present with an empty nested state,
      // because upstream always writes one.
      expect(image['caption'], isA<Map<String, Object?>>());
    });

    test('a hostile size cannot reach the layout', () {
      final editor = _editor();
      final json = <String, Object?>{
        'root': <String, Object?>{
          'children': <Object?>[
            <String, Object?>{
              'altText': '',
              'caption': {'editorState': null},
              'height': -1,
              'maxWidth': 0,
              'showCaption': false,
              'src': 'a.png',
              'type': 'image',
              'version': 1,
              'width': 1e309, // infinity once parsed
            },
          ],
          'direction': null,
          'format': '',
          'indent': 0,
          'type': 'root',
          'version': 1,
        },
      };
      editor.setEditorState(editor.parseEditorState(json));
      editor.read(() {
        final image = $getRoot().getFirstChild()! as ImageNode;
        expect(image.width, 0);
        expect(image.height, 0);
        expect(image.maxWidth, ImageNode.defaultMaxWidth);
      });
    });
  });

  group('editing', () {
    test('inserting puts the image inside the paragraph, as upstream does', () {
      final editor = _editor();
      registerRichText(editor);
      registerImage(editor);
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('davor')));
        ($getRoot().getFirstChild()! as ElementNode).selectEnd();
      }, discrete: true);

      editor.dispatchCommand(
        insertImageCommand,
        const ImageAttributes(src: 'a.png', altText: 'A'),
      );

      editor.read(() {
        final root = $getRoot();
        expect(root.children.map((node) => node.type), ['paragraph']);
        final paragraph = root.getFirstChild()! as ElementNode;
        expect(paragraph.children.map((node) => node.type), ['text', 'image']);
        assertTreeIntegrity(root);
      });
    });

    test('inserting with no selection still lands in a paragraph', () {
      // The caret sits on the root in an empty document, and an inline node
      // there is a tree no other Lexical client writes.
      final editor = _editor();
      registerImage(editor);
      editor.update(() => $getRoot().clear(), discrete: true);

      editor.dispatchCommand(
        insertImageCommand,
        const ImageAttributes(src: 'a.png'),
      );

      editor.read(() {
        final root = $getRoot();
        expect(root.children.map((node) => node.type), ['paragraph']);
        expect(_theImage().src, 'a.png');
        assertTreeIntegrity(root);
      });
    });

    test('editing the caption replaces it with plain text', () {
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      editor.update(() {
        _theImage().setCaptionText('Neu');
      }, discrete: true);

      editor.read(() {
        final image = _theImage();
        expect(image.captionText, 'Neu');
        expect(image.showCaption, isTrue);
      });
      // Still a valid nested editor state, so the web side can read it.
      final restored = _editor();
      final json = editor.editorState.toJson();
      restored.setEditorState(restored.parseEditorState(json));
      expect(restored.editorState.toJson(), json);
    });

    test('removing the caption hides it', () {
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      editor.update(() {
        _theImage().setCaptionText(null);
      }, discrete: true);
      editor.read(() {
        expect(_theImage().showCaption, isFalse);
      });
    });

    test('a gif is an image, not a node of its own', () {
      // Worth pinning: upstream's "GIF" menu entry dispatches the ordinary
      // insert command with a .gif source, and so does this.
      final editor = _editor();
      registerImage(editor);
      editor.update(() => $getRoot().clear(), discrete: true);
      editor.dispatchCommand(
        insertImageCommand,
        const ImageAttributes(src: 'cat-typing.gif', altText: 'Katze'),
      );
      editor.read(() {
        final image = _theImage();
        expect(image.type, 'image');
        expect(image.src, endsWith('.gif'));
      });
    });
  });

  group('resizing', () {
    const limits = ImageSizeLimits(minWidth: 100, maxWidth: 400);

    test('a corner drag keeps the shape', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(40, 0),
        handle: ImageHandle.bottomRight,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.width, 240);
      expect(size.height, 120);
    });

    test('the axis the pointer moved further along wins', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(10, 60),
        handle: ImageHandle.bottomRight,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.height, 160);
      expect(size.width, 320);
    });

    test('an edge drag resizes the other axis with it', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(0, 50),
        handle: ImageHandle.bottom,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.height, 150);
      expect(size.width, 300);
    });

    test('the maximum clamps without distorting', () {
      // Clamping the axes separately would stretch the picture the moment one
      // of them hit the limit.
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(400, 0),
        handle: ImageHandle.right,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.width, 400);
      expect(size.height, 200);
      expect(size.width / size.height, 2);
    });

    test('the minimum clamps without distorting', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(-190, 0),
        handle: ImageHandle.right,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.width, 100);
      expect(size.height, 50);
    });

    test('dragging a left handle grows leftwards', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(-40, 0),
        handle: ImageHandle.left,
        limits: limits,
        aspectRatio: 2,
      );
      expect(size.width, 240);
    });

    test('without an aspect ratio the axes are free', () {
      final size = resizeImage(
        start: const Size(200, 100),
        delta: const Offset(50, 50),
        handle: ImageHandle.bottomRight,
        limits: limits,
      );
      expect(size.width, 250);
      expect(size.height, 150);
    });
  });

  group('resolving a source', () {
    test('http, data and assets resolve', () {
      expect(defaultImageResolver('https://example.org/a.png'), isNotNull);
      expect(defaultImageResolver('bilder/a.png'), isNotNull);
      expect(
        defaultImageResolver('data:image/gif;base64,R0lGODlhAQABAAAAACw='),
        isNotNull,
      );
    });

    test('the same data: URI resolves to the same provider', () {
      // `MemoryImage` compares its bytes by identity and decoding a URI hands
      // back a fresh buffer every time, so a plain one was never `==` to the
      // provider from the previous build. A widget that resolves per build
      // then re-resolved every frame: the image never settled long enough to
      // report a size, and it re-decoded its payload for as long as it was on
      // screen.
      const uri = 'data:image/gif;base64,R0lGODlhAQABAAAAACw=';

      expect(defaultImageResolver(uri), defaultImageResolver(uri));
      expect(
        defaultImageResolver(uri).hashCode,
        defaultImageResolver(uri).hashCode,
      );
      // A different payload is still a different picture.
      expect(
        defaultImageResolver(uri),
        isNot(
          defaultImageResolver(
            'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
          ),
        ),
      );
    });

    test('a file URL does not', () {
      // A document from someone else has no business reading the local disk.
      expect(defaultImageResolver('file:///etc/passwd'), isNull);
      expect(defaultImageResolver(''), isNull);
    });
  });

  group('drawing', () {
    // A 1x1 transparent GIF: real enough to decode, small enough to inline.
    const pixel =
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAAB'
        'AAEAAAIBRAA7';

    Future<void> pump(WidgetTester tester, double width) async {
      final editor = _editor();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: LexicalImageView(
                editor: editor,
                nodeKey: const NodeKey('1'),
                src: pixel,
                width: 900,
                height: 600,
                captionsEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a stored size wider than the column is scaled to fit', (
      tester,
    ) async {
      // The same document opened on a phone: the image was sized on someone
      // else's screen, and it must not push past the edge of this one.
      await pump(tester, 300);
      expect(tester.takeException(), isNull);

      final image = tester.getSize(find.byType(Image));
      expect(image.width, 300);
      // Scaled, not squashed: 900x600 is 3:2, and so is what is drawn.
      expect(image.height, 200);
    });

    testWidgets('an image that was never resized draws at its own size', (
      tester,
    ) async {
      // The node spells "the image's own size" `0`; this widget spells it
      // `null`. Forwarding the node's zero verbatim — which is exactly what
      // the decorator builder does — used to force every freshly inserted
      // image into a 0x0 box: uploaded, stored, exported, and invisible.
      final editor = _editor();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: LexicalImageView(
                editor: editor,
                nodeKey: const NodeKey('1'),
                src: pixel,
                width: 0,
                height: 0,
                captionsEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Asserted on the box rather than on the painted size: a `data:` image
      // decodes asynchronously, so nothing has intrinsic dimensions yet — and
      // the defect is precisely that the box refuses to give it any room to
      // report them in.
      final box = tester.widget<SizedBox>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(SizedBox))
            .first,
      );
      expect(box.width, isNull);
      expect(box.height, isNull);
    });

    testWidgets('an image that was never resized still offers handles', (
      tester,
    ) async {
      // Handles need geometry, and geometry used to mean a *stored* size — so
      // the only image anyone ever wants to resize, a freshly inserted one,
      // was the one image that could not be. The size the image reports is a
      // size too.
      final editor = _editor();
      final stable = MemoryImage(
        base64Decode(pixel.substring(pixel.indexOf(',') + 1)),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: LexicalImageView(
                editor: editor,
                nodeKey: const NodeKey('1'),
                src: pixel,
                width: 0,
                height: 0,
                captionsEnabled: false,
                resolver: (_) => stable,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await precacheImage(stable, tester.element(find.byType(Image)));
      });
      await tester.pumpAndSettle();

      // Hover is what reveals them, the same as for a sized image.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(Image)));
      await tester.pumpAndSettle();

      expect(
        find.byType(MouseRegion, skipOffstage: false),
        findsWidgets,
        reason: 'no handle regions were built',
      );
      expect(
        tester
            .widgetList<MouseRegion>(find.byType(MouseRegion))
            .where(
              (region) =>
                  region.cursor == SystemMouseCursors.resizeUpLeftDownRight,
            ),
        isNotEmpty,
        reason: 'the corner handles are missing',
      );
    });

    testWidgets('a column with room draws the size the document asked for', (
      tester,
    ) async {
      // The default test surface is 800 wide, which the clamp would reach.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, 1000);
      expect(tester.getSize(find.byType(Image)), const Size(900, 600));
    });
  });

  group('an image that is already decoded', () {
    // The state every picture is in from the second time it is shown: the
    // bytes are in the image cache, and the completer hands them to a new
    // listener *synchronously*, inside whatever call added it.
    const marker = ValueKey<String>('placeholder');

    /// A 900x600 picture, decoded before the test starts.
    ///
    /// Made in `setUp` rather than in the test: decoding is real asynchronous
    /// work, and inside `testWidgets` the clock is fake — awaiting it there
    /// hangs the test and trips the framework's own async guard.
    late ui.Image decoded;

    setUp(() async {
      imageCache
        ..clear()
        ..clearLiveImages();
      decoded = await createTestImage(width: 900, height: 600);
    });

    Future<void> pump(
      WidgetTester tester,
      ImageProvider<Object> provider, {
      String altText = '',
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: LexicalImageView(
                editor: _editor(),
                nodeKey: const NodeKey('1'),
                src: 'decoded',
                altText: altText,
                captionsEnabled: false,
                resolver: (_) => provider,
                placeholderBuilder: (context, src) =>
                    const SizedBox(key: marker, width: 8, height: 8),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('draws at its own size, and not the placeholder', (
      tester,
    ) async {
      // Reading the size now happens outside the build, and the picture is
      // already decoded when the listener is attached — so the listener is
      // called *synchronously*, from inside `didChangeDependencies`. That the
      // size still arrives, and that nothing is reported as an image error, is
      // what this pins: a `setState` from the wrong place there is caught by
      // the completer and reported as a failed image, and the picture draws
      // its "could not be loaded" stand-in instead.
      final provider = _DecodedImage(decoded);

      await pump(tester, provider);

      expect(tester.takeException(), isNull);
      expect(find.byKey(marker), findsNothing);
      // The size it reported was adopted, scaled into the column: the listener
      // did its job rather than merely not crashing.
      expect(tester.getSize(find.byType(Image)), const Size(300, 200));
    });

    testWidgets('is listened to once, however often it is rebuilt', (
      tester,
    ) async {
      final provider = _DecodedImage(decoded);

      await pump(tester, provider);
      final settled = provider.completer.listeners;

      for (final altText in ['eins', 'zwei', 'drei', 'vier', 'fünf']) {
        await pump(tester, provider, altText: altText);
      }

      expect(
        provider.completer.listeners,
        settled,
        reason: 'a listener per build is a decoded picture leaked per build',
      );
    });

    testWidgets('that failed is not fetched again on every rebuild', (
      tester,
    ) async {
      // A provider behind an API evicts itself when a request fails — it has
      // to, or one timeout is remembered as "this picture is broken" for the
      // life of the process. Which means that after a failure, resolving it
      // again is a fresh request to the server. In an editor a rebuild is a
      // keystroke, and nothing should ask a server anything per keystroke.
      final provider = _FailingImage();

      await pump(tester, provider);
      expect(provider.loads, 1);
      expect(find.byKey(marker), findsOneWidget);

      for (final altText in ['eins', 'zwei', 'drei', 'vier', 'fünf']) {
        await pump(tester, provider, altText: altText);
      }

      expect(
        provider.loads,
        1,
        reason: 'a rebuild asked the server for the picture all over again',
      );
    });

    testWidgets('that failed is not remembered as broken forever', (
      tester,
    ) async {
      // The other half of what was reported: once one picture had failed,
      // nothing would render again. Flutter's image cache keeps the completer
      // that reported the failure, so every later request for that address is
      // answered with the remembered error instead of a request — for the life
      // of the process, in every document. Closing the page and opening it
      // again has to be enough to try again.
      final provider = _FailingImage();

      await pump(tester, provider);
      expect(provider.loads, 1);
      expect(find.byKey(marker), findsOneWidget);

      // The document is closed, and opened again.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, provider);

      expect(
        provider.loads,
        2,
        reason: 'the failure outlived the reason for it',
      );
    });

    testWidgets('lets go of the picture when it goes away', (tester) async {
      final provider = _DecodedImage(decoded);

      await pump(tester, provider);
      expect(imageCache.liveImageCount, 1);

      await tester.pumpWidget(const SizedBox());

      expect(
        imageCache.liveImageCount,
        0,
        reason: 'a listener that is never removed pins the image in the cache',
      );
      expect(provider.completer.listeners, 0);
    });
  });

  group('dragging a handle', () {
    const pixel =
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAAB'
        'AAEAAAIBRAA7';

    /// An editor holding one 200x100 image, shown by a host that follows it.
    Future<LexicalEditor> pumpImage(WidgetTester tester) async {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createImageNode(src: pixel, width: 200, height: 100)),
          );
      }, discrete: true);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 900, child: _ImageHost(editor: editor)),
          ),
        ),
      );
      await tester.pump();

      // The handles only exist while the pointer is over the image, and the
      // hover has to be established once and kept: adding a second mouse
      // pointer while the first is still there trips the mouse tracker's own
      // assertions.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getRect(find.byType(Image)).center,
      );
      addTearDown(mouse.removePointer);
      await tester.pump();
      return editor;
    }

    /// Drags the image's right-edge handle by [by].
    Future<void> dragRightEdge(WidgetTester tester, Offset by) async {
      final image = tester.getRect(find.byType(Image));
      // Two pixels inside the edge: the dot straddles it, and the half
      // outside is clipped away by the stack.
      final drag = await tester.startGesture(
        image.centerRight - const Offset(2, 0),
      );
      // Two moves rather than one: an origin that is only wrong on the first
      // update would be invisible to a drag that jumps straight to its
      // destination.
      await drag.moveBy(by / 2);
      await tester.pump();
      await drag.moveBy(by / 2);
      await tester.pump();
      await drag.up();
      await tester.pump();
    }

    testWidgets('the right edge follows the pointer', (tester) async {
      // The bug this pins: the origin the distance was measured from used to
      // live in the handle's own `build`, which every update rebuilds. The
      // first update then measured from (0, 0) — the pointer's absolute
      // position — and the image jumped to its widest allowed size at once.
      final editor = await pumpImage(tester);
      await dragRightEdge(tester, const Offset(60, 0));

      expect(_storedWidth(editor), 260);
    });

    testWidgets('dragging back in shrinks it again', (tester) async {
      // The other half of the report: after the first drag, nothing worked.
      final editor = await pumpImage(tester);
      await dragRightEdge(tester, const Offset(60, 0));
      await dragRightEdge(tester, const Offset(-100, 0));

      expect(_storedWidth(editor), 160);
    });

    testWidgets('the document is written once, at the end of the drag', (
      tester,
    ) async {
      // Resizing has to be one undo step, not one per pointer move.
      final editor = await pumpImage(tester);
      var commits = 0;
      final unsubscribe = editor.registerUpdateListener((_) => commits++);
      addTearDown(unsubscribe);

      await dragRightEdge(tester, const Offset(60, 0));

      expect(commits, 1);
    });
  });

  group('dragging a handle with a finger', () {
    const pixel =
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAAB'
        'AAEAAAIBRAA7';

    /// The same 200x100 image, inside something that scrolls — which is where
    /// every document is.
    Future<(LexicalEditor, ScrollController)> pumpScrolled(
      WidgetTester tester,
    ) async {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createImageNode(src: pixel, width: 200, height: 100)),
          );
      }, discrete: true);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              height: 300,
              child: ListView(
                controller: controller,
                children: [
                  _ImageHost(editor: editor),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A finger reveals the handles by tapping the picture; there is no
      // hover to do it.
      await tester.tap(find.byType(Image));
      await tester.pump();
      return (editor, controller);
    }

    testWidgets('resizes the image instead of scrolling the page', (
      tester,
    ) async {
      // What was reported: on a phone an image cannot be dragged at all. A
      // scrollable's vertical drag declares itself after `kTouchSlop` and a
      // pan only after `kPanSlop`, twice as far — so the scroll view won every
      // arena and the handle never started. With a mouse it always worked,
      // because a scroll view does not accept mouse drags at all, which is
      // exactly why this went unnoticed.
      final (editor, controller) = await pumpScrolled(tester);
      final image = tester.getRect(find.byType(Image));

      // A shade inside the corner: a box does not hit-test its own far edge,
      // so the exact bottom-right pixel belongs to nothing.
      final finger = await tester.startGesture(
        image.bottomRight - const Offset(2, 2),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(30, 15));
      await tester.pump();
      await finger.moveBy(const Offset(30, 15));
      await tester.pump();
      await finger.up();
      await tester.pump();

      expect(_storedWidth(editor), 260);
      expect(controller.offset, 0, reason: 'the page scrolled instead');
    });

    testWidgets('takes a touch that misses the dot by a finger width', (
      tester,
    ) async {
      // The dot is 10 logical pixels and sits *centred* on the corner, so half
      // of it — three quarters, at a corner — hangs outside the stack, where
      // nothing is hit-tested at all. What is left is smaller than the error
      // in where a finger thinks it is.
      final (editor, _) = await pumpScrolled(tester);
      final image = tester.getRect(find.byType(Image));

      final finger = await tester.startGesture(
        image.bottomRight - const Offset(12, 12),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(60, 30));
      await tester.pump();
      await finger.up();
      await tester.pump();

      expect(_storedWidth(editor), 260);
    });

    testWidgets('a tap on a handle does not edit the document', (tester) async {
      // A handle claims its pointer the moment it goes down, so a tap arrives
      // as a drag of zero pixels. Writing the size it already has would still
      // be an edit: an undo step and a save, for touching a picture.
      final (editor, _) = await pumpScrolled(tester);
      var commits = 0;
      final unsubscribe = editor.registerUpdateListener((_) => commits++);
      addTearDown(unsubscribe);

      await tester.tapAt(
        tester.getRect(find.byType(Image)).bottomRight - const Offset(2, 2),
      );
      await tester.pump();

      expect(commits, 0);
      expect(_storedWidth(editor), 200);
    });
  });
}

/// The stored width of the one image in [editor].
double _storedWidth(LexicalEditor editor) => editor.read(() {
  final paragraph = $getRoot().getFirstChild()! as ElementNode;
  return (paragraph.getFirstChild()! as ImageNode).width;
});

/// Shows the image in [editor] and follows it, the way a decorator builder
/// does: the node is read here, and the widget is handed values.
class _ImageHost extends StatefulWidget {
  const _ImageHost({required this.editor});

  final LexicalEditor editor;

  @override
  State<_ImageHost> createState() => _ImageHostState();
}

class _ImageHostState extends State<_ImageHost> {
  Unsubscribe? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.editor.registerUpdateListener((_) => setState(() {}));
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.editor.read(() {
    final paragraph = $getRoot().getFirstChild()! as ElementNode;
    final image = paragraph.getFirstChild()! as ImageNode;
    return LexicalImageView(
      editor: widget.editor,
      nodeKey: image.key,
      src: image.src,
      width: image.width == 0 ? null : image.width,
      height: image.height == 0 ? null : image.height,
      captionsEnabled: false,
    );
  });
}

/// A picture that is decoded before anyone asks for it.
///
/// Not a contrivance: it is what the image cache holds for every address that
/// has been shown once, and the second showing is where the bug lived.
class _DecodedImage extends ImageProvider<_DecodedImage> {
  _DecodedImage(this.image);

  final ui.Image image;

  late final _CountingCompleter completer = _CountingCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
  );

  @override
  Future<_DecodedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DecodedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _DecodedImage key,
    ImageDecoderCallback decode,
  ) => completer;
}

/// A picture whose request fails, and which does nothing about it.
///
/// Shaped after `NetworkImage`: it leaves the failure in the image cache,
/// which is where "this picture is broken until the app restarts" comes from.
class _FailingImage extends ImageProvider<_FailingImage> {
  /// How many times the bytes have been asked for.
  int loads = 0;

  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(StateError('the request failed')),
    );
  }
}

/// Counts what is listening to it, which is the leak made visible.
class _CountingCompleter extends OneFrameImageStreamCompleter {
  _CountingCompleter(super.image);

  int listeners = 0;

  @override
  void addListener(ImageStreamListener listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners--;
    super.removeListener(listener);
  }
}

/// The one image node in the document, wherever it sits. Read scope only.
ImageNode _theImage() {
  ImageNode? found;
  void visit(LexicalNode node) {
    if (node is ImageNode) found ??= node;
    if (node is ElementNode) node.children.forEach(visit);
  }

  visit($getRoot());
  return found!;
}

/// The one image node inside a serialized document, wherever it sits.
Map<String, Object?> _imageJson(Map<String, Object?> document) {
  Map<String, Object?>? find(Map<String, Object?> node) {
    if (node['type'] == 'image') return node;
    final children = node['children'];
    if (children is! List) return null;
    for (final child in children) {
      if (child is Map<String, Object?>) {
        final hit = find(child);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  return find(document['root']! as Map<String, Object?>)!;
}
