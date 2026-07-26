/// The base class every embed shares.
library;

import 'package:lexical_core/lexical_core.dart';

/// A decorator that occupies a whole block, and can be aligned.
///
/// Upstream keeps this class in `@lexical/react` because the alignment is
/// applied by a React wrapper. Only the *data* half is portable, and that half
/// is one field: `format`, the same alignment string an element carries. It
/// lives here rather than in `lexical_core` for the same reason it lives
/// outside `lexical` upstream — nothing in the core model needs it.
///
/// ```json
/// { "type": "youtube", "version": 1, "format": "", "videoID": "dQw4w9WgXcQ" }
/// ```
abstract class DecoratorBlockNode extends DecoratorNode {
  /// Creates a block decorator with [format] alignment.
  DecoratorBlockNode({ElementFormat format = ElementFormat.none})
    : _format = format;

  ElementFormat _format;

  /// A block, never part of a line of text.
  @override
  bool get isInline => false;

  /// How the block is aligned, or [ElementFormat.none].
  ElementFormat get format => getLatest<DecoratorBlockNode>()._format;

  /// Aligns the block.
  DecoratorBlockNode setFormat(ElementFormat value) =>
      getWritable<DecoratorBlockNode>().._format = value;

  @override
  void afterCloneFrom(covariant DecoratorBlockNode prev) {
    super.afterCloneFrom(prev);
    _format = prev._format;
  }

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'format': _format.wire,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _format = ElementFormat.fromWire(json['format']);
  }
}
