import 'dart:convert';
import 'dart:io';

import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_layout/lexical_layout.dart';
import 'package:test/test.dart';

LexicalEditor _editor() {
  final editor = LexicalEditor(nodes: layoutNodes);
  registerRichText(editor);
  registerLayout(editor);
  return editor;
}

Map<String, Object?> _fixture(String name) =>
    jsonDecode(
          File('../lexical_core/test/fixtures/$name.json').readAsStringSync(),
        )
        as Map<String, Object?>;

/// Seeds `[before?] layout(columns…) [after?]`, each column one paragraph
/// holding its text (empty string for an empty paragraph).
void _seed(
  LexicalEditor editor,
  List<String> columns, {
  String template = '1fr 1fr',
  String? before,
  String? after,
}) {
  editor.update(() {
    final container = $createLayoutContainerNode(template);
    for (final text in columns) {
      final paragraph = $createParagraphNode();
      if (text.isNotEmpty) paragraph.append($createTextNode(text));
      container.append($createLayoutItemNode()..append(paragraph));
    }
    final root = $getRoot()..clear();
    if (before != null) {
      root.append($createParagraphNode()..append($createTextNode(before)));
    }
    root.append(container);
    if (after != null) {
      root.append($createParagraphNode()..append($createTextNode(after)));
    }
  }, discrete: true);
}

/// Must be called inside a read or an update.
LayoutContainerNode _container() =>
    $getRoot().children.whereType<LayoutContainerNode>().first;

/// Places the caret in [column]'s first paragraph at [offset].
void _caretIn(LexicalEditor editor, int column, {int? offset}) {
  editor.update(() {
    final item = _container().getChildAtIndex(column)! as LayoutItemNode;
    final paragraph = item.getFirstChild()! as ElementNode;
    final text = paragraph.getFirstChild();
    if (text is TextNode) {
      text.select(offset ?? text.getTextContentSize());
    } else {
      paragraph.selectStart();
    }
  }, discrete: true);
}

/// The column texts, one entry per item, blocks joined by `|`.
List<String> _columns(LexicalEditor editor) => editor.read(
  () => [
    for (final item in _container().items)
      item.children.map((block) => block.getTextContent()).join('|'),
  ],
);

String? _caretColumnText(LexicalEditor editor) => editor.read(() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return null;
  LexicalNode? node = selection.focus.getNode();
  while (node != null && node is! LayoutItemNode) {
    node = node.getParent();
  }
  if (node == null) return null;
  return node.getTextContent();
});

