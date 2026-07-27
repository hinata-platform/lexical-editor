/// The transformer types markdown conversion is built from.
///
/// Both directions are described by the *same* declaration, which is the point:
/// a heading that imports from `## ` and exports to something else is a bug
/// that a split design makes easy to write and hard to notice.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

/// Renders an element's inline content back to markdown.
typedef ExportChildren = String Function(ElementNode element);

/// Turns a matched line into a block.
///
/// [block] is the paragraph the line was parsed into; replace it, or move
/// [children] into a different element. Returning without touching it leaves
/// the line as a paragraph.
typedef ElementReplace =
    void Function(
      ElementNode block,
      List<LexicalNode> children,
      RegExpMatch match,
    );

/// Renders a block to markdown, or returns `null` to decline it.
///
/// Takes a [LexicalNode] rather than an [ElementNode] because not every block
/// is an element: a video embed is a block-level *decorator* with no children
/// at all, and a signature that could not name it would drop it from every
/// export without a word.
typedef ElementExport =
    String? Function(LexicalNode node, ExportChildren exportChildren);

/// A block-level markdown rule.
@immutable
final class ElementTransformer {
  /// Creates a rule matching [regExp] on a single line.
  const ElementTransformer({
    required this.regExp,
    required this.replace,
    required this.export,
    this.exportsSubtree = false,
  });

  /// Matched against one line of markdown, anchored at its start.
  final RegExp regExp;

  /// Builds the block from a match.
  final ElementReplace replace;

  /// Renders a block of the type this rule produces.
  final ElementExport export;

  /// Whether [export] renders the block's child blocks as well.
  ///
  /// Normally it does not, and it should not: a list item renders its own
  /// line, and the nested list inside it is rendered by the same rule one
  /// level down. Appending the children afterwards is what makes nesting work
  /// without every rule having to walk a subtree.
  ///
  /// A table is the exception. Its rows and cells have no markdown spelling
  /// of their own — a row is only meaningful as a line of the table it is in —
  /// so the rule renders the whole thing at once. Without this flag the cells
  /// are then appended a second time, one per line, under the table.
  final bool exportsSubtree;
}

/// A paired inline delimiter, such as `**` for bold.
@immutable
final class TextFormatTransformer {
  /// Declares [tag] as the delimiter for [format].
  const TextFormatTransformer({
    required this.tag,
    required this.format,
    this.literal = false,
  });

  /// The delimiter, opening and closing.
  final String tag;

  /// The format bit it sets.
  final TextFormat format;

  /// Whether what the delimiters enclose is taken exactly as written.
  ///
  /// True for a code span, and the reason is not a preference: in markdown the
  /// content of `` `a **b**` `` is the characters `a **b**`, so parsing
  /// emphasis inside it invents formatting the author did not write and — far
  /// worse — exports as `` `a `**`b`** ``, which is no longer the same
  /// document and no longer valid markdown. CommonMark and upstream both stop
  /// inline parsing inside a code span.
  final bool literal;
}

/// Builds a node from an inline match, or returns `null` to decline it.
typedef TextMatchReplace = LexicalNode? Function(RegExpMatch match, int format);

/// Renders an inline node to markdown, or returns `null` to decline it.
typedef TextMatchExport =
    String? Function(LexicalNode node, ExportChildren exportChildren);

/// An inline markdown rule that is not a paired delimiter — a link, say.
@immutable
final class TextMatchTransformer {
  /// Creates a rule matching [regExp] anywhere in a line.
  const TextMatchTransformer({
    required this.regExp,
    required this.replace,
    required this.export,
    this.parsesInlineContent = false,
  });

  /// Matched against the text of a line.
  final RegExp regExp;

  /// Builds the node from a match.
  final TextMatchReplace replace;

  /// Renders a node of the type this rule produces.
  final TextMatchExport export;

  /// Whether the text [replace] puts inside the node is itself inline markdown.
  ///
  /// A link label is: CommonMark reads `[ein *kursiver* Link](url)` as a link
  /// holding emphasis, not as a link holding three asterisk characters. The
  /// rule cannot parse it itself — [TextMatchReplace] is handed a match, not
  /// the rule set — so it says so here and the importer parses the text
  /// children of whatever it built.
  ///
  /// Off by default, and it has to be: a rule whose content is deliberately
  /// literal — anything code-like — would have its content rewritten by a
  /// setting it never asked for. Opting in is the difference between a rule
  /// that carries markdown and one that carries characters.
  final bool parsesInlineContent;
}

/// A complete set of markdown rules.
@immutable
final class MarkdownTransformers {
  /// Bundles the three kinds of rule.
  const MarkdownTransformers({
    this.elements = const [],
    this.textFormats = const [],
    this.textMatches = const [],
  });

  /// Block-level rules, tried in order.
  final List<ElementTransformer> elements;

  /// Paired inline delimiters.
  ///
  /// Order matters for ambiguous prefixes: `**` must be tried before `*`, or
  /// bold parses as two empty italics.
  final List<TextFormatTransformer> textFormats;

  /// Inline rules that are not paired delimiters.
  final List<TextMatchTransformer> textMatches;

  /// Returns a copy with extra rules appended.
  MarkdownTransformers extend({
    List<ElementTransformer> elements = const [],
    List<TextFormatTransformer> textFormats = const [],
    List<TextMatchTransformer> textMatches = const [],
  }) => MarkdownTransformers(
    elements: [...elements, ...this.elements],
    textFormats: [...textFormats, ...this.textFormats],
    textMatches: [...textMatches, ...this.textMatches],
  );
}
