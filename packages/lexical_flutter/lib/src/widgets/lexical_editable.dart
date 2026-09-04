/// The editable document widget.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexical_core/lexical_core.dart';

import '../input/lexical_input.dart';
import '../render/block_offset_map.dart';
import '../render/render_lexical_block.dart';
import '../selection/document_selection.dart';
import '../selection/selection_overlay.dart';
import '../theme/lexical_theme.dart';
import 'block_registry.dart';
import 'lexical_document.dart';
import 'lexical_interaction.dart';

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

/// Someone else's selection, to paint alongside the local one.
///
/// Deliberately free of any notion of where it came from: a collaborative
/// session, a "reviewer is reading this" marker and a test all hand over the
/// same two points and a colour. Resolve a peer's selection into [Point]s with
/// `LexicalCollab.remoteSelections` from `lexical_collab`, or build them by
/// hand.
@immutable
class RemoteSelection {
  /// Records a selection from [anchor] to [focus], painted in [color].
  const RemoteSelection({
    required this.anchor,
    required this.focus,
    required this.color,
    this.label,
  });

  /// Where the peer's selection started.
  final Point anchor;

  /// Where the peer's caret sits.
  final Point focus;

  /// The colour identifying them.
  final Color color;

  /// A name to show beside the caret, drawn by the application.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is RemoteSelection &&
      other.anchor.key == anchor.key &&
      other.anchor.offset == anchor.offset &&
      other.anchor.type == anchor.type &&
      other.focus.key == focus.key &&
      other.focus.offset == focus.offset &&
      other.focus.type == focus.type &&
      other.color == color &&
      other.label == label;

  @override
  int get hashCode => Object.hash(
    anchor.key,
    anchor.offset,
    focus.key,
    focus.offset,
    color,
    label,
  );
}

/// An editable Lexical document.
///
/// Wraps [LexicalDocument] with everything an edit needs: a platform input
/// connection, selection, a caret, pointer and keyboard handling, drag
/// handles and a context menu.
///
/// Caret and selection are pushed **straight onto the render objects** rather
/// than through the widget tree. A blinking caret that rebuilt widgets would
/// rebuild a block twice a second forever; this way a blink is one
/// `markNeedsPaint` on one block.
///
/// The handles and the menu come from Flutter's own [TextSelectionControls]
/// and [AdaptiveTextSelectionToolbar], so they look native on every platform
/// without this package having an opinion about how a handle should look.
/// Replace either through [selectionControls] and [contextMenuBuilder]; the
/// raw geometry is still exposed for a design system that wants to draw its
/// own — see [LexicalEditableState.caretRect] and
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
    this.remoteSelections = const <RemoteSelection>[],
    this.selectionControls,
    this.contextMenuBuilder = defaultLexicalContextMenu,
    this.onContextMenu,
    this.magnifierConfiguration,
    this.showSelectionHandles,
    this.enableInteractiveSelection = true,
    this.interaction,
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

  /// Other people's selections, painted under the local one.
  final List<RemoteSelection> remoteSelections;

  /// The handle shapes. Defaults to the running platform's own.
  final TextSelectionControls? selectionControls;

  /// Builds the menu shown over a selection.
  final LexicalContextMenuBuilder contextMenuBuilder;

  /// Called when the editable decides a context menu belongs on screen — a
  /// long press, or a right-click.
  ///
  /// For an application that draws its own actions instead of the platform's:
  /// suppressing [contextMenuBuilder] hides the menu, but nothing then says
  /// *when* one was asked for, which is the one thing a replacement needs to
  /// know. Whether there is a selection to act on is the caller's to read off
  /// the editable it already holds.
  final VoidCallback? onContextMenu;

  /// How to magnify under a dragging finger. Defaults to the platform's.
  final TextMagnifierConfiguration? magnifierConfiguration;

  /// Whether to show drag handles. Defaults to touch platforms only.
  ///
  /// Handles on a desktop are wrong twice over: the platform does not draw
  /// them, and a mouse does not need them.
  final bool? showSelectionHandles;

  /// Whether the selection may be changed by pointer at all.
  ///
  /// `false` still allows programmatic selection, which is what a document
  /// that must not be selectable — a preview, a drag proxy — needs.
  final bool enableInteractiveSelection;

  /// Which node types respond to hover and tap, and how.
  ///
  /// A tap on an interactive node still moves the caret — this is an editor,
  /// and text inside a link has to stay reachable. The callback runs as well,
  /// so an application that wants a link to open only while reading, or only
  /// with a modifier held, decides that in the callback.
  final LexicalInteraction? interaction;

  @override
  State<LexicalEditable> createState() => LexicalEditableState();
}

