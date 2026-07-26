/// The widget an embed is drawn with.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'embed_nodes.dart';
import 'embed_urls.dart';

/// Opens an embed outside the editor.
///
/// A hook rather than a dependency: launching a URL needs a plugin, and which
/// one — an in-app browser, the system browser, a native player, a route in
/// the host application — is not this package's decision to make.
typedef EmbedOpener = void Function(EmbedKind kind, String url);

/// Finds a still image for an embed, or returns `null` for a plain card.
typedef EmbedThumbnailResolver =
    ImageProvider<Object>? Function(EmbedKind kind, String id);

/// Uses YouTube's public thumbnail, and nothing for the other kinds.
///
/// Twitter and Figma have no image that can be fetched without an API key, so
/// asking for one would only produce a broken request per card.
ImageProvider<Object>? defaultEmbedThumbnailResolver(
  EmbedKind kind,
  String id,
) => switch (kind) {
  EmbedKind.youtube => NetworkImage(
    'https://img.youtube.com/vi/$id/hqdefault.jpg',
  ),
  EmbedKind.tweet || EmbedKind.figma => null,
};

/// A card standing in for an embedded video, tweet or Figma document.
///
/// **It is a card, not a player.** Playing a video in Flutter means a platform
/// view and a plugin dependency, and a document package that dragged one in
/// would impose it on everyone who merely wanted to *read* a document
/// containing a video. The card carries the thumbnail, the title and a tap
/// target; [onOpen] decides what happens next, and an application that does
/// want an inline player can build its own widget and register it in place of
/// this one.
class LexicalEmbedView extends StatelessWidget {
  /// Draws a card for the embed [id] of [kind], linking to [url].
  const LexicalEmbedView({
    required this.kind,
    required this.id,
    required this.url,
    super.key,
    this.label,
    this.onOpen,
    this.thumbnailResolver = defaultEmbedThumbnailResolver,
    this.maxWidth = 560,
    this.accentColor = const Color(0xFF4DA3FF),
    this.surfaceColor = const Color(0x14808DAD),
    this.textColor = const Color(0xFF0B1020),
    this.mutedTextColor = const Color(0xFF808DAD),
  });

  /// What kind of embed this is.
  final EmbedKind kind;

  /// The stored identifier.
  final String id;

  /// Where a tap should lead.
  final String url;

  /// A title to show instead of the URL, when the application knows one.
  final String? label;

  /// Called when the card is tapped. A card with no opener is not tappable.
  final EmbedOpener? onOpen;

  /// Finds the still image, if there is one.
  final EmbedThumbnailResolver thumbnailResolver;

  /// The widest the card is drawn.
  final double maxWidth;

  /// The colour of the play badge.
  final Color accentColor;

  /// The card's background.
  final Color surfaceColor;

  /// The colour of the title.
  final Color textColor;

  /// The colour of the second line.
  final Color mutedTextColor;

  String get _kindLabel => switch (kind) {
    EmbedKind.youtube => 'YouTube',
    EmbedKind.tweet => 'Tweet',
    EmbedKind.figma => 'Figma',
  };

  @override
  Widget build(BuildContext context) {
    final thumbnail = thumbnailResolver(kind, id);
    final opener = onOpen;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (thumbnail != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: thumbnail,
                      fit: BoxFit.cover,
                      // A thumbnail that fails to load must not take the card
                      // with it: the URL is still the content.
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                    Center(child: _PlayBadge(color: accentColor)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label ?? _kindLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      link: true,
      label: '$_kindLabel: ${label ?? url}',
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: opener == null
                ? card
                : MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => opener(kind, url),
                      child: card,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The triangle in a circle every video thumbnail on earth has.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: CustomPaint(painter: _PlayBadgePainter(color)),
  );
}

class _PlayBadgePainter extends CustomPainter {
  const _PlayBadgePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      centre,
      size.width / 2,
      Paint()..color = const Color(0xCC0B1020),
    );
    final triangle = Path()
      ..moveTo(centre.dx - size.width * 0.12, centre.dy - size.height * 0.18)
      ..lineTo(centre.dx + size.width * 0.20, centre.dy)
      ..lineTo(centre.dx - size.width * 0.12, centre.dy + size.height * 0.18)
      ..close();
    canvas.drawPath(triangle, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlayBadgePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Decorator builders for `youtube`, `tweet` and `figma`.
///
/// ```dart
/// LexicalEditable(
///   editor: editor,
///   theme: theme,
///   decoratorBuilders: embedDecoratorBuilders(
///     onOpen: (kind, url) => launchUrlString(url),
///   ),
/// )
/// ```
///
/// {@macro lexical_flutter.builder_read_scope}
Map<String, Widget Function(BuildContext, DecoratorNode)>
embedDecoratorBuilders({
  EmbedOpener? onOpen,
  EmbedThumbnailResolver thumbnailResolver = defaultEmbedThumbnailResolver,
  String Function(EmbedKind kind, String id)? labelFor,
  double maxWidth = 560,
}) {
  Widget build(EmbedKind kind, String id, String url) => LexicalEmbedView(
    kind: kind,
    id: id,
    url: url,
    label: labelFor?.call(kind, id),
    onOpen: onOpen,
    thumbnailResolver: thumbnailResolver,
    maxWidth: maxWidth,
  );

  return {
    'youtube': (context, node) {
      final video = node as YouTubeNode;
      return build(EmbedKind.youtube, video.videoId, video.watchUrl);
    },
    'tweet': (context, node) {
      final tweet = node as TweetNode;
      return build(EmbedKind.tweet, tweet.tweetId, tweet.url);
    },
    'figma': (context, node) {
      final figma = node as FigmaNode;
      return build(EmbedKind.figma, figma.documentId, figma.url);
    },
  };
}
