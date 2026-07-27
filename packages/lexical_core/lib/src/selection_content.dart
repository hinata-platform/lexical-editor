/// Where a point sits, and taking content out of a selection.
///
/// Everything here answers a question about the *boundary* of a selection
/// rather than about its content: is the caret at the end of this block, does
/// this node contribute any text to the range, how much has to come off the
/// end to fit a limit. They are small, and they are the pieces that turn out
/// to be wrong when an editor deletes one character too many.
library;

import 'editor.dart';
import 'errors.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/root_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';
import 'selection_ops.dart';
import 'updates.dart';

/// Whether [point] addresses the very end of the node it sits in.
///
/// The end of a text node is past its last code unit; the end of an element
/// is past its last child. Says nothing about the document — a point at the
/// end of the first of three paragraphs is at a node end.
bool $isAtNodeEnd(Point point) {
  final node = point.getNode();
  if (point.type == PointType.text) {
    if (node is! TextNode) {
      throw LexicalStateError(
        'isAtNodeEnd: a text point must address a text node, '
        'and ${point.key} is ${node?.type ?? 'gone'}.',
      );
    }
    return point.offset == node.getTextContentSize();
  }
  if (node is! ElementNode) {
    throw LexicalStateError(
      'isAtNodeEnd: an element point must address an element, '
      'and ${point.key} is ${node?.type ?? 'gone'}.',
    );
  }
  return point.offset == node.childrenSize;
}

/// Whether nothing of [element]'s content lies before [point].
///
/// The generalization of [$isAtNodeEnd] to an ancestor: the point may sit any
/// number of levels down, and this is true only when it is at the leading
/// edge at every one of them. An empty [element] counts as both edges.
bool $isAtStartOfNode(Point point, ElementNode element) =>
    _isAtEdge(point, element, towardsStart: true);

/// Whether nothing of [element]'s content lies after [point].
bool $isAtEndOfNode(Point point, ElementNode element) =>
    _isAtEdge(point, element, towardsStart: false);

bool _isAtEdge(Point point, ElementNode element, {required bool towardsStart}) {
  final node = point.getNode();
  if (node == null) return false;

  if (point.type == PointType.text) {
    if (node is! TextNode) return false;
    final edge = towardsStart ? 0 : node.getTextContentSize();
    if (point.offset != edge) return false;
  } else {
    if (node is! ElementNode) return false;
    final edge = towardsStart ? 0 : node.childrenSize;
    if (point.offset != edge) return false;
  }

  for (LexicalNode? current = node; current != null;) {
    if (current.key == element.key) return true;
    final sibling = towardsStart
        ? current.getPreviousSibling()
        : current.getNextSibling();
    if (sibling != null) return false;
    current = current.getParent();
  }
  // [element] is not an ancestor of the point at all.
  return false;
}

/// The text of [textNode] that [selection] covers.
///
/// What an exporter needs and a node cannot answer: a copied range ends
/// mid-word if the selection did, and a text node has no notion of being
/// partly covered. Only the first and last node of a range are ever narrowed
/// — everything between them is covered whole — and a token or segmented node
/// comes back whole either way, because half of one is not a smaller one.
///
/// A node the selection does not reach at all answers with its whole text
/// rather than with nothing, matching the upstream contract: the caller is
/// asking what to write for a node it has already decided to write.
///
/// **Divergence from upstream, deliberate.** `@lexical/selection` returns a
/// *node* here, optionally a clone, and writes the shortened text into it
/// behind the accessors. Neither half of that survives the port. A clone
/// carries the original's key, so every accessor on it resolves through the
/// node map back to the original and the shortened text is unreachable; and
/// writing into the live node instead would edit the committed document from
/// inside what is meant to be a read. The text is the same information with
/// neither hazard.
String $sliceSelectedTextContent(BaseSelection selection, TextNode textNode) {
  final full = textNode.getTextContent();
  if (selection is! RangeSelection) return full;
  if (textNode.isToken || textNode.isSegmented) return full;
  if (!selection.getNodes().any((node) => node.key == textNode.key)) {
    return full;
  }

  final anchorNode = selection.anchor.getNode();
  final focusNode = selection.focus.getNode();
  if (anchorNode == null || focusNode == null) return full;
  final isAnchor = anchorNode.key == textNode.key;
  final isFocus = focusNode.key == textNode.key;
  if (!isAnchor && !isFocus) return full;

  final (anchorOffset, focusOffset) = _characterOffsets(selection);
  final backwards = selection.isBackward;
  final firstKey = backwards ? focusNode.key : anchorNode.key;
  final lastKey = backwards ? anchorNode.key : focusNode.key;

  var start = 0;
  var end = full.length;

  if (anchorNode.key == focusNode.key) {
    start = anchorOffset < focusOffset ? anchorOffset : focusOffset;
    end = anchorOffset < focusOffset ? focusOffset : anchorOffset;
  } else if (textNode.key == firstKey) {
    start = backwards ? focusOffset : anchorOffset;
  } else if (textNode.key == lastKey) {
    end = backwards ? anchorOffset : focusOffset;
  }

  start = start.clamp(0, full.length);
  end = end.clamp(start, full.length);
  return full.substring(start, end);
}

