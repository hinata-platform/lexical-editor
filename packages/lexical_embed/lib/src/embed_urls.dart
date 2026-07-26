/// Turning a pasted URL into an embed, or declining to.
library;

import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

import 'embed_nodes.dart';

/// The kinds of embed Lexical has.
///
/// The list is short and it is *closed*: these are the three the playground
/// implements, and a fourth would be a node no other client can open.
enum EmbedKind {
  /// A YouTube video — the only kind of video Lexical knows.
  youtube,

  /// A tweet.
  tweet,

  /// A Figma file or prototype.
  figma,
}

/// A URL that turned out to be embeddable.
@immutable
final class EmbedTarget {
  /// Describes an embed of [kind] with [id], found in [url].
  const EmbedTarget({required this.kind, required this.id, required this.url});

  /// What kind of embed it is.
  final EmbedKind kind;

  /// The identifier the node stores — a video id, a status id, a file key.
  final String id;

  /// The URL it was recognised in, kept for diagnostics rather than storage.
  final String url;

  /// The node for this target.
  LexicalNode createNode() => switch (kind) {
    EmbedKind.youtube => $createYouTubeNode(id),
    EmbedKind.tweet => $createTweetNode(id),
    EmbedKind.figma => $createFigmaNode(id),
  };

  @override
  bool operator ==(Object other) =>
      other is EmbedTarget &&
      other.kind == kind &&
      other.id == id &&
      other.url == url;

  @override
  int get hashCode => Object.hash(kind, id, url);

  @override
  String toString() => 'EmbedTarget(${kind.name}, $id)';
}

// The three patterns below are upstream's, from the playground's
// AutoEmbedPlugin. Rewriting them "more cleanly" would change which URLs are
// accepted, and the point is to accept exactly the same ones. The single
// deliberate difference is the escaped dot in `figma\.com`: upstream leaves it
// unescaped, so its pattern also matches `figmaXcom`, which is a host somebody
// else can register.
final RegExp _youTube = RegExp(
  r'^.*(youtu\.be/|v/|u/\w/|embed/|watch\?v=|&v=)([^#&?]*).*$',
);
final RegExp _tweet = RegExp(
  r'^https://(twitter|x)\.com/(#!/)?(\w+)/status(es)*/(\d+)$',
);
final RegExp _figma = RegExp(
  r'https://([\w.-]+\.)?figma\.com/(file|proto)/([0-9a-zA-Z]{22,128})(?:/.*)?$',
);

/// The length of a YouTube video id. Upstream checks it, and so does this:
/// the pattern above is loose enough to match `youtube.com/feed/v/`.
const int _youTubeIdLength = 11;

/// Recognises an embeddable URL, or returns `null`.
///
/// ```dart
/// matchEmbedUrl('https://youtu.be/dQw4w9WgXcQ');   // youtube
/// matchEmbedUrl('https://vimeo.com/76979871');     // null
/// ```
///
/// A `null` is not a failure to be papered over — **Lexical has no generic
/// video node**, so a Vimeo link, an MP4 or an HLS stream has no
/// representation that another Lexical client could open. The honest handling
/// is to leave such a URL as a link, which is what the playground does too.
EmbedTarget? matchEmbedUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final youTube = _youTube.firstMatch(trimmed);
  final videoId = youTube?.group(2);
  if (videoId != null && videoId.length == _youTubeIdLength) {
    return EmbedTarget(kind: EmbedKind.youtube, id: videoId, url: trimmed);
  }

  final tweet = _tweet.firstMatch(trimmed);
  if (tweet != null) {
    return EmbedTarget(
      kind: EmbedKind.tweet,
      id: tweet.group(5)!,
      url: trimmed,
    );
  }

  final figma = _figma.firstMatch(trimmed);
  if (figma != null) {
    return EmbedTarget(
      kind: EmbedKind.figma,
      id: figma.group(3)!,
      url: trimmed,
    );
  }

  return null;
}
