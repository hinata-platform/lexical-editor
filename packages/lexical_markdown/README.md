# lexical_markdown

Markdown import and export for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_markdown: ^0.1.0
```

```dart
editor.update(() {
  $convertFromMarkdown(source, transformers: defaultMarkdownTransformers);
}, discrete: true);

final back = editor.read(
  () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
);
```

## One declaration, both directions

Conversion is built from **transformers**: each describes one construct going
in *and* coming out.

```dart
final ElementTransformer headingTransformer = ElementTransformer(
  regExp: RegExp(r'^(#{1,6})\s+(.*)$'),
  replace: (block, children, match) => block.replace(
    $createHeadingNode(HeadingTag.values[match.group(1)!.length - 1])
      ..appendAll(children),
  ),
  export: (node, exportChildren) => node is! HeadingNode
      ? null
      : '${'#' * node.tag.level} ${exportChildren(node)}',
);
```

Splitting import and export into separate tables makes it easy to write a
heading that reads `## ` but writes something else, and hard to notice. Keeping
them in one place makes that particular bug unwriteable.

## What survives, and what does not

Markdown is lossier than the document model, and this package is honest about
it rather than pretending otherwise.

**Round-trips:** headings, quotes, paragraphs, bullet, ordered and check lists
including nesting, fenced code with its language, links with titles, and
bold / italic / strikethrough / inline code.

**Does not:** block alignment, indentation, text colour and other CSS, marks,
hashtags, mentions, tables. None of these have a markdown spelling.

Use the JSON wire format to move documents between editors. Use markdown to
move them between *people*.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
