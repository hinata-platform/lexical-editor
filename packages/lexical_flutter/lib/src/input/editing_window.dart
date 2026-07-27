/// The bounded slice of the document handed to the platform input method.
library;

import 'package:flutter/services.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

import '../render/block_offset_map.dart';

/// How much text either side of the caret the platform is told about.
///
/// The platform value is serialized across a channel on every push, so a
/// document with one enormous block would pay for its whole length on each
/// one. The window bounds that, in the same spirit as the bounded importer:
/// nothing here should scale with the size of the document.
const int defaultWindowRadius = 4096;

/// How close the caret may come to a window edge before the window moves.
///
/// Re-centring on every keystroke would push a new value on every keystroke
/// and undo the point of the window. Re-centring only near an edge means a
/// normal typing run costs no pushes at all.
const int windowRewindowMargin = 512;

/// One block's contribution to the platform's editing value.
///
/// The value the platform sees is `prefix + slice + suffix`:
///
/// * **slice** is the block's own flat text between [start] and [end].
/// * **prefix** is a single newline when a previous block exists and the
///   slice reaches the block's start. Without it, backspace at the start of a
///   paragraph produces no delta at all — the platform has nothing to delete —
///   and merging blocks becomes impossible from a soft keyboard.
/// * **suffix** is the mirror image, for forward delete at the block's end.
@immutable
final class EditingWindow {
  /// Describes the window over [blockKey].
  const EditingWindow({
    required this.blockKey,
    required this.offsets,
    required this.value,
    required this.start,
    required this.end,
    required this.hasPrefix,
    required this.hasSuffix,
  });

  /// The block the window covers.
  final NodeKey blockKey;

  /// The block's model-side offset map.
  final BlockOffsetMap offsets;

  /// What the platform is told.
  final TextEditingValue value;

  /// Flat offset in the block where the slice begins.
  final int start;

  /// Flat offset in the block where the slice ends.
  final int end;

  /// Whether a newline stands in for the preceding block boundary.
  final bool hasPrefix;

  /// Whether a newline stands in for the following block boundary.
  final bool hasSuffix;

  /// Length of the leading sentinel, in code units.
  int get prefixLength => hasPrefix ? 1 : 0;

  /// Window offset one past the end of the slice.
  int get sliceEndInWindow => prefixLength + (end - start);

  /// Converts a block flat offset to a window offset.
  int toWindow(int flatOffset) =>
      flatOffset.clamp(start, end) - start + prefixLength;

  /// Converts a window offset to a block flat offset.
  int toFlat(int windowOffset) =>
      (windowOffset - prefixLength).clamp(0, end - start) + start;

  /// Whether [range] *removes* part of the preceding block boundary.
  ///
  /// A collapsed range at the sentinel is not a crossing — it is a caret at
  /// the block's start, and treating it as one would merge two blocks the
  /// moment the user typed there.
  bool crossesStart(TextRange range) =>
      hasPrefix && range.start < prefixLength && range.end > range.start;

  /// Whether [range] removes part of the following block boundary.
  bool crossesEnd(TextRange range) =>
      hasSuffix && range.end > sliceEndInWindow && range.end > range.start;

  @override
  String toString() =>
      'EditingWindow($blockKey, $start..$end, "${value.text}")';
}

/// Where a previous window sat, so the next one can stay put.
@immutable
final class WindowAnchor {
  /// Records a window over [blockKey] spanning [start] to [end].
  const WindowAnchor(this.blockKey, this.start, this.end);

  /// The block the window covered.
  final NodeKey blockKey;

  /// Flat offset the slice began at.
  final int start;

  /// Flat offset the slice ended at.
  final int end;
}

/// Builds the editing window for the current selection, or `null`.
///
/// [reuseOffsets] is a map built for an earlier window. It is used instead of
/// walking the block again **only** when it describes the same block and the
/// caller states the document has not changed since — which is every commit
/// of a selection drag, where the block's text is by definition the same and
/// rebuilding it once per pointer move is the difference between a smooth
/// selection and a stuttering one.
///
/// Must be called inside a read or update context.
EditingWindow? $buildEditingWindow({
  WindowAnchor? previous,
  BlockOffsetMap? reuseOffsets,
  int radius = defaultWindowRadius,
  TextRange composing = TextRange.empty,
}) {
  final selection = $getSelection();
  if (selection is! RangeSelection) return null;
  final focusNode = selection.focus.getNode();
  if (focusNode == null) return null;

  final block = $getNearestBlock(focusNode);
  final offsets = reuseOffsets != null && reuseOffsets.blockKey == block.key
      ? reuseOffsets
      : buildModelOffsets(block);
  final length = offsets.length;

  final caret =
      offsets.flatOffsetFor(
        selection.focus.key,
        selection.focus.offset,
        selection.focus.type,
      ) ??
      0;

  var start = 0;
  var end = length;
  if (length > radius * 2) {
    final keepPrevious =
        previous != null &&
        previous.blockKey == block.key &&
        caret >= previous.start + windowRewindowMargin &&
        caret <= previous.end - windowRewindowMargin;
    if (keepPrevious) {
      start = previous.start.clamp(0, length);
      end = previous.end.clamp(start, length);
    } else {
      start = (caret - radius).clamp(0, length);
      end = (caret + radius).clamp(start, length);
    }
  }

  final hasPrefix = start == 0 && $getPreviousBlock(block) != null;
  final hasSuffix = end == length && $getNextBlock(block) != null;
  final prefixLength = hasPrefix ? 1 : 0;
  final prefix = hasPrefix ? '\n' : '';
  final suffix = hasSuffix ? '\n' : '';
  final text = '$prefix${offsets.flatText.substring(start, end)}$suffix';

  // A point outside the window — the far end of a selection that spans
  // blocks — clamps to the edge of the *slice*, never onto a sentinel. That
  // keeps a clamped selection distinguishable from a real block crossing,
  // and the delta handler recognizes a range equal to the reported selection
  // and operates on the model's own selection instead, so nothing is lost.
  final sliceEnd = prefixLength + (end - start);
  int windowOffset(Point point, {required bool clampToEnd}) {
    final flat = offsets.flatOffsetFor(point.key, point.offset, point.type);
    if (flat == null) return clampToEnd ? sliceEnd : prefixLength;
    return (flat.clamp(start, end) - start + prefixLength).clamp(
      prefixLength,
      sliceEnd,
    );
  }

  final anchorIsFirst = !selection.isBackward;

  return EditingWindow(
    blockKey: block.key,
    offsets: offsets,
    value: TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: windowOffset(selection.anchor, clampToEnd: !anchorIsFirst),
        extentOffset: windowOffset(selection.focus, clampToEnd: anchorIsFirst),
      ),
      composing: _clampComposing(composing, text.length),
    ),
    start: start,
    end: end,
    hasPrefix: hasPrefix,
    hasSuffix: hasSuffix,
  );
}

TextRange _clampComposing(TextRange composing, int length) {
  if (!composing.isValid) return TextRange.empty;
  final start = composing.start.clamp(0, length);
  final end = composing.end.clamp(start, length);
  if (start == end) return TextRange.empty;
  return TextRange(start: start, end: end);
}
