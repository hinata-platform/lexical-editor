/// Typed, priority-ordered commands.
///
/// Commands are the extension mechanism that keeps features decoupled from
/// the core: a list plugin claims Tab without the core knowing lists exist,
/// and an application overrides a default by registering at a higher
/// priority rather than by patching.
library;

import 'package:meta/meta.dart';

import 'nodes/element_node.dart';
import 'nodes/text_node.dart';

/// Cancels a registration. Every `register*` returns one.
///
/// Collect them and call them in `dispose()`; a leaked subscription keeps a
/// whole editor state alive.
typedef Unsubscribe = void Function();

/// Handles a dispatched command.
///
/// Return `true` to mark the command handled and stop propagation to lower
/// priorities. Handlers run inside an update, so `$` helpers are available.
typedef CommandHandler<P> = bool Function(P payload);

/// A dispatchable, typed command.
///
/// Identity, not the label, distinguishes commands: two commands with the
/// same label are different commands. The label exists for debugging.
///
/// The type parameter gives genuinely better payload typing than upstream's,
/// because the handler signature is checked at the registration site. Use it
/// — a `dynamic` payload throws away the main advantage of the port.
final class LexicalCommand<P> {
  /// Creates a command labelled [label] carrying a payload of type [P].
  const LexicalCommand(this.label);

  /// Human-readable name, for debugging only.
  final String label;

  @override
  String toString() => 'LexicalCommand($label)';
}

/// Where a handler sits in the dispatch order.
///
/// Dispatch walks from [critical] down to [editor] and stops at the first
/// handler that returns `true`. There are five levels; each `before*` variant
/// shares its level but is inserted at the **front** of it, so `before*`
/// handlers run most-recently-registered first while plain handlers run in
/// registration order.
///
/// Guidance worth following in your own plugins: register defaults at
/// [editor] and overrides at [beforeEditor]. The higher levels exist mostly
/// for observers that watch without handling. A plugin reaching for
/// [critical] is usually working around an ordering bug rather than
/// expressing a real priority.
enum CommandPriority {
  /// Lowest. Where a package's own defaults belong.
  editor(0, before: false),

  /// Runs just before [editor] handlers. Where an override belongs.
  beforeEditor(0, before: true),

  /// Low priority.
  low(1, before: false),

  /// Runs before other [low] handlers.
  beforeLow(1, before: true),

  /// Normal priority.
  normal(2, before: false),

  /// Runs before other [normal] handlers.
  beforeNormal(2, before: true),

  /// High priority.
  high(3, before: false),

  /// Runs before other [high] handlers.
  beforeHigh(3, before: true),

  /// Highest priority.
  critical(4, before: false),

  /// Runs before other [critical] handlers — the very first to see a command.
  beforeCritical(4, before: true);

  const CommandPriority(this.level, {required this.before});

  /// Which of the five dispatch levels this priority belongs to.
  final int level;

  /// Whether registration prepends within the level instead of appending.
  final bool before;

  /// Number of dispatch levels.
  static const int levelCount = 5;
}

abstract class _Entry {
  bool run(Object? payload);
}

class _TypedEntry<P> implements _Entry {
  _TypedEntry(this.handler);

  final CommandHandler<P> handler;

  @override
  bool run(Object? payload) => handler(payload as P);
}

/// Per-editor command handler storage and dispatch.
@internal
final class CommandRegistry {
  final Map<LexicalCommand<Object?>, List<List<_Entry>>> _byCommand =
      <LexicalCommand<Object?>, List<List<_Entry>>>{};

  /// Registers [handler] for [command] at [priority].
  Unsubscribe register<P>(
    LexicalCommand<P> command,
    CommandHandler<P> handler,
    CommandPriority priority,
  ) {
    final levels = _byCommand.putIfAbsent(
      command,
      () => List<List<_Entry>>.generate(
        CommandPriority.levelCount,
        (_) => <_Entry>[],
        growable: false,
      ),
    );
    final entry = _TypedEntry<P>(handler);
    final level = levels[priority.level];
    if (priority.before) {
      level.insert(0, entry);
    } else {
      level.add(entry);
    }
    return () {
      level.remove(entry);
      if (levels.every((level) => level.isEmpty)) {
        _byCommand.remove(command);
      }
    };
  }

