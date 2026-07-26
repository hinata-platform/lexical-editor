/// The markdown spelling of an image.
library;

import 'package:lexical_markdown/lexical_markdown.dart';

import 'image_node.dart';

/// `![alt](src)`, in both directions.
///
/// This is deliberately **not** part of [defaultMarkdownTransformers], because
/// it is not part of upstream's `TRANSFORMERS` either — `@lexical/markdown`
/// ships no image rule, and the playground adds its own to the list it passes
/// in. Add it the same way:
///
/// ```dart
/// final transformers = defaultMarkdownTransformers.extend(
///   textMatches: [imageTransformer],
/// );
/// ```
///
/// ## What markdown cannot carry
///
/// Only the alt text and the source survive. Size, caption and `maxWidth` have
/// no markdown spelling, so a round trip through markdown drops them — which
/// is markdown's limit rather than this port's, and the reason the JSON wire
/// format exists. Upstream loses exactly the same fields.
///
/// The `maxWidth` an imported image is given is `800`, not
/// [ImageNode.defaultMaxWidth]. That looks arbitrary and is: it is the number
/// the playground's own IMAGE transformer writes, and matching it means the
/// same markdown decodes to the same document on both platforms.
final TextMatchTransformer imageTransformer = TextMatchTransformer(
  // The `!` has to be part of the match. Without it the link rule claims the
  // `[alt](src)` that follows, and the image arrives as a link with a stray
  // exclamation mark in front of it.
  regExp: RegExp(r'!\[([^\[\]]*)\]\(([^)\s]+)\)'),
  replace: (match, format) => $createImageNode(
    src: match.group(2)!,
    altText: match.group(1)!,
    maxWidth: markdownImageMaxWidth,
  ),
  export: (node, exportChildren) {
    if (node is! ImageNode) return null;
    return '![${node.altText}](${node.src})';
  },
);

/// The `maxWidth` given to an image parsed from markdown.
///
/// Upstream's IMAGE transformer hard-codes `800`. Keeping the same number
/// keeps the two ports byte-identical on the same input.
const double markdownImageMaxWidth = 800;
