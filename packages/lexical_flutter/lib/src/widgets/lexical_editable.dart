/// The editable document widget.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import '../input/lexical_input.dart';
import '../render/block_offset_map.dart';
import '../render/render_lexical_block.dart';
import '../selection/document_selection.dart';
import '../theme/lexical_theme.dart';
import 'block_registry.dart';
import 'lexical_document.dart';

/// A raw key press, before any default handling.
///
/// Register for it at [CommandPriority.beforeEditor] or higher and return
/// `true` to claim a shortcut; everything below is the widget's own defaults.
const LexicalCommand<KeyEvent> keyDownCommand = LexicalCommand('KEY_DOWN');

/// Copy the selection to the clipboard.
const LexicalCommand<void> copyCommand = LexicalCommand('COPY');

/// Cut the selection to the clipboard.
const LexicalCommand<void> cutCommand = LexicalCommand('CUT');

/// Paste the clipboard at the selection.
const LexicalCommand<void> pasteCommand = LexicalCommand('PASTE');

/// What the Tab key does.
enum TabBehaviour {
  /// Indent the selected blocks, and nest list items.
  ///
  /// The default, because the block-editor reading of Tab is what a list
  /// makes people expect.
  indent,

  /// Insert a tab node.
  insertTab,

  /// Leave Tab to the focus traversal, so the editor can be escaped by
  /// keyboard. The accessible choice inside a form.
  moveFocus,
}

/// An editable Lexical document.
///
/// Wraps [LexicalDocument] with everything an edit needs: a platform input
/// connection, selection, a caret, pointer and keyboard handling.
///
/// Caret and selection are pushed **straight onto the render objects** rather
/// than through the widget tree. A blinking caret that rebuilt widgets would
/// rebuild a block twice a second forever; this way a blink is one
/// `markNeedsPaint` on one block.
///
/// Selection handles and a context toolbar are deliberately not included.
/// They are design-system decisions — Material and Cupertino disagree, and so
/// will your app — and this package would have to pick one. The geometry they
/// need is exposed instead: see [LexicalEditableState.caretRect] and
/// [LexicalEditableState.selectionRects].
class LexicalEditable extends StatefulWidget {
  /// Creates an editable view of [editor].
  const LexicalEditable({
    required this.editor,
    required this.theme,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.decoratorBuilders = const {},
    this.padding = EdgeInsets.zero,
    this.scrollable = true,
    this.scrollController,
    this.textDirection,
    this.textScaler,
    this.cursorColor = const Color(0xFF2196F3),
    this.selectionColor = const Color(0x402196F3),
    this.composingColor = const Color(0x80000000),
    this.showCursor = true,
    this.cursorWidth = 2,
    this.cursorBlinkInterval = const Duration(milliseconds: 500),
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableIMEPersonalizedLearning = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.keyboardAppearance = Brightness.light,
    this.tabBehaviour = TabBehaviour.indent,
    this.windowRadius = 4096,
  });

  /// The editor being edited.
  final LexicalEditor editor;

  /// Styling for text, blocks and markers.
  final LexicalTheme theme;

  /// Focus node to use; one is created when omitted.
  final FocusNode? focusNode;

  /// Whether to take focus on first build.
  final bool autofocus;

  /// Whether the document rejects edits but stays selectable.
  final bool readOnly;

  /// Widget builders for decorator node types.
  final Map<String, DecoratorBuilder> decoratorBuilders;

  /// Padding around the document.
  final EdgeInsetsGeometry padding;

  /// Whether to scroll, culling off-screen blocks.
  final bool scrollable;

  /// Controller for the internal scroll view.
  final ScrollController? scrollController;

  /// Overrides the ambient text direction.
  final TextDirection? textDirection;

  /// Overrides the ambient text scaler.
  final TextScaler? textScaler;

  /// Caret colour.
  final Color cursorColor;

  /// Fill painted behind selected text.
  final Color selectionColor;

  /// Colour of the input method's composing underline.
  final Color composingColor;

  /// Whether to paint a caret at all.
  final bool showCursor;

  /// Caret width in logical pixels.
  final double cursorWidth;

  /// Half-period of the caret blink. [Duration.zero] disables blinking.
  final Duration cursorBlinkInterval;

  /// Whether the platform may autocorrect.
  final bool autocorrect;

  /// Whether the platform may offer suggestions.
  final bool enableSuggestions;

  /// Whether keystrokes may train the platform's personalized model.
  final bool enableIMEPersonalizedLearning;