  /// Runs handlers for [command] from the highest level down.
  ///
  /// Returns `true` as soon as a handler claims the command.
  bool dispatch<P>(LexicalCommand<P> command, P payload) {
    final levels = _byCommand[command];
    if (levels == null) return false;
    for (var level = CommandPriority.levelCount - 1; level >= 0; level--) {
      final handlers = levels[level];
      if (handlers.isEmpty) continue;
      // Copy: a handler is allowed to unregister itself or its neighbours.
      for (final entry in List<_Entry>.of(handlers)) {
        if (entry.run(payload)) return true;
      }
    }
    return false;
  }

  /// Whether anything is listening for [command].
  bool hasHandlers(LexicalCommand<Object?> command) =>
      _byCommand.containsKey(command);
}

// ---------------------------------------------------------------------------
// Built-in commands
//
// Only the platform-agnostic ones live here. Keyboard and pointer commands
// carry Flutter event types and belong in lexical_flutter, so that the core
// stays free of any Flutter dependency.
// ---------------------------------------------------------------------------

/// Fired after the selection changed.
const LexicalCommand<void> selectionChangeCommand = LexicalCommand(
  'SELECTION_CHANGE',
);

/// Insert plain text at the selection.
const LexicalCommand<String> insertTextCommand = LexicalCommand('INSERT_TEXT');

/// Replace the selected range with text, as one operation.
///
/// Deliberately distinct from delete-then-insert: decomposing a replacement
/// produces two undo entries, runs transforms against an intermediate state
/// that never existed, and breaks IME candidate replacement on CJK.
const LexicalCommand<String> replaceTextCommand = LexicalCommand(
  'REPLACE_TEXT',
);

/// Delete the selection, or one character when it is collapsed.
///
/// The payload is `true` for a backwards delete (backspace).
const LexicalCommand<bool> deleteCharacterCommand = LexicalCommand(
  'DELETE_CHARACTER',
);

/// Delete a word. `true` deletes backwards.
const LexicalCommand<bool> deleteWordCommand = LexicalCommand('DELETE_WORD');

/// Delete to the line boundary. `true` deletes backwards.
const LexicalCommand<bool> deleteLineCommand = LexicalCommand('DELETE_LINE');

/// Remove the selected content without inserting anything.
const LexicalCommand<void> removeTextCommand = LexicalCommand('REMOVE_TEXT');

/// Split the current block, creating a new one.
const LexicalCommand<void> insertParagraphCommand = LexicalCommand(
  'INSERT_PARAGRAPH',
);

/// Insert a hard line break inside the current block.
const LexicalCommand<bool> insertLineBreakCommand = LexicalCommand(
  'INSERT_LINE_BREAK',
);

/// Insert a tab node.
const LexicalCommand<void> insertTabCommand = LexicalCommand('INSERT_TAB');

/// Toggle a text format over the selection.
const LexicalCommand<TextFormat> formatTextCommand = LexicalCommand(
  'FORMAT_TEXT',
);

/// Set block alignment over the selection.
const LexicalCommand<ElementFormat> formatElementCommand = LexicalCommand(
  'FORMAT_ELEMENT',
);

/// Increase the indent of the selected blocks.
const LexicalCommand<void> indentContentCommand = LexicalCommand(
  'INDENT_CONTENT',
);

/// Decrease the indent of the selected blocks.
const LexicalCommand<void> outdentContentCommand = LexicalCommand(
  'OUTDENT_CONTENT',
);

/// Select the whole document.
const LexicalCommand<void> selectAllCommand = LexicalCommand('SELECT_ALL');

/// Empty the document.
const LexicalCommand<void> clearEditorCommand = LexicalCommand('CLEAR_EDITOR');

/// Undo the last change.
const LexicalCommand<void> undoCommand = LexicalCommand('UNDO');

/// Redo the last undone change.
const LexicalCommand<void> redoCommand = LexicalCommand('REDO');

/// Discard the undo and redo stacks.
const LexicalCommand<void> clearHistoryCommand = LexicalCommand(
  'CLEAR_HISTORY',
);

/// Reports whether an undo is available. Dispatched by the history plugin.
const LexicalCommand<bool> canUndoCommand = LexicalCommand('CAN_UNDO');

/// Reports whether a redo is available. Dispatched by the history plugin.
const LexicalCommand<bool> canRedoCommand = LexicalCommand('CAN_REDO');
