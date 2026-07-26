/// Reaching the editor that is drawing the document around you.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

/// Makes the [LexicalEditor] rendering a document available to its subtree.
///
/// Published by `LexicalDocument`, so anything drawn *inside* a document —
/// a decorator widget, a block layout, an application's own overlay — can
/// reach the editor without being handed it through every constructor.
///
/// ```dart
/// final editor = LexicalEditorScope.of(context);
/// ```
///
/// The editor is the identity of the document being drawn, not a value that
/// changes as it is edited: reading it does **not** make a widget follow the
/// document. Use `LexicalBuilder` for that.
class LexicalEditorScope extends InheritedWidget {
  /// Provides [editor] to [child].
  const LexicalEditorScope({
    required this.editor,
    required super.child,
    super.key,
  });

  /// The editor drawing the enclosing document.
  final LexicalEditor editor;

  /// The enclosing editor, or `null` outside a document.
  static LexicalEditor? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LexicalEditorScope>()?.editor;

  /// The enclosing editor.
  ///
  /// Throws when there is none, because a widget that needs the editor and is
  /// drawn outside a document is misplaced rather than unlucky.
  static LexicalEditor of(BuildContext context) {
    final editor = maybeOf(context);
    if (editor == null) {
      throw FlutterError(
        'LexicalEditorScope.of() was called outside a LexicalDocument.\n'
        'Widgets that need the editor must be drawn inside the document '
        'that renders them — a decorator builder or a block layout is.',
      );
    }
    return editor;
  }

  @override
  bool updateShouldNotify(LexicalEditorScope oldWidget) =>
      !identical(oldWidget.editor, editor);
}
