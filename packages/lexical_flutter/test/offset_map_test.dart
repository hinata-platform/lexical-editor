import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

import 'support/harness.dart';

Future<BuiltBlockSpan> _build(WidgetTester tester, LexicalEditor editor) async {
  late BuiltBlockSpan built;
  await tester.pumpWidget(
    wrap(
      Builder(
        builder: (context) {
          built = editor.read(() {
            final block = $getRoot().getFirstChild()! as ElementNode;
            return SpanBuilder(
              theme: testTheme,
              context: context,
            ).buildBlock(block);
          });
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return built;
}

void main() {
  testWidgets('offsets map both ways within one run', (tester) async {
    final editor = editorWithParagraph('Hallo Welt');
    final built = await _build(tester, editor);
    final key = firstText(editor).key;

    expect(built.offsets.flatOffsetFor(key, 0, PointType.text), 0);
    expect(built.offsets.flatOffsetFor(key, 5, PointType.text), 5);
    expect(built.offsets.flatOffsetFor(key, 10, PointType.text), 10);

    expect(built.offsets.pointFor(5), ResolvedPoint(key, 5, PointType.text));
    expect(built.offsets.pointFor(0), ResolvedPoint(key, 0, PointType.text));
    expect(built.offsets.pointFor(10), ResolvedPoint(key, 10, PointType.text));
  });

  testWidgets('an out-of-range offset clamps rather than throwing', (
    tester,
  ) async {
    final editor = editorWithParagraph('kurz');
    final built = await _build(tester, editor);
    final key = firstText(editor).key;

    expect(built.offsets.flatOffsetFor(key, 999, PointType.text), 4);
    expect(built.offsets.pointFor(999).offset, 4);
    expect(built.offsets.pointFor(-5).offset, 0);
  });

  testWidgets('the join between two runs resolves to the earlier one', (
    tester,
  ) async {
    // Ambiguous by construction; resolved as end-of-previous so a caret at a
    // boundary inherits the formatting to its left, as every editor does.
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append(
        $createParagraphNode()
          ..append($createTextNode('AAA'))
          ..append($createTextNode('BBB')..toggleFormat(TextFormat.bold)),
      );
    }, discrete: true);

    final built = await _build(tester, editor);
    final keys = editor.read(
      () => ($getRoot().getFirstChild()! as ElementNode).children
          .map((node) => node.key)
          .toList(),
    );

    expect(
      built.offsets.pointFor(3),
      ResolvedPoint(keys[0], 3, PointType.text),
    );
    expect(
      built.offsets.pointFor(4),
      ResolvedPoint(keys[1], 1, PointType.text),
    );
  });

  testWidgets('a line break resolves to an element point on its parent', (
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

    final built = await _build(tester, editor);
    final blockKey = editor.read(() => $getRoot().getFirstChild()!.key);

    // Offset 4 is just past the break: an element point after child index 1.
    final point = built.offsets.pointFor(4);
    expect(point.type, PointType.element);
    expect(point.key, blockKey);
    expect(point.offset, 2);
  });

  testWidgets('an empty block maps everything to an element point', (
    tester,
  ) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot().append($createParagraphNode());
    }, discrete: true);

    final built = await _build(tester, editor);
    final blockKey = editor.read(() => $getRoot().getFirstChild()!.key);

    expect(built.offsets.length, 0);
    expect(
      built.offsets.pointFor(0),
      ResolvedPoint(blockKey, 0, PointType.element),
    );
  });

  testWidgets('a node from another block is not resolvable here', (
    tester,
  ) async {
    final editor = LexicalEditor();
    editor.update(() {
      $getRoot()
        ..append($createParagraphNode()..append($createTextNode('eins')))
        ..append($createParagraphNode()..append($createTextNode('zwei')));
    }, discrete: true);

    final built = await _build(tester, editor);
    final otherKey = editor.read(
      () => ($getRoot().getLastChild()! as ElementNode).getFirstChild()!.key,
    );

    expect(
      built.offsets.flatOffsetFor(otherKey, 0, PointType.text),
      isNull,
      reason: 'each block owns its own coordinate space',
    );
    expect(built.offsets.contains(otherKey), isFalse);
  });

  testWidgets('unicode offsets count UTF-16 code units', (tester) async {
    const emoji = '\u{1F469}‍\u{1F4BB}';
    final editor = editorWithParagraph('a${emoji}b');
    final built = await _build(tester, editor);
    final key = firstText(editor).key;

    // 1 + 5 + 1 code units; grapheme counting would give 3.
    expect(built.offsets.length, 7);
    expect(built.offsets.flatOffsetFor(key, 6, PointType.text), 6);
  });
}
