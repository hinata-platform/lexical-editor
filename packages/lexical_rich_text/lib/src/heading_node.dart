/// Headings.
library;

import 'package:lexical_core/lexical_core.dart';

/// The heading levels Lexical serializes.
enum HeadingTag {
  /// Level 1.
  h1,

  /// Level 2.
  h2,

  /// Level 3.
  h3,

  /// Level 4.
  h4,

  /// Level 5.
  h5,

  /// Level 6.
  h6;

  /// The wire-format string, which is the enum name.
  String get wire => name;

  /// Parses a wire-format tag, defaulting to [h1] for anything unknown.
  ///
  /// Upstream has no notion of an invalid tag — its type is a union — so a
  /// document carrying one is already outside the format. Defaulting keeps
  /// the rest of the document readable rather than failing the whole import.
  static HeadingTag fromWire(Object? value) {
    for (final tag in HeadingTag.values) {
      if (tag.wire == value) return tag;
    }
    return HeadingTag.h1;
  }

  /// The nesting level, 1 through 6.
  int get level => index + 1;
}

/// A section heading.
class HeadingNode extends ElementNode {
  /// Creates a heading at [tag].
  HeadingNode([this._tag = HeadingTag.h1]);

  HeadingTag _tag;

  @override
  String get type => 'heading';

  @override
  HeadingNode clone() => HeadingNode(_tag);

  @override
  void afterCloneFrom(covariant HeadingNode prev) {
    super.afterCloneFrom(prev);
    _tag = prev._tag;
  }

  /// The heading level.
  HeadingTag get tag => getLatest<HeadingNode>()._tag;

  /// Sets the heading level.
  HeadingNode setTag(HeadingTag value) =>
      getWritable<HeadingNode>().._tag = value;

  @override
  ElementNode insertNewAfter({required bool isAtEnd}) {
    // Enter at the end of a heading starts body text; Enter inside it splits
    // the heading in two. Both match Lexical web, and the first is the one
    // people notice when it is wrong.
    final next = isAtEnd ? $createParagraphNode() : $createHeadingNode(tag);
    next.setDirection(getDirection());
    insertAfter(next);
    return next;
  }

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'tag': _tag.wire,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _tag = HeadingTag.fromWire(json['tag']);
  }
}

/// Creates a heading, applying any registered node replacement.
HeadingNode $createHeadingNode([HeadingTag tag = HeadingTag.h1]) =>
    $applyNodeReplacement(HeadingNode(tag));
