/// The platform input-method connection and the delta-to-command mapping.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lexical_core/lexical_core.dart';

import 'editing_window.dart';

/// Marks an update that came from the platform input method.
///
/// Listeners can tell typing apart from a programmatic edit without guessing,
/// which matters for anything that should not react to the user's own
/// keystrokes — a collaboration layer echoing back, say.
const String imeUpdateTag = 'ime';

/// Fired when the platform requests an editing action Flutter models as an
/// input action rather than as text — the return key on a single-line field,
/// for instance.
const LexicalCommand<TextInputAction> inputActionCommand = LexicalCommand(
  'INPUT_ACTION',
);

/// Owns the platform text-input connection for one editor.
///
/// Three rules shape everything here, and each of them fixes a class of bug
/// that is otherwise found only on a device:
///
/// 1. **A replacement is one command.** `TextEditingDeltaReplacement` maps to
///    a single replace, never to a delete followed by an insert. Splitting it
///    produces two undo entries and breaks CJK candidate replacement.
/// 2. **The model is authoritative about the caret.** After a text-changing
///    delta the model places the caret and the corrected value is pushed
///    back, rather than trusting the platform's guess. It is the only way
///    atomic tokens can work: the platform thinks one character went, the
///    model removed a whole mention, and the platform has to be told.
/// 3. **The composing region never enters the editor state.** It is a
///    presentational hint about text that is already in the document, so it
///    lives here and is read by the renderer for its underline.
class LexicalInput implements DeltaTextInputClient {
  /// Creates an input connection for [editor].
  LexicalInput({
    required this.editor,
    this.windowRadius = defaultWindowRadius,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableIMEPersonalizedLearning = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.keyboardAppearance = Brightness.light,
    this.readOnly = false,
    this.onComposingChanged,
  });

  /// The editor this connection edits.
  final LexicalEditor editor;

  /// How much text either side of the caret the platform is told about.
  final int windowRadius;

  /// Whether the platform may autocorrect.
  final bool autocorrect;

  /// Whether the platform may offer suggestions.
  final bool enableSuggestions;

  /// Whether keystrokes may train the platform's personalized model.
  ///
  /// Off by default. An editor holds documents its user did not choose to
  /// share with the keyboard vendor, and the opposite default quietly makes
  /// that decision for them.
  final bool enableIMEPersonalizedLearning;

  /// How the platform capitalizes typed text.
  final TextCapitalization textCapitalization;

  /// Light or dark keyboard chrome, on platforms that ask.
  final Brightness keyboardAppearance;

  /// Whether the document rejects edits.
  final bool readOnly;

  /// Called when the composing region moves, so the caller can repaint it.
  final VoidCallback? onComposingChanged;

  TextInputConnection? _connection;
  TextEditingValue _lastKnownValue = TextEditingValue.empty;
  EditingWindow? _window;
  WindowAnchor? _anchor;
  TextRange _composing = TextRange.empty;
  bool _applyingDeltas = false;

  /// Whether a platform connection is open.
  bool get attached => _connection?.attached ?? false;

  /// The block the composing region sits in, or `null`.
  NodeKey? get composingBlock =>
      _composing.isValid && !_composing.isCollapsed ? _window?.blockKey : null;

  /// The composing region as flat offsets in [composingBlock], or `null`.
  TextRange? get composingRange {
    final window = _window;
    if (window == null || !_composing.isValid || _composing.isCollapsed) {
      return null;
    }
    return TextRange(
      start: window.toFlat(_composing.start),
      end: window.toFlat(_composing.end),
    );
  }

  /// Whether an edit currently being applied came from the platform.
  bool get isApplyingDeltas => _applyingDeltas;

  // -------------------------------------------------------------------
  // Connection lifecycle
  // -------------------------------------------------------------------

  /// Opens the connection and shows the keyboard.
  void attach() {
    if (readOnly) return;
    final existing = _connection;
    if (existing != null && existing.attached) {
      existing.show();
      return;
    }
    final connection = TextInput.attach(this, _configuration)
      ..setEditingState(_lastKnownValue);
    _connection = connection;
    syncToModel(force: true);
    connection.show();
  }

  /// Closes the connection and hides the keyboard.
  void detach() {
    _connection?.close();
    _connection = null;
    if (_composing.isValid && !_composing.isCollapsed) {
      _composing = TextRange.empty;
      onComposingChanged?.call();
    }
  }

  /// Asks the platform to show the keyboard for an open connection.
  void show() => _connection?.show();

