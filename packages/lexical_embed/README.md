![lexical_embed](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_embed.png)

# lexical_embed

Embedded videos, tweets and Figma documents for
[`lexical_core`](https://pub.dev/packages/lexical_core) — the three embeds the
Lexical playground implements, in its wire format.

```yaml
dependencies:
  lexical_embed: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: embedNodes);
registerEmbed(editor);

LexicalEditable(
  editor: editor,
  theme: theme,
  decoratorBuilders: embedDecoratorBuilders(
    onOpen: (kind, url) => launchUrlString(url),
  ),
);

// Whatever the user pasted:
final handled = editor.dispatchCommand(insertEmbedFromUrlCommand, url);
if (!handled) {
  // Not embeddable — make it a link.
}
```

## What "video" means in Lexical

There is **no generic video node**. No `<video>` element node, no file-backed
media node, and no published `@lexical/*` package for either: the playground
implements `youtube`, `tweet` and `figma`, and that is the whole list.

This package implements exactly those three. A fourth type would produce
documents that no other Lexical client could open, which is the opposite of
what an interchange format is for.

| URL | Result |
|---|---|
| `youtube.com/watch?v=…`, `youtu.be/…`, `youtube.com/embed/…` | `youtube` |
| `twitter.com/…/status/…`, `x.com/…/status/…` | `tweet` |
| `figma.com/file/…`, `figma.com/proto/…` | `figma` |
| Vimeo, an MP4, an HLS stream, anything else | **not an embed** |

`insertEmbedFromUrlCommand` returns `false` for the last row rather than
inventing a node for it, which leaves the URL to a lower-priority handler —
normally an auto-link. That is what the playground does too.

The URL patterns are upstream's, so the same links are accepted here and
there. The one deliberate difference: upstream leaves the dot in `figma.com`
unescaped, so its pattern also matches hosts like `figmaXcom`. This one
doesn't.

## A card, not a player

`LexicalEmbedView` draws a thumbnail, a title and a tap target. Playing a
video in Flutter means a platform view and a plugin dependency, and a document
package has no business imposing one on everyone who merely wants to *read* a
document that contains a video. `onOpen` decides what a tap does; if you want
an inline player, register your own builder for `youtube`.

Only YouTube has a still image that can be fetched without an API key, so
tweets and Figma files draw as plain cards.

## Markdown

```dart
final transformers = defaultMarkdownTransformers.extend(
  elements: embedTransformers,
);
```

A tweet uses upstream's own odd spelling, `<tweet id="…" />`, so a document
exported here pastes back into the playground as a tweet.

Videos and Figma files have no upstream markdown rule at all — the playground
simply loses them on export. This package writes them as a **bare URL on its
own line**, which is valid markdown everywhere, reads correctly for a human,
and is what auto-embed turns back into a video when pasted into the playground.
Reading it back here produces the embed again.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc. See `NOTICE`.
