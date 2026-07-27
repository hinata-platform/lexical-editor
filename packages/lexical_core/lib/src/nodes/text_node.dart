/// Text nodes and their format bitmasks.
library;

import 'package:meta/meta.dart';

import '../updates.dart';
import 'lexical_node.dart';

/// A single text format, as a bit in a text node's format mask.
///
/// Values are fixed by the wire format and verified against lexical 0.48.
/// Do not allocate new flags above bit 30: bitwise operations compile to
/// 32-bit semantics under dart2js, and the format field is plain JSON.
enum TextFormat {
  /// Bold.
  bold(1),

  /// Italic.
  italic(2),

  /// Strikethrough.
  strikethrough(4),

  /// Underline.
  underline(8),

  /// Inline code.
  code(16),

  /// Subscript.
  subscript(32),

  /// Superscript.
  superscript(64),

  /// Highlight / mark.
  highlight(128),

  /// Render lowercased. Presentational; the model text is unchanged.
  lowercase(256),

  /// Render uppercased. Presentational; the model text is unchanged.
  uppercase(512),

  /// Render capitalized. Presentational; the model text is unchanged.
  capitalize(1024);

  const TextFormat(this.bit);

  /// The bit this format occupies in a format bitmask.
  final int bit;

  /// Every format bit OR-ed together.
  static const int all = 2047;

  /// The three mutually exclusive case transforms.
  static const int caseMask = 256 | 512 | 1024;

  /// Parses a wire-format format name, or `null` when unrecognized.
  static TextFormat? byName(String name) {
    for (final format in TextFormat.values) {
      if (format.name == name) return format;
    }
    return null;
  }
}

/// A flag in a text node's detail mask.
enum TextDetail {
  /// The node takes no part in direction resolution.
  directionless(1),

  /// The node must not merge with adjacent text runs.
  ///
  /// This is why a tab survives as its own node rather than dissolving into
  /// the text around it.
  unmergeable(2);

  const TextDetail(this.bit);

  /// The bit this detail occupies in a detail bitmask.
  final int bit;
}

/// How a text node behaves under editing.
enum TextMode {
  /// Ordinary editable text.
  normal('normal'),

  /// Atomic: edited as a unit, deleted whole.
  token('token'),

  /// Deleted by segment (word) and becomes [normal] once edited.
  segmented('segmented');

  const TextMode(this.wire);

  /// The wire-format string for this mode.
  final String wire;

  /// Parses a wire-format mode, defaulting to [normal].
  static TextMode fromWire(Object? value) {
    for (final mode in TextMode.values) {
      if (mode.wire == value) return mode;
    }
    return TextMode.normal;
  }
}

/// A run of text with uniform formatting.
///
/// A text node **never contains a newline** — line breaks are `LineBreakNode`
/// — and a text node is never a direct child of the root. Both invariants are
/// rejected at import and asserted by the integrity walk.
///
/// Text offsets are UTF-16 code-unit indices, matching JavaScript.
/// They are never grapheme indices; mixing the two produces carets that land
/// one character off for some inputs and not others.
class TextNode extends LexicalNode {
  /// Creates a text node holding [textInternal] in [modeInternal].
  ///
  /// The mode is a constructor argument rather than something a subclass sets
  /// afterwards, because a subclass constructor must not call accessors:
  /// during a clone the node is not yet in the node map, so `getWritable()`
  /// would resolve to the node being cloned and quietly write to the wrong
  /// object. Constructor arguments and direct field initialisers are the only
  /// safe way to establish state.
  TextNode([this.textInternal = '', this.modeInternal = TextMode.normal]);

  @override
  String get type => 'text';

  @override
  bool get isInline => true;

  /// Raw text content. Framework-internal; read through [getTextContent].
  @internal
  String textInternal;

  /// Format bitmask. Framework-internal; read through [getFormat].
  @internal
  int formatInternal = 0;

  /// Raw CSS style string, preserved verbatim for wire compatibility.
  @internal
  String styleInternal = '';

  /// Editing mode. Framework-internal; read through [getMode].
  @internal
  TextMode modeInternal;

  /// Detail bitmask. Framework-internal; read through [getDetail].
  @internal
  int detailInternal = 0;

  /// Creates a copy carrying this node's constructor state.
  ///
  /// Subclasses in other packages only need to carry *their own* fields:
  /// text, format, style, mode and detail are restored by
  /// [afterCloneFrom]. Read the text with [getTextContent] — the raw field
  /// is framework-internal.
  @override
  TextNode clone() => TextNode(textInternal);

  @override
  @mustCallSuper
  void afterCloneFrom(covariant TextNode prev) {
    super.afterCloneFrom(prev);
    textInternal = prev.textInternal;
    formatInternal = prev.formatInternal;
    styleInternal = prev.styleInternal;
    modeInternal = prev.modeInternal;
    detailInternal = prev.detailInternal;
  }

  @override
  String getTextContent() => getLatest<TextNode>().textInternal;

  @override
  int getTextContentSize() => getLatest<TextNode>().textInternal.length;

  /// The format bitmask.
  int getFormat() => getLatest<TextNode>().formatInternal;

  /// The detail bitmask.
  int getDetail() => getLatest<TextNode>().detailInternal;

  /// The raw CSS style string.
  String getStyle() => getLatest<TextNode>().styleInternal;

  /// The editing mode.
  TextMode getMode() => getLatest<TextNode>().modeInternal;

  /// Whether [format] is set on this node.
  bool hasFormat(TextFormat format) => (getFormat() & format.bit) == format.bit;

  /// Whether [detail] is set on this node.
  bool hasDetail(TextDetail detail) => (getDetail() & detail.bit) == detail.bit;