/// State of a [LexicalEditable]; exposed for caret and selection geometry.
class LexicalEditableState extends State<LexicalEditable> {
  final BlockRegistry _registry = BlockRegistry();
  final GlobalKey<LexicalInteractionRegionState> _interactionKey =
      GlobalKey<LexicalInteractionRegionState>();
  late LexicalInput _input;
  FocusNode? _ownedFocusNode;
  Unsubscribe? _unsubscribeEditor;
  Timer? _blinkTimer;
  bool _caretVisible = true;
  DocumentSelection? _selection;
  List<(DocumentSelection, Color)> _remote = const [];
  LexicalSelectionOverlay? _overlay;

  /// Whether a pointer is dragging the selection right now.
  ///
  /// The caret is only scrolled into view when it moved for a reason the user
  /// cannot see — a keystroke, an IME commit, a programmatic edit. While they
  /// are dragging, they are looking at where they are pointing.
  bool _draggingSelection = false;

  /// What the pointer drag in progress must keep selected, in document order.
  ///
  /// A drag spans from where it began, so **both** ends are written on every
  /// move rather than only the moving one. Extending from whatever the anchor
  /// happens to be by then is what makes a right-to-left selection impossible:
  /// the platform hands the value back with the ends in document order — an
  /// `NSRange` has a location and a length and no direction — and the swapped
  /// anchor then pins the wrong end, leaving the one character between two
  /// pointer moves selected.
  ///
  /// The two are the same point for a plain drag and the word a long press
  /// picked out for a touch one, which is what keeps that word whole while the
  /// finger travels past either side of it.
  ResolvedPoint? _dragBaseStart;
  ResolvedPoint? _dragBaseEnd;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  /// Whether this platform draws drag handles.
  bool get _wantsHandles =>
      widget.showSelectionHandles ??
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

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
    // Presentation is imperative, so a changed `remoteSelections` reaches the
    // render objects only if it is pushed — nothing rebuilds them.
    _applyPresentation();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _overlay?.dispose();
    _overlay = null;
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
    // A commit that moved only the selection — every commit of a drag, and
    // every arrow key — leaves the text of every block exactly as it was.
    // Saying so lets the work below skip what only the text can invalidate.
    final documentChanged =
        update.isFullReconcile ||
        update.dirtyLeaves.isNotEmpty ||
        update.dirtyElements.isNotEmpty;
    _refreshSelection();
    _input.syncToModel(documentChanged: documentChanged);
    _restartBlink();
    _applyPresentation();
    // Not while a pointer is dragging the selection: the user is pointing at
    // where they want to be, and scrolling the view under them on every move
    // is both wrong and the most expensive thing on this path — it walks to
    // the enclosing scrollable and repaints everything between.
    if (!_draggingSelection) _revealCaret();
    _overlay?.update();
  }

  void _refreshSelection() {
    widget.editor.read(() {
      _selection = $resolveDocumentSelection();
      _remote = <(DocumentSelection, Color)>[
        for (final remote in widget.remoteSelections)
          // Copied rather than passed through: a RangeSelection claims the
          // points it is built from, and these belong to the caller.
          if ($resolveSelectionSpans(
                RangeSelection(
                  Point(
                    remote.anchor.key,
                    remote.anchor.offset,
                    remote.anchor.type,
                  ),
                  Point(
                    remote.focus.key,
                    remote.focus.offset,
                    remote.focus.type,
                  ),
                ),
              )
              case final resolved?)
            (resolved, remote.color),
      ];
    });
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
        ..foreignSelections = _foreignFor(block)
        ..composing = block.key == composingBlock ? composingRange : null
        ..caret = _caretFor(block, caret, focused: focused);
    }
  }

  List<ForeignSelection> _foreignFor(MountedBlock block) {
    if (_remote.isEmpty) return const [];
    final result = <ForeignSelection>[];
    for (final (selection, color) in _remote) {
      TextRange? range;
      for (final span in selection.spans) {
        if (span.blockKey != block.key) continue;
        range = flatSelectionFor(span, block.offsets);
        break;
      }
      final caret = selection.caret;
      int? caretOffset;
      if (caret != null && caret.blockKey == block.key) {
        caretOffset = block.offsets.flatOffsetFor(
          caret.point.key,
          caret.point.offset,
          caret.point.type,
        );
      }
      if (range == null && caretOffset == null) continue;
      result.add(
        ForeignSelection(
          color: color,
          range: range,
          caretOffset: caretOffset,
          caretWidth: widget.cursorWidth,
        ),
      );
    }
    return result;
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
    // A range has no caret to blink — see [_caretFor] — so a drag would
    // otherwise cancel and re-arm a periodic timer on every pointer move for
    // something that is not on screen.
    if (_selection?.hasRange ?? false) return;
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

  /// The editable's own rectangle in global coordinates, or `null`.
  Rect? get editableBounds {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  /// Where the two ends of the selection sit, in global coordinates.
  ///
  /// This is what a handle, a toolbar anchor and a magnifier all need, and
  /// the only thing they need — which is why it is exposed rather than kept
  /// behind the overlay that happens to use it.
  SelectionEndpoints? get selectionEndpoints {
    final selection = _selection;
    if (selection == null) return null;
    if (!selection.hasRange) {
      final caret = caretRect;
      if (caret == null) return null;
      final point = Offset(caret.left, caret.bottom);
      return SelectionEndpoints(
        start: point,
        end: point,
        startHeight: caret.height,
        endHeight: caret.height,
      );
    }
    final rects = selectionRects;
    if (rects.isEmpty) return null;
    final first = rects.first;
    final last = rects.last;
    return SelectionEndpoints(
      start: Offset(first.left, first.bottom),
      end: Offset(last.right, last.bottom),
      startHeight: first.height,
      endHeight: last.height,
    );
  }

  /// Where the platform's context menu should be anchored, or `null`.
  TextSelectionToolbarAnchors? get contextMenuAnchors {
    final endpoints = selectionEndpoints;
    final box = context.findRenderObject() as RenderBox?;
    if (endpoints == null || box == null || !box.hasSize) return null;
    return TextSelectionToolbarAnchors.fromSelection(
      renderBox: box,
      startGlyphHeight: endpoints.startHeight,
      endGlyphHeight: endpoints.endHeight,
      selectionEndpoints: <TextSelectionPoint>[
        TextSelectionPoint(box.globalToLocal(endpoints.start), null),
        TextSelectionPoint(box.globalToLocal(endpoints.end), null),
      ],
    );
  }

  /// The entries the default context menu offers.
  ///
  /// An entry that cannot do anything is left out rather than disabled: a
  /// greyed-out Cut over an empty selection is noise, and every platform's
  /// own menu omits it.
  List<ContextMenuButtonItem> get contextMenuButtonItems {
    final hasRange = _selection?.hasRange ?? false;
    return <ContextMenuButtonItem>[
      if (hasRange && !widget.readOnly)
        ContextMenuButtonItem(
          onPressed: () {
            cut();
            hideToolbar();
          },
          type: ContextMenuButtonType.cut,
        ),
      if (hasRange)
        ContextMenuButtonItem(
          onPressed: () {
            copy();
            hideToolbar();
          },
          type: ContextMenuButtonType.copy,
        ),
      if (!widget.readOnly)
        ContextMenuButtonItem(
          onPressed: () {
            paste();
            hideToolbar();
          },
          type: ContextMenuButtonType.paste,
        ),
      if (!hasRange)
        ContextMenuButtonItem(
          onPressed: () {
            selectAll();
            showToolbar();
          },
          type: ContextMenuButtonType.selectAll,
        ),
    ];
  }

  /// The caret rectangles of [LexicalEditable.remoteSelections], by index.
  ///
  /// For drawing a collaborator's name beside their caret, which is an
  /// application's job — it knows the typography and the avatar.
  Map<int, Rect> get remoteCaretRects {
    final result = <int, Rect>{};
    for (var i = 0; i < _remote.length; i++) {
      final caret = _remote[i].$1.caret;
      if (caret == null) continue;
      final block = _registry[caret.blockKey];
      if (block == null || !block.render.hasSize) continue;
      final flat = block.offsets.flatOffsetFor(
        caret.point.key,
        caret.point.offset,
        caret.point.type,
      );
      if (flat == null) continue;
      result[i] = MatrixUtils.transformRect(
        block.render.getTransformTo(null),
        block.render.caretRect(flat, width: widget.cursorWidth),
      );
    }
    return result;
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
  ///
  /// Resolved against the nearest block rather than only the one the point is
  /// inside — see [BlockRegistry.blockNear]. A press that resolves to nothing
  /// leaves the previous anchor in place, which turns the next drag into a
  /// selection from somewhere the user never pointed at.
  ({NodeKey block, ResolvedPoint point})? pointAt(Offset globalPosition) {
    final block = _registry.blockNear(globalPosition);
    if (block == null || !block.render.hasSize) return null;
    final local = block.render.globalToLocal(globalPosition);
    final position = block.render.getPositionForOffset(local);
    return (block: block.key, point: block.offsets.pointFor(position.offset));
  }

  /// Moves the caret to [globalPosition]; false when nothing was there.
  bool _placeCaret(Offset globalPosition, {required bool extend}) {
    final hit = pointAt(globalPosition);
    if (hit == null) return false;
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
    return true;
  }

  /// Moves one end of the selection to [globalPosition].
  ///
  /// [movingStart] names the end being dragged in *document* order, not
  /// whether it is the anchor: a user dragging the left handle is pointing at
  /// a glyph, and does not know which end the model calls the anchor.
  void extendSelectionTo(Offset globalPosition, {required bool movingStart}) {
    final hit = pointAt(globalPosition);
    if (hit == null) return;
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      final (start, end) = selection.orderedPoints;
      final fixed = movingStart ? end : start;
      selection.anchor.set(fixed.key, fixed.offset, fixed.type);
      selection.focus.set(hit.point.key, hit.point.offset, hit.point.type);
    });
  }

  void _onTapDown(TapDownDetails details) {
    requestFocus();
    hideToolbar();
    if (!widget.enableInteractiveSelection) return;
    _placeCaret(
      details.globalPosition,
      extend: HardwareKeyboard.instance.isShiftPressed,
    );
    if (_wantsHandles) showHandles();
  }

  /// Reports the tap to [LexicalEditable.interaction], if it hit a node.
  ///
  /// On tap **up**, not down: a tap that turned into a selection drag is not a
  /// tap, and opening a link because someone started selecting inside it is
  /// the kind of bug that only shows up in someone else's hands.
  void _onTapUp(TapUpDetails details) {
    _interactionKey.currentState?.handleTapAt(details.globalPosition);
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    requestFocus();
    if (!(_selection?.hasRange ?? false)) {
      _placeCaret(details.globalPosition, extend: false);
    }
    showToolbar();
  }

  void _selectWordAt(Offset globalPosition) {
    _placeCaret(globalPosition, extend: false);
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is RangeSelection) selection.selectWord();
    });
  }

  /// Remembers what the drag starting now must keep selected.
  ///
  /// Read back off the model rather than taken from the pointer, so a long
  /// press that selected a word hands the whole word over — see
  /// [_dragBaseStart].
  void _rememberDragBase() {
    widget.editor.read(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) {
        _dragBaseStart = null;
        _dragBaseEnd = null;
        return;
      }
      final (start, end) = selection.orderedPoints;
      _dragBaseStart = ResolvedPoint(start.key, start.offset, start.type);
      _dragBaseEnd = ResolvedPoint(end.key, end.offset, end.type);
    });
  }

  void _endDrag() {
    _dragBaseStart = null;
    _dragBaseEnd = null;
  }

  /// Spans the selection from the base of the drag in progress to [position].
  void _extendDragTo(Offset position) {
    final base = _dragBaseStart;
    final baseEnd = _dragBaseEnd;
    // No base means no drag start was seen — a stray move. Extending from the
    // model's own anchor is the best that can be said about it.
    if (base == null || baseEnd == null) {
      _placeCaret(position, extend: true);
      return;
    }
    final hit = pointAt(position);
    if (hit == null) return;
    widget.editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      selection
        ..anchor.set(base.key, base.offset, base.type)
        ..focus.set(hit.point.key, hit.point.offset, hit.point.type)
        ..dirty = true;
      // Dragged past the base's own start: the far end of it is the one that
      // stands still, so the word a long press picked out stays selected
      // whichever side the finger wanders to.
      if (baseEnd != base && selection.isBackward) {
        selection.anchor.set(baseEnd.key, baseEnd.offset, baseEnd.type);
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    requestFocus();
    hideToolbar();
    if (!widget.enableInteractiveSelection) return;
    _draggingSelection = true;
    // A press that landed on nothing leaves no base behind: the drag then has
    // no origin of its own, and extending an older selection from wherever it
    // happens to be beats spanning from a point the user never pointed at.
    if (_placeCaret(details.globalPosition, extend: false)) {
      _rememberDragBase();
    } else {
      _endDrag();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enableInteractiveSelection) return;
    _extendDragTo(details.globalPosition);
  }

  void _onDragEnd(DragEndDetails details) {
    _draggingSelection = false;
    _endDrag();
    if (_selection?.hasRange ?? false) showToolbar();
  }

  void _onDragCancel() {
    _draggingSelection = false;
    _endDrag();
  }

  // -------------------------------------------------------------------
  // Handles, toolbar, actions
  // -------------------------------------------------------------------

  LexicalSelectionOverlay _ensureOverlay() =>
      _overlay ??= LexicalSelectionOverlay(
        context: context,
        editable: this,
        selectionControls:
            widget.selectionControls ?? _platformSelectionControls,
        contextMenuBuilder: widget.contextMenuBuilder,
        magnifierConfiguration:
            widget.magnifierConfiguration ??
            TextMagnifier.adaptiveMagnifierConfiguration,
      );

  static TextSelectionControls get _platformSelectionControls =>
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
        TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
        TargetPlatform.android ||
        TargetPlatform.fuchsia => materialTextSelectionHandleControls,
        TargetPlatform.linux ||
        TargetPlatform.windows => desktopTextSelectionHandleControls,
      };

  /// Shows the drag handles, if this platform uses them.
  void showHandles() {
    if (!widget.enableInteractiveSelection) return;
    _ensureOverlay().showHandles();
  }

  /// Hides the drag handles.
  void hideHandles() => _overlay?.hideHandles();

  /// Shows the context menu over the selection.
  void showToolbar() {
    if (!widget.enableInteractiveSelection) return;
    widget.onContextMenu?.call();
    _ensureOverlay()
      ..hideToolbar()
      ..showToolbar();
  }

  /// Hides the context menu.
  void hideToolbar() => _overlay?.hideToolbar();

  /// Whether the context menu is on screen.
  bool get toolbarVisible => _overlay?.toolbarVisible ?? false;

  /// Selects the whole document.
  void selectAll() => widget.editor.dispatchCommand(selectAllCommand, null);

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
      copy();
      return KeyEventResult.handled;
    }

    if (widget.readOnly) return KeyEventResult.ignored;

    if (primary) {
      switch (key) {
        case LogicalKeyboardKey.keyX:
          cut();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          paste();
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

  /// Copies the selection to the clipboard.
  void copy() {
    if (widget.editor.dispatchCommand(copyCommand, null)) return;
    final text = _selectedText();
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  /// Cuts the selection to the clipboard.
  void cut() {
    if (widget.editor.dispatchCommand(cutCommand, null)) return;
    final text = _selectedText();
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    widget.editor.dispatchCommand(removeTextCommand, null);
  }

  /// Pastes the clipboard at the selection.
  void paste() {
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

    // The interaction region replaces the plain cursor region rather than
    // nesting inside it: one MouseRegion owns the cursor, and it is the one
    // that knows whether the pointer is over a link.
    Widget hover(Widget child) {
      final interaction = widget.interaction;
      if (interaction == null) {
        return MouseRegion(cursor: SystemMouseCursors.text, child: child);
      }
      return LexicalInteractionRegion(
        key: _interactionKey,
        editor: widget.editor,
        registry: _registry,
        interaction: interaction,
        cursor: SystemMouseCursors.text,
        // The caret's own recognizer already owns taps here; a second one in
        // the same arena would win and the caret would stop moving.
        handleTaps: false,
        child: child,
      );
    }

    return Actions(
      // The one action that makes a custom editable behave like a text field.
      //
      // `DefaultTextEditingShortcuts` — which `WidgetsApp` installs over the
      // whole application — binds space, backspace, the arrows and the rest to
      // text intents. `EditableText` supplies the matching actions; anything
      // that is *not* an `EditableText` does not, so those intents go
      // unhandled and the key carries on up the tree to whatever is above.
      // For space that is a scrollable, and the visible result is the page
      // jumping a screen down every time a word is finished. `consumesKey:
      // false` is what `EditableText` uses and what is wanted here too: the
      // intent is handled so the key stops travelling, and the key itself is
      // left unconsumed so the input method still delivers the character.
      actions: <Type, Action<Intent>>{
        DoNothingAndStopPropagationTextIntent: DoNothingAction(
          consumesKey: false,
        ),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKeyEvent,
        child: hover(
          NotificationListener<ScrollNotification>(
            // Handles that stay behind while the text scrolls away are worse
            // than no handles at all.
            onNotification: (_) {
              _overlay?.update();
              return false;
            },
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      TapGestureRecognizer.new,
                      (instance) => instance
                        ..onTapDown = _onTapDown
                        ..onTapUp = _onTapUp
                        ..onSecondaryTapDown = _onSecondaryTapDown,
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
                          hideToolbar();
                          _selectWordAt(details.globalPosition);
                          _rememberDragBase();
                          if (_wantsHandles) showHandles();
                        }
                        ..onLongPressMoveUpdate = (details) {
                          _extendDragTo(details.globalPosition);
                        }
                        ..onLongPressEnd = (_) {
                          _endDrag();
                          // Unconditionally, exactly as a right-click does. A
                          // long press *is* the request for the menu, and the
                          // menu adapts itself: with a range it offers cut and
                          // copy, with a bare caret paste and select-all.
                          // Gating it on there being a range meant a long press
                          // on an empty field — where there is no word to
                          // select — produced nothing at all, so there was no
                          // way to paste into one.
                          showToolbar();
                        }
                        ..onLongPressCancel = _endDrag,
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
                        ..onUpdate = _onDragUpdate
                        ..onEnd = _onDragEnd
                        // A drag the arena takes away mid-way must not leave
                        // its base behind: the next one would then span from
                        // wherever this one began.
                        ..onCancel = _onDragCancel,
                    ),
              },
              child: document,
            ),
          ),
        ),
      ),
    );
  }
}