/// The two ends of [selection] as text offsets.
///
/// An element point has no text offset of its own, so it resolves to one end
/// of the element's text: past the last child means its whole length, any
/// other index means the start.
(int, int) _characterOffsets(RangeSelection selection) {
  final anchor = selection.anchor;
  final focus = selection.focus;
  if (anchor.type == PointType.element &&
      focus.type == PointType.element &&
      anchor.key == focus.key &&
      anchor.offset == focus.offset) {
    return (0, 0);
  }
  return (_characterOffset(anchor), _characterOffset(focus));
}

int _characterOffset(Point point) {
  if (point.type == PointType.text) return point.offset;
  final node = point.getNode();
  if (node is! ElementNode) return point.offset;
  return point.offset == node.childrenSize ? node.getTextContent().length : 0;
}

/// Removes [count] characters of content ending at [anchor].
///
/// The primitive behind a maximum document length: given how far over the
/// limit the document is, this takes exactly that much off, walking backwards
/// out of the anchor through whatever it finds — text, then whole nodes, then
/// the blocks holding them, counting the two characters a block boundary is
/// worth in [LexicalNode.getTextContent] so the accounting matches what was
/// measured.
///
/// A node whose text changed in this same update is *restored* rather than
/// trimmed. That is the difference between rejecting an overlong paste and
/// truncating it, and rejecting is what a length limit means: the writer gets
/// back exactly what they had, with the caret where they left it.
///
/// Must be called inside an update.
void $trimTextContentFromAnchor(LexicalEditor editor, Point anchor, int count) {
  errorOnReadOnly();
  var remaining = count;
  var current = anchor.getNode();

  if (current is ElementNode) {
    current = current.getDescendantByIndex(anchor.offset) ?? current;
  }

  while (remaining > 0 && current != null) {
    var node = current;
    if (node is ElementNode) {
      node = node.getLastDescendant() ?? node;
    }

    // Where the walk continues once this node is consumed: the previous
    // sibling, or the nearest one an ancestor has.
    var next = node.getPreviousSibling();
    var blockBoundary = 0;
    if (next == null) {
      var parent = node.getParent();
      var parentSibling = parent?.getPreviousSibling();
      while (parentSibling == null) {
        parent = parent?.getParent();
        if (parent == null) break;
        parentSibling = parent.getPreviousSibling();
      }
      if (parent != null) {
        blockBoundary = parent.isInline ? 0 : 2;
        next = parentSibling;
      }
    }

    var text = node.getTextContent();
    // An empty block still separates what is around it, and that separation
    // was counted when the document was measured.
    if (text.isEmpty && node is ElementNode && !node.isInline) text = '\n\n';
    final size = text.length;

    if (node is! TextNode || remaining >= size) {
      final parent = node.getParent();
      node.remove();
      if (parent != null && parent.isEmpty && parent is! RootNode) {
        parent.remove();
      }
      remaining -= size + blockBoundary;
      current = next;
      continue;
    }

    final previousText = _committedTextOf(editor, node.key);
    if (previousText != null && previousText != text) {
      var target = node;
      if (!node.isSimpleText) {
        final replacement = $createTextNode(previousText);
        node.replace(replacement);
        target = replacement;
      } else {
        node.setTextContent(previousText);
      }
      final previous = editor.committedEditorState.selection;
      if (previous is RangeSelection && previous.isCollapsed) {
        final offset = previous.anchor.offset;
        target.select(offset, offset);
      }
    } else if (node.isSimpleText) {
      final isAnchored = anchor.key == node.key;
      var anchorOffset = anchor.offset;
      // Below `remaining` the split would start at a negative offset; the
      // anchor is stale, so measure from the end of the node instead.
      if (anchorOffset < remaining) anchorOffset = size;
      final from = isAnchored ? anchorOffset - remaining : 0;
      final to = isAnchored ? anchorOffset : size - remaining;
      final parts = node.splitText([from, to]);
      // The removed run is the head only when it starts the node *and* the
      // anchor is what put it there; otherwise the trailing part is the one
      // that overran.
      parts[isAnchored && from == 0 ? 0 : 1].remove();
    } else {
      node.replace($createTextNode(text.substring(0, size - remaining)));
    }
    remaining = 0;
  }
}

/// The text [key] held in the last committed state, when it held simple text.
String? _committedTextOf(LexicalEditor editor, NodeKey key) =>
    readEditorState(editor.committedEditorState, () {
      final previous = $getNodeByKey(key);
      return previous is TextNode && previous.isSimpleText
          ? previous.getTextContent()
          : null;
    }, editor: editor);

/// Whether the element [node] sits in reads right-to-left.
///
/// **Divergence from upstream, of necessity:** the browser answers this from
/// the computed style of the rendered element. There is no computed style
/// here, so the answer comes from the model's own [ElementNode.getDirection],
/// which the direction pass sets from the text itself. That is the same
/// information the reconciler renders with, one step earlier.
bool $isParentRtl(LexicalNode node) =>
    _isRtl(node is RootNode ? node : node.getParent());

/// Whether the block [selection]'s anchor sits in reads right-to-left.
bool $isParentElementRtl(RangeSelection selection) {
  final node = selection.anchor.getNode();
  if (node == null) return false;
  return _isRtl(node is ElementNode ? node : node.getParent());
}

/// Direction is inherited, so the nearest ancestor that declares one wins.
bool _isRtl(ElementNode? element) {
  for (var current = element; current != null; current = current.getParent()) {
    final direction = current.getDirection();
    if (direction != null) return direction == NodeDirection.rtl;
  }
  return false;
}
