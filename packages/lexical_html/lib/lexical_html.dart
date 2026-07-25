/// HTML import and export for `lexical_core`.
///
/// Two jobs, both real and both distinct from the JSON wire format:
///
/// * **Export** renders a document as ordinary HTML — `<strong>`, not
///   `<span class="lexical-bold">` — so text that leaves the editor is
///   readable by a mail client, a CMS, or a browser that has never heard of
///   Lexical.
/// * **Import** turns HTML from anywhere else into nodes, mapping the tags
///   documents actually arrive as and contributing the *text* of anything it
///   does not recognize. A paste that silently drops content is the one
///   outcome worth designing against.
///
/// ```dart
/// final html = editor.read($generateHtmlFromNodes);
///
/// editor.update(() {
///   final selection = $getSelection();
///   if (selection is RangeSelection) {
///     selection.insertNodes($generateNodesFromHtml(pasted));
///   }
/// });
/// ```
///
/// **A note on the clipboard.** Flutter's built-in `Clipboard` carries plain
/// text only; putting HTML on the system clipboard needs a platform plugin,
/// which this package deliberately does not pull in. It converts whatever
/// HTML the host hands it, and leaves the transport to the host.
///
/// **A note on trust.** Neither direction sanitizes. Import keeps a URL
/// verbatim because validating it belongs where the link is made tappable,
/// and export escapes every value it writes but does not filter what a
/// document contains. An application rendering the result as live HTML must
/// sanitize it, exactly as it must for any HTML it did not author.
library;

export 'src/export.dart'
    show HtmlExport, HtmlNodeExport, escapeHtml, $generateHtmlFromNodes;
export 'src/import.dart'
    show HtmlImport, HtmlImportLimits, HtmlNodeImport, $generateNodesFromHtml;
