/// The markdown spelling of an embed.
library;

import 'package:lexical_markdown/lexical_markdown.dart';

import 'embed_nodes.dart';
import 'embed_urls.dart';

/// `<tweet id="1234567890" />`, exactly as the playground writes it.
///
/// An odd spelling for markdown, and it is upstream's — matching it is what
/// lets a document exported here be pasted into the playground and come back
/// as a tweet rather than as a line of literal text.
final ElementTransformer tweetTransformer = ElementTransformer(
  regExp: RegExp(r'^<tweet id="([^"]+?)"\s?/>\s?$'),
  replace: (block, children, match) {
    block.replace($createTweetNode(match.group(1)!));
  },
  export: (node, exportChildren) {
    if (node is! TweetNode) return null;
    return '<tweet id="${node.tweetId}" />';
  },
);

/// A line that is nothing but an embeddable URL.
///
/// Upstream has no markdown rule for YouTube or Figma at all, so a video is
/// simply lost when the playground exports markdown. This rule is therefore an
/// **addition**, not a port — and it is deliberately shaped so that the
/// markdown stays ordinary: a bare URL on its own line is valid markdown
/// everywhere, reads correctly for a human, and is what the playground's
/// auto-embed turns into a video anyway when it is pasted back in.
///
/// It claims a line only when the *whole* line is one embeddable URL. A URL in
/// a sentence stays a URL.
final ElementTransformer embedUrlTransformer = ElementTransformer(
  // Narrow on purpose. A rule that claimed any single-word line would take
  // `>quote` and `#Titel` away from the rules that come after it, because the
  // first rule to match a line is the one that gets it.
  regExp: RegExp(r'^\s*(https?://\S+)\s*$'),
  replace: (block, children, match) {
    final target = matchEmbedUrl(match.group(1)!);
    if (target == null) {
      // An ordinary URL. The rule claimed the line, so it has to put the line
      // back — the importer has already handed over its parsed children and
      // will not append them itself.
      block.appendAll(children);
      return;
    }
    block.replace(target.createNode());
  },
  export: (node, exportChildren) => switch (node) {
    final YouTubeNode video => video.watchUrl,
    final FigmaNode figma => figma.url,
    // A tweet has upstream's own spelling; it is handled by
    // [tweetTransformer], which is tried first.
    _ => null,
  },
);

/// Both embed rules, in the order they have to be tried.
///
/// ```dart
/// final transformers = defaultMarkdownTransformers.extend(
///   elements: embedTransformers,
/// );
/// ```
final List<ElementTransformer> embedTransformers = [
  tweetTransformer,
  embedUrlTransformer,
];
