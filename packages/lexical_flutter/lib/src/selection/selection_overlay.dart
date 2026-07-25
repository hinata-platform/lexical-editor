/// Drag handles, the context toolbar and the magnifier.
///
/// These are the parts of a text field a user touches rather than types into,
/// and Flutter already ships every piece: [TextSelectionControls] draws the
/// platform's handles, [AdaptiveTextSelectionToolbar] draws its menu, and
/// [TextMagnifierConfiguration] its magnifier. What is missing is the
/// geometry, because all of that machinery is bolted to `RenderEditable` and
/// this editor is a column of block render objects instead.
///
/// So this file supplies the geometry and reuses the chrome. The result looks
/// native on every platform without this package having an opinion about how
/// a handle should look — which it should not, since Material and Cupertino
/// disagree and so will the application.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/lexical_editable.dart';

/// Where the two ends of a selection sit, in global coordinates.
@immutable
final class SelectionEndpoints {
  /// Records the ends of a selection.
  const SelectionEndpoints({
    required this.start,
    required this.end,
    required this.startHeight,
    required this.endHeight,
  });

  /// The bottom-left of the first selected glyph.
  final Offset start;

  /// The bottom-right of the last selected glyph.
  final Offset end;

  /// Line height at the start, which sizes the handle.
  final double startHeight;

  /// Line height at the end.
  final double endHeight;

  /// Whether both ends coincide.
  bool get isCollapsed => start == end;

  @override
  bool operator ==(Object other) =>
      other is SelectionEndpoints &&
      other.start == start &&
      other.end == end &&
      other.startHeight == startHeight &&
      other.endHeight == endHeight;

  @override
  int get hashCode => Object.hash(start, end, startHeight, endHeight);
}

/// Builds the menu shown over a selection.
typedef LexicalContextMenuBuilder =
    Widget Function(BuildContext context, LexicalEditableState editable);

/// The platform's own selection menu, with the usual four entries.
///
/// [AdaptiveTextSelectionToolbar] picks the right shape and the localized
/// labels for the platform it runs on, so this is one line rather than four
/// designs.
Widget defaultLexicalContextMenu(
  BuildContext context,
  LexicalEditableState editable,
) {
  final anchors = editable.contextMenuAnchors;
  if (anchors == null) return const SizedBox.shrink();
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: editable.contextMenuButtonItems,
  );
}

/// The handles, toolbar and magnifier of one editable.
///
/// Owned by [LexicalEditableState]; an application does not build one.
final class LexicalSelectionOverlay {
  /// Creates an overlay for [editable], anchored in [context].
  LexicalSelectionOverlay({
    required this.context,
    required this.editable,
    required this.selectionControls,
    required this.contextMenuBuilder,
    required this.magnifierConfiguration,
  });

  /// The editable's context, used to find the overlay.
  final BuildContext context;

  /// The editable whose selection is being decorated.
  final LexicalEditableState editable;

  /// Platform handles. `null` disables handles altogether.
  final TextSelectionControls? selectionControls;

  /// Builds the context menu.
  final LexicalContextMenuBuilder contextMenuBuilder;

  /// How to magnify under a dragging finger.
  final TextMagnifierConfiguration magnifierConfiguration;

  final MagnifierController _magnifier = MagnifierController();
  final ValueNotifier<MagnifierInfo> _magnifierInfo =
      ValueNotifier<MagnifierInfo>(MagnifierInfo.empty);

  OverlayEntry? _handlesEntry;
  OverlayEntry? _toolbarEntry;
  bool _draggingHandle = false;

  /// Whether the drag handles are on screen.
  bool get handlesVisible => _handlesEntry != null;

  /// Whether the context menu is on screen.
  bool get toolbarVisible => _toolbarEntry != null;

