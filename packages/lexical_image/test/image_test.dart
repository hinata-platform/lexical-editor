import 'dart:ui';

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
const Map<String, Object?> _playgroundImage = <String, Object?>{
  'root': <String, Object?>{
    'children': <Object?>[
      <String, Object?>{
        'children': <Object?>[],
        'direction': null,
        'format': '',
        'indent': 0,
        'type': 'paragraph',
        'version': 1,
        'textFormat': 0,
        'textStyle': '',
      },
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
        final image = $getRoot().getLastChild()! as ImageNode;
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
        ($getRoot().getLastChild()! as ImageNode).setSize(240, 160);
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
          ..append($createImageNode(src: 'a.png'));
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
    test('inserting puts the image in its own block, with a way out', () {
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

      final types = editor.read(
        () => $getRoot().children.map((node) => node.type).toList(),
      );
      // An image at the end with nothing after it is a trap: no block below
      // would take the caret.
      expect(types, ['paragraph', 'image', 'paragraph']);
      editor.read(() => assertTreeIntegrity($getRoot()));
    });

    test('editing the caption replaces it with plain text', () {
      final editor = _editor();
      editor.setEditorState(editor.parseEditorState(_playgroundImage));
      editor.update(() {
        ($getRoot().getLastChild()! as ImageNode).setCaptionText('Neu');
      }, discrete: true);

      editor.read(() {
        final image = $getRoot().getLastChild()! as ImageNode;
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
        ($getRoot().getLastChild()! as ImageNode).setCaptionText(null);
      }, discrete: true);
      editor.read(() {
        expect(($getRoot().getLastChild()! as ImageNode).showCaption, isFalse);
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
        final image = $getRoot().children.whereType<ImageNode>().single;
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
}

/// The one image node inside a serialized document.
Map<String, Object?> _imageJson(Map<String, Object?> document) {
  final root = document['root']! as Map<String, Object?>;
  final children = (root['children']! as List).cast<Map<String, Object?>>();
  return children.firstWhere((child) => child['type'] == 'image');
}
