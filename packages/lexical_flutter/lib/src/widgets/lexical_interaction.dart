/// Hover and tap for the nodes a document links out of.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'block_registry.dart';

/// A node under the pointer, with everything needed to act on it.
///
/// Deliberately a **snapshot**, not a node. It is handed to callbacks that
/// outlive the read it was resolved in — a hover handler stores it in state and
/// a preview card reads it three frames later — and a node reference is only
/// valid inside `editor.read`. Everything here is a plain value, so it stays
/// true for as long as the application holds it.
@immutable
final class LexicalNodeHit {
  /// Describes the node [key] found under [globalPosition].
  const LexicalNodeHit({
    required this.key,
    required this.type,
    required this.text,
    required this.json,
    required this.rect,
    required this.globalPosition,
  });

  /// The node's key, for looking it up again inside a read.
  final NodeKey key;

  /// The node's type string — `link`, `mention`, `hashtag`, whatever matched.
  final String type;

  /// The node's text content.
  final String text;

  /// The node's serialized fields.
  ///
  /// This is how a caller reads `url` from a link or `mentionId` from a
  /// mention without this package knowing that either type exists. Element
  /// nodes carry an empty `children` list; the fields are what matters.
  final Map<String, Object?> json;

  /// The node's bounds in global coordinates.
  ///
  /// Anchor a preview card to this. A node broken across lines reports the
  /// union of its line boxes, which is the rectangle a popover should avoid
  /// rather than the one it should point at — use [globalPosition] when the
  /// pointer's own position is the better anchor.
  final Rect rect;

  /// Where the pointer was.
  final Offset globalPosition;

  @override
  String toString() => 'LexicalNodeHit($type $key, "$text")';
}

/// Called when the pointer enters, leaves or taps an interactive node.
typedef LexicalNodeHitCallback = void Function(LexicalNodeHit hit);

/// Declares which node types react to the pointer, and what happens when they
/// do.
///
/// The point of a smart link: hovering an issue shows a preview, tapping it
/// navigates. Both need to know *which* node is under the pointer, and that is
/// what this resolves — by **type string**, so this package still knows
/// nothing about links, mentions or hashtags.
///
/// ```dart
/// LexicalInteraction(
///   types: const {'link', 'autolink', 'mention', 'hashtag'},
///   onEnter: (hit) => previewController.show(hit),
///   onExit: (hit) => previewController.hide(hit.key),
///   onTap: (hit) => switch (hit.type) {
///     'mention' => context.go('/users/${hit.json['mentionId']}'),
///     _ => launchUrlString(hit.json['url']! as String),
///   },
/// )
/// ```
///
/// [onEnter] and [onExit] are mouse events: they never fire on a touch screen,
/// where there is no pointer to hover with. Anything reachable only by hover is
/// unreachable on a phone, so treat a preview as an enhancement and put what
/// matters behind [onTap].
@immutable
final class LexicalInteraction {
  /// Makes nodes whose type is in [types] respond to the pointer.
  const LexicalInteraction({
    required this.types,
    this.onTap,
    this.onEnter,
    this.onExit,
    this.cursor = SystemMouseCursors.click,
  });

  /// The node types that react. Nothing else is hit-tested.
  ///
  /// A node inside one of these — the text inside a link — resolves to its
  /// nearest matching **ancestor**, which is what makes a link tappable
  /// although the pointer is over one of its text children.
  final Set<String> types;

  /// Called when an interactive node is tapped.
  ///
  /// Fires on tap **up**, so a drag that started on a link does not navigate.
  /// In an editable the caret still moves to the tap: refusing to place it
  /// would leave the text inside a link unreachable. Navigation that must not
  /// happen while editing belongs behind a modifier or a read-only view, and
  /// that is the application's call, not this package's.
  ///
  /// One timing note worth knowing before it is mistaken for lag: inside an
  /// editable the tap resolves only after the **double-tap deadline**
  /// (~300 ms), because double-tap-to-select shares the gesture arena. A
  /// read-only
  /// document runs no such recognizer and reacts immediately, which is what a
  /// list of smart links wants anyway.
  final LexicalNodeHitCallback? onTap;

  /// Called when the mouse enters an interactive node.
  final LexicalNodeHitCallback? onEnter;

  /// Called when the mouse leaves one, with the node it left.
  final LexicalNodeHitCallback? onExit;

  /// The cursor shown over an interactive node.
  final MouseCursor cursor;

  @override
  bool operator ==(Object other) =>
      other is LexicalInteraction &&
      setEquals(other.types, types) &&
      other.onTap == onTap &&
      other.onEnter == onEnter &&
      other.onExit == onExit &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(types),
    onTap,
    onEnter,
    onExit,
    cursor,
  );
}

