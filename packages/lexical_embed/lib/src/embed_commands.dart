/// Inserting an embed.
library;

import 'package:lexical_core/lexical_core.dart';

import 'embed_nodes.dart';
import 'embed_urls.dart';

/// Inserts an embed for a pasted URL, if the URL is one Lexical can embed.
///
/// The handler returns `false` for anything else, which lets a lower-priority
/// handler — an auto-link plugin, usually — have the URL instead. That is the
/// whole fallback story for video sources Lexical does not support: they stay
/// links, because there is no node that would make them anything else.
const LexicalCommand<String> insertEmbedFromUrlCommand = LexicalCommand(
  'INSERT_EMBED_FROM_URL',
);

/// Inserts a YouTube video by id.
const LexicalCommand<String> insertYouTubeCommand = LexicalCommand(
  'INSERT_YOUTUBE',
);

/// Inserts a tweet by status id.
const LexicalCommand<String> insertTweetCommand = LexicalCommand(
  'INSERT_TWEET',
);

/// Inserts a Figma document by id.
const LexicalCommand<String> insertFigmaCommand = LexicalCommand(
  'INSERT_FIGMA',
);

/// Registers the embed commands on [editor].
Unsubscribe registerEmbed(LexicalEditor editor) {
  final subscriptions = <Unsubscribe>[
    editor.registerCommand<String>(insertEmbedFromUrlCommand, (url) {
      final target = matchEmbedUrl(url);
      if (target == null) return false;
      $insertEmbed(target.createNode());
      return true;
    }, CommandPriority.editor),
    editor.registerCommand<String>(insertYouTubeCommand, (id) {
      $insertEmbed($createYouTubeNode(id));
      return true;
    }, CommandPriority.editor),
    editor.registerCommand<String>(insertTweetCommand, (id) {
      $insertEmbed($createTweetNode(id));
      return true;
    }, CommandPriority.editor),
    editor.registerCommand<String>(insertFigmaCommand, (id) {
      $insertEmbed($createFigmaNode(id));
      return true;
    }, CommandPriority.editor),
  ];
  return () {
    for (final unsubscribe in subscriptions) {
      unsubscribe();
    }
  };
}

/// Puts [node] on its own line at the selection, with a way out below it.
///
/// An embed is a block decorator: it cannot sit inside a paragraph, and an
/// embed as the last thing in a document is a trap, because there is no block
/// below it that would take the caret. The empty paragraph the user was
/// standing on is removed — inserting *on* an empty line should not leave that
/// line behind.
void $insertEmbed(LexicalNode node) {
  final selection = $getSelection();
  final block = selection is RangeSelection
      ? _topLevelBlockOf(selection.focus.getNode())
      : null;

  if (block == null) {
    $getRoot()
      ..append(node)
      ..append($createParagraphNode());
    return;
  }

  final after = $createParagraphNode();
  block.insertAfter(node);
  node.insertAfter(after);
  after.selectStart();

  if (block is ParagraphNode && block.childrenSize == 0) block.remove();
}

/// The top-level block [node] sits in, or `null`.
LexicalNode? _topLevelBlockOf(LexicalNode? node) {
  var current = node;
  while (current != null) {
    final parent = current.getParent();
    if (parent == null) return null;
    if (parent is RootNode) return current;
    current = parent;
  }
  return null;
}