  /// Reports the editor's rectangle so the platform can place its own UI.
  void setEditableSizeAndTransform(Size size, Matrix4 transform) {
    _connection?.setEditableSizeAndTransform(size, transform);
  }

  /// Reports the caret rectangle so the platform can place suggestion popups.
  void setCaretRect(Rect rect) => _connection?.setCaretRect(rect);

  TextInputConfiguration get _configuration => TextInputConfiguration(
    // Multiline: the value carries newlines, both real ones and the sentinels
    // that stand in for block boundaries, and a single-line configuration
    // would have the platform strip them.
    inputType: TextInputType.multiline,
    inputAction: TextInputAction.newline,
    autocorrect: autocorrect,
    enableSuggestions: enableSuggestions,
    enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
    textCapitalization: textCapitalization,
    keyboardAppearance: keyboardAppearance,
    enableDeltaModel: true,
  );

  // -------------------------------------------------------------------
  // Model to platform
  // -------------------------------------------------------------------

  /// Recomputes the editing value and pushes it if the platform's has drifted.
  ///
  /// Nothing is sent when the two agree, which is the normal case while
  /// typing: the platform applied the same edit we did, so the connection
  /// stays silent and a long block is never re-serialized.
  ///
  /// Pass `documentChanged: false` when the commit moved only the selection.
  /// The block's own text is then known to be unchanged, so the offset map is
  /// reused rather than rebuilt — which is what keeps a selection drag from
  /// re-walking the block on every pointer move.
  void syncToModel({bool force = false, bool documentChanged = true}) {
    if (_applyingDeltas) return;
    final window = editor.read(
      () => $buildEditingWindow(
        previous: _anchor,
        reuseOffsets: documentChanged ? null : _window?.offsets,
        radius: windowRadius,
        composing: _composing,
      ),
    );
    if (window == null) {
      _window = null;
      _anchor = null;
      return;
    }
    _window = window;
    _anchor = WindowAnchor(window.blockKey, window.start, window.end);
    if (!force && _platformHolds(window.value)) return;
    _lastKnownValue = window.value;
    _connection?.setEditingState(window.value);
  }

  /// Whether the platform already holds [value], give or take the *direction*
  /// of its selection.
  ///
  /// Direction is left out of the comparison because half the platforms cannot
  /// carry it: iOS and macOS hold the selection as a location and a length,
  /// so a backwards range comes back with its ends in document order. Pushing
  /// our own direction at such a platform on every echo is a conversation that
  /// never ends, and it could not hold the answer anyway. The model keeps the
  /// direction — see [_applySelection] — and the platform is told the range.
  bool _platformHolds(TextEditingValue value) {
    final ours = value.selection;
    final theirs = _lastKnownValue.selection;
    return value.text == _lastKnownValue.text &&
        value.composing == _lastKnownValue.composing &&
        ours.isValid == theirs.isValid &&
        ours.start == theirs.start &&
        ours.end == theirs.end;
  }

  // -------------------------------------------------------------------
  // Platform to model
  // -------------------------------------------------------------------

