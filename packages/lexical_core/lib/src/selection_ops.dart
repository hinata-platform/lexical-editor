/// Editing operations on a range selection.
///
/// This is the layer between a command — "insert text", "delete backwards" —
/// and the tree mutators. It lives in the core rather than in a Flutter
/// package because none of it is platform-specific: the same operations serve
/// an IME delta, a hardware key, a paste, and a programmatic edit, and keeping
/// one implementation is what makes those four paths agree.
///
/// Two rules run through everything here:
///
/// * **A replacement is one operation.** Decomposing it into delete-then-
///   insert produces two undo entries, runs transforms over an intermediate
///   state that never existed, and breaks IME candidate replacement on CJK.
/// * **Offsets are UTF-16 code units, movement is by grapheme.** The model
///   speaks the same units as JavaScript so the wire format stays honest,
///   while a backspace removes one *perceived* character — an emoji with a
///   skin-tone modifier is one press, not four.
library;

import 'package:characters/characters.dart';

import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/line_break_node.dart';
import 'nodes/paragraph_node.dart';
import 'nodes/root_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';
import 'updates.dart';

// ---------------------------------------------------------------------------
// Selection creation and node helpers
// ---------------------------------------------------------------------------

/// Creates a collapsed selection at the start of the document.
RangeSelection $createRangeSelection() {
  final root = $getRoot();
  final point = _firstPointIn(root) ?? Point(root.key, 0, PointType.element);
  return RangeSelection(
    Point(point.key, point.offset, point.type),
    Point(point.key, point.offset, point.type),
  );
}

/// Selects the whole document.
///
/// The ends are resolved to the first and last leaf rather than to the root's
/// child indices, so that a subsequent edit has real text nodes to work with
/// instead of having to materialize them.
void $selectAll() {
  final root = $getRoot();
  final first = _firstPointIn(root) ?? Point(root.key, 0, PointType.element);
  final last = _lastPointIn(root) ?? Point(root.key, 0, PointType.element);
  $setSelection(
    RangeSelection(
      Point(first.key, first.offset, first.type),
      Point(last.key, last.offset, last.type),
    ),
  );
}

/// What a caret movement steps over.
enum SelectionUnit {
  /// One grapheme cluster.
  character,

  /// One word, by the boundary rules in this library.
  word,

  /// To the block's edge.
  ///
  /// **Block**, not visual line: where a line wraps is a property of the
  /// laid-out text, which the model cannot know. `lexical_flutter` overrides
  /// line movement with true visual semantics for blocks that are on screen.
  line,
}

/// The nearest block-level ancestor of [node], or the root.
///
/// "Block" means the innermost element that is not inline: a list *item*
/// rather than the list, a table *cell* rather than the table. That is the
/// granularity a caret, an input method, and a line of text all work at.
ElementNode $getNearestBlock(LexicalNode node) => _blockOf(node);

/// The block before [block] in document order, or `null`.
ElementNode? $getPreviousBlock(ElementNode block) => _previousBlockOf(block);

/// The block after [block] in document order, or `null`.
ElementNode? $getNextBlock(ElementNode block) => _nextBlockOf(block);

/// Selection helpers shared by every node type.
extension LexicalNodeSelection on LexicalNode {
  /// Places a collapsed selection immediately before this node.
  void selectPrevious() {
    final previous = getPreviousSibling();
    if (previous is TextNode) {
      _collapseAt(
        Point(previous.key, previous.getTextContentSize(), PointType.text),
      );
      return;
    }
    final parent = getParent();
    if (parent == null) return;
    _collapseAt(Point(parent.key, indexWithinParent, PointType.element));
  }

  /// Places a collapsed selection immediately after this node.
  void selectNext() {
    final next = getNextSibling();
    if (next is TextNode) {
      _collapseAt(Point(next.key, 0, PointType.text));
      return;
    }
    final parent = getParent();
    if (parent == null) return;
    _collapseAt(Point(parent.key, indexWithinParent + 1, PointType.element));
  }
}

/// Selection helpers for text nodes.
extension TextNodeSelection on TextNode {
  /// Selects a range within this node, in UTF-16 code units.
  ///
  /// Both offsets default to the end of the text, which is what makes
  /// `node.select()` mean "put the caret after this".
  RangeSelection select([int? anchorOffset, int? focusOffset]) {
    final size = getTextContentSize();
    final anchor = (anchorOffset ?? size).clamp(0, size);
    final focus = (focusOffset ?? anchorOffset ?? size).clamp(0, size);
    final selection = RangeSelection(
      Point(key, anchor, PointType.text),
      Point(key, focus, PointType.text),
    );
    $setSelection(selection);
    return selection;
  }

  /// Places a collapsed selection at the start of this node.
  RangeSelection selectStart() => select(0, 0);

  /// Places a collapsed selection at the end of this node.
  RangeSelection selectEnd() {
    final size = getTextContentSize();
    return select(size, size);
  }
}

/// Selection helpers for element nodes.
extension ElementNodeSelection on ElementNode {
  /// Selects a range of this element's children, by index.
  RangeSelection select([int? anchorOffset, int? focusOffset]) {
    final size = childrenSize;
    final anchor = (anchorOffset ?? size).clamp(0, size);
    final focus = (focusOffset ?? anchorOffset ?? size).clamp(0, size);
    final selection = RangeSelection(
      Point(key, anchor, PointType.element),
      Point(key, focus, PointType.element),
    );
    $setSelection(selection);
    return selection;
  }

  /// Places a collapsed selection at the start of this element's content.
  RangeSelection selectStart() {
    final point = _firstPointIn(this) ?? Point(key, 0, PointType.element);
    final selection = RangeSelection(
      Point(point.key, point.offset, point.type),
      Point(point.key, point.offset, point.type),
    );
    $setSelection(selection);
    return selection;
  }

