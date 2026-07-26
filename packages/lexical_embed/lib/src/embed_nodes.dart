/// The three embed nodes Lexical actually has.
library;

import 'package:lexical_core/lexical_core.dart';

import 'decorator_block_node.dart';

/// A YouTube video.
///
/// **This is what "a video" means in Lexical.** There is no generic video
/// node, no `<video>` element node and no file-backed media node anywhere in
/// the project — the playground embeds YouTube, Twitter and Figma, and that is
/// the whole list. A document claiming otherwise would not open on the web.
///
/// ```json
/// { "type": "youtube", "version": 1, "format": "", "videoID": "dQw4w9WgXcQ" }
/// ```
///
/// Only the **id** is stored, never the URL it was pasted from. That is
/// upstream's choice and a good one: `youtu.be/x`, `youtube.com/watch?v=x` and
/// `youtube.com/embed/x` are the same video, and keeping the accident of how
/// it was pasted would make two identical documents compare unequal.
class YouTubeNode extends DecoratorBlockNode {
  /// Creates a node showing the video with [videoId].
  YouTubeNode({String videoId = '', super.format}) : _videoId = videoId;

  String _videoId;

  @override
  String get type => 'youtube';

  /// The video's id — the eleven characters after `v=`.
  String get videoId => getLatest<YouTubeNode>()._videoId;

  /// The page a viewer should be sent to.
  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  /// The player URL, on the cookie-free host upstream uses.
  String get embedUrl => 'https://www.youtube-nocookie.com/embed/$videoId';

  /// A still from the video, served by YouTube without an API key.
  String get thumbnailUrl =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  @override
  YouTubeNode clone() => YouTubeNode(videoId: _videoId, format: format);

  @override
  void afterCloneFrom(covariant YouTubeNode prev) {
    super.afterCloneFrom(prev);
    _videoId = prev._videoId;
  }

  /// The text a copy of this block should produce: upstream's watch URL.
  @override
  String getTextContent() => watchUrl;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'videoID': _videoId,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final id = json['videoID'];
    _videoId = id is String ? id : '';
  }

  @override
  String toString() => 'YouTubeNode($_videoId)';
}

/// A tweet, by whatever the site is called this year.
///
/// ```json
/// { "type": "tweet", "version": 1, "format": "", "id": "1234567890" }
/// ```
class TweetNode extends DecoratorBlockNode {
  /// Creates a node showing the tweet with [tweetId].
  TweetNode({String tweetId = '', super.format}) : _tweetId = tweetId;

  String _tweetId;

  @override
  String get type => 'tweet';

  /// The status id.
  String get tweetId => getLatest<TweetNode>()._tweetId;

  /// The page a viewer should be sent to.
  String get url => 'https://x.com/i/web/status/$tweetId';

  @override
  TweetNode clone() => TweetNode(tweetId: _tweetId, format: format);

  @override
  void afterCloneFrom(covariant TweetNode prev) {
    super.afterCloneFrom(prev);
    _tweetId = prev._tweetId;
  }

  @override
  String getTextContent() => url;

  @override
  Map<String, Object?> exportJson() => {...super.exportJson(), 'id': _tweetId};

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final id = json['id'];
    _tweetId = id is String ? id : '';
  }

  @override
  String toString() => 'TweetNode($_tweetId)';
}

/// A Figma file or prototype.
///
/// ```json
/// { "type": "figma", "version": 1, "format": "", "documentID": "abc…" }
/// ```
class FigmaNode extends DecoratorBlockNode {
  /// Creates a node showing the document with [documentId].
  FigmaNode({String documentId = '', super.format}) : _documentId = documentId;

  String _documentId;

  @override
  String get type => 'figma';

  /// The document id.
  String get documentId => getLatest<FigmaNode>()._documentId;

  /// The page a viewer should be sent to.
  String get url => 'https://www.figma.com/file/$documentId';

  @override
  FigmaNode clone() => FigmaNode(documentId: _documentId, format: format);

  @override
  void afterCloneFrom(covariant FigmaNode prev) {
    super.afterCloneFrom(prev);
    _documentId = prev._documentId;
  }

  @override
  String getTextContent() => url;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'documentID': _documentId,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final id = json['documentID'];
    _documentId = id is String ? id : '';
  }

  @override
  String toString() => 'FigmaNode($_documentId)';
}

/// Creates a YouTube embed, applying any registered node replacement.
YouTubeNode $createYouTubeNode(String videoId) =>
    $applyNodeReplacement(YouTubeNode(videoId: videoId));

/// Creates a tweet embed, applying any registered node replacement.
TweetNode $createTweetNode(String tweetId) =>
    $applyNodeReplacement(TweetNode(tweetId: tweetId));

/// Creates a Figma embed, applying any registered node replacement.
FigmaNode $createFigmaNode(String documentId) =>
    $applyNodeReplacement(FigmaNode(documentId: documentId));
