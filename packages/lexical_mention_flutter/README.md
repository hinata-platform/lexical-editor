![lexical_mention_flutter](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_mention_flutter.png)

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

A suggestion's `label` carries **no trigger character** — the label builder
prepends it. A label of `#108` behind a `#` trigger inserts `##108`.

## Mentions as chips

A mention is a token `TextNode`, so a theme entry styles it like any text:
colour, weight, a background. Padding and a rounded corner need a widget, and
`tokenBuilders` is where one goes:

```dart
LexicalTheme(
  baseTextStyle: ...,
  tokenBuilders: {
    'mention': (context, node, style) => MentionChip(
      // Read the node *here*: the builder runs inside the editor's read, the
      // widget it returns is built later without one.
      label: node.getTextContent(),
      kind: (node as MentionNode).mentionType,
      style: style,
    ),
  },
)
```

The node stays text in the model — same JSON, same web client, same atomic
delete — only its presentation changes. `style` is what the mention would have
been drawn with, so merging it keeps the chip in step with the document's font
size and the platform's text scale. The cost is a placeholder layout and a
render object per mention, which is why it is opt-in per type rather than the
default.

## Hover previews, tap to navigate

The other half of a smart link. `LexicalInteraction` (from `lexical_flutter`)
reports the mention under the pointer, with the serialized fields to act on and
the bounds to anchor a card to:

```dart
LexicalEditable(
  editor: editor,
  theme: theme,
  interaction: LexicalInteraction(
    types: const {'mention'},
    onEnter: (hit) => preview.showAt(hit.rect, hit.json['mentionId']),
    onExit: (_) => preview.hide(),
    onTap: (hit) => router.go('/users/${hit.json['mentionId']}'),
  ),
)
```

`onEnter`/`onExit` are mouse events and never fire on a phone, so keep what
matters behind `onTap`. The example app wires all three.

## Rows are yours

`itemBuilder` builds each row, so avatars, subtitles and highlighting are the
application's decision. The popover re-applies the ambient theme and text style
inside the overlay, so rows are not left in Flutter's "you forgot a `Material`"
fallback — a trap that looks like a bug in the item builder and is not.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