  /// Places a collapsed selection at the end of this element's content.
  RangeSelection selectEnd() {
    final point =
        _lastPointIn(this) ?? Point(key, childrenSize, PointType.element);
    final selection = RangeSelection(
      Point(point.key, point.offset, point.type),
      Point(point.key, point.offset, point.type),
    );
    $setSelection(selection);
    return selection;
  }
}

// ---------------------------------------------------------------------------
// Range selection editing
// ---------------------------------------------------------------------------

/// The editing operations of a range selection.
extension RangeSelectionEditing on RangeSelection {
  /// Whether the focus precedes the anchor — a backwards drag.
  bool get isBackward => _comparePoints(focus, anchor) < 0;

  /// The selection's points in document order.
  (Point, Point) get orderedPoints =>
      isBackward ? (focus, anchor) : (anchor, focus);

  /// The plain text the selection covers.
  String getTextContent() {
    if (isCollapsed) return '';
    final (start, end) = orderedPoints;
    final startNode = start.getNode();
    final endNode = end.getNode();
    if (startNode == null || endNode == null) return '';

    if (startNode is TextNode && start.key == end.key) {
      final text = startNode.getTextContent();
      final from = start.offset.clamp(0, text.length);
      final to = end.offset.clamp(from, text.length);
      return text.substring(from, to);
    }

    final buffer = StringBuffer();
    var previousBlock = _blockOf(startNode).key;
    for (final node in _leavesBetween(startNode, endNode)) {
      final block = _blockOf(node).key;
      if (block != previousBlock) {
        buffer.write('\n');
        previousBlock = block;
      }
      if (node is TextNode) {
        final text = node.getTextContent();
        var from = 0;
        var to = text.length;
        if (node.key == start.key && start.type == PointType.text) {
          from = start.offset.clamp(0, text.length);
        }
        if (node.key == end.key && end.type == PointType.text) {
          to = end.offset.clamp(0, text.length);
        }
        if (to > from) buffer.write(text.substring(from, to));
      } else {
        buffer.write(node.getTextContent());
      }
    }
    return buffer.toString();
  }

  /// Removes the selected content.
  ///
  /// Implemented as an empty insertion so that deleting and replacing take
  /// exactly the same code path; a range delete that behaves differently from
  /// a range replace is a bug waiting to be found by a user, not a test.
  void removeText() => insertText('');

  /// Replaces the selected range with [text], as a single operation.
  void insertText(String text) {
    errorOnReadOnly();
    final (start, end) = orderedPoints;
    final caret = _deleteBetween(
      Point(start.key, start.offset, start.type),
      Point(end.key, end.offset, end.type),
    );
    if (text.isEmpty) {
      _collapseAt(caret);
      return;
    }
    _collapseAt(_insertTextAt(caret, text, format: format, style: style));
  }

  /// Inserts [nodes] at the selection, replacing whatever it covers.
  ///
  /// Inline nodes are spliced into the current text run; block nodes split it.
  /// This is the operation paste and mention insertion are built on.
  void insertNodes(List<LexicalNode> nodes) {
    errorOnReadOnly();
    if (nodes.isEmpty) return;
    if (!isCollapsed) removeText();
    if (nodes.every((node) => node.isInline)) {
      _insertInline(nodes);
      return;
    }
    _insertBlocks(nodes);
  }

  /// Inserts a hard line break at the selection.
  void insertLineBreak() => insertNodes([$createLineBreakNode()]);

  /// Splits the current block in two at the caret.
  ///
  /// The kind of block created is decided by [ElementNode.insertNewAfter], so
  /// Enter inside a list item continues the list while Enter in a heading
  /// drops to a paragraph.
  void insertParagraph() {
    errorOnReadOnly();
    if (!isCollapsed) removeText();

    final anchorNode = anchor.getNode();
    if (anchorNode == null) return;
    final block = _blockOf(anchorNode);
    if (block is RootNode) {
      // No block to split: the caret sits directly on the root, which happens
      // only in an empty document.
      final paragraph = $createParagraphNode();
      block.splice(anchor.offset.clamp(0, block.childrenSize), 0, [paragraph]);
      _collapseAt(Point(paragraph.key, 0, PointType.element));
      return;
    }

    final tail = _splitBlockContentAt(block, anchor);
    final newBlock = block.insertNewAfter(isAtEnd: tail.isEmpty);
    if (tail.isNotEmpty) newBlock.appendAll(tail);
    _collapseAt(
      _firstPointIn(newBlock) ?? Point(newBlock.key, 0, PointType.element),
    );
  }

  /// Deletes one grapheme, or the selected range when there is one.
  ///
  /// [backwards] is backspace; forwards is the delete key. At a block
  /// boundary this merges the two blocks, which is what makes backspace at
  /// the start of a paragraph behave the way every editor does.
  void deleteCharacter({required bool backwards}) {
    errorOnReadOnly();
    if (!isCollapsed) {
      removeText();
      return;
    }
    final moved = _movePoint(
      focus,
      backwards: backwards,
      unit: _Unit.character,
    );
    if (moved == null) return;
    _deleteTowards(moved, backwards: backwards);
  }

  /// Deletes to the nearest word boundary.
  void deleteWord({required bool backwards}) {
    errorOnReadOnly();
    if (!isCollapsed) {
      removeText();
      return;
    }
    final moved = _movePoint(focus, backwards: backwards, unit: _Unit.word);
    if (moved == null) return;
    _deleteTowards(moved, backwards: backwards);
  }

