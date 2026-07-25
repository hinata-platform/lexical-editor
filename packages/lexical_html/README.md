![lexical_html](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_html.png)

# lexical_html

HTML import and export for
[`lexical_core`](https://pub.dev/packages/lexical_core). Pure Dart.

```yaml
dependencies:
  lexical_html: ^1.0.0
```

```dart
final html = editor.read($generateHtmlFromNodes);

editor.update(() {
  final selection = $getSelection();
  if (selection is RangeSelection) {
    selection.insertNodes($generateNodesFromHtml(pasted));
  }
});
```

## Export writes HTML, not a private dialect

`<strong>`, not `<span class="lexical-bold">`. Text that leaves the editor has
to be readable by a mail client, a CMS, or a browser that has never heard of
Lexical — that is the entire point of an HTML export.

## Import never drops content

An unrecognized tag contributes its **text**. A paste that silently loses part
of what the user copied is the one outcome worth designing against, so
anything this package cannot map to a node type still arrives as words.

Tables are converted as their text rather than as a grid. Reproducing a
browser's table model — colspan, rowspan, implied sections — inside a paste
path is a great deal of code that fails in ways nobody can predict from a
screenshot.

## Two things to know before you ship it

**The clipboard.** Flutter's built-in `Clipboard` carries plain text only.
Putting HTML on the system clipboard needs a platform plugin, which this
package deliberately does not pull in: it converts whatever HTML the host
hands it and leaves the transport to the host.

**Trust.** Neither direction sanitizes. Import keeps a URL verbatim because
validating it belongs where the link is made tappable, and export escapes
every value it writes but does not filter what a document contains. An
application that renders the result as live HTML must sanitize it, exactly as
it must for any HTML it did not author.

Parsing is bounded — nesting depth, node count and text length — because
pasted markup is untrusted input.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
