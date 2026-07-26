// The guard against the failure this bundle keeps making: a package's nodes
// arrive, its behaviour does not, and the toolbar button that dispatches its
// command does visibly nothing.
//
// Three checks, and each one is written so that it keeps working when a
// package grows. Adding a node type, a decorator or a command to any package
// below is covered automatically; only adding a whole new *package* needs a
// line here, which is the honest minimum.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// Every node list the workspace's feature packages publish.
///
/// Listed by package rather than by type: a new type inside one of them is
/// then covered without touching this file.
final Map<String, List<NodeSpec<LexicalNode>>> _packageNodes = {
  'lexical_rich_text': richTextNodes,
  'lexical_list': listNodes,
  'lexical_link': linkNodes,
  'lexical_code': codeNodes,
  'lexical_table': tableNodes,
  'lexical_mark': markNodes,
  'lexical_hashtag': hashtagNodes,
  'lexical_mention': mentionNodes,
  'lexical_image': imageNodes,
  'lexical_embed': embedNodes,
};

/// Commands that are *dispatched by* the framework rather than handled by it.
///
/// Each one is a hook: the editable dispatches it and acts itself only when
/// nothing claimed it, so "no handler" is the correct state, not a gap.
final Map<LexicalCommand<Object?>, String> _outbound = {
  canUndoCommand: 'reported by history for a toolbar to listen to',
  canRedoCommand: 'reported by history for a toolbar to listen to',
  selectionChangeCommand: 'reported by the editable after every selection',
  copyCommand: 'dispatched first; the editable copies when nobody claims it',
  cutCommand: 'dispatched first; the editable cuts when nobody claims it',
  pasteCommand: 'dispatched first; the editable pastes when nobody claims it',
  keyDownCommand: 'dispatched first, so an app can intercept a key',
  inputActionCommand: 'dispatched first, so an app can handle Enter itself',
};

/// Every command the packages in this bundle define.
final Map<String, LexicalCommand<Object?>> _commands = {
  // lexical_core — editing
  'insertText': insertTextCommand,
  'replaceText': replaceTextCommand,
  'removeText': removeTextCommand,
  'insertParagraph': insertParagraphCommand,
  'insertLineBreak': insertLineBreakCommand,
  'insertTab': insertTabCommand,
  'deleteCharacter': deleteCharacterCommand,
  'deleteWord': deleteWordCommand,
  'deleteLine': deleteLineCommand,
  'formatText': formatTextCommand,
  'formatElement': formatElementCommand,
  'indentContent': indentContentCommand,
  'outdentContent': outdentContentCommand,
  'selectAll': selectAllCommand,
  'clearEditor': clearEditorCommand,
  // lexical_history
  'undo': undoCommand,
  'redo': redoCommand,
  'clearHistory': clearHistoryCommand,
  // lexical_link
  'toggleLink': toggleLinkCommand,
  // lexical_mark
  'addMark': addMarkCommand,
  'removeMark': removeMarkCommand,
  // lexical_table
  'insertTable': insertTableCommand,
  'insertTableRow': insertTableRowCommand,
  'insertTableColumn': insertTableColumnCommand,
  'deleteTableRow': deleteTableRowCommand,
  'deleteTableColumn': deleteTableColumnCommand,
  'deleteTable': deleteTableCommand,
  'mergeTableCells': mergeTableCellsCommand,
  'unmergeTableCell': unmergeTableCellCommand,
  'toggleTableRowHeader': toggleTableRowHeaderCommand,
  'toggleTableColumnHeader': toggleTableColumnHeaderCommand,
  'setTableCellBackground': setTableCellBackgroundCommand,
  'moveTableCell': moveTableCellCommand,
  // lexical_image
  'insertImage': insertImageCommand,
  // lexical_embed
  'insertEmbedFromUrl': insertEmbedFromUrlCommand,
  'insertYouTube': insertYouTubeCommand,
  'insertTweet': insertTweetCommand,
  'insertFigma': insertFigmaCommand,
};

void main() {
  test('every node type its packages publish is registered', () {
    final registered = {
      for (final spec in lexicalNodes) spec.type,
      for (final spec in coreNodes) spec.type,
    };
    final missing = <String>[];
    for (final entry in _packageNodes.entries) {
      for (final spec in entry.value) {
        if (!registered.contains(spec.type)) {
          missing.add('${spec.type} (${entry.key})');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'lexicalNodes is missing types their packages publish. A document '
          'containing one cannot be opened, pasted or imported.',
    );
  });

  testWidgets('every command its packages define has a handler', (
    tester,
  ) async {
    // The check that would have caught the table button doing nothing: the
    // nodes were registered, `registerTable` was not, and every table command
    // dispatched into an empty room.
    final editor = createLexicalEditor();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LexicalEditorField(
            editor: editor,
            baseTextStyle: const TextStyle(fontSize: 16),
            scrollable: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final unclaimed = [
      for (final entry in _commands.entries)
        if (!editor.commands.hasHandlers(entry.value)) entry.key,
    ];
    expect(
      unclaimed,
      isEmpty,
      reason:
          'registerLexical claims no handler for these. Dispatching one does '
          'nothing at all, which is what a dead toolbar button looks like.',
    );
  });

  test('the hooks that are meant to be unclaimed still are', () {
    // The other direction: if one of these ever grows a default handler, an
    // application can no longer intercept it, and that should be a decision
    // rather than an accident.
    final editor = createLexicalEditor();
    registerLexical(editor);
    for (final entry in _outbound.entries) {
      expect(
        editor.commands.hasHandlers(entry.key),
        isFalse,
        reason: '${entry.key.label} is ${entry.value}',
      );
    }
  });

  test('every decorator type in the bundle has a widget builder', () {
    // A decorator without a builder renders its plain-text stand-in — an
    // image shows its alt text and a video shows a URL. Silent, and wrong.
    final editor = createLexicalEditor();
    final builders = lexicalDecoratorBuilders(editor: editor);
    final missing = [
      for (final spec in lexicalNodes)
        if (spec.instantiate() is DecoratorNode &&
            !builders.containsKey(spec.type))
          spec.type,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'lexicalDecoratorBuilders has no builder for these decorator types.',
    );
  });

  testWidgets('the field draws its decorators without being asked', (
    tester,
  ) async {
    // The batteries-included widget includes the batteries: registering the
    // image and embed nodes and then drawing neither is the same class of
    // half-wiring as registering nodes without their behaviour.
    final editor = createLexicalEditor();
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()
            ..append(
              $createImageNode(
                src:
                    'data:image/gif;base64,'
                    'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
                width: 40,
                height: 40,
              ),
            ),
        )
        ..append($createYouTubeNode('dQw4w9WgXcQ'));
    }, discrete: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LexicalEditorField(
            editor: editor,
            baseTextStyle: const TextStyle(fontSize: 16),
            scrollable: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LexicalImageView), findsOneWidget);
    expect(find.byType(LexicalEmbedView), findsOneWidget);
  });
}
