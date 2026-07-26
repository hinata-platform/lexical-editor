/// Turning `#something` into a hashtag while it is typed.
library;

import 'package:lexical_core/lexical_core.dart';

import 'hashtag_node.dart';

/// What counts as a hashtag.
///
/// `#` followed by letters, digits or underscores, and only at the start of a
/// word — otherwise `a#b` and every URL fragment would become one. Letters
/// are matched by Unicode class, so `#Grüße` and `#مرحبا` are tags too.
final RegExp defaultHashtagPattern = RegExp(
  r'(?<![\w#])#[\p{L}\p{N}_]+',
  unicode: true,
);

/// Detects hashtags as they are typed, and undoes the detection when the
/// text stops being one.
///
/// Without this a `HashtagNode` can only be created in code — which is what
/// `lexical_hashtag` did until now, and not what a package with this name is
/// expected to do. Upstream registers the same pair of transforms.
///
/// ```dart
/// final editor = LexicalEditor(nodes: hashtagNodes);
/// registerHashtag(editor);
/// ```
///
/// Both directions matter and the second is the one that is easy to forget:
/// deleting the `#` in front of a tag has to turn it back into ordinary text,
/// or the run stays a hashtag that no longer looks like one.
///
/// Text inside a code block is left alone — `#include` is not a tag.
Unsubscribe registerHashtag(
  LexicalEditor editor, {
  RegExp? pattern,
  Set<String> excludedAncestors = const {'code'},
}) {
  final match = pattern ?? defaultHashtagPattern;

  bool insideExcluded(LexicalNode node) {
    for (
      LexicalNode? parent = node.getParent();
      parent != null;
      parent = parent.getParent()
    ) {
      if (excludedAncestors.contains(parent.type)) return true;
    }
    return false;
  }

  final unsubscribes = <Unsubscribe>[
    editor.registerNodeTransform('text', (node) {
      if (node is! TextNode || node is HashtagNode) return;
      if (node.isToken || insideExcluded(node)) return;
      final text = node.getTextContent();
      final hit = match.firstMatch(text);
      if (hit == null) return;

      // Split off the tag and replace only that run: the surrounding text
      // keeps its own formatting, and the caret keeps its offsets.
      final offsets = <int>[
        if (hit.start > 0) hit.start,
        if (hit.end < text.length) hit.end,
      ];
      final parts = offsets.isEmpty ? [node] : node.splitText(offsets);
      final target = hit.start > 0 ? parts[1] : parts.first;
      target.replace(
        $createHashtagNode(target.getTextContent())
          ..setFormat(target.getFormat())
          ..setStyle(target.getStyle()),
      );
    }),
    editor.registerNodeTransform('hashtag', (node) {
      if (node is! HashtagNode) return;
      final text = node.getTextContent();
      final hit = match.firstMatch(text);
      // Still exactly a tag: nothing to do.
      if (hit != null && hit.start == 0 && hit.end == text.length) return;
      // No longer one — the `#` was deleted, or ordinary text was typed onto
      // the end. It goes back to being text, and the transform above picks
      // the tag out again if one is still in there.
      node.replace(
        $createTextNode(text)
          ..setFormat(node.getFormat())
          ..setStyle(node.getStyle()),
      );
    }),
  ];

  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}
