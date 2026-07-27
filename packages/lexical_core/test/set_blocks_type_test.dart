import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

/// A container: a block whose children are blocks, the way a table or a list
/// is. Enough to stand in for one without pulling those packages into a core
/// test — what matters is the shape, not which package declares it.
class _ContainerNode extends ElementNode {
  _ContainerNode();

  @override
  String get type => 'container';

  @override
  _ContainerNode clone() => _ContainerNode();
}

/// A block that holds a line, so it is convertible.
class _BannerNode extends ElementNode {
  _BannerNode();

  @override
  String get type => 'banner';

  @override
  _BannerNode clone() => _BannerNode();
}

LexicalEditor _editor() => LexicalEditor(
  nodes: [
    NodeSpec<_ContainerNode>(type: 'container', create: _ContainerNode.new),
    NodeSpec<_BannerNode>(type: 'banner', create: _BannerNode.new),
  ],
);

void _seed(LexicalEditor editor, List<String> paragraphs) {
  editor.update(() {
    final root = $getRoot()..clear();
    for (final text in paragraphs) {
      root.append($createParagraphNode()..append($createTextNode(text)));
    }
  }, discrete: true);
}

List<String> _types(LexicalEditor editor) =>
    editor.read(() => $getRoot().children.map((node) => node.type).toList());

List<String> _texts(LexicalEditor editor) => editor.read(
  () => $getRoot().children.map((node) => node.getTextContent()).toList(),
);

/// Puts a caret in the text of the block at [path], descending elements.
void _caretAt(LexicalEditor editor, List<int> path) {
  editor.update(() {
    LexicalNode node = $getRoot();
    for (final index in path) {
      node = (node as ElementNode).getChildAtIndex(index)!;
    }
    (node as TextNode).select(0, 0);
  }, discrete: true);
}

void main() {
  group(r'$isBlock', () {
    test('a block holding a line is one', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      editor.read(() {
        expect($isBlock($getRoot().getFirstChild()), isTrue);
      });
    });

    test('an empty block is one — there is nothing stopping it', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode());
      }, discrete: true);
      editor.read(() {
        expect($isBlock($getRoot().getFirstChild()), isTrue);
      });
    });

    test(
      'a block whose first child is a block is a container, not a block',
      () {
        final editor = _editor();
        editor.update(() {
          $getRoot()
            ..clear()
            ..append(
              _ContainerNode()..append(
                $createParagraphNode()..append($createTextNode('drin')),
              ),
            );
        }, discrete: true);
        editor.read(() {
          expect($isBlock($getRoot().getFirstChild()), isFalse);
        });
      },
    );

    test('the root is not a block, and neither is a text node', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      editor.read(() {
        expect($isBlock($getRoot()), isFalse);
        expect(
          $isBlock(
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild(),
          ),
          isFalse,
        );
        expect($isBlock(null), isFalse);
      });
    });
  });

  group(r'$setBlocksType', () {
    test('a caret converts the block it sits in', () {
      final editor = _editor();
      _seed(editor, ['eins', 'zwei']);
      _caretAt(editor, [0, 0]);

      editor.update(() {
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(_types(editor), ['banner', 'paragraph']);
      expect(_texts(editor), ['eins', 'zwei']);
    });

    test('each selected block becomes its own element', () {
      // The failure this rules out: every selected block flattened into one
      // element, with the text of all of them run together and no boundary
      // left between them.
      final editor = _editor();
      _seed(editor, ['eins', 'zwei', 'drei']);
      editor.update(() {
        final root = $getRoot();
        final first =
            (root.getFirstChild()! as ElementNode).getFirstChild()! as TextNode;
        final last =
            (root.getLastChild()! as ElementNode).getFirstChild()! as TextNode;
        final selection = $createRangeSelection();
        selection.anchor.set(first.key, 0, PointType.text);
        selection.focus.set(last.key, 4, PointType.text);
        $setSelection(selection);
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(_types(editor), ['banner', 'banner', 'banner']);
      expect(_texts(editor), ['eins', 'zwei', 'drei']);
    });

    test('a container is left alone, and its content converts instead', () {
      // The data-loss case: a caret inside a table cell, and a heading button.
      // Rewriting the container would run every cell's text together into one
      // element and drop the rows — with all the words still present, so
      // nothing downstream reports a problem.
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            _ContainerNode()
              ..append($createParagraphNode()..append($createTextNode('a')))
              ..append($createParagraphNode()..append($createTextNode('b'))),
          );
      }, discrete: true);
      _caretAt(editor, [0, 0, 0]);
      final before = _texts(editor);

      editor.update(() {
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(_types(editor), ['container']);
      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).children
              .map((node) => node.type)
              .toList(),
        ),
        ['banner', 'paragraph'],
      );
      // Not a single character moved: the flattening this guards against loses
      // the boundaries, not the words, so only the unchanged text proves it.
      expect(_texts(editor), before);
    });

    test('the children move across untouched', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()
              ..append($createTextNode('vor '))
              ..append($createTextNode('fett')..setFormat(TextFormat.bold.bit))
              ..append($createTextNode(' nach')),
          );
      }, discrete: true);
      _caretAt(editor, [0, 0]);

      editor.update(() {
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).children
              .cast<TextNode>()
              .map((node) => (node.getTextContent(), node.getFormat()))
              .toList(),
        ),
        [('vor ', 0), ('fett', TextFormat.bold.bit), (' nach', 0)],
      );
    });

    test('format and indent survive the conversion', () {
      final editor = _editor();
      _seed(editor, ['eins']);
      editor.update(() {
        ($getRoot().getFirstChild()! as ElementNode).setIndent(2);
      }, discrete: true);
      _caretAt(editor, [0, 0]);

      editor.update(() {
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(
        editor.read(
          () => ($getRoot().getFirstChild()! as ElementNode).getIndent(),
        ),
        2,
      );
    });

    test('a null selection does nothing rather than throwing', () {
      final editor = _editor();
      _seed(editor, ['eins']);

      editor.update(() {
        $setSelection(null);
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(_types(editor), ['paragraph']);
    });

    test('a selection of the root itself does not replace the root', () {
      // `root.replace` throws, and the throw lands inside the caller's update.
      final editor = _editor();
      _seed(editor, ['eins']);

      editor.update(() {
        $getRoot().select();
        $setBlocksType($getSelection(), _BannerNode.new);
      }, discrete: true);

      expect(editor.read(() => $getRoot().type), 'root');
      expect(_texts(editor), ['eins']);
    });
  });
}
