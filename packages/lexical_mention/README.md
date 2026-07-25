![lexical_mention](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_mention.png)

# lexical_mention

Typed `@mention` nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart — the
picker widget lives in `lexical_mention_flutter`.

```yaml
dependencies:
  lexical_mention: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: mentionNodes);

editor.update(() {
  $getRoot().append(
    $createParagraphNode()
      ..append($createTextNode('cc '))
      ..append($createMentionNode(
        text: '@Rebar',
        mentionType: 'user',
        mentionId: 'u_42',
      )),
  );
}, discrete: true);
```

## Why a token, not a decorator

A mention is a **token-mode `TextNode`**. Token mode makes it atomic — edited
as a unit, deleted whole — while it stays part of the ordinary text run, so it
costs one span rather than one widget, one placeholder layout and one
render-object child. A document with a thousand mentions lays out like a
document with a thousand words, not like one with a thousand widgets.

A decorator buys you an avatar and charges for it on every frame. If a
particular mention type needs one, render *that type* as a `WidgetSpan` and
leave the rest as text.

## The kind is data, not a subclass

`mentionType` is a free-form string, so `user`, `issue`, `doc`, `sprint` and
`release` all work without a new node type, a registry entry or a schema
migration. Anything else the entity needs — an avatar URL, a project key, a
status colour — goes in the node state, which round-trips untouched:

```dart
mention.setData('avatarUrl', 'https://…');
```

## Trigger detection is bounded

```dart
const triggers = [
  MentionTrigger(character: '@', mentionType: 'user'),
  MentionTrigger(character: '#', mentionType: 'issue'),
];

final match = matchMentionTrigger(text, caretOffset, triggers);
```

The scan walks backwards from the caret **at most `maxQueryLength + 1`
characters**, so its cost does not grow with the paragraph. That matters
because it runs on every keystroke: the test suite drives 2 000 keystrokes
across a 200 000-character paragraph and asserts it stays under half a second.

`requireLeadingBoundary` defaults to true, so `name@example.org` does not open
a people picker mid-word; `allowSpaces` defaults to false, so the picker
closes when the user moves on rather than treating the rest of the sentence as
a query.

## Search: debounce, cancel, cache

```dart
final controller = MentionSearchController(
  triggers: triggers,
  source: CallbackMentionSource((query) => api.searchUsers(query.text)),
  debounce: const Duration(milliseconds: 150),
);

controller.onTextChanged(textBeforeCaret, caretOffset);
controller.states.listen(render);
```

Three things it does that are easy to leave out and expensive to add back:

- **Debounce.** Typing an eight-character name otherwise fires eight requests
  and the list flickers through seven answers nobody wanted.
- **Stale-response rejection.** An answer to a query the user has already
  typed past never replaces what is on screen. This is the flicker everyone
  recognises and nobody can reproduce on demand.
- **An LRU query cache.** Backspacing through a query re-asks for answers
  already seen; the cache turns the most common interaction into zero
  requests.

All of it is pure Dart and driven directly by the test suite, because these
are exactly the parts that are miserable to test through a widget.

## Wire format

```json
{ "detail": 0, "format": 0, "mode": "token", "style": "",
  "text": "@Rebar", "type": "mention", "version": 1,
  "mentionType": "user", "mentionId": "u_42", "trigger": "@" }
```

`mention` is not an upstream Lexical type, so this schema is **ours** — a web
counterpart has to match it. Keep additions in the `"$"` node-state bucket,
which round-trips on clients that know nothing about them and so needs no
coordinated deployment.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