/// The interactive node under [globalPosition], or `null`.
///
/// Resolution runs from the glyph outwards: the flat offset under the pointer
/// names a segment, the segment names a node, and the walk up the ancestors
/// stops at the first type asked for. The hit is then confirmed against the
/// node's own line boxes — without that, `getPositionForOffset` happily
/// reports the nearest position for a point far to the right of the last word,
/// and a link at the end of a line would answer for the whole margin beside
/// it.
LexicalNodeHit? hitTestNodes({
  required BlockRegistry registry,
  required LexicalEditor editor,
  required Set<String> types,
  required Offset globalPosition,
}) {
  if (types.isEmpty) return null;
  final block = registry.blockAt(globalPosition);
  if (block == null || !block.render.attached || !block.render.hasSize) {
    return null;
  }
  final local = block.render.globalToLocal(globalPosition);
  final position = block.render.getPositionForOffset(local);
  final segment = block.offsets.segmentAt(position.offset);
  if (segment == null) return null;

  final resolved = editor.read<({NodeKey key, String type, Set<NodeKey> own})?>(
    () {
      var node = $getNodeByKey(segment.key);
      while (node != null && !types.contains(node.type)) {
        node = node.getParent();
      }
      if (node == null) return null;
      final own = <NodeKey>{node.key};
      if (node is ElementNode) {
        void collect(ElementNode element) {
          for (final child in element.children) {
            own.add(child.key);
            if (child is ElementNode) collect(child);
          }
        }

        collect(node);
      }
      return (key: node.key, type: node.type, own: own);
    },
  );
  if (resolved == null) return null;

  var start = -1;
  var end = -1;
  for (final candidate in block.offsets.segments) {
    if (!resolved.own.contains(candidate.key)) continue;
    if (start < 0 || candidate.flatStart < start) start = candidate.flatStart;
    if (candidate.flatEnd > end) end = candidate.flatEnd;
  }
  if (start < 0 || end <= start) return null;

  final boxes = block.render.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
  if (boxes.isEmpty) return null;
  Rect? bounds;
  var inside = false;
  for (final box in boxes) {
    final rect = box.toRect();
    bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    if (rect.contains(local)) inside = true;
  }
  if (!inside || bounds == null) return null;

  final origin = block.render.localToGlobal(Offset.zero);
  return editor.read(() {
    final node = $getNodeByKey(resolved.key);
    if (node == null) return null;
    return LexicalNodeHit(
      key: resolved.key,
      type: resolved.type,
      text: node.getTextContent(),
      json: node.exportJson(),
      rect: bounds!.shift(origin),
      globalPosition: globalPosition,
    );
  });
}

/// Turns pointer movement over a document into [LexicalInteraction] callbacks.
///
/// Used by `LexicalDocument` and `LexicalEditable`; an application configures
/// it through their `interaction` parameter rather than mounting it directly.
class LexicalInteractionRegion extends StatefulWidget {
  /// Watches the pointer over [child].
  const LexicalInteractionRegion({
    required this.editor,
    required this.registry,
    required this.interaction,
    required this.child,
    super.key,
    this.cursor = MouseCursor.defer,
    this.handleTaps = true,
  });

  /// The editor whose nodes are being resolved.
  final LexicalEditor editor;

  /// The registry of mounted blocks to hit-test against.
  final BlockRegistry registry;

  /// What reacts, and how.
  final LexicalInteraction interaction;

  /// The cursor shown when the pointer is *not* over an interactive node.
  final MouseCursor cursor;

  /// Whether this region recognizes taps itself.
  ///
  /// `false` inside an editable, which already runs a tap recognizer for the
  /// caret: two recognizers in one arena means the inner one wins and the
  /// caret stops moving. The editable feeds its own taps in instead.
  final bool handleTaps;

  /// The document being watched.
  final Widget child;

  @override
  State<LexicalInteractionRegion> createState() =>
      LexicalInteractionRegionState();
}

/// State of a [LexicalInteractionRegion], for feeding in external taps.
class LexicalInteractionRegionState extends State<LexicalInteractionRegion> {
  LexicalNodeHit? _hovered;

  /// Reports a tap at [globalPosition], as an editable's recognizer does.
  ///
  /// Returns whether an interactive node was hit.
  bool handleTapAt(Offset globalPosition) {
    final onTap = widget.interaction.onTap;
    if (onTap == null) return false;
    final hit = _hitTest(globalPosition);
    if (hit == null) return false;
    onTap(hit);
    return true;
  }

  LexicalNodeHit? _hitTest(Offset globalPosition) => hitTestNodes(
    registry: widget.registry,
    editor: widget.editor,
    types: widget.interaction.types,
    globalPosition: globalPosition,
  );

  void _onHover(PointerHoverEvent event) {
    final interaction = widget.interaction;
    if (interaction.onEnter == null &&
        interaction.onExit == null &&
        interaction.cursor == MouseCursor.defer) {
      return;
    }
    final hit = _hitTest(event.position);
    // Moving within the same node is not an event. Without this a preview
    // card is torn down and rebuilt on every mouse move across the word it
    // belongs to.
    if (hit?.key == _hovered?.key) return;
    final left = _hovered;
    setState(() => _hovered = hit);
    if (left != null) interaction.onExit?.call(left);
    if (hit != null) interaction.onEnter?.call(hit);
  }

  void _onExit() {
    final left = _hovered;
    if (left == null) return;
    setState(() => _hovered = null);
    widget.interaction.onExit?.call(left);
  }

  @override
  void didUpdateWidget(LexicalInteractionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A document that changed under a stationary pointer may no longer have
    // the node we think we are on; the next move resolves it, but the state
    // must not claim a node that is gone.
    if (_hovered != null && !identical(oldWidget.editor, widget.editor)) {
      _hovered = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.handleTaps
        ? GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTapUp: (details) => handleTapAt(details.globalPosition),
            child: widget.child,
          )
        : widget.child;
    return MouseRegion(
      cursor: _hovered == null ? widget.cursor : widget.interaction.cursor,
      onHover: _onHover,
      onExit: (_) => _onExit(),
      child: content,
    );
  }
}
