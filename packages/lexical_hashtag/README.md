![lexical_hashtag](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_hashtag.png)

# lexical_hashtag

Hashtag nodes for [`lexical_core`](https://pub.dev/packages/lexical_core).
Pure Dart.

```yaml
dependencies:
  lexical_hashtag: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: hashtagNodes);

editor.update(() {
  $getRoot().append(
    $createParagraphNode()..append($createHashtagNode('#flutter')),
  );
}, discrete: true);
```

A hashtag is a `TextNode` subclass with no extra fields — only its type string
differs on the wire. That alone makes it non-mergeable with the text around it,
which is exactly what a tag needs: it stays one addressable run instead of
dissolving into the sentence on the next normalization pass.

Wire-compatible with `@lexical/hashtag` 0.48.x.

## Hover and tap

A hashtag is worth rendering only if it leads somewhere. Pass its type to a
`LexicalInteraction` in `lexical_flutter` and hovering or tapping one reports
it, with its text and its bounds for anchoring a preview:

```dart
LexicalInteraction(
  types: const {'hashtag'},
  onTap: (hit) => search(hit.text),
)
```

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
