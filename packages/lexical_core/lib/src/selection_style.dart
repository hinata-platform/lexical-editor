/// Reading and writing the CSS style of a selection.
///
/// The counterpart to [RangeSelectionEditing.formatText]. Bold is a bit in a
/// bitmask the wire format defines; a colour, a font, a size are CSS, which
/// the model deliberately does not interpret — so "make this red" cannot be a
/// flag, it has to be a patch against whatever declarations the text already
/// carries.
///
/// That is the whole reason [$patchStyleText] exists rather than a setter.
/// Replacing a node's style outright is one line
/// ([RangeSelectionEditing.setTextStyle]) and it silently drops the font size
/// the writer set a minute ago. Patching changes the one property asked for
/// and leaves the rest of the declaration alone.
///
/// ```dart
/// editor.update(() {
///   $patchStyleText($getSelection(), {
///     'color': const StyleValue('#c0392b'),
///     'font-size': const StyleValue.unset(),
///   });
/// });
/// ```
library;

import 'css.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';
import 'selection_ops.dart';
import 'updates.dart';

/// What one entry of a [StylePatch] does to its declaration.
///
/// Three shapes, because a style patch has three jobs: set a property, drop
/// it, or derive the new value from the current one — which is what a toggle
/// needs, since it cannot know in advance which way it is going.
final class StyleValue {
  /// Sets the declaration to [css], whatever it was before.
  const StyleValue(String css) : _css = css, _derive = null, _unset = false;

  /// Drops the declaration.
  ///
  /// The property is removed rather than set to an empty value: an empty
  /// declaration is not valid CSS and would not survive a round trip.
  const StyleValue.unset() : _css = null, _derive = null, _unset = true;

  /// Derives the new value from the current one.
  ///
  /// [derive] receives the declaration's present value, or `null` when the
  /// property is not set, and returns the new one — or `null` to drop it.
  const StyleValue.derived(String? Function(String? current) derive)
    : _css = null,
      _derive = derive,
      _unset = false;

  final String? _css;
  final String? Function(String?)? _derive;
  final bool _unset;

  String? _apply(String? current) {
    if (_unset) return null;
    final derive = _derive;
    return derive == null ? _css : derive(current);
  }
}

/// CSS declarations to apply, keyed by property name.
///
/// Property names are the CSS ones — `font-size`, not `fontSize` — because
/// they are written into the document verbatim and read back by Lexical web.
typedef StylePatch = Map<String, StyleValue>;

/// Applies [patch] to [css] and returns the new declaration string.
String _patched(String css, StylePatch patch) {
  final styles = getStyleObjectFromCss(css);
  for (final entry in patch.entries) {
    final next = entry.value._apply(styles[entry.key]);
    if (next == null) {
      styles.remove(entry.key);
    } else {
      styles[entry.key] = next;
    }
  }
  return getCssFromStyleObject(styles);
}

/// Patching the style of a text node.
extension TextNodeStylePatch on TextNode {
  /// Applies [patch] to this node's CSS declarations.
  ///
  /// Only the properties [patch] names change; everything else the node
  /// carries is preserved.
  void patchStyle(StylePatch patch) => setStyle(_patched(getStyle(), patch));
}

/// Patching the style an element hands to text typed into it.
extension ElementNodeStylePatch on ElementNode {
  /// Applies [patch] to this element's [ElementNode.getTextStyle].
  ///
  /// An empty block has no text node to carry a style, so it keeps one of its
  /// own — that is what makes a colour chosen in an empty paragraph still
  /// apply to the first character typed there.
  void patchStyle(StylePatch patch) =>
      setTextStyle(_patched(getTextStyle(), patch));
}

/// Patching the style a collapsed selection will type with.
extension RangeSelectionStylePatch on RangeSelection {
  /// Applies [patch] to [RangeSelection.style].
  void patchStyle(StylePatch patch) {
    style = _patched(style, patch);
    dirty = true;
  }
}

/// Applies [patch] to every text node the selection covers.
///
/// A partially selected node is split so the patch lands on exactly the
/// covered run, the way [RangeSelectionEditing.formatText] does. A collapsed
/// selection records the patch as *pending* instead, so it applies to the
/// next character typed rather than to nothing at all — pressing a colour and
/// then typing is the common case, and an implementation that only styles
/// existing text silently does nothing there.
///
/// Empty elements the selection covers are patched too, so the style survives
/// in a paragraph that has no text yet.
///
/// Must be called inside an update.
void $patchStyleText(BaseSelection? selection, StylePatch patch) {
  if (selection == null) return;
  errorOnReadOnly();

  if (selection is RangeSelection && selection.isCollapsed) {
    selection.patchStyle(patch);
    final anchorNode = selection.anchor.getNode();
    if (anchorNode is ElementNode && anchorNode.isEmpty) {
      anchorNode.patchStyle(patch);
    }
  }

  $forEachSelectedTextNode(
    (textNode) => textNode.patchStyle(patch),
    selection: selection,
  );

  // Read after the splitting above, so the nodes are the ones that now exist.
  final patched = <NodeKey>{};
  for (final node in selection.getNodes()) {
    if (node is! ElementNode || !node.canBeEmpty || !node.isEmpty) continue;
    if (!patched.add(node.key)) continue;
    node.patchStyle(patch);
  }
}

