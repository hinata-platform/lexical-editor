import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

import 'support/harness.dart';

/// A link, defined here rather than imported.
///
/// The interaction layer resolves by **type string**, so this package can make
/// links tappable without depending on `lexical_link` — and this test proves
/// it rather than trusting it.
class _Link extends ElementNode {
  _Link([this._url = 'https://example.org']);

  String _url;

  @override
  String get type => 'link';

  @override
  bool get isInline => true;

  @override
  _Link clone() => _Link(_url);

  @override
  void afterCloneFrom(covariant _Link prev) {
    super.afterCloneFrom(prev);
    _url = prev._url;
  }

  @override
  Map<String, Object?> exportJson() => {...super.exportJson(), 'url': _url};

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final url = json['url'];
    if (url is String) _url = url;
  }
}

/// A token mention, the other shape an interactive node comes in.
class _Mention extends TextNode {
  _Mention([String text = '', this._id = 'u_1']) : super(text, TextMode.token);

  String _id;

  @override
  String get type => 'mention';

  @override
  _Mention clone() => _Mention(getTextContent(), _id);

  @override
  void afterCloneFrom(covariant _Mention prev) {
    super.afterCloneFrom(prev);
    _id = prev._id;
  }

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'mentionId': _id,
  };
}

const Set<String> _types = {'link', 'mention'};

/// `vorher LINK nachher @Ada` in one paragraph.
LexicalEditor _linked() {
  final editor = LexicalEditor(
    nodes: [
      NodeSpec<_Link>(type: 'link', create: _Link.new),
      NodeSpec<_Mention>(type: 'mention', create: _Mention.new),
    ],
  );
  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('vorher '))
          ..append(_Link()..append($createTextNode('LINK')))
          ..append($createTextNode(' nachher '))
          ..append($applyNodeReplacement(_Mention('@Ada'))),
      );
  }, discrete: true);
  return editor;
}

/// The global centre of [text] inside the rendered block.
Offset _centreOf(WidgetTester tester, String text) {
  final block = tester.renderObject<RenderLexicalBlock>(
    find.byType(LexicalInlineBlock),
  );
  final flat = block.text.toPlainText();
  final start = flat.indexOf(text);
  expect(start, isNonNegative, reason: 'no "$text" in "$flat"');
  final boxes = block.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + text.length),
  );
  expect(boxes, isNotEmpty);
  return block.localToGlobal(boxes.first.toRect().center);
}

Future<void> _pumpDocument(
  WidgetTester tester,
  LexicalEditor editor,
  LexicalInteraction interaction,
) => tester.pumpWidget(
  wrap(
    SizedBox(
      width: 600,
      height: 300,
      child: LexicalDocument(
        editor: editor,
        theme: testTheme,
        scrollable: false,
        interaction: interaction,
      ),
    ),
  ),
);

void main() {
  testWidgets('a tap on a link reports the link, not its text', (tester) async {
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(types: _types, onTap: taps.add),
    );
    await tester.pump();

    await tester.tapAt(_centreOf(tester, 'LINK'));
    await tester.pump();

    expect(taps, hasLength(1));
    // The pointer was over a text node; what a caller wants is the link that
    // owns it, resolved by walking up the ancestors.
    expect(taps.single.type, 'link');
    expect(taps.single.text, 'LINK');
    expect(taps.single.json['url'], 'https://example.org');
  });

  testWidgets('a tap on a token reports the token itself', (tester) async {
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(types: _types, onTap: taps.add),
    );
    await tester.pump();

    await tester.tapAt(_centreOf(tester, '@Ada'));
    await tester.pump();

    expect(taps.single.type, 'mention');
    expect(taps.single.json['mentionId'], 'u_1');
  });

  testWidgets('a tap on ordinary text reports nothing', (tester) async {
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(types: _types, onTap: taps.add),
    );
    await tester.pump();

    await tester.tapAt(_centreOf(tester, 'vorher'));
    await tester.pump();
    expect(taps, isEmpty);
  });

  testWidgets('the margin past the last word is not the last node', (
    tester,
  ) async {
    // getPositionForOffset answers with the nearest position however far away
    // the pointer is, so without confirming the hit against the node's own
    // boxes a mention at the end of a line owns the whole margin beside it.
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(types: _types, onTap: taps.add),
    );
    await tester.pump();

    final mention = _centreOf(tester, '@Ada');
    await tester.tapAt(Offset(mention.dx + 220, mention.dy));
    await tester.pump();
    expect(taps, isEmpty);
  });

  testWidgets('hover enters and leaves, once per node', (tester) async {
    final editor = _linked();
    final entered = <String>[];
    final exited = <String>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(
        types: _types,
        onEnter: (hit) => entered.add(hit.text),
        onExit: (hit) => exited.add(hit.text),
      ),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final link = _centreOf(tester, 'LINK');
    await mouse.moveTo(link);
    await tester.pump();
    expect(entered, ['LINK']);
    expect(exited, isEmpty);

    // Moving *within* the same node is not an event: a preview card that is
    // torn down and rebuilt on every mouse move is unusable.
    await mouse.moveTo(link + const Offset(2, 0));
    await tester.pump();
    expect(entered, ['LINK']);

    await mouse.moveTo(_centreOf(tester, '@Ada'));
    await tester.pump();
    expect(exited, ['LINK']);
    expect(entered, ['LINK', '@Ada']);

    await mouse.moveTo(_centreOf(tester, 'vorher'));
    await tester.pump();
    expect(exited, ['LINK', '@Ada']);
  });

  testWidgets('the cursor changes over an interactive node', (tester) async {
    final editor = _linked();
    await _pumpDocument(
      tester,
      editor,
      const LexicalInteraction(types: _types),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(_centreOf(tester, 'vorher'));
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    await mouse.moveTo(_centreOf(tester, 'LINK'));
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('the reported rect can anchor a preview', (tester) async {
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await _pumpDocument(
      tester,
      editor,
      LexicalInteraction(types: _types, onTap: taps.add),
    );
    await tester.pump();

    final centre = _centreOf(tester, 'LINK');
    await tester.tapAt(centre);
    await tester.pump();

    final rect = taps.single.rect;
    expect(rect.contains(centre), isTrue);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  testWidgets('in an editable the caret still moves', (tester) async {
    // Refusing the caret would leave the text inside a link unreachable, which
    // is a worse bug than the one it avoids.
    final editor = _linked();
    final taps = <LexicalNodeHit>[];
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 600,
          height: 300,
          child: LexicalEditable(
            editor: editor,
            theme: testTheme,
            scrollable: false,
            interaction: LexicalInteraction(types: _types, onTap: taps.add),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(_centreOf(tester, 'LINK'));
    // One frame, not a deadline. A single tap used to wait out the double-tap
    // recognizer's timeout before anyone heard about it; the serial recognizer
    // reports each tap with its count instead, so nothing is held back.
    await tester.pump();

    expect(taps, hasLength(1));
    expect(taps.single.type, 'link');
    final selection = editor.read($getSelection);
    expect(selection, isA<RangeSelection>());
    final anchor = (selection! as RangeSelection).anchor;
    expect(
      editor.read(() => $getNodeByKey(anchor.key)?.getTextContent()),
      'LINK',
    );
    // Let the serial recognizer's "is another tap coming?" timer expire.
    await tester.pump(const Duration(milliseconds: 400));
  });
}