void main() {
  group('wire format', () {
    for (final name in [
      'layout-two-columns',
      'layout-three-columns',
      'layout-nested',
    ]) {
      test('$name is a fixed point', () {
        final json = _fixture(name);
        final editor = LexicalEditor(nodes: layoutNodes);
        final encoded = editor.parseEditorState(json).toJson();
        expect(jsonFirstDifference(json, encoded), isNull);
        final again = editor.parseEditorState(encoded).toJson();
        expect(jsonFirstDifference(encoded, again), isNull);
      });
    }

    test('the nested fixture keeps its block style', () {
      final editor = LexicalEditor(nodes: layoutNodes)
        ..setEditorState(
          LexicalEditor(
            nodes: layoutNodes,
          ).parseEditorState(_fixture('layout-nested')),
        );
      expect(
        editor.read(() => $getBlockStyle($getRoot().getFirstChild()!)),
        'max-width:600px;margin:0 auto',
      );
    });

    test('the container is a shadow root that cannot be empty', () {
      final editor = _editor();
      _seed(editor, ['a', 'b']);
      editor.read(() {
        final container = _container();
        expect(container.isShadowRoot, isTrue);
        expect(container.canBeEmpty, isFalse);
        expect(container.items.first.isShadowRoot, isTrue);
        expect(container.templateColumns, '1fr 1fr');
      });
    });
  });

  group('template columns', () {
    test('parses the supported subset', () {
      expect(parseTemplateColumns('1fr 2fr'), const [
        LayoutTrack(LayoutTrackKind.fraction, 1),
        LayoutTrack(LayoutTrackKind.fraction, 2),
      ]);
      expect(parseTemplateColumns(' 200px  25% auto minmax(0, 120px) '), const [
        LayoutTrack(LayoutTrackKind.pixels, 200),
        LayoutTrack(LayoutTrackKind.percent, 25),
        LayoutTrack(LayoutTrackKind.auto, 0),
        LayoutTrack(LayoutTrackKind.upTo, 120),
      ]);
      expect(parseTemplateColumns(''), isEmpty);
    });

    test('an unknown track reads as 1fr', () {
      expect(parseTemplateColumns('repeat(2, 1fr) 10vw fit-content(4px)'), [
        LayoutTrack.oneFraction,
        LayoutTrack.oneFraction,
        LayoutTrack.oneFraction,
      ]);
    });

    test('is bounded', () {
      expect(
        parseTemplateColumns(List.filled(100, '1fr').join(' ')),
        hasLength(maxLayoutTracks),
      );
      expect(parseTemplateColumns('99999999px').single.value, 10000);
      expect(() => parseTemplateColumns('(' * 5000), returnsNormally);
    });

    test('fractions share what fixed tracks leave', () {
      final tracks = parseTemplateColumns('200px 1fr 3fr');
      expect(resolveTemplateColumns(tracks, 600), [200, 100, 300]);
      expect(
        resolveTemplateColumns(parseTemplateColumns('25% 1fr'), 400),
        [100, 300],
      );
      expect(
        resolveTemplateColumns(parseTemplateColumns('1fr 1fr'), 410, gap: 10),
        [200, 200],
      );
    });

    test('minmax(0, N) grows up to N before fractions', () {
      final tracks = parseTemplateColumns('minmax(0, 100px) 1fr');
      expect(resolveTemplateColumns(tracks, 600), [100, 500]);
      expect(
        resolveTemplateColumns(
          parseTemplateColumns('minmax(0, 100px) minmax(0, 400px)'),
          300,
        ),
        [100, 200],
      );
    });

    test('stacks below the sum of the fixed tracks', () {
      final tracks = parseTemplateColumns('300px 300px');
      expect(minimumTemplateWidth(tracks), 600);
      expect(resolveTemplateColumns(tracks, 600), [300, 300]);
      expect(resolveTemplateColumns(tracks, 390), isNull);
      // Fractions alone never force a stack.
      expect(resolveTemplateColumns(parseTemplateColumns('1fr 1fr'), 10), [
        5,
        5,
      ]);
    });
  });

  group('editing inside a column', () {
    test('Enter splits the paragraph inside its column', () {
      final editor = _editor();
      _seed(editor, ['links', 'rechts']);
      _caretIn(editor, 0, offset: 2);
      editor.dispatchCommand(insertParagraphCommand, null);
      expect(_columns(editor), ['li|nks', 'rechts']);
      expect(_caretColumnText(editor), 'li\n\nnks');
    });

    test('typing lands in the column the caret is in', () {
      final editor = _editor();
      _seed(editor, ['a', 'b']);
      _caretIn(editor, 1);
      editor.dispatchCommand(insertTextCommand, 'c');
      expect(_columns(editor), ['a', 'bc']);
    });

    test('backspace at the start of a column does not merge columns', () {
      final editor = _editor();
      _seed(editor, ['a', 'b']);
      _caretIn(editor, 1, offset: 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_columns(editor), ['a', 'b']);
    });

    test('backspace in an empty second column leaves the layout', () {
      final editor = _editor();
      _seed(editor, ['', ''], before: 'vor', after: 'nach');
      _caretIn(editor, 1);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_columns(editor), ['', '']);
    });

    test('backspace in the empty first column of an empty layout removes it',
        () {
      final editor = _editor();
      _seed(editor, ['', ''], before: 'vor', after: 'nach');
      _caretIn(editor, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph', 'paragraph'],
      );
      // The caret survives the removal on a block that still exists.
      expect(
        editor.read(() {
          final selection = $getSelection()! as RangeSelection;
          return selection.focus.getNode()?.getTextContent();
        }),
        'vor',
      );
    });

    test('backspace in the empty first column keeps a non-empty layout', () {
      final editor = _editor();
      _seed(editor, ['', 'b']);
      _caretIn(editor, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(_columns(editor), ['', 'b']);
    });

    test('a layout alone in the document becomes a paragraph', () {
      final editor = _editor();
      _seed(editor, ['', '']);
      _caretIn(editor, 0);
      editor.dispatchCommand(deleteCharacterCommand, true);
      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph'],
      );
    });

    test('arrows move between columns in reading order', () {
      final editor = _editor();
      _seed(editor, ['ab', 'cd'], before: 'x', after: 'y');
      _caretIn(editor, 0);
      editor.update(() {
        ($getSelection()! as RangeSelection).moveCaret(backwards: false);
      }, discrete: true);
      expect(_caretColumnText(editor), 'cd');
      editor.update(() {
        ($getSelection()! as RangeSelection).moveCaret(backwards: true);
      }, discrete: true);
      expect(_caretColumnText(editor), 'ab');

      _caretIn(editor, 1);
      editor.update(() {
        ($getSelection()! as RangeSelection).moveCaret(backwards: false);
      }, discrete: true);
      expect(
        editor.read(
          () => ($getSelection()! as RangeSelection).focus
              .getNode()
              ?.getTextContent(),
        ),
        'y',
      );
    });
  });

  group('structure', () {
    test('an emptied item gets a paragraph back', () {
      final editor = _editor();
      _seed(editor, ['a', 'b']);
      editor.update(() {
        (_container().getFirstChild()! as ElementNode).clear();
      }, discrete: true);
      expect(
        editor.read(
          () => (_container().getFirstChild()! as ElementNode).children
              .map((n) => n.type)
              .toList(),
        ),
        ['paragraph'],
      );
    });

    test('an item outside a container is unwrapped', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createLayoutItemNode()
              ..append($createParagraphNode()..append($createTextNode('x'))),
          );
      }, discrete: true);
      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph'],
      );
    });

    test('a container holding a non-item is unwrapped', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createLayoutContainerNode('1fr')
              ..append($createParagraphNode()..append($createTextNode('x'))),
          );
      }, discrete: true);
      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph'],
      );
    });

    test('insertLayoutCommand inserts columns and a way out', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('a')));
        ($getRoot().getFirstChild()! as ElementNode).selectEnd();
      }, discrete: true);
      editor.update(() {
        editor.dispatchCommand(insertLayoutCommand, '1fr 1fr 1fr');
      }, discrete: true);
      expect(
        editor.read(() => $getRoot().children.map((n) => n.type).toList()),
        ['paragraph', 'layout-container', 'paragraph'],
      );
      expect(_columns(editor), ['', '', '']);
      expect(_caretColumnText(editor), '');
    });

    test('updateLayoutCommand adds and removes columns', () {
      final editor = _editor();
      _seed(editor, ['a', 'b', 'c'], template: '1fr 1fr 1fr');
      final key = editor.read(() => _container().key);
      editor.update(() {
        editor.dispatchCommand(
          updateLayoutCommand,
          LayoutUpdate(nodeKey: key, template: '1fr 2fr'),
        );
      }, discrete: true);
      expect(_columns(editor), ['a', 'b']);
      editor.update(() {
        editor.dispatchCommand(
          updateLayoutCommand,
          LayoutUpdate(nodeKey: key, template: '1fr 1fr 1fr 1fr'),
        );
      }, discrete: true);
      expect(_columns(editor), ['a', 'b', '', '']);
      expect(editor.read(() => _container().templateColumns), '1fr 1fr 1fr 1fr');
    });
  });
}
