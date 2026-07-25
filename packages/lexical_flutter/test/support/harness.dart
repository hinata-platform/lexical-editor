/// Shared setup for the renderer tests.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

/// A deterministic theme: no ambient font, fixed sizes, no platform scaling.
///
/// Golden and layout tests are environment-sensitive, and an inherited style
/// is the usual reason a suite passes on one machine and fails on another.
const LexicalTheme testTheme = LexicalTheme(
  baseTextStyle: TextStyle(
    fontSize: 14,
    height: 1.4,
    color: Color(0xFF000000),
    fontFamily: 'Ahem',
  ),
  blockStyles: {
    'heading': BlockStyle(
      textStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    ),
    'quote': BlockStyle(padding: EdgeInsets.only(left: 12)),
  },
);

/// Wraps [child] in the minimum needed to lay out text.
Widget wrap(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

/// Builds an editor holding one paragraph of [text].
LexicalEditor editorWithParagraph(String text) {
  final editor = LexicalEditor();
  editor.update(() {
    $getRoot().append($createParagraphNode()..append($createTextNode(text)));
  }, discrete: true);
  return editor;
}

/// The first paragraph's first text node, resolved inside a read.
TextNode firstText(LexicalEditor editor) => editor.read(
  () =>
      ($getRoot().getFirstChild()! as ElementNode).getFirstChild()! as TextNode,
);
