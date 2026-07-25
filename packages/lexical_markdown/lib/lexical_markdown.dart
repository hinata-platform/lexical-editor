/// Markdown import and export for `lexical_core`.
///
/// Conversion is built from **transformers**: small declarations that describe
/// one construct in both directions at once. That is the whole design, and the
/// reason for it is that a heading which imports from `## ` but exports to
/// something else is a bug a split design makes easy to write and hard to
/// notice.
///
/// ```dart
/// editor.update(() {
///   $convertFromMarkdown(source, transformers: defaultMarkdownTransformers);
/// }, discrete: true);
///
/// final back = editor.read(
///   () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
/// );
/// ```
///
/// **Markdown is lossier than the document model**, and the conversion is
/// honest about it rather than pretending otherwise: alignment, indentation,
/// text colour, marks and mentions have no markdown spelling and do not
/// survive a round trip through it. Use the JSON wire format to move documents
/// between editors; use markdown to move them between *people*.
library;

export 'src/default_transformers.dart'
    show
        bulletListTransformer,
        checkListTransformer,
        codeTransformer,
        defaultMarkdownTransformers,
        defaultTextFormatTransformers,
        headingTransformer,
        linkTransformer,
        orderedListTransformer,
        quoteTransformer;
export 'src/export.dart' show $convertToMarkdown;
export 'src/import.dart' show $convertFromMarkdown;
export 'src/transformers.dart'
    show
        ElementExport,
        ElementReplace,
        ElementTransformer,
        ExportChildren,
        MarkdownTransformers,
        TextFormatTransformer,
        TextMatchExport,
        TextMatchReplace,
        TextMatchTransformer;
