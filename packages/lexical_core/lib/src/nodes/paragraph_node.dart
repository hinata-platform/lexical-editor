/// The default block element.
library;

import '../updates.dart';
import 'element_node.dart';
import 'text_node.dart';

/// An ordinary block of text.
///
/// The paragraph is where the wire format's one genuinely surprising rule
/// lives. `textFormat` and `textStyle` record the format a newly typed
/// character would inherit at the caret, so they are **copied on import but
/// derived on export**: whatever the input JSON claimed is overwritten by the
/// first text child's format and style.
///
/// The consequence for testing is that upstream itself fails a byte-identity
/// round-trip on hand-written JSON, so the compatibility contract is a *fixed
/// point on canonical fixtures* rather than byte equality against raw input.
/// The consequence for implementation is that the derivation must be redone
/// here rather than copied through — a document edited in this port and
/// reopened on the web would otherwise show the wrong active format in its
/// toolbar.
class ParagraphNode extends ElementNode {
  /// Creates an empty paragraph.
  ParagraphNode();

  @override
  String get type => 'paragraph';

  @override
  ParagraphNode clone() => ParagraphNode();

  @override
  Map<String, Object?> exportJson() {
    final json = super.exportJson();
    // The element base only writes these when there is no text child to
    // recompute them from. A paragraph always emits both.
    if (!json.containsKey('textFormat') || !json.containsKey('textStyle')) {
      TextNode? firstText;
      for (final child in children) {
        if (child is TextNode) {
          firstText = child;
          break;
        }
      }
      if (firstText != null) {
        json['textFormat'] = firstText.getFormat();
        json['textStyle'] = firstText.getStyle();
      } else {
        json['textFormat'] = textFormat;
        json['textStyle'] = textStyle;
      }
    }
    return json;
  }
}

/// Creates a paragraph, applying any registered node replacement.
ParagraphNode $createParagraphNode() => $applyNodeReplacement(ParagraphNode());