  /// Whether this node is atomic.
  bool get isToken => getMode() == TextMode.token;

  /// Whether this node deletes by segment.
  bool get isSegmented => getMode() == TextMode.segmented;

  /// Whether this node refuses to merge with its neighbours.
  bool get isUnmergeable => hasDetail(TextDetail.unmergeable);

  /// Whether this is a plain text node with no special behaviour.
  ///
  /// Subclasses (hashtags, code highlights) are not simple text even when
  /// their fields are identical, because merging them would change their
  /// type.
  bool get isSimpleText => type == 'text' && modeInternal == TextMode.normal;

  /// Whether formatting and styling may change this node.
  ///
  /// A node type that renders something other than its own text — a stamped
  /// date, a chip whose colour carries meaning — overrides this to opt out of
  /// bold and of the colour pickers, rather than being restyled into
  /// something that no longer reads as what it is.
  ///
  /// This is about *whether* to format, not about splitting: an atomic node
  /// says that with [TextMode.token], and nothing splits one of those.
  bool get canHaveFormat => true;

  /// Replaces the text content.
  TextNode setTextContent(String text) =>
      getWritable<TextNode>()..textInternal = text;

  /// Replaces the format bitmask.
  TextNode setFormat(int format) =>
      getWritable<TextNode>()..formatInternal = format & TextFormat.all;

  /// Replaces the detail bitmask.
  TextNode setDetail(int detail) =>
      getWritable<TextNode>()..detailInternal = detail;

  /// Replaces the raw CSS style string.
  TextNode setStyle(String style) =>
      getWritable<TextNode>()..styleInternal = style;

  /// Replaces the editing mode.
  TextNode setMode(TextMode mode) =>
      getWritable<TextNode>()..modeInternal = mode;

  /// Toggles a single format bit.
  ///
  /// The three case transforms are mutually exclusive: enabling one clears
  /// the other two, matching upstream.
  TextNode toggleFormat(TextFormat format) {
    final current = getFormat();
    final enabled = (current & format.bit) == 0;
    var next = enabled ? current | format.bit : current & ~format.bit;
    if (enabled && (format.bit & TextFormat.caseMask) != 0) {
      next &= ~(TextFormat.caseMask & ~format.bit);
    }
    return setFormat(next);
  }

  /// Whether this node can merge with [other] into a single run.
  ///
  /// Merging adjacent identical runs is required for wire compatibility:
  /// upstream merges them, so a port that does not would emit a different
  /// node count for the same document.
  bool canMergeWith(TextNode other) =>
      isSimpleText &&
      other.isSimpleText &&
      getFormat() == other.getFormat() &&
      getStyle() == other.getStyle() &&
      getMode() == other.getMode() &&
      !isUnmergeable &&
      !other.isUnmergeable &&
      type == other.type;

  /// Replaces [delCount] code units at [offset] with [newText].
  ///
  /// The single primitive every text edit funnels through. Offsets are
  /// clamped rather than asserted: they arrive from platform IMEs, which
  /// occasionally report a range against a value they have not finished
  /// applying, and throwing there would freeze the editor over a transient
  /// disagreement that the next delta corrects.
  TextNode spliceText(int offset, int delCount, String newText) {
    final writable = getWritable<TextNode>();
    final text = writable.textInternal;
    final start = offset.clamp(0, text.length);
    final requested = start + (delCount < 0 ? 0 : delCount);
    final end = requested.clamp(start, text.length);
    writable.textInternal = text.replaceRange(start, end, newText);
    return writable;
  }

  /// Splits this node at the given code-unit [offsets].
  ///
  /// Returns the resulting nodes in document order, this node first. Offsets
  /// outside the text or at its edges are ignored.
  List<TextNode> splitText(List<int> offsets) {
    errorOnReadOnly();
    final self = getLatest<TextNode>();
    final text = self.textInternal;
    final splitPoints =
        (offsets
            .where((offset) => offset > 0 && offset < text.length)
            .toSet()
            .toList()
          ..sort());
    if (splitPoints.isEmpty) return [getWritable<TextNode>()];

    final parts = <String>[];
    var start = 0;
    for (final point in splitPoints) {
      parts.add(text.substring(start, point));
      start = point;
    }
    parts.add(text.substring(start));

    final writableSelf = getWritable<TextNode>()..textInternal = parts.first;
    final result = <TextNode>[writableSelf];
    var previous = writableSelf;
    for (final part in parts.skip(1)) {
      final node = clone()
        ..textInternal = part
        ..formatInternal = writableSelf.formatInternal
        ..styleInternal = writableSelf.styleInternal
        ..modeInternal = writableSelf.modeInternal
        ..detailInternal = writableSelf.detailInternal;
      previous.insertAfter(node);
      result.add(node);
      previous = node;
    }
    return result;
  }

  @override
  Map<String, Object?> exportJson() => <String, Object?>{
    'detail': detailInternal,
    'format': formatInternal,
    'mode': modeInternal.wire,
    'style': styleInternal,
    'text': textInternal,
    ...super.exportJson(),
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final text = json['text'];
    textInternal = text is String ? text : '';
    final format = json['format'];
    formatInternal = format is int ? format & TextFormat.all : 0;
    final detail = json['detail'];
    detailInternal = detail is int ? detail : 0;
    modeInternal = TextMode.fromWire(json['mode']);
    final style = json['style'];
    styleInternal = style is String ? style : '';
  }
}

/// Creates a text node, applying any registered node replacement.
TextNode $createTextNode([String text = '']) =>
    $applyNodeReplacement(TextNode(text));