  /// Deletes to the start or end of the current block.
  ///
  /// **Block**, not visual line: where a line wraps is a property of the
  /// laid-out text, which the model cannot know. `lexical_flutter` overrides
  /// this command at a higher priority with true line semantics when the
  /// block is on screen; this is the fallback and the headless behaviour.
  void deleteLine({required bool backwards}) {
    errorOnReadOnly();
    if (!isCollapsed) {
      removeText();
      return;
    }
    final node = focus.getNode();
    if (node == null) return;
    final block = _blockOf(node);
    final target = backwards ? _firstPointIn(block) : _lastPointIn(block);
    if (target == null) return;
    if (target.key == focus.key && target.offset == focus.offset) return;
    _deleteTowards(target, backwards: backwards);
  }

  /// Toggles [textFormat] over the selection.
  ///
  /// A collapsed selection records the format as *pending*, so it applies to
  /// the next character typed rather than to nothing at all — pressing ⌘B and
  /// then typing is the common case, and an implementation that only formats
  /// existing text silently does nothing there.
  void formatText(TextFormat textFormat) {
    errorOnReadOnly();
    if (isCollapsed) {
      format = _toggledFormat(format, textFormat);
      dirty = true;
      return;
    }
    final nodes = _splitAtBoundaries();
    if (nodes.isEmpty) return;
    final allSet = nodes.every((node) => node.hasFormat(textFormat));
    for (final node in nodes) {
      if (node.isToken && node.type != 'text') continue;
      final current = node.getFormat();
      node.setFormat(
        allSet
            ? current & ~textFormat.bit
            : _toggledFormat(current & ~textFormat.bit, textFormat),
      );
    }
    format = nodes.first.getFormat();
    dirty = true;
  }

  /// Applies [style] to every text node in the selection, replacing whatever
  /// each had.
  ///
  /// The value is stored verbatim: it is CSS, the model does not interpret it,
  /// and rewriting it here would break round-tripping with Lexical web.
  void setTextStyle(String cssStyle) {
    errorOnReadOnly();
    if (isCollapsed) {
      style = cssStyle;
      dirty = true;
      return;
    }
    for (final node in _splitAtBoundaries()) {
      node.setStyle(cssStyle);
    }
    style = cssStyle;
    dirty = true;
  }

  /// Moves the caret one [unit], returning whether it moved.
  ///
  /// [extend] keeps the anchor where it is, which is what Shift-arrow does.
  /// Without it, an arrow key over a *range* collapses to that range's edge
  /// rather than stepping one further — the behaviour every text field has
  /// and the one people notice immediately when it is missing.
  bool moveCaret({
    required bool backwards,
    SelectionUnit unit = SelectionUnit.character,
    bool extend = false,
  }) {
    errorOnReadOnly();
    Point? target;

    if (unit == SelectionUnit.line) {
      final node = focus.getNode();
      if (node == null) return false;
      final block = _blockOf(node);
      target = backwards ? _firstPointIn(block) : _lastPointIn(block);
      if (target != null &&
          target.key == focus.key &&
          target.offset == focus.offset) {
        target = _crossBoundary(node, backwards: backwards);
      }
    } else if (!extend && !isCollapsed) {
      final (start, end) = orderedPoints;
      final edge = backwards ? start : end;
      target = Point(edge.key, edge.offset, edge.type);
    } else {
      target = _movePoint(
        focus,
        backwards: backwards,
        unit: unit == SelectionUnit.word ? _Unit.word : _Unit.character,
      );
    }

    if (target == null) return false;
    final resolved = _resolvePoint(target);
    if (resolved.key == focus.key &&
        resolved.offset == focus.offset &&
        (extend || isCollapsed)) {
      return false;
    }
    focus.set(resolved.key, resolved.offset, resolved.type);
    if (!extend) anchor.set(resolved.key, resolved.offset, resolved.type);
    dirty = true;
    return true;
  }

  /// Moves the focus to [offset] inside [key], keeping the anchor when
  /// [extend] is set.
  void moveTo(NodeKey key, int offset, PointType type, {bool extend = false}) {
    errorOnReadOnly();
    final resolved = _resolvePoint(Point(key, offset, type));
    focus.set(resolved.key, resolved.offset, resolved.type);
    if (!extend) anchor.set(resolved.key, resolved.offset, resolved.type);
    dirty = true;
  }

  /// Selects the word around the focus.
  void selectWord() {
    errorOnReadOnly();
    final node = focus.getNode();
    if (node is! TextNode || focus.type != PointType.text) return;
    final text = node.getTextContent();
    final start = _previousWord(text, _nextWord(text, focus.offset));
    final end = _nextWord(text, start);
    anchor.set(node.key, start.clamp(0, text.length), PointType.text);
    focus.set(node.key, end.clamp(0, text.length), PointType.text);
    dirty = true;
  }

  /// The blocks the selection touches, in document order.
  List<ElementNode> getBlocks() {
    final (start, end) = orderedPoints;
    final startNode = start.getNode();
    final endNode = end.getNode();
    if (startNode == null || endNode == null) return const [];
    final blocks = <NodeKey, ElementNode>{};
    final startBlock = _blockOf(startNode);
    blocks[startBlock.key] = startBlock;
    if (start.key != end.key || start.offset != end.offset) {
      for (final node in _leavesBetween(startNode, endNode)) {
        final block = _blockOf(node);
        blocks[block.key] = block;
      }
    }
    final endBlock = _blockOf(endNode);
    blocks[endBlock.key] = endBlock;
    return blocks.values.where((block) => block is! RootNode).toList();
  }
}

// ---------------------------------------------------------------------------
// Point ordering
// ---------------------------------------------------------------------------

/// Orders two points by their position in the document.
///
/// Comparison runs over the path of child indices from the root rather than
/// over `isBefore`, because one point may address an *ancestor* of the other —
/// a caret on a paragraph and a caret in that paragraph's text — and ancestry
/// is not an ordering.
int _comparePoints(Point a, Point b) {
  if (a.key == b.key) return a.offset.compareTo(b.offset);
  final pathA = _pathOf(a);
  final pathB = _pathOf(b);
  final shared = pathA.length < pathB.length ? pathA.length : pathB.length;
  for (var i = 0; i < shared; i++) {
    if (pathA[i] != pathB[i]) return pathA[i].compareTo(pathB[i]);
  }
  return pathA.length.compareTo(pathB.length);
}