  @override
  TextEditingValue? get currentTextEditingValue => _lastKnownValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (readOnly) return;
    _applyingDeltas = true;
    try {
      for (final delta in textEditingDeltas) {
        _applyDelta(delta);
      }
    } finally {
      _applyingDeltas = false;
    }
    // The model has the last word on where the caret ended up, so the value
    // is recomputed from it rather than from the platform's guess.
    syncToModel();
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    // Only reached when the platform ignores enableDeltaModel. Treated as one
    // wholesale replacement of the window, which is lossy for IME state but
    // never wrong about the text.
    if (readOnly) return;
    if (value.text == _lastKnownValue.text) {
      _applySelection(value.selection);
      _lastKnownValue = value;
      return;
    }
    _applyDelta(
      TextEditingDeltaReplacement(
        oldText: _lastKnownValue.text,
        replacementText: value.text,
        replacedRange: TextRange(start: 0, end: _lastKnownValue.text.length),
        selection: value.selection,
        composing: value.composing,
      ),
    );
    syncToModel();
  }

  /// Applies [deltas] to the model. Exposed so the mapping can be tested
  /// without a platform channel, which is where its bugs actually live.
  @visibleForTesting
  void applyDeltasForTesting(List<TextEditingDelta> deltas) =>
      updateEditingValueWithDeltas(deltas);

  /// Seeds the value the platform is believed to hold. Test-only.
  @visibleForTesting
  void primeForTesting() => syncToModel(force: true);

  /// The value the platform is believed to hold. Test-only.
  @visibleForTesting
  TextEditingValue get lastKnownValue => _lastKnownValue;

  void _applyDelta(TextEditingDelta delta) {
    // A delta computed against a value we no longer hold means the platform
    // and the model have diverged — a race, or a key the framework handled
    // itself. Applying it would corrupt the document; the correct repair is
    // to re-state our value and drop the delta.
    if (delta.oldText != _lastKnownValue.text) {
      _lastKnownValue = TextEditingValue.empty;
      syncToModel(force: true);
      return;
    }

    final composingBefore = _composing;
    switch (delta) {
      case final TextEditingDeltaNonTextUpdate update:
        _applySelection(update.selection);
      case final TextEditingDeltaInsertion insertion:
        _replaceRange(
          TextRange.collapsed(insertion.insertionOffset),
          insertion.textInserted,
        );
      case final TextEditingDeltaDeletion deletion:
        _replaceRange(deletion.deletedRange, '');
      case final TextEditingDeltaReplacement replacement:
        _replaceRange(replacement.replacedRange, replacement.replacementText);
    }

    _lastKnownValue = delta.apply(_lastKnownValue);
    _composing = delta.composing;
    if (_composing != composingBefore) onComposingChanged?.call();
  }

  /// Points the model at the range [range] names, then edits it.
  void _replaceRange(TextRange range, String text) {
    final window = _window;
    if (window == null) return;

    final normalized = TextRange(
      start: range.start < range.end ? range.start : range.end,
      end: range.start < range.end ? range.end : range.start,
    );
    // A range identical to what we last reported means "the selection you
    // told me about". That selection may span blocks, which no window can
    // express, so the model's own is used untouched — and a clamped end is
    // then not mistaken for a block crossing.
    final reported = _lastKnownValue.selection;
    final matchesReported =
        reported.isValid &&
        reported.start == normalized.start &&
        reported.end == normalized.end;

    final crossesStart = !matchesReported && window.crossesStart(normalized);
    final crossesEnd = !matchesReported && window.crossesEnd(normalized);

    final fromFlat = window.toFlat(normalized.start);
    final toFlat = window.toFlat(normalized.end);
    final hasInnerRange = toFlat > fromFlat;

    if (!matchesReported || crossesStart || crossesEnd) {
      editor.update(() {
        final selection = $getSelection();
        if (selection is! RangeSelection) return;
        final start = window.offsets.pointFor(fromFlat);
        final end = window.offsets.pointFor(toFlat);
        selection
          ..anchor.set(start.key, start.offset, start.type)
          ..focus.set(end.key, end.offset, end.type)
          ..dirty = true;
      }, tags: const {imeUpdateTag});
    }

    final needsRemove =
        hasInnerRange || (matchesReported && !reported.isCollapsed);

    if (!crossesStart && !crossesEnd) {
      // The common path, and the one that has to stay a single operation:
      // an insertion replaces the selection itself rather than deleting it
      // first.
      if (text.isEmpty) {
        if (needsRemove) {
          editor.dispatchCommand(removeTextCommand, null);
        } else if (normalized.isCollapsed) {
          // A deletion that deletes no range: the platform asked for one
          // character and this block had none to give, which is what an empty
          // block looks like from the outside. The character it wants is the
          // block boundary itself, and the core spells that as a character
          // delete at the edge — the same operation backspace performs.
          //
          // Without this the keystroke was swallowed whole: an empty line the
          // writer had just made with Enter could not be taken back out,
          // because the range the platform sent was identical to the caret we
          // had reported and so was read as "the selection you told me about"
          // rather than as an edit.
          //
          // Which edge the caret sits on says which way to delete. On an empty
          // block both edges are offset zero, and backspace is what put the
          // line there.
          editor.dispatchCommand(deleteCharacterCommand, fromFlat <= 0);
        }
      } else {
        _insertWithBreaks(text, replace: true);
      }
      return;
    }

    if (needsRemove) editor.dispatchCommand(removeTextCommand, null);
    // Crossing a block boundary is a merge, and the core expresses that as a
    // character delete at the edge — the same operation backspace performs.
    if (crossesStart) editor.dispatchCommand(deleteCharacterCommand, true);
    if (crossesEnd) editor.dispatchCommand(deleteCharacterCommand, false);
    if (text.isNotEmpty) _insertWithBreaks(text, replace: false);
  }

  /// Inserts [text], turning each newline into a block split.
  void _insertWithBreaks(String text, {required bool replace}) {
    final parts = text.split('\n');
    var first = replace;
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) editor.dispatchCommand(insertParagraphCommand, null);
      if (parts[i].isEmpty) continue;
      editor.dispatchCommand(
        first ? replaceTextCommand : insertTextCommand,
        parts[i],
      );
      first = false;
    }
  }

  void _applySelection(TextSelection selection) {
    final window = _window;
    if (window == null || !selection.isValid) return;
    // The range we last reported, handed straight back. That is what a
    // platform without a direction does — iOS and macOS both carry the
    // selection as an `NSRange`, which has a location and a length and nothing
    // else — and taking it at face value swaps the anchor and the focus of
    // every backwards selection. The next extend then moves the end that was
    // meant to stand still, which is why a right-to-left drag used to collapse
    // to the single character between two pointer moves, and why shift-left
    // stopped after one. The model already holds this range, and it is the one
    // that knows which end the user is dragging.
    final reported = _lastKnownValue.selection;
    if (reported.isValid &&
        reported.start == selection.start &&
        reported.end == selection.end) {
      return;
    }
    editor.update(() {
      final current = $getSelection();
      if (current is! RangeSelection) return;
      final base = window.offsets.pointFor(window.toFlat(selection.baseOffset));
      final extent = window.offsets.pointFor(
        window.toFlat(selection.extentOffset),
      );
      current
        ..anchor.set(base.key, base.offset, base.type)
        ..focus.set(extent.key, extent.offset, extent.type)
        ..dirty = true;
    }, tags: const {imeUpdateTag});
  }

  // -------------------------------------------------------------------
  // The rest of the client contract
  // -------------------------------------------------------------------

  @override
  void performAction(TextInputAction action) {
    if (readOnly) return;
    if (editor.dispatchCommand(inputActionCommand, action)) return;
    if (action == TextInputAction.newline) {
      editor.dispatchCommand(insertParagraphCommand, null);
      syncToModel();
    }
  }

  @override
  void performSelector(String selectorName) {
    if (readOnly) return;
    // macOS routes editing keys through the input method as selectors rather
    // than as key events, so this is the only place several of them arrive.
    final handled = switch (selectorName) {
      'deleteBackward:' => editor.dispatchCommand(deleteCharacterCommand, true),
      'deleteForward:' => editor.dispatchCommand(deleteCharacterCommand, false),
      'deleteWordBackward:' => editor.dispatchCommand(deleteWordCommand, true),
      'deleteWordForward:' => editor.dispatchCommand(deleteWordCommand, false),
      'deleteToBeginningOfLine:' => editor.dispatchCommand(
        deleteLineCommand,
        true,
      ),
      'deleteToEndOfLine:' => editor.dispatchCommand(deleteLineCommand, false),
      'insertNewline:' => editor.dispatchCommand(insertParagraphCommand, null),
      'insertTab:' => editor.dispatchCommand(insertTabCommand, null),
      _ => _moveForSelector(selectorName),
    };
    if (handled) syncToModel();
  }

  bool _moveForSelector(String selectorName) {
    final extend = selectorName.contains('AndModifySelection');
    final backwards =
        selectorName.startsWith('moveLeft') ||
        selectorName.startsWith('moveBackward') ||
        selectorName.startsWith('moveWordLeft') ||
        selectorName.startsWith('moveWordBackward') ||
        selectorName.startsWith('moveToBeginningOfLine') ||
        selectorName.startsWith('moveToLeftEndOfLine');
    final unit = selectorName.contains('Word')
        ? SelectionUnit.word
        : (selectorName.contains('OfLine')
              ? SelectionUnit.line
              : SelectionUnit.character);
    if (!selectorName.startsWith('move')) return false;

    var moved = false;
    editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      moved = selection.moveCaret(
        backwards: backwards,
        unit: unit,
        extend: extend,
      );
    }, tags: const {imeUpdateTag});
    return moved;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    if (_composing.isValid && !_composing.isCollapsed) {
      _composing = TextRange.empty;
      onComposingChanged?.call();
    }
  }

  /// Whether the platform's focus request was accepted.
  ///
  /// Reported as unhandled so the framework keeps its own focus behaviour;
  /// focus here belongs to the widget`s focus node, not to the connection.
  @override
  bool onFocusReceived() => false;

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}
}
