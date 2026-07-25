/// Resolving the model's selection into something a block can paint.
library;

import 'package:flutter/rendering.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

import '../render/block_offset_map.dart';

/// A point together with the block that contains it.
@immutable
final class BlockPoint {
  /// Records [point] as belonging to [blockKey].
  const BlockPoint(this.blockKey, this.point);

  /// The block the point sits in.
  final NodeKey blockKey;

  /// The point itself.
  final ResolvedPoint point;

  @override
  bool operator ==(Object other) =>
      other is BlockPoint && other.blockKey == blockKey && other.point == point;

  @override
  int get hashCode => Object.hash(blockKey, point);

  @override
  String toString() => 'BlockPoint($blockKey, $point)';
}

/// One block's share of a selection that may cover several.
///
/// A `null` end means "to this block's edge", which is what a block wholly
/// inside the selection looks like. Storing it that way rather than as a
/// resolved offset means the span stays correct while the block is still
/// being laid out.
@immutable
final class BlockSelectionSpan {
  /// Describes the part of [blockKey] the selection covers.
  const BlockSelectionSpan({required this.blockKey, this.start, this.end});

  /// The block this span belongs to.
  final NodeKey blockKey;

  /// Where the selection starts, or `null` for the block's start.
  final ResolvedPoint? start;

  /// Where the selection ends, or `null` for the block's end.
  final ResolvedPoint? end;

  @override
  bool operator ==(Object other) =>
      other is BlockSelectionSpan &&
      other.blockKey == blockKey &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(blockKey, start, end);

  @override
  String toString() => 'BlockSelectionSpan($blockKey, $start..$end)';
}

/// The model's selection, split across the blocks it touches.
@immutable
final class DocumentSelection {
  /// Records [spans] and the [caret].
  const DocumentSelection({required this.spans, this.caret});

  /// The highlighted ranges, one entry per block, in document order.
  final List<BlockSelectionSpan> spans;

  /// Where the caret sits, or `null` when nothing is selected.
  final BlockPoint? caret;

  /// Whether there is a range to highlight.
  bool get hasRange => spans.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DocumentSelection &&
      other.caret == caret &&
      _listEquals(other.spans, spans);

  @override
  int get hashCode => Object.hash(caret, Object.hashAll(spans));

  static bool _listEquals(
    List<BlockSelectionSpan> a,
    List<BlockSelectionSpan> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Resolves the active selection into per-block spans.
///
/// Must be called inside a read or update context.
DocumentSelection? $resolveDocumentSelection() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return null;
  final focusNode = selection.focus.getNode();
  if (focusNode == null) return null;

  final caret = BlockPoint(
    $getNearestBlock(focusNode).key,
    ResolvedPoint(
      selection.focus.key,
      selection.focus.offset,
      selection.focus.type,
    ),
  );
  if (selection.isCollapsed) {
    return DocumentSelection(spans: const [], caret: caret);
  }

  final (start, end) = selection.orderedPoints;
  final startNode = start.getNode();
  final endNode = end.getNode();
  if (startNode == null || endNode == null) {
    return DocumentSelection(spans: const [], caret: caret);
  }
  final startBlock = $getNearestBlock(startNode).key;
  final endBlock = $getNearestBlock(endNode).key;

  final spans = <BlockSelectionSpan>[];
  for (final block in selection.getBlocks()) {
    spans.add(
      BlockSelectionSpan(
        blockKey: block.key,
        start: block.key == startBlock
            ? ResolvedPoint(start.key, start.offset, start.type)
            : null,
        end: block.key == endBlock
            ? ResolvedPoint(end.key, end.offset, end.type)
            : null,
      ),
    );
  }
  return DocumentSelection(spans: spans, caret: caret);
}

/// Converts [span] into flat offsets against [offsets], or `null` when empty.
TextSelection? flatSelectionFor(
  BlockSelectionSpan span,
  BlockOffsetMap offsets,
) {
  final start = span.start;
  final end = span.end;
  final from = start == null
      ? 0
      : (offsets.flatOffsetFor(start.key, start.offset, start.type) ?? 0);
  final to = end == null
      ? offsets.length
      : (offsets.flatOffsetFor(end.key, end.offset, end.type) ??
            offsets.length);
  if (to <= from) return null;
  return TextSelection(baseOffset: from, extentOffset: to);
}
