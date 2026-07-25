/// Default command handlers that turn commands into edits.
///
/// **Divergence from upstream, deliberate.** Lexical splits this into
/// `@lexical/plain-text` and `@lexical/rich-text`, a split that exists to keep
/// JavaScript bundles small. Dart tree-shakes unreferenced code, so the split
/// would buy nothing here and would cost something real: `lexical_flutter`
/// would have to depend on a feature package to make a document editable at
/// all, which inverts the layering. Both registrations therefore live in the
/// core, next to the operations they wire.
///
/// Everything registers at [CommandPriority.editor], the lowest level, so an
/// application overrides any of it by registering at
/// [CommandPriority.beforeEditor] and returning `true` — no patching, no fork.
library;

import 'commands.dart';
import 'editor.dart';
import 'nodes/element_node.dart';
import 'nodes/paragraph_node.dart';
import 'nodes/tab_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';
import 'selection_ops.dart';
import 'updates.dart';

/// How deep [indentContentCommand] will nest a block.
///
/// A bound rather than none: indentation is a per-block integer, and a key
/// held down against an unbounded counter is a slow way to produce a document
/// no layout can render.
const int maxIndent = 7;

/// Wires the commands a plain-text editor needs.
///
/// Enter inserts a line break rather than splitting the block, and the
/// formatting commands are left unhandled, so a plugin may claim them.
Unsubscribe registerPlainText(LexicalEditor editor) =>
    _register(editor, richText: false);

/// Wires the commands a rich-text editor needs.
///
/// Adds block splitting, text and block formatting, and indentation on top of
/// the plain-text set.
Unsubscribe registerRichText(LexicalEditor editor) =>
    _register(editor, richText: true);

Unsubscribe _register(LexicalEditor editor, {required bool richText}) {
  final unsubscribes = <Unsubscribe>[];

  void on<P>(LexicalCommand<P> command, bool Function(P payload) handler) {
    unsubscribes.add(
      editor.registerCommand<P>(command, handler, CommandPriority.editor),
    );
  }

  /// Runs [action] against the current range selection.
  ///
  /// No selection means no caret, and inventing one would put text somewhere
  /// the user never pointed at. Returning `false` lets a lower-priority
  /// handler — or nothing at all — deal with it.
  bool withSelection(void Function(RangeSelection selection) action) {
    final selection = $getSelection();
    if (selection is! RangeSelection) return false;
    action(selection);
    return true;
  }

  on<String>(insertTextCommand, (text) {
    if (text.isEmpty) return true;
    return withSelection((selection) => selection.insertText(text));
  });

  on<String>(
    replaceTextCommand,
    (text) => withSelection((selection) => selection.insertText(text)),
  );

  on<void>(
    removeTextCommand,
    (_) => withSelection((selection) => selection.removeText()),
  );

  on<bool>(
    deleteCharacterCommand,
    (backwards) => withSelection(
      (selection) => selection.deleteCharacter(backwards: backwards),
    ),
  );

  on<bool>(
    deleteWordCommand,
    (backwards) => withSelection(
      (selection) => selection.deleteWord(backwards: backwards),
    ),
  );

  on<bool>(
    deleteLineCommand,
    (backwards) => withSelection(
      (selection) => selection.deleteLine(backwards: backwards),
    ),
  );

  on<bool>(
    insertLineBreakCommand,
    (_) => withSelection((selection) => selection.insertLineBreak()),
  );

  on<void>(
    insertTabCommand,
    (_) =>
        withSelection((selection) => selection.insertNodes([$createTabNode()])),
  );

  on<void>(insertParagraphCommand, (_) {
    return withSelection((selection) {
      if (richText) {
        selection.insertParagraph();
      } else {
        // Plain text has one block by definition; Enter stays inside it.
        selection.insertLineBreak();
      }
    });
  });

  on<void>(selectAllCommand, (_) {
    $selectAll();
    return true;
  });

  on<void>(clearEditorCommand, (_) {
    final root = $getRoot();
    root.clear();
    final paragraph = $createParagraphNode();
    root.append(paragraph);
    paragraph.selectStart();
    return true;
  });

  if (richText) {
    on<TextFormat>(
      formatTextCommand,
      (format) => withSelection((selection) => selection.formatText(format)),
    );

    on<ElementFormat>(
      formatElementCommand,
      (format) => withSelection((selection) {
        for (final block in selection.getBlocks()) {
          block.setFormat(format);
        }
      }),
    );

    on<void>(
      indentContentCommand,
      (_) => withSelection((selection) => _shiftIndent(selection, 1)),
    );

    on<void>(
      outdentContentCommand,
      (_) => withSelection((selection) => _shiftIndent(selection, -1)),
    );
  }

  // The document must always contain somewhere to put the caret. Expressing
  // that as a root transform rather than as a check in every handler is what
  // makes it hold no matter how the last block was removed — a delete, a
  // paste, an undo, or a collaborative patch.
  unsubscribes.add(
    editor.registerNodeTransform('root', (node) {
      if (node is ElementNode && node.isEmpty) {
        node.append($createParagraphNode());
      }
    }),
  );

  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

void _shiftIndent(RangeSelection selection, int delta) {
  for (final block in selection.getBlocks()) {
    if (!block.canIndent) continue;
    final next = block.getIndent() + delta;
    if (next < 0 || next > maxIndent) continue;
    block.setIndent(next);
  }
}
