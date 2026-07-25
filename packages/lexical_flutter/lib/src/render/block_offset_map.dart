/// Mapping between a block's flat text offsets and model points.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

/// One node's contribution to a block's flat text.
@immutable
final class OffsetSegment {
  /// Describes the run [key] contributes at [flatStart].
  const OffsetSegment({
    required this.key,
    required this.flatStart,
    required this.flatLength,
    required this.modelLength,
    required this.type,
    required this.parent,
    required this.indexInParent,
  });

  /// The node this run belongs to.
  final NodeKey key;

  /// Where the run starts in the block's flat text, in UTF-16 code units.
  final int flatStart;

  /// How many flat code units the run occupies as rendered.
  final int flatLength;

  /// How many code units the run occupies in the *model*.
  ///
  /// Usually equal to [flatLength]. They diverge only when a presentational
  /// case transform changes length — `ß` uppercases to `SS` — in which case
  /// offsets inside the run are not one-to-one and the caret snaps to the
  /// run's edges rather than landing somewhere arbitrary.
  final int modelLength;

  /// How an offset inside this run should be interpreted.
  final PointType type;

  /// The element that owns this run, for element-typed points.
  final NodeKey parent;

  /// The run's child index within [parent].
  final int indexInParent;

  /// The flat offset one past the end of this run.
  int get flatEnd => flatStart + flatLength;

  /// Whether model and rendered offsets line up one to one.
  bool get isIdentity => flatLength == modelLength;

  @override
  String toString() =>
      'OffsetSegment($key, $flatStart..$flatEnd, ${type.name})';
}

/// A resolved position in the document.
@immutable
final class ResolvedPoint {
  /// Creates a point addressing [key] at [offset].
  const ResolvedPoint(this.key, this.offset, this.type);

  /// The addressed node.
  final NodeKey key;

  /// The offset within it.
  final int offset;

  /// How to interpret [offset].
  final PointType type;

  @override
  bool operator ==(Object other) =>
      other is ResolvedPoint &&
      other.key == key &&
      other.offset == offset &&
      other.type == type;

  @override
  int get hashCode => Object.hash(key, offset, type);

  @override
  String toString() => 'ResolvedPoint($key, $offset, ${type.name})';
}

/// The bidirectional map between one block's flat text and its model points.
///
/// Selection and IME both speak flat integer offsets; the model speaks
/// `(NodeKey, offset, type)`. This is the piece that reconciles them, and it
/// is built in the *same walk* that builds the block's `InlineSpan` — two maps
/// built separately drift, and the resulting bug (the caret lands one
/// character off, but only after certain edits) is extremely hard to localize.
@immutable
final class BlockOffsetMap {
  /// Creates a map over [segments] describing [flatText].
  const BlockOffsetMap({
    required this.blockKey,
    required this.flatText,
    required this.segments,
  });

  /// An empty map for a block with no inline content.
  factory BlockOffsetMap.empty(NodeKey blockKey) =>
      BlockOffsetMap(blockKey: blockKey, flatText: '', segments: const []);

  /// The block this map belongs to.
  final NodeKey blockKey;

  /// The block's rendered text, as laid out.
  final String flatText;

  /// The runs making up [flatText], in document order.
  final List<OffsetSegment> segments;

  /// Length of [flatText] in UTF-16 code units.
  int get length => flatText.length;

  /// The flat offset corresponding to [offset] inside [key].
  ///
  /// Returns `null` when the node is not part of this block.
  int? flatOffsetFor(NodeKey key, int offset, PointType type) {
    for (final segment in segments) {
      if (segment.key != key) continue;
      if (type == PointType.element) {
        // An element-typed point addresses a child index, which has no flat
        // position of its own; it maps to the boundary of that child.
        return segment.flatStart;
      }
      if (!segment.isIdentity) {
        return offset <= 0 ? segment.flatStart : segment.flatEnd;
      }
      final clamped = offset.clamp(0, segment.modelLength);
      return segment.flatStart + clamped;
    }
    // An element point on the block itself: index into its children.
    if (key == blockKey && type == PointType.element) {
      if (segments.isEmpty) return 0;
      for (final segment in segments) {
        if (segment.indexInParent >= offset && segment.parent == blockKey) {
          return segment.flatStart;
        }
      }
      return length;
    }
    return null;
  }

  /// The model point corresponding to flat [offset].
  ///
  /// The join between two adjacent runs is ambiguous. This resolves it
  /// consistently as **end of the previous run** rather than start of the
  /// next, so a caret typed at a boundary inherits the formatting to its
  /// left — which is what every text editor does.
  ResolvedPoint pointFor(int offset) {
    if (segments.isEmpty) {
      return ResolvedPoint(blockKey, 0, PointType.element);
    }
    final clamped = offset.clamp(0, length);
    for (final segment in segments) {
      if (clamped > segment.flatStart && clamped <= segment.flatEnd) {
        if (segment.type == PointType.element) {
          // A run with no addressable interior — a decorator or a line break.
          final atEnd = clamped == segment.flatEnd;
          return ResolvedPoint(
            segment.parent,
            atEnd ? segment.indexInParent + 1 : segment.indexInParent,
            PointType.element,
          );
        }
        if (!segment.isIdentity) {
          final atEnd = clamped == segment.flatEnd;
          return ResolvedPoint(
            segment.key,
            atEnd ? segment.modelLength : 0,
            PointType.text,
          );
        }
        return ResolvedPoint(
          segment.key,
          clamped - segment.flatStart,
          PointType.text,
        );
      }
    }
    // Offset 0, before the first run.
    final first = segments.first;
    if (first.type == PointType.element) {
      return ResolvedPoint(
        first.parent,
        first.indexInParent,
        PointType.element,
      );
    }
    return ResolvedPoint(first.key, 0, PointType.text);
  }

  /// The segment covering flat [offset], or `null` when out of range.
  OffsetSegment? segmentAt(int offset) {
    for (final segment in segments) {
      if (offset >= segment.flatStart && offset < segment.flatEnd) {
        return segment;
      }
    }
    return segments.isEmpty ? null : segments.last;
  }

  /// Whether [key] contributes anything to this block.
  bool contains(NodeKey key) =>
      key == blockKey || segments.any((segment) => segment.key == key);
}