List<int> _pathOf(Point point) {
  final path = <int>[];
  var node = point.getNode();
  while (node != null && node.key != NodeKey.root) {
    path.insert(0, node.indexWithinParent);
    node = node.getParent();
  }
  path.add(point.offset);
  return path;
}

// ---------------------------------------------------------------------------
// Positions
// ---------------------------------------------------------------------------

/// The nearest block-level ancestor of [node], or the root.
ElementNode _blockOf(LexicalNode node) {
  LexicalNode? current = node;
  while (current != null) {
    if (current is RootNode) return current;
    if (current is ElementNode && !current.isInline) return current;
    current = current.getParent();
  }
  return $getRoot();
}

/// The nearest shadow root containing [node], or the document root.
ElementNode _shadowRootOf(LexicalNode node) {
  LexicalNode? current = node.getParent();
  while (current != null) {
    if (current is ElementNode && current.isShadowRoot) return current;
    current = current.getParent();
  }
  return $getRoot();
}

Point? _firstPointIn(ElementNode element) {
  final child = element.getFirstChild();
  if (child == null) {
    return element is RootNode
        ? null
        : Point(element.key, 0, PointType.element);
  }
  if (child is TextNode) return Point(child.key, 0, PointType.text);
  if (child is ElementNode) return _firstPointIn(child);
  return Point(element.key, 0, PointType.element);
}

Point? _lastPointIn(ElementNode element) {
  final child = element.getLastChild();
  if (child == null) {
    return element is RootNode
        ? null
        : Point(element.key, 0, PointType.element);
  }
  if (child is TextNode) {
    return Point(child.key, child.getTextContentSize(), PointType.text);
  }
  if (child is ElementNode) return _lastPointIn(child);
  return Point(element.key, element.childrenSize, PointType.element);
}

/// Every leaf from [start] to [end] inclusive, in document order.
List<LexicalNode> _leavesBetween(LexicalNode start, LexicalNode end) {
  if (start.key == end.key) return [start];
  return start
      .getNodesBetween(end)
      .where((node) => node is! ElementNode || node.isEmpty)
      .toList();
}

void _collapseAt(Point point) {
  final selection = $getActiveEditorState().selection;
  final resolved = _resolvePoint(point);
  if (selection is RangeSelection) {
    selection.anchor.set(resolved.key, resolved.offset, resolved.type);
    selection.focus.set(resolved.key, resolved.offset, resolved.type);
    selection.dirty = true;
    return;
  }
  $setSelection(
    RangeSelection(
      Point(resolved.key, resolved.offset, resolved.type),
      Point(resolved.key, resolved.offset, resolved.type),
    ),
  );
}

