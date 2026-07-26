/// Mentions, configured rather than assembled.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_mention_flutter/lexical_mention_flutter.dart';

import 'default_theme.dart';

/// The `@mention` typeahead of a `LexicalEditorField`.
///
/// Mentions are the one feature in this bundle that **cannot** have a default:
/// every other package knows what it does on its own, but only the
/// application knows who can be mentioned. That is the whole reason there is
/// no `registerMention` beside `registerTable` and the rest — a mention has
/// no editing behaviour to register, it has a data source to be given.
///
/// ```dart
/// LexicalEditorField(
///   editor: editor,
///   baseTextStyle: …,
///   mentions: LexicalMentions(
///     source: CallbackMentionSource((query) async => search(query.text)),
///   ),
/// )
/// ```
///
/// Everything else has a default: `@` for people, a row per suggestion, a
/// popover styled from the field's palette. Replace any of it, or drop this
/// type and use `MentionScope` directly — this is a convenience over it, not
/// a wall in front of it.
@immutable
class LexicalMentions {
  /// Configures the picker over [source].
  const LexicalMentions({
    required this.source,
    this.triggers = const [MentionTrigger(character: '@', mentionType: 'user')],
    this.itemBuilder,
    this.emptyBuilder,
    this.loadingBuilder,
    this.decoration,
    this.debounce = const Duration(milliseconds: 150),
    this.limit = 8,
    this.width = 280,
    this.maxHeight = 240,
    this.label = defaultMentionLabel,
    this.trailingSpace = true,
    this.onInserted,
  });

  /// Where suggestions come from.
  final MentionSource source;

  /// What opens the picker, and which kind of entity each one names.
  ///
  /// Defaults to `@` for people. A second trigger — `#` for issues, say — is
  /// a second entry here and needs nothing else: the kind is data on the
  /// node, not a node type.
  final List<MentionTrigger> triggers;

  /// Builds one suggestion row. A label with its subtitle when omitted.
  final MentionItemBuilder? itemBuilder;

  /// Shown when a search returned nothing. Hidden when omitted.
  final WidgetBuilder? emptyBuilder;

  /// Shown while the first search of a query is in flight.
  final WidgetBuilder? loadingBuilder;

  /// Popover chrome. Derived from the field's palette when omitted.
  final Decoration? decoration;

  /// How long to wait after the last keystroke before searching.
  final Duration debounce;

  /// How many suggestions to request.
  final int limit;

  /// Popover width in logical pixels.
  final double width;

  /// Greatest popover height before the list scrolls.
  final double maxHeight;

  /// Builds the text an inserted mention carries.
  final MentionLabelBuilder label;

  /// Whether to insert a space after the mention.
  final bool trailingSpace;

  /// Called after a suggestion was inserted.
  final void Function(MentionSuggestion suggestion)? onInserted;

  /// The row drawn for a suggestion when [itemBuilder] is omitted.
  MentionItemBuilder resolveItemBuilder(
    TextStyle baseTextStyle,
    LexicalPalette palette,
  ) =>
      itemBuilder ??
      (context, suggestion, highlighted) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: highlighted
            ? palette.accent.withValues(alpha: 0.16)
            : const Color(0x00000000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              suggestion.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: baseTextStyle.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (suggestion.subtitle case final subtitle?)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseTextStyle.copyWith(
                  color: palette.muted,
                  fontSize: (baseTextStyle.fontSize ?? 16) * 0.85,
                ),
              ),
          ],
        ),
      );

  /// The popover chrome drawn when [decoration] is omitted.
  ///
  /// A popover floats over the document, so its fill has to be opaque —
  /// [LexicalPalette.surface] is a tint meant to sit *on* the page and would
  /// leave the text showing through. The palette does not say whether it is
  /// light or dark, so that is read off the text colour, which does.
  Decoration resolveDecoration(LexicalPalette palette) =>
      decoration ??
      BoxDecoration(
        color: palette.text.computeLuminance() > 0.5
            ? const Color(0xFF202124)
            : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      );
}
