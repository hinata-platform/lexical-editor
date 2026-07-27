/// The default block element.
library;

import '../selection_ops.dart';
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
  bool collapseAtStart() {
    // A blank first line is the one thing backspace can do something about
    // when there is nothing before it: remove the line and move on to the
    // next. A paragraph with words in it stays — there is nothing to collapse
    // a paragraph *into*.
    final first = getFirstChild();
    final blank =
        first == null || (first is TextNode && first.getTextContent().isEmpty);
    if (!blank) return false;
    // The caret moves into the neighbour before the line goes, so it lands on
    // real content rather than on an index that shifts when this one is
    // removed.
    final next = getNextSibling();
    if (next is ElementNode) {
      next.selectStart();
      remove();
      return true;
    }
    final previous = getPreviousSibling();
    if (previous is ElementNode) {
      previous.selectEnd();
      remove();
      return true;
    }
    return false;
  }

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
