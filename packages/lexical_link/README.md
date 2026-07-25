![lexical_link](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_link.png)

# lexical_link

Link and auto-link nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_link: ^1.0.0
```

```dart
final editor = LexicalEditor(nodes: linkNodes);

editor.update(() {
  $getRoot().append(
    $createParagraphNode()
      ..append($createLinkNode('https://lexical.dev')
        ..append($createTextNode('Quelle'))),
  );
}, discrete: true);
```

## Security: validate at the point of use

A stored document is untrusted input, and a link is the one place where that
input becomes an **action**. This package therefore keeps the URL byte-for-byte
in the model — so documents round-trip unchanged — and gives you `isSafeUrl`
to call before wiring up a gesture:

```dart
if (link.isSafe) {
  // make it tappable
} else {
  // render inert
}
```

`isSafeUrl` allow-lists `http`, `https`, `mailto`, `tel`, `sms` and `ftp`,
treats relative URLs as safe (they cannot name a scheme), and rejects control
characters used to smuggle a scheme past naive checks (`java\tscript:`).

Sanitizing on import would be the wrong fix twice over: it silently rewrites
user documents and it breaks wire compatibility.

## Wire shape

`rel`, `target` and `title` are emitted **even when null** — upstream writes
them unconditionally, so omitting them fails a strict fixed-point comparison.
`AutoLinkNode` adds `isUnlinked`, recording that the user dismissed an
automatic link so it is not recreated.

Wire-compatible with `@lexical/link` 0.48.x.

## Making a link

```dart
registerLink(editor);                                    // once
editor.dispatchCommand(toggleLinkCommand, 'https://…');  // link the selection
editor.dispatchCommand(toggleLinkCommand, null);         // unlink it
```

`$toggleLink` splits the boundary text nodes so the link covers exactly what
was selected, unwraps links already inside the range so the result is one link
rather than nested ones, and wraps each run of siblings where it sits — a
selection crossing a paragraph boundary produces one link per paragraph,
because an element cannot span two parents and linking only the first half
loses the gesture.

A selection **inside** an existing link retargets that link instead of nesting
a second one, which is what someone editing a URL means. `$getLinkAtSelection`
answers with the link under the caret, so a link editor can open with the
current URL filled in.

## Hover and tap

A link that cannot be followed is decoration. `lexical_flutter` resolves the
node under the pointer by **type string**, so this package stays free of any
Flutter dependency while its nodes still respond:

```dart
LexicalEditable(
  editor: editor,
  theme: theme,
  interaction: LexicalInteraction(
    types: const {'link', 'autolink'},
    onEnter: (hit) => preview.show(hit.json['url']! as String, hit.rect),
    onExit: (_) => preview.hide(),
    onTap: (hit) => launchUrlString(hit.json['url']! as String),
  ),
)
```

The hit reports the **link**, not the text node the pointer was over, and
carries the node's serialized fields — which is how `url` arrives without the
render layer knowing this package exists.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
