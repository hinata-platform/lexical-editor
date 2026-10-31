# lexical_layout

Column layout nodes for [`lexical_core`](https://pub.dev/packages/lexical_core),
wire-compatible with the `layout-container` and `layout-item` nodes of the
Lexical playground. Pure Dart.

```yaml
dependencies:
  lexical_layout: ^1.11.0
```

```dart
final editor = LexicalEditor(nodes: layoutNodes);
registerLayout(editor);

editor.update(() {
  $getRoot().append($createLayoutWithColumns('200px 1fr'));
}, discrete: true);
```

## The shapes

```json
{"type": "layout-container", "templateColumns": "1fr 1fr", "children": [
  {"type": "layout-item", "children": [ blocks ]},
  {"type": "layout-item", "children": [ blocks ]}
]}
```

Both are shadow roots, like a table cell: Enter splits a paragraph inside its
column, backspace stops at a column's edge, and backspace in the first column
of a layout whose columns are all empty removes the layout. The container
cannot be empty.

## Columns

`templateColumns` is a CSS grid template, kept verbatim. The renderer reads
the subset documents carry — `Nfr`, `Npx`, `N%`, `auto`, `minmax(0, Npx)`;
anything else counts as `1fr`:

```dart
final tracks = parseTemplateColumns('200px 1fr 3fr');
resolveTemplateColumns(tracks, 600); // [200, 100, 300]
resolveTemplateColumns(tracks, 150); // null: narrower than the fixed tracks, so stack
```

`registerLayout` adds `insertLayoutCommand`, `updateLayoutCommand` and
upstream's structural transforms: an item outside a container is unwrapped,
an empty item gets a paragraph, and a container holding anything but items is
unwrapped.
