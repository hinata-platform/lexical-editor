/// Typeahead UI for `lexical_mention`.
///
/// A caret-anchored popover with debounced, cancellation-safe search and
/// keyboard navigation, over the atomic `MentionNode` from `lexical_mention`.
///
/// ```dart
/// MentionScope(
///   editor: editor,
///   triggers: const [
///     MentionTrigger(character: '@', mentionType: 'user'),
///     MentionTrigger(character: '#', mentionType: 'issue'),
///   ],
///   source: CallbackMentionSource(searchBackend),
///   itemBuilder: (context, suggestion, highlighted) =>
///       MyRow(suggestion, highlighted),
///   builder: (context, key) =>
///       LexicalEditable(key: key, editor: editor, theme: theme),
/// )
/// ```
///
/// Three properties are worth knowing because they are what make it usable on
/// a real backend rather than on a fixture:
///
/// * **Matching is bounded.** Detection reads a fixed number of characters
///   before the caret, never the paragraph, so its cost does not grow with the
///   document.
/// * **Stale answers are dropped.** A response for a query the user has
///   already typed past never reaches the screen — that is the flicker
///   everyone recognizes and nobody can reproduce.
/// * **Insertion is one undo step**, and produces a token that deletes whole.
library;

export 'src/mention_context.dart'
    show
        CaretContext,
        MentionLabelBuilder,
        defaultMentionLabel,
        $insertMention,
        $textBeforeCaret;
export 'src/mention_scope.dart'
    show
        MentionEditableBuilder,
        MentionItemBuilder,
        MentionScope,
        MentionScopeState;