  /// How the platform capitalizes typed text.
  final TextCapitalization textCapitalization;

  /// Light or dark keyboard chrome.
  final Brightness keyboardAppearance;

  /// What the Tab key does.
  final TabBehaviour tabBehaviour;

  /// How much text either side of the caret the platform is told about.
  final int windowRadius;

  @override
  State<LexicalEditable> createState() => LexicalEditableState();
}

/// State of a [LexicalEditable]; exposed for caret and selection geometry.
class LexicalEditableState extends State<LexicalEditable> {
  final BlockRegistry _registry = BlockRegistry();
  late LexicalInput _input;
  FocusNode? _ownedFocusNode;
  Unsubscribe? _unsubscribeEditor;
  Timer? _blinkTimer;
  bool _caretVisible = true;
  DocumentSelection? _selection;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  /// The blocks currently on screen.
  BlockRegistry get registry => _registry;

  /// The platform input connection.
  LexicalInput get input => _input;

  @override
  void initState() {
    super.initState();
    _input = _createInput();
    _registry.addListener(_applyPresentation);
    _unsubscribeEditor = widget.editor.registerUpdateListener(_onCommit);
    _focusNode.addListener(_onFocusChanged);
    _refreshSelection();
  }

  @override
  void didUpdateWidget(LexicalEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _focusNode.addListener(_onFocusChanged);
    }
    if (!identical(oldWidget.editor, widget.editor) ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.autocorrect != widget.autocorrect ||
        oldWidget.enableSuggestions != widget.enableSuggestions ||
        oldWidget.enableIMEPersonalizedLearning !=
            widget.enableIMEPersonalizedLearning ||
        oldWidget.textCapitalization != widget.textCapitalization ||
        oldWidget.keyboardAppearance != widget.keyboardAppearance ||
        oldWidget.windowRadius != widget.windowRadius) {
      _unsubscribeEditor?.call();
      _input.detach();
      _input = _createInput();
      _unsubscribeEditor = widget.editor.registerUpdateListener(_onCommit);
      if (_focusNode.hasFocus) _input.attach();
    }
    _refreshSelection();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _unsubscribeEditor?.call();
    _registry.removeListener(_applyPresentation);
    _registry.dispose();
    _input.detach();
    (widget.focusNode ?? _ownedFocusNode)?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  LexicalInput _createInput() => LexicalInput(
    editor: widget.editor,
    readOnly: widget.readOnly,
    windowRadius: widget.windowRadius,
    autocorrect: widget.autocorrect,
    enableSuggestions: widget.enableSuggestions,
    enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
    textCapitalization: widget.textCapitalization,
    keyboardAppearance: widget.keyboardAppearance,
    onComposingChanged: _applyPresentation,
  );

