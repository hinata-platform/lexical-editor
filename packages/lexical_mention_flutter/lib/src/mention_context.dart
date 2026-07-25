/// Reading the text a trigger could be hiding in, and inserting the result.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:meta/meta.dart';

/// The text immediately before the caret, and where the caret sits in it.
@immutable
final class CaretContext {
  /// Records [text] with the caret at [caretOffset].
  const CaretContext(this.text, this.caretOffset);

  /// The text collected before the caret, truncated to a bounded length.
  final String text;

  /// The caret's offset in [text], which is always its length.
  final int caretOffset;
}

/// Collects at most [limit] code units of text before the caret.
///
/// **Not** the whole block. Trigger matching only ever looks back a bounded
/// distance, so reading the whole block would make every keystroke cost the
/// length of the paragraph for no benefit — the difference between typing
/// staying smooth in a long document and not.
///
/// The scan stops at anything that is not plain text — a token, a line break,
/// an inline decorator — because a trigger cannot reach across one. That is
/// also what keeps a second `@` from picking up the first mention's label as
/// part of its query.
///
/// Must be called inside a read or update context.
CaretContext? $textBeforeCaret({required int limit}) {
  final selection = $getSelection();
  if (selection is! RangeSelection || !selection.isCollapsed) return null;
  if (selection.focus.type != PointType.text) return null;
  final node = selection.focus.getNode();
  if (node is! TextNode || node.isToken) return null;

  final pieces = <String>[];
  var remaining = limit;

  final text = node.getTextContent();
  var head = text.substring(0, selection.focus.offset.clamp(0, text.length));
  if (head.length > remaining) head = head.substring(head.length - remaining);
  pieces.add(head);
  remaining -= head.length;

  LexicalNode current = node;
  while (remaining > 0) {
    final previous = current.getPreviousSibling();
    if (previous is! TextNode || previous.isToken) break;
    var run = previous.getTextContent();
    if (run.length > remaining) run = run.substring(run.length - remaining);
    pieces.add(run);
    remaining -= run.length;
    current = previous;
  }

  final joined = pieces.reversed.join();
  return CaretContext(joined, joined.length);
}

/// Builds the label an inserted mention carries.
typedef MentionLabelBuilder =
    String Function(MentionTrigger trigger, MentionSuggestion suggestion);

/// The default label: the trigger character followed by the entity's name.
String defaultMentionLabel(
  MentionTrigger trigger,
  MentionSuggestion suggestion,
) => '${trigger.character}${suggestion.label}';

/// Replaces [match]'s range with a mention for [suggestion].
///
/// Runs as one update, so it is one undo step: an accepted suggestion should
/// come back in a single press, not character by character.
///
/// Must be called inside an update context.
void $insertMention({
  required MentionMatch match,
  required MentionSuggestion suggestion,
  MentionLabelBuilder label = defaultMentionLabel,
  bool trailingSpace = true,
}) {
  final selection = $getSelection();
  if (selection is! RangeSelection) return;
  final focusNode = selection.focus.getNode();
  if (focusNode == null) return;

  // The match's offsets are relative to the text collected before the caret,
  // which ends at the caret; the block's flat offsets are what the model
  // speaks, so the range is re-anchored on the caret rather than on zero.
  final block = $getNearestBlock(focusNode);
  final offsets = buildModelOffsets(block);
  final caretFlat = offsets.flatOffsetFor(
    selection.focus.key,
    selection.focus.offset,
    selection.focus.type,
  );
  if (caretFlat == null) return;
  final startFlat = caretFlat - (match.caretOffset - match.triggerOffset);
  if (startFlat < 0) return;

  final start = offsets.pointFor(startFlat);
  final end = offsets.pointFor(caretFlat);
  selection
    ..anchor.set(start.key, start.offset, start.type)
    ..focus.set(end.key, end.offset, end.type)
    ..dirty = true;

  final mention = $createMentionNode(
    text: label(match.trigger, suggestion),
    mentionType: suggestion.mentionType,
    mentionId: suggestion.id,
    trigger: match.trigger.character,
  );
  for (final entry in suggestion.data.entries) {
    mention.setData(entry.key, entry.value);
  }

  selection.insertNodes([
    mention,
    // A trailing space is what lets the next word be typed without the token
    // swallowing it, and what stops a second trigger matching immediately.
    if (trailingSpace) $createTextNode(' '),
  ]);
}
