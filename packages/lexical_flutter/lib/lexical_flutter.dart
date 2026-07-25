/// Flutter rendering for `lexical_core`.
///
/// Lexical's reconciler diffs into a DOM and lets `contenteditable` handle
/// input and selection. Flutter offers neither, so this layer is designed
/// rather than translated:
///
/// * one render object **per block**, so a keystroke relayouts a paragraph
///   rather than the document;
/// * an `InlineSpan` and a bidirectional offset map built in the same walk,
///   so they cannot drift apart;
/// * rebuilds driven by each commit's dirty set, so untouched blocks are
///   reused by reference.
///
/// ```dart
/// LexicalDocument(
///   editor: editor,
///   theme: LexicalTheme(baseTextStyle: DefaultTextStyle.of(context).style),
/// )
/// ```
///
/// Node types come from their own packages; this one knows only the element
/// and text base shapes, and styles blocks by their **type string** so it
/// never has to import them.
library;

export 'src/render/block_offset_map.dart'
    show BlockOffsetMap, OffsetSegment, ResolvedPoint;
export 'src/render/render_lexical_block.dart'
    show BlockCaret, RenderLexicalBlock;
export 'src/render/span_builder.dart'
    show BuiltBlockSpan, SpanBuilder, isInlineContent;
export 'src/theme/css_style.dart'
    show
        CssStyleResolver,
        defaultCssStyleResolver,
        parseCssColor,
        parseCssDeclarations,
        parseCssFontWeight,
        parseCssLength,
        parseCssTextDecoration;
export 'src/theme/lexical_theme.dart'
    show
        BlockMarker,
        BlockMarkerBuilder,
        BlockStyle,
        DecoratorBuilder,
        LexicalTheme,
        applyCaseTransform;
export 'src/widgets/block_registry.dart'
    show BlockRegistry, BlockRegistryScope, MountedBlock, RegisteredBlock;
export 'src/widgets/lexical_document.dart'
    show LexicalDocument, LexicalDocumentState, LexicalRenderStats;
export 'src/widgets/lexical_inline_block.dart' show LexicalInlineBlock;
