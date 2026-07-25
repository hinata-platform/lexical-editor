# lexical_mention_flutter

The typeahead UI for [`lexical_mention`](https://pub.dev/packages/lexical_mention):
a caret-anchored popover with debounced async search and keyboard navigation.

```yaml
dependencies:
  lexical_mention_flutter: ^0.1.0
```

```dart
MentionScope(
  editor: editor,
  triggers: const [
    MentionTrigger(character: '@', mentionType: 'user'),
    MentionTrigger(character: '#', mentionType: 'issue'),
  ],
  source: CallbackMentionSource(searchBackend),
  itemBuilder: (context, suggestion, highlighted) =>
      MyRow(suggestion, highlighted),
  builder: (context, key) =>
      LexicalEditable(key: key, editor: editor, theme: theme),
)
```

The builder is handed the key it must attach — that is how the popover reaches
the caret's geometry, and handing it over removes the failure mode where it is
simply forgotten.

## What makes it work on a real backend

**Matching is bounded.** Detection reads a fixed number of characters before
the caret, never the paragraph, so its cost does not grow with the document.
The scan also stops at a token, which is what keeps a second `@` from reading
the first mention's label as part of its query.

**Stale answers are dropped.** A response for a query the user has already
typed past never reaches the screen. That is the flicker everyone recognizes
and nobody can reproduce on demand.

**Insertion is one undo step**, and produces a token that deletes whole.

**The popover takes no focus**, so the caret keeps blinking and the software
keyboard stays up while the user picks.

## Rows are yours

`itemBuilder` builds each row, so avatars, subtitles and highlighting are the
application's decision. The popover re-applies the ambient theme and text style
inside the overlay, so rows are not left in Flutter's "you forgot a `Material`"
fallback — a trap that looks like a bug in the item builder and is not.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
