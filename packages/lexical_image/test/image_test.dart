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
