/// Editing behaviour inside a code block.
library;

import 'package:lexical_core/lexical_core.dart';

import 'code_node.dart';

/// Makes Enter and Tab behave the way they do in an editor, inside code.
///
/// Enter inserts a newline **into the text** rather than splitting the block,
/// which is both what a code block means and what the wire format says: the
/// canonical Lexical fixture for a code block holds its line breaks inside a
/// single text node. Tab inserts an indent rather than moving focus.
///
/// Registered at [CommandPriority.beforeEditor], and both handlers return
/// `false` outside a code block, so nothing changes anywhere else.
Unsubscribe registerCode(LexicalEditor editor, {String indent = '  '}) {
  final unsubscribes = <Unsubscribe>[
    editor.registerCommand<void>(
      insertParagraphCommand,
      (_) => _insertInCode('\n'),
      CommandPriority.beforeEditor,
    ),
    editor.registerCommand<void>(
      insertTabCommand,
      (_) => _insertInCode(indent),
      CommandPriority.beforeEditor,
    ),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

bool _insertInCode(String text) {
  final selection = $getSelection();
  if (selection is! RangeSelection) return false;
  if (!_insideCode(selection.anchor.getNode())) return false;
  selection.insertText(text);
  return true;
}

bool _insideCode(LexicalNode? node) {
  var current = node;
  while (current != null) {
    if (current is CodeNode) return true;
    current = current.getParent();
  }
  return false;
}
