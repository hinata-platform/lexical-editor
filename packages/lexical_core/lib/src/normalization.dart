/// Canonicalizing the tree after an edit.
///
/// Normalization belongs here rather than scattered through command
/// handlers: keeping it in one place run over dirty nodes is what makes the
/// model self-healing regardless of how an edit arrived — typing, paste, a
/// programmatic mutation, or a collaborative patch.
library;

import 'package:meta/meta.dart';

import 'errors.dart';
import 'nodes/line_break_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';

/// Merges [node] with adjacent runs it is equivalent to, and drops it when
/// it has become empty.
///
/// This is required for wire compatibility, not merely tidiness: upstream
/// merges adjacent identical runs, so a port that does not would emit a
/// different node count for the same document.
@internal
void $normalizeTextNode(TextNode node) {
  var current = node;

  if (current.textInternal.isEmpty &&
      current.isSimpleText &&
      !current.isUnmergeable) {
    current.remove();
    return;
  }

  // Backwards.
  while (true) {
    final previous = current.getPreviousSibling();
    if (previous is! TextNode ||
        !previous.isSimpleText ||
        previous.isUnmergeable) {
      break;
    }
    if (previous.textInternal.isEmpty) {
      previous.remove();
      continue;
    }
    if (!previous.canMergeWith(current)) break;
    current = mergeTextNodes(previous, current);
    break;
  }

  // Forwards.
  while (true) {
    final next = current.getNextSibling();
    if (next is! TextNode || !next.isSimpleText || next.isUnmergeable) break;
    if (next.textInternal.isEmpty) {
      next.remove();
      continue;
    }
    if (!current.canMergeWith(next)) break;
    current = mergeTextNodes(current, next);
    break;
  }
}

/// Merges [target] into [node], which must be an immediate sibling.
///
/// Selection points inside the disappearing node are re-anchored onto the
/// survivor with their offsets adjusted; otherwise the commit would fail
/// with a lost selection far from the merge that caused it.
@internal
TextNode mergeTextNodes(TextNode node, TextNode target) {
  final previous = node.getPreviousSibling();
  final isBefore = previous != null && previous.key == target.key;
  if (!isBefore) {
    final next = node.getNextSibling();
    if (next == null || next.key != target.key) {
      throw const LexicalTreeError(
        'mergeTextNodes: target must be an immediate sibling',
      );
    }
  }

  final text = node.getTextContent();
  final textLength = text.length;
  final selection = $getSelection();
  if (selection is RangeSelection) {
    for (final point in [selection.anchor, selection.focus]) {
      if (point.key != target.key) continue;
      if (point.type == PointType.text) {
        point.set(
          node.key,
          isBefore ? point.offset : point.offset + textLength,
          PointType.text,
        );
      } else if (point.offset > target.indexWithinParent) {
        point.set(point.key, point.offset - 1, point.type);
      }
    }
  }

  final targetText = target.getTextContent();
  node.setTextContent(isBefore ? '$targetText$text' : '$text$targetText');
  final writable = node.getWritable<TextNode>();
  target.remove();
  return writable;
}

/// Splits a text node containing newlines into runs separated by line breaks.
///
/// A text node must never contain `\n`. Documents reach this state through
/// paste and through programmatic insertion, so the repair belongs in a
/// transform rather than at every call site that could introduce one.
@internal
void $splitNewlines(TextNode node) {
  final text = node.getTextContent();
  if (!text.contains('\n')) return;
  if (node.getParent() == null) return;

  final segments = text.split('\n');
  final writable = node.setTextContent(segments.first);
  var anchor = writable;
  for (final segment in segments.skip(1)) {
    final lineBreak = $createLineBreakNode();
    anchor.insertAfter(lineBreak);
    final next = node.clone()
      ..textInternal = segment
      ..formatInternal = writable.formatInternal
      ..styleInternal = writable.styleInternal
      ..modeInternal = writable.modeInternal
      ..detailInternal = writable.detailInternal;
    lineBreak.insertAfter(next);
    anchor = next;
  }
}