  // -------------------------------------------------------------------
  // Focus and the input connection
  // -------------------------------------------------------------------

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _input.attach();
      _restartBlink();
    } else {
      _input.detach();
      _blinkTimer?.cancel();
      _caretVisible = false;
    }
    _applyPresentation();
  }

  /// Focuses the editor and shows the software keyboard.
  void requestFocus() {
    _focusNode.requestFocus();
    _input
      ..attach()
      ..show();
  }

  // -------------------------------------------------------------------
  // Presentation
  // -------------------------------------------------------------------

  void _onCommit(EditorUpdate update) {
    _refreshSelection();
    _input.syncToModel();
    _restartBlink();
    _applyPresentation();
    _revealCaret();
  }

  void _refreshSelection() {
    _selection = widget.editor.read($resolveDocumentSelection);
  }

  /// Writes caret, selection and composing state onto the mounted blocks.
  ///
  /// Deliberately imperative. Routing this through the widget tree would
  /// rebuild every visible block whenever the caret moved, and the caret
  /// moves on every keystroke.
  void _applyPresentation() {
    if (!mounted) return;
    final selection = _selection;
    final caret = selection?.caret;
    final focused = _focusNode.hasFocus;
    final composingBlock = _input.composingBlock;
    final composingRange = _input.composingRange;

    for (final block in _registry.blocks) {
      final render = block.render;
      render
        ..selectionColor = widget.selectionColor
        ..composingColor = widget.composingColor
        ..selections = _selectionsFor(block, selection)
        ..composing = block.key == composingBlock ? composingRange : null
        ..caret = _caretFor(block, caret, focused: focused);
    }
  }

  List<TextSelection> _selectionsFor(
    MountedBlock block,
    DocumentSelection? selection,
  ) {
    if (selection == null || !selection.hasRange) return const [];
    for (final span in selection.spans) {
      if (span.blockKey != block.key) continue;
      final flat = flatSelectionFor(span, block.offsets);
      return flat == null ? const [] : [flat];
    }
    return const [];
  }

  BlockCaret? _caretFor(
    MountedBlock block,
    BlockPoint? caret, {
    required bool focused,
  }) {
    if (!widget.showCursor || !focused || caret == null) return null;
    if (caret.blockKey != block.key) return null;
    if (_selection?.hasRange ?? false) return null;
    final flat = block.offsets.flatOffsetFor(
      caret.point.key,
      caret.point.offset,
      caret.point.type,
    );
    if (flat == null) return null;
    return BlockCaret(
      offset: flat,
      color: widget.cursorColor,
      width: widget.cursorWidth,
      opacity: _caretVisible ? 1 : 0,
    );
  }

  void _restartBlink() {
    _blinkTimer?.cancel();
    _caretVisible = true;
    if (!_focusNode.hasFocus) return;
    if (widget.cursorBlinkInterval == Duration.zero) return;
    _blinkTimer = Timer.periodic(widget.cursorBlinkInterval, (_) {
      _caretVisible = !_caretVisible;
      _applyPresentation();
    });
  }

  /// The caret rectangle in global coordinates, or `null`.
  ///
  /// Exposed so a host can position its own toolbar or magnifier without
  /// this package having to grow one.
  Rect? get caretRect {
    final caret = _selection?.caret;
    if (caret == null) return null;
    final block = _registry[caret.blockKey];
    if (block == null || !block.render.hasSize) return null;
    final flat = block.offsets.flatOffsetFor(
      caret.point.key,
      caret.point.offset,
      caret.point.type,
    );
    if (flat == null) return null;
    final local = block.render.caretRect(flat, width: widget.cursorWidth);
    return MatrixUtils.transformRect(block.render.getTransformTo(null), local);
  }

  /// The selected rectangles in global coordinates.
  List<Rect> get selectionRects {
    final selection = _selection;
    if (selection == null || !selection.hasRange) return const [];
    final rects = <Rect>[];
    for (final span in selection.spans) {
      final block = _registry[span.blockKey];
      if (block == null || !block.render.hasSize) continue;
      final flat = flatSelectionFor(span, block.offsets);
      if (flat == null) continue;
      final transform = block.render.getTransformTo(null);
      for (final box in block.render.getBoxesForSelection(flat)) {
        rects.add(MatrixUtils.transformRect(transform, box.toRect()));
      }
    }
    return rects;
  }

  void _revealCaret() {
    final caret = _selection?.caret;
    if (caret == null || !_focusNode.hasFocus) return;
    final block = _registry[caret.blockKey];
    if (block == null || !block.render.attached || !block.render.hasSize) {
      return;
    }
    final flat = block.offsets.flatOffsetFor(
      caret.point.key,
      caret.point.offset,
      caret.point.type,
    );
    if (flat == null) return;
    final rect = block.render.caretRect(flat, width: widget.cursorWidth);
    block.render.showOnScreen(rect: rect.inflate(8), duration: Duration.zero);
    _input.setCaretRect(rect);
  }

  // -------------------------------------------------------------------
  // Pointer
  // -------------------------------------------------------------------

  /// The model point under [globalPosition], or `null`.
  ({NodeKey block, ResolvedPoint point})? pointAt(Offset globalPosition) {
    final block = _registry.blockAt(globalPosition);
    if (block == null || !block.render.hasSize) return null;
    final local = block.render.globalToLocal(globalPosition);
    final position = block.render.getPositionForOffset(local);
    return (block: block.key, point: block.offsets.pointFor(position.offset));
  }

  void _placeCaret(Offset globalPosition, {required bool extend}) {
    final hit = pointAt(globalPosition);
    if (hit == null) return;
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is RangeSelection) {
        selection.moveTo(
          hit.point.key,
          hit.point.offset,
          hit.point.type,
          extend: extend,
        );
        return;
      }
      $setSelection(
        RangeSelection(
          Point(hit.point.key, hit.point.offset, hit.point.type),
          Point(hit.point.key, hit.point.offset, hit.point.type),
        ),
      );
    });
  }

  void _onTapDown(TapDownDetails details) {
    requestFocus();
    _placeCaret(
      details.globalPosition,
      extend: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void _selectWordAt(Offset globalPosition) {
    _placeCaret(globalPosition, extend: false);
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is RangeSelection) selection.selectWord();
    });
  }

  void _onDragStart(DragStartDetails details) {
    requestFocus();
    _placeCaret(details.globalPosition, extend: false);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _placeCaret(details.globalPosition, extend: true);
  }

  // -------------------------------------------------------------------
  // Keyboard
  // -------------------------------------------------------------------

  bool get _usesMetaShortcuts =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (widget.editor.dispatchCommand(keyDownCommand, event)) {
      return KeyEventResult.handled;
    }

    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final alt = keys.isAltPressed;
    final primary = _usesMetaShortcuts
        ? keys.isMetaPressed
        : keys.isControlPressed;
    final key = event.logicalKey;
    final editor = widget.editor;

    // Selection movement works read-only too; that is what makes a document
    // keyboard-navigable without being editable.
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        final backwards = key == LogicalKeyboardKey.arrowLeft;
        final unit = primary
            ? SelectionUnit.line
            : (alt || (!_usesMetaShortcuts && keys.isControlPressed)
                  ? SelectionUnit.word
                  : SelectionUnit.character);
        _move(backwards: backwards, unit: unit, extend: shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        _moveVertically(
          down: key == LogicalKeyboardKey.arrowDown,
          extend: shift,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _move(backwards: true, unit: SelectionUnit.line, extend: shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _move(backwards: false, unit: SelectionUnit.line, extend: shift);
        return KeyEventResult.handled;
    }

    if (primary && key == LogicalKeyboardKey.keyA) {
      editor.dispatchCommand(selectAllCommand, null);
      return KeyEventResult.handled;
    }
    if (primary && key == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }

    if (widget.readOnly) return KeyEventResult.ignored;

    if (primary) {
      switch (key) {
        case LogicalKeyboardKey.keyX:
          _cut();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          _paste();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyB:
          editor.dispatchCommand(formatTextCommand, TextFormat.bold);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyI:
          editor.dispatchCommand(formatTextCommand, TextFormat.italic);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyU:
          editor.dispatchCommand(formatTextCommand, TextFormat.underline);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyZ:
          editor.dispatchCommand(shift ? redoCommand : undoCommand, null);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY when !_usesMetaShortcuts:
          editor.dispatchCommand(redoCommand, null);
          return KeyEventResult.handled;
      }
    }

    switch (key) {
      case LogicalKeyboardKey.backspace:
        _deleteBy(backwards: true, alt: alt, primary: primary);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        _deleteBy(backwards: false, alt: alt, primary: primary);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // Shift-Enter is a line break inside the block; Enter splits it.
        if (shift) {
          editor.dispatchCommand(insertLineBreakCommand, false);
        } else {
          editor.dispatchCommand(insertParagraphCommand, null);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        return _handleTab(shift: shift);
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTab({required bool shift}) {
    switch (widget.tabBehaviour) {
      case TabBehaviour.moveFocus:
        return KeyEventResult.ignored;
      case TabBehaviour.insertTab:
        if (shift) return KeyEventResult.ignored;
        widget.editor.dispatchCommand(insertTabCommand, null);
        return KeyEventResult.handled;
      case TabBehaviour.indent:
        widget.editor.dispatchCommand(
          shift ? outdentContentCommand : indentContentCommand,
          null,
        );
        return KeyEventResult.handled;
    }
  }

  void _deleteBy({
    required bool backwards,
    required bool alt,
    required bool primary,
  }) {
    if (primary && _usesMetaShortcuts) {
      widget.editor.dispatchCommand(deleteLineCommand, backwards);
      return;
    }
    if (alt || (!_usesMetaShortcuts && primary)) {
      widget.editor.dispatchCommand(deleteWordCommand, backwards);
      return;
    }
    widget.editor.dispatchCommand(deleteCharacterCommand, backwards);
  }

  void _move({
    required bool backwards,
    required SelectionUnit unit,
    required bool extend,
  }) {
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      selection.moveCaret(backwards: backwards, unit: unit, extend: extend);
    });
  }

  /// Moves the caret one *visual* line, which only the laid-out text knows.
  ///
  /// Falls back to the block edge when the target block is off screen: there
  /// is no line information for a block that has not been laid out, and
  /// guessing one would put the caret in the wrong place rather than merely
  /// an approximate one.
  void _moveVertically({required bool down, required bool extend}) {
    final caret = _selection?.caret;
    if (caret == null) {
      _move(backwards: !down, unit: SelectionUnit.character, extend: extend);
      return;
    }
    final block = _registry[caret.blockKey];
    if (block == null || !block.render.hasSize) {
      _move(backwards: !down, unit: SelectionUnit.line, extend: extend);
      return;
    }
    final flat = block.offsets.flatOffsetFor(
      caret.point.key,
      caret.point.offset,
      caret.point.type,
    );
    if (flat == null) return;

    final rect = block.render.caretRect(flat, width: widget.cursorWidth);
    final target = Offset(
      rect.left,
      down ? rect.bottom + rect.height / 2 : rect.top - rect.height / 2,
    );

    if (target.dy >= 0 && target.dy <= block.render.size.height) {
      final position = block.render.getPositionForOffset(target);
      final point = block.offsets.pointFor(position.offset);
      _moveToPoint(point, extend: extend);
      return;
    }

    final neighbourKey = widget.editor.read(() {
      final node = $getNodeByKey(caret.blockKey);
      if (node is! ElementNode) return null;
      return (down ? $getNextBlock(node) : $getPreviousBlock(node))?.key;
    });
    if (neighbourKey == null) {
      _move(backwards: !down, unit: SelectionUnit.line, extend: extend);
      return;
    }
    final neighbour = _registry[neighbourKey];
    if (neighbour == null || !neighbour.render.hasSize) {
      _move(backwards: !down, unit: SelectionUnit.line, extend: extend);
      return;
    }
    // Keep the horizontal position across the block boundary, which is what
    // makes a column of arrow presses track a straight line down the page.
    final dx = block.render.localToGlobal(Offset(rect.left, 0)).dx;
    final localX = neighbour.render.globalToLocal(Offset(dx, 0)).dx;
    final position = neighbour.render.getPositionForOffset(
      Offset(localX, down ? 1 : neighbour.render.size.height - 1),
    );
    _moveToPoint(neighbour.offsets.pointFor(position.offset), extend: extend);
  }

  void _moveToPoint(ResolvedPoint point, {required bool extend}) {
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      selection.moveTo(point.key, point.offset, point.type, extend: extend);
    });
  }

  // -------------------------------------------------------------------
  // Clipboard
  // -------------------------------------------------------------------

  String _selectedText() => widget.editor.read(() {
    final selection = $getSelection();
    return selection is RangeSelection ? selection.getTextContent() : '';
  });

  void _copy() {
    if (widget.editor.dispatchCommand(copyCommand, null)) return;
    final text = _selectedText();
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void _cut() {
    if (widget.editor.dispatchCommand(cutCommand, null)) return;
    final text = _selectedText();
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    widget.editor.dispatchCommand(removeTextCommand, null);
  }

  void _paste() {
    if (widget.editor.dispatchCommand(pasteCommand, null)) return;
    unawaited(_pastePlainText());
  }

  Future<void> _pastePlainText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    // Newlines become blocks: pasting three lines into a document should
    // produce three paragraphs, not one paragraph with newlines in it.
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) widget.editor.dispatchCommand(insertParagraphCommand, null);
      if (parts[i].isNotEmpty) {
        widget.editor.dispatchCommand(insertTextCommand, parts[i]);
      }
    }
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final document = LexicalDocument(
      editor: widget.editor,
      theme: widget.theme,
      registry: _registry,
      decoratorBuilders: widget.decoratorBuilders,
      padding: widget.padding,
      scrollable: widget.scrollable,
      scrollController: widget.scrollController,
      textDirection: widget.textDirection,
      textScaler: widget.textScaler,
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (instance) => instance.onTapDown = _onTapDown,
                ),
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  DoubleTapGestureRecognizer
                >(
                  DoubleTapGestureRecognizer.new,
                  (instance) =>
                      instance.onDoubleTapDown = (details) =>
                          _selectWordAt(details.globalPosition),
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  LongPressGestureRecognizer.new,
                  (instance) => instance
                    ..onLongPressStart = (details) {
                      requestFocus();
                      _selectWordAt(details.globalPosition);
                    }
                    ..onLongPressMoveUpdate = (details) =>
                        _placeCaret(details.globalPosition, extend: true),
                ),
            // Mouse and trackpad only: a touch drag has to reach the
            // scrollable, or the document cannot be scrolled at all. Touch
            // selection goes through long-press-and-drag instead, which is
            // what every platform does.
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                  () => PanGestureRecognizer(
                    supportedDevices: const {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.invertedStylus,
                    },
                  ),
                  (instance) => instance
                    ..onStart = _onDragStart
                    ..onUpdate = _onDragUpdate,
                ),
          },
          child: document,
        ),
      ),
    );
  }
}
