/// Embedded videos, tweets and Figma documents for `lexical_core`.
///
/// ```dart
/// final editor = LexicalEditor(nodes: embedNodes);
/// registerEmbed(editor);
///
/// LexicalEditable(
///   editor: editor,
///   theme: theme,
///   decoratorBuilders: embedDecoratorBuilders(
///     onOpen: (kind, url) => launchUrlString(url),
///   ),
/// );
///
/// // Anything a user pastes:
/// final handled = editor.dispatchCommand(insertEmbedFromUrlCommand, url);
/// ```
///
/// ## What "video" means here
///
/// Lexical has **no generic video node**. There is no `<video>` element, no
/// media node backed by a file, and no published `@lexical/*` package for one:
/// the playground implements `youtube`, `tweet` and `figma`, and that is the
/// entire list. This package implements those three and nothing else, because
/// a fourth type would produce documents that no other Lexical client — web,
/// server, or a future version of this one — could open.
///
/// So a Vimeo link, an MP4 or an HLS stream is not an embed.
/// `insertEmbedFromUrlCommand` returns `false` for it, which leaves the URL to
/// a lower-priority handler, and the sensible thing for that handler to do is
/// make it a link. That is what the playground does too.
///
/// An application that genuinely needs its own media type can register a node
/// under its own type string — but it should know it is leaving the
/// interchange format when it does, and say so to its users.
///
/// ## What is drawn
///
/// A card with a thumbnail and a tap target, not a player. An inline player
/// means a platform view and a plugin dependency, which a document package has
/// no business imposing on everyone who only wants to read the document. Swap
/// in your own builder for `youtube` if you want one.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/embed_nodes.dart';

export 'src/decorator_block_node.dart' show DecoratorBlockNode;
export 'src/embed_commands.dart'
    show
        insertEmbedFromUrlCommand,
        insertFigmaCommand,
        insertTweetCommand,
        insertYouTubeCommand,
        registerEmbed,
        $insertEmbed;
export 'src/embed_markdown.dart'
    show embedTransformers, embedUrlTransformer, tweetTransformer;
export 'src/embed_nodes.dart'
    show
        FigmaNode,
        TweetNode,
        YouTubeNode,
        $createFigmaNode,
        $createTweetNode,
        $createYouTubeNode;
export 'src/embed_urls.dart' show EmbedKind, EmbedTarget, matchEmbedUrl;
export 'src/embed_view.dart'
    show
        EmbedOpener,
        EmbedThumbnailResolver,
        LexicalEmbedView,
        defaultEmbedThumbnailResolver,
        embedDecoratorBuilders;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get embedNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<YouTubeNode>(type: 'youtube', create: YouTubeNode.new),
  NodeSpec<TweetNode>(type: 'tweet', create: TweetNode.new),
  NodeSpec<FigmaNode>(type: 'figma', create: FigmaNode.new),
];