/// Runs [fn] over every text node the selection covers.
///
/// Nodes the selection covers only in part are split first, so [fn] always
/// receives a node the selection covers whole — which is what makes "bold the
/// middle of this word" produce three nodes rather than one bold word. A node
/// the selection merely touches the edge of covers no text and is skipped, so
/// a selection ending exactly at a node's start does not style it.
///
/// Token and segmented nodes are never split: they are atomic by declaration,
/// and half a mention chip is not a smaller mention chip. They are passed to
/// [fn] whole or not at all. A node type that should not be styled at all
/// says so with [TextNode.canHaveFormat].
///
/// [selection] defaults to the current one. Passing it explicitly is what
/// lets a caller work against a selection it is holding rather than the one
/// the editor state happens to have.
///
/// Must be called inside an update.
void $forEachSelectedTextNode(
  void Function(TextNode textNode) fn, {
  BaseSelection? selection,
}) {
  final target = selection ?? $getSelection();
  if (target == null) return;

  final nodes = target.getNodes();
  if (nodes.isEmpty) return;

  // The boundary points are captured before anything is split: a split moves
  // the very offsets the remaining nodes would be measured against.
  Point? start;
  Point? end;
  if (target is RangeSelection) {
    final (first, last) = target.orderedPoints;
    start = first;
    end = last;
  }

  final targets = <TextNode>[];
  TextNode? splitStart;
  TextNode? splitEnd;

  for (final node in nodes) {
    if (node is! TextNode || !node.canHaveFormat) continue;

    final size = node.getTextContentSize();
    var from = 0;
    var to = size;
    if (start != null &&
        start.type == PointType.text &&
        start.key == node.key) {
      from = start.offset.clamp(0, size);
    }
    if (end != null && end.type == PointType.text && end.key == node.key) {
      to = end.offset.clamp(from, size);
    }
    if (to <= from) continue;

    if (node.isToken || node.isSegmented || (from == 0 && to == size)) {
      targets.add(node);
      continue;
    }

    final parts = node.splitText([from, to]);
    final covered = parts[from == 0 ? 0 : 1];
    targets.add(covered);
    if (start != null && start.key == node.key) splitStart = covered;
    if (end != null && end.key == node.key) splitEnd = covered;
  }

  // A split leaves the points addressing the shortened original, whose text
  // no longer reaches the offset they name. Only the ends that actually moved
  // are rewritten, so a selection that needed no splitting keeps its exact
  // shape — including its direction.
  if (splitStart != null) start!.set(splitStart.key, 0, PointType.text);
  if (splitEnd != null) {
    end!.set(splitEnd.key, splitEnd.getTextContentSize(), PointType.text);
  }

  for (final node in targets) {
    fn(node);
  }
}

/// Swaps [selection]'s ends so the anchor comes first.
///
/// A backwards drag is a selection whose focus precedes its anchor, and that
/// order is meaningful — it is which end a shift-arrow moves. Normalize it
/// only when the direction genuinely does not matter to what happens next,
/// such as when serializing a range.
void $ensureForwardRangeSelection(RangeSelection selection) {
  if (!selection.isBackward) return;
  final anchor = selection.anchor;
  final focus = selection.focus;
  final key = anchor.key;
  final offset = anchor.offset;
  final type = anchor.type;
  anchor.set(focus.key, focus.offset, focus.type);
  focus.set(key, offset, type);
}

/// The value every selected text node gives [property], or [defaultValue].
///
/// The reader behind a toolbar's colour swatch and size field. Three answers,
/// and the difference between them is the whole point:
///
/// * the shared value, when every covered node agrees;
/// * `''`, when they disagree — which is what a picker shows as "mixed",
///   and must not be confused with the value being unset;
/// * [defaultValue], when nothing is covered or nothing sets the property.
///
/// A collapsed selection answers from its pending style first, so a colour
/// chosen but not yet typed reads back as the current one.
///
/// Nodes the selection only touches the edge of are excluded: a selection
/// starting at the very end of one node and running into the next is not a
/// selection of the first one, and letting it vote would report "mixed" for a
/// range the writer sees as uniform.
String $getSelectionStyleValueForProperty(
  BaseSelection selection,
  String property, [
  String defaultValue = '',
]) {
  String? styleValue;
  final nodes = selection.getNodes();

  NodeKey? excludedFirst;
  NodeKey? excludedRest;
  if (selection is RangeSelection) {
    if (selection.isCollapsed && selection.style.isNotEmpty) {
      final pending = getStyleObjectFromCss(selection.style)[property];
      if (pending != null) return pending;
    }
    final (start, end) = selection.orderedPoints;
    final startNode = start.getNode();
    if (startNode is TextNode &&
        start.offset == startNode.getTextContentSize()) {
      excludedFirst = startNode.key;
    }
    if (end.offset == 0) excludedRest = end.getNode()?.key;
  }

  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! TextNode) continue;
    if (node.key == (i == 0 ? excludedFirst : excludedRest)) continue;

    final value =
        getStyleObjectFromCss(node.getStyle())[property] ?? defaultValue;
    if (styleValue == null) {
      styleValue = value;
    } else if (styleValue != value) {
      // Covered nodes disagree, and there is no single answer to report.
      styleValue = '';
      break;
    }
  }

  return styleValue ?? defaultValue;
}