  /// Shows the drag handles.
  void showHandles() {
    if (_handlesEntry != null || selectionControls == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _handlesEntry = OverlayEntry(builder: _buildHandles);
    overlay.insert(_handlesEntry!);
  }

  /// Hides the drag handles.
  void hideHandles() {
    _handlesEntry?.remove();
    _handlesEntry = null;
  }

  /// Shows the context menu.
  void showToolbar() {
    if (_toolbarEntry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _toolbarEntry = OverlayEntry(
      builder: (_) => contextMenuBuilder(context, editable),
    );
    overlay.insert(_toolbarEntry!);
  }

  /// Hides the context menu.
  void hideToolbar() {
    _toolbarEntry?.remove();
    _toolbarEntry = null;
  }

  /// Hides everything.
  void hide() {
    hideToolbar();
    hideHandles();
    _hideMagnifier();
  }

  /// Rebuilds the overlay against the current geometry.
  ///
  /// Called on every commit and on every scroll: handles that do not follow
  /// the text they point at are worse than no handles.
  void update() {
    if (editable.selectionEndpoints == null) {
      hide();
      return;
    }
    _handlesEntry?.markNeedsBuild();
    _toolbarEntry?.markNeedsBuild();
  }

  /// Releases the overlay.
  void dispose() {
    hide();
    _magnifierInfo.dispose();
  }

  // -------------------------------------------------------------------
  // Handles
  // -------------------------------------------------------------------

  Widget _buildHandles(BuildContext overlayContext) {
    final controls = selectionControls;
    final endpoints = editable.selectionEndpoints;
    if (controls == null || endpoints == null) return const SizedBox.shrink();

    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) {
      return const SizedBox.shrink();
    }

    if (endpoints.isCollapsed) {
      // One handle under the caret, which is how a touch platform lets a
      // caret be moved without a selection existing first.
      return Stack(
        children: <Widget>[
          _handle(
            overlayBox,
            controls,
            TextSelectionHandleType.collapsed,
            endpoints.start,
            endpoints.startHeight,
            isStart: true,
          ),
        ],
      );
    }
    return Stack(
      children: <Widget>[
        _handle(
          overlayBox,
          controls,
          TextSelectionHandleType.left,
          endpoints.start,
          endpoints.startHeight,
          isStart: true,
        ),
        _handle(
          overlayBox,
          controls,
          TextSelectionHandleType.right,
          endpoints.end,
          endpoints.endHeight,
          isStart: false,
        ),
      ],
    );
  }

  Widget _handle(
    RenderBox overlayBox,
    TextSelectionControls controls,
    TextSelectionHandleType type,
    Offset globalPosition,
    double lineHeight, {
    required bool isStart,
  }) {
    final anchor = controls.getHandleAnchor(type, lineHeight);
    final size = controls.getHandleSize(lineHeight);
    final local = overlayBox.globalToLocal(globalPosition);

    return Positioned(
      left: local.dx - anchor.dx,
      top: local.dy - anchor.dy,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.start,
        onPanStart: (details) {
          _draggingHandle = true;
          hideToolbar();
          _showMagnifier(details.globalPosition);
        },
        onPanUpdate: (details) {
          _dragTo(details.globalPosition, isStart: isStart);
          _showMagnifier(details.globalPosition);
        },
        onPanEnd: (_) {
          _draggingHandle = false;
          _hideMagnifier();
          showToolbar();
        },
        onPanCancel: () {
          _draggingHandle = false;
          _hideMagnifier();
        },
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: controls.buildHandle(context, type, lineHeight),
        ),
      ),
    );
  }

  /// Moves one end of the selection, leaving the other where it was.
  ///
  /// Dragging the left handle moves the *start* of the selection whichever
  /// way round anchor and focus happen to be — the user is pointing at a
  /// glyph, not at a data structure.
  void _dragTo(Offset globalPosition, {required bool isStart}) {
    editable.extendSelectionTo(globalPosition, movingStart: isStart);
  }

  // -------------------------------------------------------------------
  // Magnifier
  // -------------------------------------------------------------------

  void _showMagnifier(Offset globalPosition) {
    final caret = editable.caretRect;
    final bounds = editable.editableBounds;
    if (caret == null || bounds == null) return;

    _magnifierInfo.value = MagnifierInfo(
      globalGesturePosition: globalPosition,
      caretRect: caret,
      fieldBounds: bounds,
      currentLineBoundaries: caret,
    );
    if (_magnifier.overlayEntry != null) return;
    _magnifier.show(
      context: context,
      builder: (magnifierContext) =>
          magnifierConfiguration.magnifierBuilder(
            magnifierContext,
            _magnifier,
            _magnifierInfo,
          ) ??
          const SizedBox.shrink(),
    );
  }

  void _hideMagnifier() {
    if (_magnifier.overlayEntry == null) return;
    _magnifier.hide();
  }

  /// Whether a handle is being dragged, so the caret should not blink away.
  bool get isDraggingHandle => _draggingHandle;
}
