/// The column container and its items.
library;

import 'package:lexical_core/lexical_core.dart';

/// A row of columns, laid out by a CSS grid template.
///
/// The Lexical playground's `layout-container`, with the same wire shape:
///
/// ```json
/// {"type": "layout-container", "templateColumns": "1fr 1fr", "children": […]}
/// ```
///
/// Its children are [LayoutItemNode]s, one per column. It is a shadow root —
/// traversal upwards stops here, as at a table — and it cannot be empty: the
/// last item going takes the container with it.
class LayoutContainerNode extends ElementNode {
  /// Creates a container with [templateColumns], a CSS grid template.
  LayoutContainerNode([this._templateColumns = '']);

  String _templateColumns;

  @override
  String get type => 'layout-container';

  @override
  bool get isShadowRoot => true;

  @override
  bool get canBeEmpty => false;

  @override
  LayoutContainerNode clone() => LayoutContainerNode(_templateColumns);

  @override
  void afterCloneFrom(covariant LayoutContainerNode prev) {
    super.afterCloneFrom(prev);
    _templateColumns = prev._templateColumns;
  }

  /// The CSS grid template, verbatim — `"1fr 1fr"`, `"200px 1fr"`.
  ///
  /// Read it with `parseTemplateColumns` to lay it out.
  String get templateColumns =>
      getLatest<LayoutContainerNode>()._templateColumns;

  /// Replaces the grid template.
  LayoutContainerNode setTemplateColumns(String value) =>
      getWritable<LayoutContainerNode>().._templateColumns = value;

  /// The items, in column order.
  Iterable<LayoutItemNode> get items => children.whereType<LayoutItemNode>();

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'templateColumns': _templateColumns,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final template = json['templateColumns'];
    _templateColumns = template is String ? template : '';
  }
}

/// One column of a [LayoutContainerNode].
///
/// The playground's `layout-item`. A shadow root, like a table cell: a
/// paragraph in it is a top-level block *of the column*, so Enter splits it
/// inside the column and backspace at its start stops at the column's edge.
class LayoutItemNode extends ElementNode {
  /// Creates an empty item.
  LayoutItemNode();

  @override
  String get type => 'layout-item';

  @override
  bool get isShadowRoot => true;

  @override
  LayoutItemNode clone() => LayoutItemNode();

  /// Backspace at the start of the first column removes the whole layout,
  /// but only when every column is empty — upstream's rule. Anywhere else
  /// the keystroke stops at the column's edge, so a column never swallows
  /// its neighbour.
  @override
  bool collapseAtStart() {
    final parent = getParent();
    if (parent is! LayoutContainerNode) return false;
    if (!isSameNode(parent.getFirstChild())) return false;
    if (!parent.children.every($isEmptyLayoutItemNode)) return false;

    // The caret moves before the layout goes, so it lands on a block that
    // still exists. Upstream relies on its reconciler to rescue a selection
    // left inside a removed subtree; this port places it explicitly.
    final previous = parent.getPreviousSibling();
    final next = parent.getNextSibling();
    if (previous is ElementNode) {
      previous.selectEnd();
      parent.remove();
    } else if (next is ElementNode) {
      next.selectStart();
      parent.remove();
    } else {
      final paragraph = $createParagraphNode();
      parent.replace(paragraph);
      paragraph.selectStart();
    }
    return true;
  }
}

/// Creates a container with [templateColumns].
LayoutContainerNode $createLayoutContainerNode([String templateColumns = '']) =>
    $applyNodeReplacement(LayoutContainerNode(templateColumns));

/// Creates an empty layout item.
LayoutItemNode $createLayoutItemNode() =>
    $applyNodeReplacement(LayoutItemNode());

/// Whether [node] is a [LayoutContainerNode].
bool $isLayoutContainerNode(LexicalNode? node) => node is LayoutContainerNode;

/// Whether [node] is a [LayoutItemNode].
bool $isLayoutItemNode(LexicalNode? node) => node is LayoutItemNode;

/// Whether [node] is a layout item holding one empty paragraph — what a
/// freshly inserted column contains.
bool $isEmptyLayoutItemNode(LexicalNode? node) {
  if (node is! LayoutItemNode || node.childrenSize != 1) return false;
  final first = node.getFirstChild();
  return first is ParagraphNode && first.isEmpty;
}