/// Repairs a point whose node was removed while the operation ran.
///
/// Tree mutation relocates live selection points as it goes; the points this
/// file passes around are detached copies, so one of them can name a node that
/// no longer exists. Committing that selection fails with an error far from
/// the removal that caused it, which is exactly the failure this avoids.
Point _resolvePoint(Point point) {
  final node = $getNodeByKey(point.key);
  if (node != null && node.isAttached) {
    if (point.type == PointType.text && node is TextNode) {
      return Point(
        point.key,
        point.offset.clamp(0, node.getTextContentSize()),
        PointType.text,
      );
    }
    if (point.type == PointType.element && node is ElementNode) {
      return Point(
        point.key,
        point.offset.clamp(0, node.childrenSize),
        PointType.element,
      );
    }
    return point;
  }
  final root = $getRoot();
  return _lastPointIn(root) ?? Point(root.key, 0, PointType.element);
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

/// Deletes everything between [rawStart] and [rawEnd] and returns the caret.
///
/// Within one block and across blocks are genuinely different operations and
/// are kept apart rather than unified. Within a block, both ends survive and
/// the middle goes. Across blocks, each end's block is truncated, the blocks
/// between are removed whole, and the tail of the last is appended to the
/// first — that last step is the block merge every editor performs on
/// backspace at a paragraph's start.
Point _deleteBetween(Point rawStart, Point rawEnd) {
  if (rawStart.key == rawEnd.key && rawStart.offset == rawEnd.offset) {
    return rawStart;
  }

  // Prefer text points: an element point addressing a position next to a text
  // node describes the same place, and text points keep the cases below from
  // multiplying.
  final start = _preferLeaf(rawStart, towardsEnd: true);
  final end = _preferLeaf(rawEnd, towardsEnd: false);

  final startNode = start.getNode();
  final endNode = end.getNode();
  if (startNode == null || endNode == null) return rawStart;
  if (start.key == end.key && start.offset == end.offset) return start;

  // A range inside one text node: the common case, and a plain splice.
  if (start.key == end.key &&
      start.type == PointType.text &&
      startNode is TextNode) {
    if (startNode.isToken) {
      final caret = _pointBefore(startNode);
      startNode.remove(preserveEmptyParent: true);
      return caret;
    }
    startNode.spliceText(start.offset, end.offset - start.offset, '');
    return Point(startNode.key, start.offset, PointType.text);
  }

  final startBlock = _blockOf(startNode);
  final endBlock = _blockOf(endNode);

  if (startBlock.key == endBlock.key) {
    // Strictly-between first, while both boundaries are still attached and
    // the walk between them is therefore well defined.
    _removeStrictlyBetween(startNode, endNode);
    final caret = _trimNodeStart(start, startNode, endNode);
    _trimNodeEnd(end, endNode, startNode);
    return caret;
  }

  final caret = _trimNodeStart(start, startNode, startNode);
  _removeFollowingWithin(startBlock, startNode);
  _trimNodeEnd(end, endNode, endNode);
  _removePrecedingWithin(endBlock, endNode);
  _removeBlocksBetween(startBlock, endBlock);

  if (endBlock.isAttached && startBlock.isAttached) {
    if (_canMergeBlocks(startBlock, endBlock)) {
      for (final child in endBlock.children.toList()) {
        startBlock.append(child);
      }
      _removeBlockAndEmptyAncestors(endBlock);
    }
  }
  return caret;
}

void _removeStrictlyBetween(LexicalNode start, LexicalNode end) {
  final doomed = <LexicalNode>[];
  for (final node in start.getNodesBetween(end)) {
    if (node.key == start.key || node.key == end.key) continue;
    if (node is ElementNode &&
        (node.isParentOf(start) || node.isParentOf(end))) {
      continue;
    }
    if (start.isParentOf(node) || end.isParentOf(node)) continue;
    doomed.add(node);
  }
  for (final node in doomed) {
    if (node.isAttached) node.remove(preserveEmptyParent: true);
  }
}

void _removeBlocksBetween(ElementNode startBlock, ElementNode endBlock) {
  final doomed = <LexicalNode>[];
  for (final node in startBlock.getNodesBetween(endBlock)) {
    if (node.key == startBlock.key || node.key == endBlock.key) continue;
    if (startBlock.isParentOf(node) || endBlock.isParentOf(node)) continue;
    if (node is ElementNode &&
        (node.isParentOf(startBlock) || node.isParentOf(endBlock))) {
      continue;
    }
    doomed.add(node);
  }
  for (final node in doomed) {
    if (node.isAttached) node.remove(preserveEmptyParent: true);
  }
}

/// Removes `[offset, end)` of [node], and returns the caret.
///
/// [keep] names the far end of the range, whose ancestors must survive even
/// when they sit inside the trimmed span.
Point _trimNodeStart(Point point, LexicalNode node, LexicalNode keep) {
  if (point.type == PointType.text && node is TextNode) {
    final size = node.getTextContentSize();
    if (point.offset >= size) return Point(node.key, size, PointType.text);
    if (node.isToken) {
      // Atomic: a range that reaches into a token takes all of it.
      final caret = _pointBefore(node);
      node.remove(preserveEmptyParent: true);
      return caret;
    }
    node.spliceText(point.offset, size - point.offset, '');
    return Point(node.key, point.offset, PointType.text);
  }
  if (node is ElementNode) {
    for (final child in node.children.toList().skip(point.offset)) {
      if (!child.isAttached) continue;
      if (child.key == keep.key) continue;
      if (child is ElementNode && child.isParentOf(keep)) continue;
      child.remove(preserveEmptyParent: true);
    }
    return Point(node.key, point.offset, PointType.element);
  }
  return point;
}

/// Removes `[0, offset)` of [node].
void _trimNodeEnd(Point point, LexicalNode node, LexicalNode keep) {
  if (point.type == PointType.text && node is TextNode) {
    if (point.offset <= 0) return;
    if (node.isToken) {
      node.remove(preserveEmptyParent: true);
      return;
    }
    node.spliceText(0, point.offset, '');
    return;
  }
  if (node is ElementNode) {
    final children = node.children.toList();
    final limit = point.offset.clamp(0, children.length);
    for (var i = 0; i < limit; i++) {
      final child = children[i];
      if (!child.isAttached) continue;
      if (child.key == keep.key) continue;
      if (child is ElementNode && child.isParentOf(keep)) continue;
      child.remove(preserveEmptyParent: true);
    }
  }
}

/// The equivalent text point next to an element point, when there is one.
Point _preferLeaf(Point point, {required bool towardsEnd}) {
  if (point.type == PointType.text) return point;
  final element = point.getNode();
  if (element is! ElementNode) return point;
  final size = element.childrenSize;
  final index = point.offset.clamp(0, size);

  TextNode? at(int i) {
    final child = i < 0 || i >= size ? null : element.getChildAtIndex(i);
    return child is TextNode ? child : null;
  }

  final ahead = at(index);
  final behind = at(index - 1);
  if (towardsEnd) {
    if (ahead != null) return Point(ahead.key, 0, PointType.text);
    if (behind != null) {
      return Point(behind.key, behind.getTextContentSize(), PointType.text);
    }
  } else {
    if (behind != null) {
      return Point(behind.key, behind.getTextContentSize(), PointType.text);
    }
    if (ahead != null) return Point(ahead.key, 0, PointType.text);
  }
  return point;
}

void _removeFollowingWithin(ElementNode block, LexicalNode node) {
  if (node.key == block.key) return;
  var current = node;
  while (true) {
    final parent = current.getParent();
    if (parent == null) return;
    for (final sibling in current.getNextSiblings()) {
      if (sibling.isAttached) sibling.remove(preserveEmptyParent: true);
    }
    if (parent.key == block.key) return;
    current = parent;
  }
}

void _removePrecedingWithin(ElementNode block, LexicalNode node) {
  if (node.key == block.key) return;
  var current = node;
  while (true) {
    final parent = current.getParent();
    if (parent == null) return;
    for (final sibling in current.getPreviousSiblings()) {
      if (sibling.isAttached) sibling.remove(preserveEmptyParent: true);
    }
    if (parent.key == block.key) return;
    current = parent;
  }
}

/// Whether the tail of [end] may be appended to [start].
///
/// Two blocks in different shadow roots — separate table cells, say — never
/// merge. Deleting across a cell boundary clears the cells; it does not
/// dissolve the table.
bool _canMergeBlocks(ElementNode start, ElementNode end) {
  if (start is RootNode || end is RootNode) return false;
  if (_shadowRootOf(start).key != _shadowRootOf(end).key) return false;
  return true;
}

void _removeBlockAndEmptyAncestors(ElementNode block) {
  if (block is RootNode || !block.isAttached) return;
  final parent = block.getParent();
  block.remove(preserveEmptyParent: true);
  if (parent != null &&
      parent is! RootNode &&
      parent.isAttached &&
      parent.isEmpty) {
    _removeBlockAndEmptyAncestors(parent);
  }
}

Point _pointBefore(LexicalNode node) {
  final previous = node.getPreviousSibling();
  if (previous is TextNode) {
    return Point(previous.key, previous.getTextContentSize(), PointType.text);
  }
  final parent = node.getParent();
  if (parent == null) return Point(node.key, 0, PointType.element);
  return Point(parent.key, node.indexWithinParent, PointType.element);
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

/// Inserts [text] at [caret], returning the caret after the insertion.
Point _insertTextAt(
  Point caret,
  String text, {
  required int format,
  required String style,
}) {
  final node = caret.getNode();

  if (node is TextNode && caret.type == PointType.text) {
    // A token is atomic: text typed at its edge becomes a sibling, never part
    // of the token's label. Otherwise typing next to a mention would silently
    // rewrite the entity's name.
    if (node.isToken || node.type == 'tab') {
      final fresh = _makeTextNode(text, format, style);
      if (caret.offset <= 0) {
        node.insertBefore(fresh);
      } else {
        node.insertAfter(fresh);
      }
      return Point(fresh.key, text.length, PointType.text);
    }
    if (node.getFormat() == format && node.getStyle() == style) {
      node.spliceText(caret.offset, 0, text);
      return Point(node.key, caret.offset + text.length, PointType.text);
    }
    // A different pending format: the run has to split.
    final fresh = _makeTextNode(text, format, style);
    final size = node.getTextContentSize();
    if (caret.offset <= 0) {
      node.insertBefore(fresh);
    } else if (caret.offset >= size) {
      node.insertAfter(fresh);
    } else {
      node.splitText([caret.offset]).first.insertAfter(fresh);
    }
    return Point(fresh.key, text.length, PointType.text);
  }

  if (node is ElementNode) {
    final fresh = _makeTextNode(text, format, style);
    if (node is RootNode) {
      final paragraph = $createParagraphNode()..append(fresh);
      node.splice(caret.offset.clamp(0, node.childrenSize), 0, [paragraph]);
    } else {
      node.splice(caret.offset.clamp(0, node.childrenSize), 0, [fresh]);
    }
    return Point(fresh.key, text.length, PointType.text);
  }

  return caret;
}

TextNode _makeTextNode(String text, int format, String style) {
  final node = $createTextNode(text);
  if (format != 0) node.setFormat(format);
  if (style.isNotEmpty) node.setStyle(style);
  return node;
}

extension on RangeSelection {
  void _insertInline(List<LexicalNode> nodes) {
    final node = anchor.getNode();
    LexicalNode? anchorNode;

    if (node is TextNode && anchor.type == PointType.text) {
      final size = node.getTextContentSize();
      if (anchor.offset <= 0) {
        final previous = node.getPreviousSibling();
        if (previous == null) {
          node.getParentOrThrow().splice(node.indexWithinParent, 0, nodes);
          anchorNode = nodes.last;
        } else {
          anchorNode = previous;
        }
      } else if (anchor.offset >= size) {
        anchorNode = node;
      } else {
        anchorNode = node.splitText([anchor.offset]).first;
      }
      if (anchorNode != nodes.last) {
        var previous = anchorNode;
        for (final insert in nodes) {
          previous.insertAfter(insert);
          previous = insert;
        }
      }
    } else if (node is ElementNode) {
      node.splice(anchor.offset.clamp(0, node.childrenSize), 0, nodes);
    } else {
      return;
    }

    final last = nodes.last;
    if (last is TextNode) {
      _collapseAt(Point(last.key, last.getTextContentSize(), PointType.text));
    } else {
      final parent = last.getParent();
      _collapseAt(
        parent == null
            ? Point(last.key, 0, PointType.element)
            : Point(parent.key, last.indexWithinParent + 1, PointType.element),
      );
    }
  }

  void _insertBlocks(List<LexicalNode> nodes) {
    final anchorNode = anchor.getNode();
    if (anchorNode == null) return;
    final block = _blockOf(anchorNode);

    if (block is RootNode) {
      block.splice(anchor.offset.clamp(0, block.childrenSize), 0, nodes);
    } else {
      final tail = _splitBlockContentAt(block, anchor);
      var previous = block;
      for (final insert in nodes) {
        previous.insertAfter(insert);
        if (insert is ElementNode) previous = insert;
      }
      if (tail.isNotEmpty) {
        final trailing = block.insertNewAfter(isAtEnd: false)..appendAll(tail);
        previous.insertAfter(trailing);
      } else if (block.isEmpty) {
        // The caret was in an empty block: the inserted content replaces it
        // rather than leaving a blank line above.
        block.remove(preserveEmptyParent: true);
      }
    }

    final last = nodes.last;
    if (last is ElementNode) {
      _collapseAt(
        _lastPointIn(last) ??
            Point(last.key, last.childrenSize, PointType.element),
      );
    } else {
      final parent = last.getParent();
      _collapseAt(
        parent == null
            ? Point(last.key, 0, PointType.element)
            : Point(parent.key, last.indexWithinParent + 1, PointType.element),
      );
    }
  }

  /// Splits [block] at [point] and returns the nodes that move to a new block.
  List<LexicalNode> _splitBlockContentAt(ElementNode block, Point point) {
    final node = point.getNode();
    if (node == null) return const [];

    LexicalNode? stayAfter;
    if (point.type == PointType.text && node is TextNode) {
      final size = node.getTextContentSize();
      if (point.offset <= 0) {
        stayAfter = node.getPreviousSibling();
        if (stayAfter == null && node.getParent()?.key != block.key) {
          // Nested at the very start of an inline element: split above it.
          stayAfter = _liftToBlockChild(block, node).getPreviousSibling();
        }
      } else if (point.offset >= size) {
        stayAfter = _liftToBlockChild(block, node);
      } else {
        stayAfter = _liftToBlockChild(
          block,
          node.splitText([point.offset]).first,
        );
      }
    } else if (node is ElementNode) {
      if (node.key == block.key) {
        stayAfter = node.getChildAtIndex(point.offset - 1);
      } else {
        final index = point.offset;
        final child = node.getChildAtIndex(index - 1);
        stayAfter = child == null
            ? _liftToBlockChild(block, node).getPreviousSibling()
            : _liftToBlockChild(block, child);
      }
    }

    final tail = <LexicalNode>[];
    var cursor = stayAfter == null
        ? block.getFirstChild()
        : stayAfter.getNextSibling();
    while (cursor != null) {
      final next = cursor.getNextSibling();
      tail.add(cursor);
      cursor = next;
    }
    for (final node in tail) {
      node.remove(preserveEmptyParent: true);
    }
    return tail;
  }
}

/// Splits every inline ancestor between [node] and [block].
///
/// Returns the direct child of [block] that [node] now sits at the end of, so
/// the caller can move everything after it. Splitting a link across a
/// paragraph break has to produce two links, not one link whose text is in two
/// paragraphs.
LexicalNode _liftToBlockChild(ElementNode block, LexicalNode node) {
  var current = node;
  var parent = current.getParent();
  while (parent != null && parent.key != block.key) {
    final following = current.getNextSiblings();
    if (following.isNotEmpty) {
      final tail = parent.clone();
      if (tail is! ElementNode) break;
      tail.afterCloneFrom(parent);
      parent.insertAfter(tail);
      tail.appendAll(following);
    }
    current = parent;
    parent = current.getParent();
  }
  return current;
}

// ---------------------------------------------------------------------------
// Movement
// ---------------------------------------------------------------------------

enum _Unit { character, word }

extension on RangeSelection {
  void _deleteTowards(Point moved, {required bool backwards}) {
    final anchorCopy = Point(anchor.key, anchor.offset, anchor.type);
    final caret = backwards
        ? _deleteBetween(moved, anchorCopy)
        : _deleteBetween(anchorCopy, moved);
    _collapseAt(caret);
  }

  /// Splits the boundary text nodes so the selection covers whole runs, and
  /// returns those runs.
  List<TextNode> _splitAtBoundaries() {
    final (start, end) = orderedPoints;
    final startNode = start.getNode();
    final endNode = end.getNode();
    if (startNode == null || endNode == null) return const [];

    if (start.key == end.key && startNode is TextNode) {
      final size = startNode.getTextContentSize();
      var target = startNode;
      if (start.offset > 0 || end.offset < size) {
        final parts = startNode.splitText([start.offset, end.offset]);
        target = start.offset > 0 ? parts[1] : parts[0];
      }
      anchor.set(target.key, 0, PointType.text);
      focus.set(target.key, target.getTextContentSize(), PointType.text);
      dirty = true;
      return [target];
    }

    var first = startNode;
    if (startNode is TextNode && start.type == PointType.text) {
      final size = startNode.getTextContentSize();
      if (start.offset > 0 && start.offset < size) {
        first = startNode.splitText([start.offset])[1];
      }
    }
    var last = endNode;
    if (endNode is TextNode && end.type == PointType.text) {
      final size = endNode.getTextContentSize();
      if (end.offset > 0 && end.offset < size) {
        last = endNode.splitText([end.offset])[0];
      } else if (end.offset <= 0) {
        // The range stops before this node contributes anything.
        final previous = endNode.getPreviousSibling();
        if (previous != null) last = previous;
      }
    }

    final runs = _leavesBetween(first, last).whereType<TextNode>().toList();
    if (runs.isEmpty) return const [];
    anchor.set(runs.first.key, 0, PointType.text);
    focus.set(runs.last.key, runs.last.getTextContentSize(), PointType.text);
    dirty = true;
    return runs;
  }
}

/// The point one [unit] away from [from], or `null` at the document edge.
Point? _movePoint(Point from, {required bool backwards, required _Unit unit}) {
  final node = from.getNode();
  if (node == null) return null;

  if (node is TextNode && from.type == PointType.text) {
    final text = node.getTextContent();
    if (backwards && from.offset > 0) {
      if (node.isToken) return Point(node.key, 0, PointType.text);
      final offset = unit == _Unit.character
          ? _previousGrapheme(text, from.offset)
          : _previousWord(text, from.offset);
      if (node.isSegmented && unit == _Unit.character) {
        return Point(
          node.key,
          _previousWord(text, from.offset),
          PointType.text,
        );
      }
      return Point(node.key, offset, PointType.text);
    }
    if (!backwards && from.offset < text.length) {
      if (node.isToken) {
        return Point(node.key, text.length, PointType.text);
      }
      final offset = unit == _Unit.character
          ? _nextGrapheme(text, from.offset)
          : _nextWord(text, from.offset);
      if (node.isSegmented && unit == _Unit.character) {
        return Point(node.key, _nextWord(text, from.offset), PointType.text);
      }
      return Point(node.key, offset, PointType.text);
    }
    return _crossBoundary(node, backwards: backwards);
  }

  if (node is ElementNode) {
    final index = from.offset;
    if (backwards && index > 0) {
      final child = node.getChildAtIndex(index - 1);
      if (child is TextNode) {
        return child.isToken
            ? Point(child.key, 0, PointType.text)
            : Point(
                child.key,
                unit == _Unit.character
                    ? _previousGrapheme(
                        child.getTextContent(),
                        child.getTextContentSize(),
                      )
                    : _previousWord(
                        child.getTextContent(),
                        child.getTextContentSize(),
                      ),
                PointType.text,
              );
      }
      return Point(node.key, index - 1, PointType.element);
    }
    if (!backwards && index < node.childrenSize) {
      final child = node.getChildAtIndex(index);
      if (child is TextNode) {
        return child.isToken
            ? Point(child.key, child.getTextContentSize(), PointType.text)
            : Point(
                child.key,
                unit == _Unit.character
                    ? _nextGrapheme(child.getTextContent(), 0)
                    : _nextWord(child.getTextContent(), 0),
                PointType.text,
              );
      }
      return Point(node.key, index + 1, PointType.element);
    }
    return _crossBoundary(node, backwards: backwards);
  }

  return null;
}

/// The position just outside [node]'s block, in the given direction.
Point? _crossBoundary(LexicalNode node, {required bool backwards}) {
  // Inside the block first: a previous or next inline sibling, walking out of
  // any inline elements on the way.
  var current = node;
  final block = _blockOf(node);
  while (current.key != block.key) {
    final sibling = backwards
        ? current.getPreviousSibling()
        : current.getNextSibling();
    if (sibling != null) {
      if (sibling is TextNode) {
        if (sibling.isToken) {
          return backwards
              ? Point(sibling.key, 0, PointType.text)
              : Point(
                  sibling.key,
                  sibling.getTextContentSize(),
                  PointType.text,
                );
        }
        final text = sibling.getTextContent();
        return backwards
            ? Point(
                sibling.key,
                _previousGrapheme(text, text.length),
                PointType.text,
              )
            : Point(sibling.key, _nextGrapheme(text, 0), PointType.text);
      }
      if (sibling is ElementNode) {
        final inner = backwards
            ? _lastPointIn(sibling)
            : _firstPointIn(sibling);
        if (inner != null) return inner;
      }
      final parent = sibling.getParent();
      if (parent != null) {
        return Point(
          parent.key,
          backwards ? sibling.indexWithinParent : sibling.indexWithinParent + 1,
          PointType.element,
        );
      }
    }
    final parent = current.getParent();
    if (parent == null) return null;
    current = parent;
  }

  // Out of the block: the adjacent block's far edge, which is what makes the
  // subsequent delete merge the two.
  final neighbour = backwards ? _previousBlockOf(block) : _nextBlockOf(block);
  if (neighbour == null) return null;
  return backwards ? _lastPointIn(neighbour) : _firstPointIn(neighbour);
}

ElementNode? _previousBlockOf(ElementNode block) {
  LexicalNode? current = block;
  while (current != null && current is! RootNode) {
    final previous = current.getPreviousSibling();
    if (previous is ElementNode) {
      var candidate = previous;
      while (true) {
        final last = candidate.getLastChild();
        if (last is ElementNode && !last.isInline) {
          candidate = last;
          continue;
        }
        break;
      }
      return candidate;
    }
    if (previous != null) return null;
    current = current.getParent();
  }
  return null;
}

ElementNode? _nextBlockOf(ElementNode block) {
  LexicalNode? current = block;
  while (current != null && current is! RootNode) {
    final next = current.getNextSibling();
    if (next is ElementNode) {
      var candidate = next;
      while (true) {
        final first = candidate.getFirstChild();
        if (first is ElementNode && !first.isInline) {
          candidate = first;
          continue;
        }
        break;
      }
      return candidate;
    }
    if (next != null) return null;
    current = current.getParent();
  }
  return null;
}

// ---------------------------------------------------------------------------
// Text boundaries
// ---------------------------------------------------------------------------

/// The code-unit offset one grapheme cluster before [offset].
///
/// Grapheme, not code unit and not rune: a family emoji is a single press of
/// backspace, and stepping by code units would leave half a surrogate pair
/// behind.
int _previousGrapheme(String text, int offset) {
  if (offset <= 0) return 0;
  final limit = offset.clamp(0, text.length);
  final range = CharacterRange.at(text, limit)..moveBack();
  return range.stringBeforeLength;
}

/// The code-unit offset one grapheme cluster after [offset].
int _nextGrapheme(String text, int offset) {
  if (offset >= text.length) return text.length;
  final start = offset.clamp(0, text.length);
  final range = CharacterRange.at(text, start)..moveNext();
  return text.length - range.stringAfterLength;
}

bool _isWordChar(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    codeUnit == 0x5f ||
    codeUnit > 0x7f;

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0xa0;

int _previousWord(String text, int offset) {
  var index = offset.clamp(0, text.length);
  while (index > 0 && _isSpace(text.codeUnitAt(index - 1))) {
    index--;
  }
  if (index == 0) return 0;
  final word = _isWordChar(text.codeUnitAt(index - 1));
  while (index > 0 &&
      !_isSpace(text.codeUnitAt(index - 1)) &&
      _isWordChar(text.codeUnitAt(index - 1)) == word) {
    index--;
  }
  return index;
}

int _nextWord(String text, int offset) {
  var index = offset.clamp(0, text.length);
  while (index < text.length && _isSpace(text.codeUnitAt(index))) {
    index++;
  }
  if (index == text.length) return index;
  final word = _isWordChar(text.codeUnitAt(index));
  while (index < text.length &&
      !_isSpace(text.codeUnitAt(index)) &&
      _isWordChar(text.codeUnitAt(index)) == word) {
    index++;
  }
  return index;
}

int _toggledFormat(int current, TextFormat format) {
  final enabled = (current & format.bit) == 0;
  var next = enabled ? current | format.bit : current & ~format.bit;
  if (enabled && (format.bit & TextFormat.caseMask) != 0) {
    next &= ~(TextFormat.caseMask & ~format.bit);
  }
  return next;
}
