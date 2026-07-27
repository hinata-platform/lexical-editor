import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_image/lexical_image.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

LexicalEditor _editor() => LexicalEditor(nodes: imageNodes);

MarkdownTransformers get _transformers =>
    defaultMarkdownTransformers.extend(textMatches: [imageTransformer]);

String _toMarkdown(LexicalEditor editor) =>
    editor.read(() => $convertToMarkdown(transformers: _transformers));

void _fromMarkdown(LexicalEditor editor, String source) => editor.update(
  () => $convertFromMarkdown(source, transformers: _transformers),
  discrete: true,
);

void main() {
  test('an image round-trips through markdown', () {
    final editor = _editor();
    _fromMarkdown(editor, '![Ringelblumen](https://example.org/flowers.jpg)');
    expect(
      _toMarkdown(editor),
      '![Ringelblumen](https://example.org/flowers.jpg)',
    );
  });

  test('it lands inside a paragraph, inline with its text', () {
    final editor = _editor();
    _fromMarkdown(editor, 'Davor ![Blume](a.png) danach');

    editor.read(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      expect(paragraph.children.map((node) => node.type), [
        'text',
        'image',
        'text',
      ]);
    });
    expect(_toMarkdown(editor), 'Davor ![Blume](a.png) danach');
  });

  test('the exclamation mark is what keeps it from becoming a link', () {
    // Both rules match this line; the image match starts one character
    // earlier, and the earliest match is the one that wins.
    final editor = _editor();
    _fromMarkdown(editor, '![Blume](a.png)');
    editor.read(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      expect(paragraph.children.single, isA<ImageNode>());
    });
  });

  test('a link is still a link', () {
    final editor = _editor();
    _fromMarkdown(editor, '[Blume](a.png)');
    expect(_toMarkdown(editor), '[Blume](a.png)');
  });

  test('an imported image gets the width upstream gives it', () {
    final editor = _editor();
    _fromMarkdown(editor, '![](a.png)');
    editor.read(() {
      final image =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as ImageNode;
      expect(image.maxWidth, markdownImageMaxWidth);
      expect(image.altText, isEmpty);
    });
  });

  test('size and caption do not survive markdown, and say so plainly', () {
    final editor = _editor();
    editor.update(() {
      final image = $createImageNode(src: 'a.png', altText: 'Blume')
        ..setSize(320, 240)
        ..setCaptionText('Im Juli');
      $getRoot()
        ..clear()
        ..append($createParagraphNode()..append(image));
    }, discrete: true);

    expect(_toMarkdown(editor), '![Blume](a.png)');
  });

  test('an image without the rule exports as nothing, not as a crash', () {
    final editor = _editor();
    _fromMarkdown(editor, '![Blume](a.png)');
    final plain = editor.read(
      () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
    );
    expect(plain, isEmpty);
  });
  test('the width is configurable, and defaults to upstream', () {
    // The reason this is a parameter: an application whose server writes a
    // different number has to agree with it, and the only way to change it
    // used to be copying the rule.
    final editor = _editor();
    editor.update(() {
      $convertFromMarkdown(
        '![x](https://example.org/a.png)',
        transformers: defaultMarkdownTransformers.extend(
          textMatches: [imageMarkdownTransformer(maxWidth: 500)],
        ),
      );
    }, discrete: true);

    expect(
      editor.read(
        () =>
            (($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                    as ImageNode)
                .maxWidth,
      ),
      500,
    );
  });
}
