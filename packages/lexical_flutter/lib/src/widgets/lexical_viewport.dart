/// The width the whole document is laid out in.
library;

import 'package:flutter/widgets.dart';

/// Publishes the width available to the whole document.
///
/// A block deep in a layout knows only its own width. Some decisions are
/// about the screen instead — a mail's media query stacks its columns on a
/// phone, however narrow the column holding them already is — and this is
/// where such a block reads it. [LexicalDocument] provides it.
class LexicalViewport extends InheritedWidget {
  /// Publishes [width] to [child].
  const LexicalViewport({required this.width, required super.child, super.key});

  /// The document's width in logical pixels; infinite when unbounded.
  final double width;

  /// The width of the nearest enclosing document, or `null` outside one.
  static double? widthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LexicalViewport>()?.width;

  @override
  bool updateShouldNotify(LexicalViewport oldWidget) =>
      oldWidget.width != width;
}
