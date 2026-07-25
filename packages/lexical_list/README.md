# lexical_list

Bullet, ordered and check-list nodes for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_list: ^0.1.0
```

```dart
final editor = LexicalEditor(nodes: listNodes);
registerListNumbering(editor);      // keeps `value` in step with position

editor.update(() {
  $getRoot().append(
    $createListNode(ListType.check)
      ..append($createListItemNode(true)..append($createTextNode('erledigt')))
      ..append($createListItemNode(false)..append($createTextNode('offen'))),
  );
}, discrete: true);
```

## Two details the wire format insists on

`listitem.checked` is **absent** outside a check list, not present with value
`null` — those are different values on the wire, and a blanket "skip nulls"
rule gets one of them wrong.

`listitem.value` is derived: `list.start + index`. It is maintained by the
transform `registerListNumbering` installs, not recomputed on export, because
import must stay verbatim — a document whose numbering disagrees with its
positions is preserved rather than silently rewritten.

Nesting is a list *inside an item*, not a list inside a list;
`ListItemNode.isNestedListHolder` identifies those wrapper items.

Wire-compatible with `@lexical/list` 0.48.x.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE`.
