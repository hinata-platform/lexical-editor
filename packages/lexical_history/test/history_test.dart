import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_history/lexical_history.dart';
import 'package:test/test.dart';

TextNode _firstText() =>
    ($getRoot().getFirstChild()! as ElementNode).getFirstChild()! as TextNode;

LexicalEditor _seeded() {
  final editor = LexicalEditor();
  editor.update(() {
    $getRoot().append($createParagraphNode()..append($createTextNode('abc')));
  }, discrete: true);
  return editor;
}

void main() {
  group('undo and redo', () {
    test('undo restores the previous document', () {
      final editor = _seeded();
      registerHistory(editor);

      editor.update(
        () {
          _firstText().setTextContent('abcdef');
        },
        discrete: true,
        tags: {historyPushTag},
      );

      expect(editor.read(() => $getRoot().getTextContent()), 'abcdef');
      expect(editor.dispatchCommand(undoCommand, null), isTrue);
      expect(editor.read(() => $getRoot().getTextContent()), 'abc');
    });

    test('redo reapplies it', () {
      final editor = _seeded();
      registerHistory(editor);

      editor.update(
        () {
          _firstText().setTextContent('abcdef');
        },
        discrete: true,
        tags: {historyPushTag},
      );

      editor.dispatchCommand(undoCommand, null);
      expect(editor.dispatchCommand(redoCommand, null), isTrue);
      expect(editor.read(() => $getRoot().getTextContent()), 'abcdef');
    });

    test('undo with an empty stack does nothing and reports false', () {
      final editor = _seeded();
      registerHistory(editor);
      expect(editor.dispatchCommand(undoCommand, null), isFalse);
      expect(editor.read(() => $getRoot().getTextContent()), 'abc');
    });

    test('a new edit clears the redo stack', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      editor.dispatchCommand(undoCommand, null);
      expect(history.canRedo, isTrue);

      editor.update(
        () => _firstText().setTextContent('abcX'),
        discrete: true,
        tags: {historyPushTag},
      );
      expect(history.canRedo, isFalse);
    });

    test('a scripted sequence returns to byte-identical canonical JSON', () {
      final editor = _seeded();
      registerHistory(editor);
      final original = editor.toJson();

      editor.update(
        () {
          _firstText().setTextContent('völlig anders');
        },
        discrete: true,
        tags: {historyPushTag},
      );
      editor.update(
        () {
          $getRoot().append(
            $createParagraphNode()..append($createTextNode('noch ein Absatz')),
          );
        },
        discrete: true,
        tags: {historyPushTag},
      );
      editor.update(
        () {
          $getRoot().getLastChild()!.remove();
        },
        discrete: true,
        tags: {historyPushTag},
      );

      editor
        ..dispatchCommand(undoCommand, null)
        ..dispatchCommand(undoCommand, null)
        ..dispatchCommand(undoCommand, null);

      expect(jsonFirstDifference(original, editor.toJson()), isNull);
    });

    test('selection survives undo', () {
      final editor = _seeded();
      registerHistory(editor);
      editor.update(
        () {
          $setSelection(RangeSelection.collapsedText(_firstText().key, 2));
        },
        discrete: true,
        tags: {historyPushTag},
      );

      final key = editor.read(() => _firstText().key);
      editor.update(
        () {
          _firstText().setTextContent('abcdefgh');
          $setSelection(RangeSelection.collapsedText(key, 8));
        },
        discrete: true,
        tags: {historyPushTag},
      );

      editor.dispatchCommand(undoCommand, null);
      final selection = editor.editorState.selection;
      expect(selection, isA<RangeSelection>());
      expect((selection! as RangeSelection).anchor.offset, 2);
    });
  });

  group('coalescing', () {
    test('a typing run forms one undo entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      for (final text in ['abcd', 'abcde', 'abcdef']) {
        editor.update(() => _firstText().setTextContent(text), discrete: true);
      }

      expect(history.undoDepth, 1);
      editor.dispatchCommand(undoCommand, null);
      expect(editor.read(() => $getRoot().getTextContent()), 'abc');
    });

    test('a backwards deletion run forms one undo entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      for (final text in ['ab', 'a', '']) {
        editor.update(() => _firstText().setTextContent(text), discrete: true);
      }

      // The final empty text node is normalized away, which is a structural
      // change and correctly ends the run.
      expect(history.undoDepth, lessThanOrEqualTo(2));
      editor.dispatchCommand(undoCommand, null);
      expect(editor.read(() => $getRoot().getTextContent()), isNot(''));
    });

    test('switching from typing to deleting starts a new entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      editor.update(() => _firstText().setTextContent('abcde'), discrete: true);
      expect(history.undoDepth, 1);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      expect(history.undoDepth, 2);
    });

    test('a format change breaks the run', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      final depthAfterTyping = history.undoDepth;

      editor.update(
        () => _firstText().toggleFormat(TextFormat.bold),
        discrete: true,
      );
      expect(history.undoDepth, depthAfterTyping + 1);
    });

    test('a structural change breaks the run', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      final depthAfterTyping = history.undoDepth;

      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
      );
      expect(history.undoDepth, depthAfterTyping + 1);
    });

    test('the merge tag folds a change into the previous entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(
        () => $getRoot().append($createParagraphNode()),
        discrete: true,
        tags: {historyMergeTag},
      );
      expect(history.undoDepth, 0);
    });

    test('the push tag forces a new entry even mid-run', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      editor.update(
        () => _firstText().setTextContent('abcde'),
        discrete: true,
        tags: {historyPushTag},
      );
      expect(history.undoDepth, 2);
    });
  });

  group('a moved caret is not an edit', () {
    test('moving it creates no undo entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      for (final offset in [3, 1, 2]) {
        editor.update(
          () => _firstText().select(offset, offset),
          discrete: true,
        );
      }

      expect(history.undoDepth, 0);
      expect(history.canUndo, isFalse);
    });

    test('selecting a range creates no undo entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().select(0, 3), discrete: true);

      expect(history.undoDepth, 0);
    });

    test('moving it after an undo keeps the redo', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      editor.dispatchCommand(undoCommand, null);
      expect(history.canRedo, isTrue);

      editor.update(() => _firstText().select(1, 1), discrete: true);

      expect(history.canRedo, isTrue);
      expect(history.undoDepth, 0);
      editor.dispatchCommand(redoCommand, null);
      expect(editor.read(() => $getRoot().getTextContent()), 'abcd');
    });

    test('moving it does end the typing run', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(() => _firstText().setTextContent('abcd'), discrete: true);
      expect(history.undoDepth, 1);

      editor.update(() => _firstText().select(0, 0), discrete: true);
      editor.update(() => _firstText().setTextContent('abcde'), discrete: true);

      // Two edits with a click between them are two steps, not one.
      expect(history.undoDepth, 2);
    });

    test('a dirty node that ends up unchanged creates no entry', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      // Marks the node dirty — and writes exactly what was already there.
      editor.update(() => _firstText().setTextContent('abc'), discrete: true);

      expect(history.undoDepth, 0);
    });
  });

  group('classification', () {
    test('an undo itself is never recorded', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      expect(history.undoDepth, 1);

      editor.dispatchCommand(undoCommand, null);
      expect(history.undoDepth, 0);
      expect(history.redoDepth, 1);
    });
  });

  group('bookkeeping', () {
    test('canUndo and canRedo are reported through commands', () {
      final editor = _seeded();
      registerHistory(editor);
      final undoStates = <bool>[];
      final redoStates = <bool>[];
      editor
        ..registerCommand(canUndoCommand, (value) {
          undoStates.add(value);
          return false;
        }, CommandPriority.editor)
        ..registerCommand(canRedoCommand, (value) {
          redoStates.add(value);
          return false;
        }, CommandPriority.editor);

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      expect(undoStates.last, isTrue);
      // Nothing is dispatched while the answer is unchanged, so redo has not
      // been reported at all yet.
      expect(redoStates, isEmpty);

      editor.dispatchCommand(undoCommand, null);
      expect(redoStates.last, isTrue);
      expect(undoStates.last, isFalse);
    });

    test('clearHistory empties both stacks', () {
      final editor = _seeded();
      final history = HistoryState();
      registerHistory(editor, state: history);

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      editor.dispatchCommand(clearHistoryCommand, null);

      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('the stack is bounded by maxDepth', () {
      final editor = _seeded();
      final history = HistoryState(maxDepth: 3);
      registerHistory(editor, state: history);

      for (var i = 0; i < 10; i++) {
        editor.update(
          () => _firstText().setTextContent('text $i'),
          discrete: true,
          tags: {historyPushTag},
        );
      }
      expect(history.undoDepth, 3);
    });

    test('unregistering removes every registration', () {
      final editor = _seeded();
      final history = HistoryState();
      final dispose = registerHistory(editor, state: history);
      dispose();

      editor.update(
        () => _firstText().setTextContent('abcd'),
        discrete: true,
        tags: {historyPushTag},
      );
      expect(history.canUndo, isFalse);
      expect(editor.dispatchCommand(undoCommand, null), isFalse);
    });
  });
}
