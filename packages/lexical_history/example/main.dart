// Run it with:  dart run example/main.dart
//
// Undo and redo, and the part that is actually hard: deciding what counts as
// one step. Undoing a whole paragraph because it was typed without pausing is
// as wrong as undoing one letter at a time.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_history/lexical_history.dart';

String text(LexicalEditor editor) =>
    editor.read(() => $getRoot().getTextContent());

/// Types [word] at the end of the document, as a keystroke would.
void type(LexicalEditor editor, String word, {Set<String>? tags}) {
  editor.update(
    () {
      final paragraph = $getRoot().getLastChild()! as ElementNode;
      (paragraph.getLastChild()! as TextNode).selectEnd();
      ($getSelection()! as RangeSelection).insertText(word);
    },
    discrete: true,
    tags: tags,
  );
}

void main() {
  final editor = LexicalEditor();
  registerRichText(editor);
  registerHistory(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode('Hello')));
  }, discrete: true);

  // Typing a run of characters coalesces into one undo step.
  for (final letter in ' world'.split('')) {
    type(editor, letter);
  }
  print('typed:        "${text(editor)}"');

  editor.dispatchCommand(undoCommand, null);
  print('after undo:   "${text(editor)}"');
  print('  — one step, not five: an uninterrupted run is one thing the user');
  print('    did, whatever the keyboard reported.');

  editor.dispatchCommand(redoCommand, null);
  print('after redo:   "${text(editor)}"');

  // A tag forces a boundary. This is how a command that should never merge
  // with the keystroke before it says so.
  type(editor, '!', tags: {historyPushTag});
  type(editor, '?');
  print('\ntyped "!" then "?": "${text(editor)}"');
  editor.dispatchCommand(undoCommand, null);
  print('after undo:   "${text(editor)}"  — the "!" survived its own step');

  // The opposite tag merges a change into the step before it, for an edit the
  // user did not initiate: an autocorrect, a transform, a format normalized.
  type(editor, ' corrected', tags: {historyMergeTag});
  editor.dispatchCommand(undoCommand, null);
  print('after a merged edit and one undo: "${text(editor)}"');

  // Whether undo is available is a question the UI has to answer, so it is
  // published rather than inferred.
  editor.registerCommand<bool>(canUndoCommand, (can) {
    print('  can undo: $can');
    return false;
  }, CommandPriority.editor);
  editor.dispatchCommand(undoCommand, null);
  print('\nback to:      "${text(editor)}"');

  // A collaborator's change never becomes an undo entry of its own, so
  // pressing undo does not walk backwards through someone else's typing.
  type(editor, ' and then', tags: {historyPushTag});
  final depth = editor.read(() => 0); // just to keep the read symmetric
  type(editor, ' von jemand anderem', tags: {collaborationTag});
  print('\nwith a collaborator typing in between: "${text(editor)}"');
  editor.dispatchCommand(undoCommand, null);
  print('after undo: "${text(editor)}"');
  print('  — one press stepped over *this* user\'s " and then", not over the');
  print('    collaborator\'s text, which never had a step of its own.');
  print('  (a snapshot history still cannot undo only the local changes; a');
  print('   collaborative session wants an undo manager scoped to the');
  print('   replicated document instead of this one.) $depth');
}
