/// Detecting a mention trigger in the text before the caret.
library;

import 'package:meta/meta.dart';

/// Declares one way a mention can be started.
///
/// An application registers as many as it needs — `@` for people, `#` for
/// issues, `/` for commands — and each carries the [mentionType] the resulting
/// node will get.
@immutable
final class MentionTrigger {
  /// Declares [character] as a trigger producing mentions of [mentionType].
  const MentionTrigger({
    required this.character,
    required this.mentionType,
    this.minQueryLength = 0,
    this.maxQueryLength = 48,
    this.allowSpaces = false,
    this.requireLeadingBoundary = true,
  }) : assert(character.length == 1, 'a trigger is a single character');

  /// The character that opens a mention, such as `@`.
  final String character;

  /// The `MentionNode.mentionType` a match produces.
  final String mentionType;

  /// How many characters must follow the trigger before searching.
  ///
  /// Zero means the picker opens on the bare trigger, which is usually what
  /// people expect from `@`.
  final int minQueryLength;

  /// The longest query considered.
  ///
  /// This is what bounds the cost of matching: the scan looks back at most
  /// this far from the caret, so detection is O(maxQueryLength) rather than
  /// O(text) — the difference between typing staying smooth in a long
  /// paragraph and not.
  final int maxQueryLength;

  /// Whether a space may appear inside the query.
  ///
  /// Off by default. Allowing spaces makes every subsequent keystroke a
  /// candidate query and keeps the picker open long after the user moved on.
  final bool allowSpaces;

  /// Whether the trigger must sit at the start of a word.
  ///
  /// On by default, so an email address does not open a people picker in the
  /// middle of `name@example.org`.
  final bool requireLeadingBoundary;

  @override
  bool operator ==(Object other) =>
      other is MentionTrigger &&
      other.character == character &&
      other.mentionType == mentionType &&
      other.minQueryLength == minQueryLength &&
      other.maxQueryLength == maxQueryLength &&
      other.allowSpaces == allowSpaces &&
      other.requireLeadingBoundary == requireLeadingBoundary;

  @override
  int get hashCode => Object.hash(
    character,
    mentionType,
    minQueryLength,
    maxQueryLength,
    allowSpaces,
    requireLeadingBoundary,
  );

  @override
  String toString() => 'MentionTrigger($character -> $mentionType)';
}

/// A trigger found in the text before the caret.
@immutable
final class MentionMatch {
  /// Records that [trigger] opened [query] at [triggerOffset].
  const MentionMatch({
    required this.trigger,
    required this.query,
    required this.triggerOffset,
    required this.caretOffset,
  });

  /// The trigger that matched.
  final MentionTrigger trigger;

  /// The text typed after the trigger, excluding the trigger itself.
  final String query;

  /// Offset of the trigger character, in UTF-16 code units.
  final int triggerOffset;

  /// Offset of the caret, one past the end of [query].
  final int caretOffset;

  /// The range the mention node will replace, trigger included.
  int get replaceStart => triggerOffset;

  /// End of the range the mention node will replace.
  int get replaceEnd => caretOffset;

  @override
  bool operator ==(Object other) =>
      other is MentionMatch &&
      other.trigger == trigger &&
      other.query == query &&
      other.triggerOffset == triggerOffset &&
      other.caretOffset == caretOffset;

  @override
  int get hashCode => Object.hash(trigger, query, triggerOffset, caretOffset);

  @override
  String toString() =>
      'MentionMatch(${trigger.character}$query @$triggerOffset)';
}

const int _space = 0x20;
const int _tab = 0x09;
const int _newline = 0x0a;
const int _nonBreakingSpace = 0xa0;

bool _isBoundary(int codeUnit) =>
    codeUnit == _space ||
    codeUnit == _tab ||
    codeUnit == _newline ||
    codeUnit == _nonBreakingSpace;

/// Finds the mention trigger governing the caret, or `null`.
///
/// [text] is the block's text and [caretOffset] the caret's position in it.
/// The scan walks **backwards from the caret**, at most
/// `maxQueryLength + 1` characters, and stops at the first boundary — so its
/// cost does not grow with the length of the paragraph, which is what keeps
/// it viable on every keystroke.
MentionMatch? matchMentionTrigger(
  String text,
  int caretOffset,
  List<MentionTrigger> triggers,
) {
  if (triggers.isEmpty) return null;
  final caret = caretOffset.clamp(0, text.length);
  if (caret == 0) return null;

  var longestLookback = 0;
  for (final trigger in triggers) {
    if (trigger.maxQueryLength > longestLookback) {
      longestLookback = trigger.maxQueryLength;
    }
  }
  final lowest = caret - longestLookback - 1;
  final limit = lowest < 0 ? 0 : lowest;

  for (var index = caret - 1; index >= limit; index--) {
    final codeUnit = text.codeUnitAt(index);
    final character = text[index];

    for (final trigger in triggers) {
      if (character != trigger.character) continue;
      final queryLength = caret - index - 1;
      if (queryLength > trigger.maxQueryLength) continue;
      if (queryLength < trigger.minQueryLength) continue;
      if (trigger.requireLeadingBoundary && index > 0) {
        if (!_isBoundary(text.codeUnitAt(index - 1))) continue;
      }
      final query = text.substring(index + 1, caret);
      if (!trigger.allowSpaces && query.codeUnits.any(_isBoundary)) {
        continue;
      }
      return MentionMatch(
        trigger: trigger,
        query: query,
        triggerOffset: index,
        caretOffset: caret,
      );
    }

    // A boundary ends the candidate region for every space-free trigger. Any
    // trigger allowing spaces keeps scanning, which is exactly why that
    // option is off by default.
    if (_isBoundary(codeUnit) &&
        !triggers.any((trigger) => trigger.allowSpaces)) {
      return null;
    }
  }
  return null;
}
