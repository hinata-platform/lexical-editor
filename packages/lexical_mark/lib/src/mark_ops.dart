/// Marking a selection, and taking a mark back off it.
library;

import 'package:lexical_core/lexical_core.dart';

import 'mark_node.dart';

/// Marks the selection with the identifier in the payload.
const LexicalCommand<String> addMarkCommand = LexicalCommand('ADD_MARK');

/// Removes the identifier in the payload from the whole document.
const LexicalCommand<String> removeMarkCommand = LexicalCommand('REMOVE_MARK');

/// Registers [addMarkCommand] and [removeMarkCommand] on [editor].
Unsubscribe registerMark(LexicalEditor editor) {
  final unsubscribes = <Unsubscribe>[
    editor.registerCommand<String>(addMarkCommand, (id) {
      $markSelection(id);
      return true;
    }, CommandPriority.editor),
    editor.registerCommand<String>(removeMarkCommand, (id) {
      $removeMark(id);
      return true;
    }, CommandPriority.editor),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

/// Tags the selection with [id].
///
/// A comment thread is one identifier: the document records *that* a range is
/// annotated, and the application keeps what the annotation says. Nothing about
/// the comment itself enters the document, which is what lets comments be
/// added, edited and resolved without touching it.
///
/// Where the selection already carries a mark, the two overlap — and
/// overlapping annotations are represented by **nesting**, because a node
/// cannot belong to two ranges. Marking exactly the same range twice adds the
/// identifier to the mark that is already there rather than stacking a second
/// one, so the common case stays flat.
void $markSelection(String id) {
  final selection = $getSelection();
  if (selection is! RangeSelection || selection.isCollapsed) return;

  for (final run in _selectedRuns(selection)) {
    if (run.isEmpty) continue;
    final parent = run.first.getParent();
    if (parent is MarkNode && parent.childrenSize == run.length) {
      // The same range, annotated again: one mark, two identifiers.
      parent.addId(id);
      continue;
    }
    final mark = $createMarkNode([id]);
    run.first.insertBefore(mark);
    for (final node in run) {
      mark.append(node);
    }
  }
}

/// Removes [id] from every mark in the document.
///
/// A mark left with no identifiers is unwrapped rather than kept: an
/// annotation nobody refers to is invisible, and leaving it behind would grow
/// the document by one element per resolved comment forever.
void $removeMark(String id) {
  for (final mark in _allMarks($getRoot())) {
    if (!mark.hasId(id)) continue;
    mark.removeId(id);
    if (mark.ids.isEmpty) _unwrap(mark);
  }
}

/// The identifiers on the marks the selection touches.
Set<String> $getMarkIdsAtSelection() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return const {};
  final ids = <String>{};
  for (final node in selection.getNodes()) {
    var current = node.getParent();
    if (node is MarkNode) ids.addAll(node.ids);
    while (current != null) {
      if (current is MarkNode) ids.addAll(current.ids);
      current = current.getParent();
    }
  }
  return ids;
}

/// The text carrying [id], or an empty string when nothing does.
///
/// What a comment sidebar quotes above the thread. It is read from the
/// document rather than stored with the comment, so it follows the text as it
/// is edited instead of quoting something that no longer exists.
String $getMarkedText(String id) {
  final buffer = StringBuffer();
  for (final mark in _allMarks($getRoot())) {
    if (mark.hasId(id)) buffer.write(mark.getTextContent());
  }
  return buffer.toString();
}

/// Every mark in the tree, in document order, outermost first.
List<MarkNode> _allMarks(ElementNode root) {
  final marks = <MarkNode>[];
  void walk(ElementNode element) {
    for (final child in element.children) {
      if (child is MarkNode) marks.add(child);
      if (child is ElementNode) walk(child);
    }
  }

  walk(root);
  return marks;
}

/// Replaces [mark] with its children, keeping the text where it was.
void _unwrap(MarkNode mark) {
  for (final child in mark.children.toList()) {
    mark.insertBefore(child);
  }
  mark.remove();
}

/// The selected text nodes, split at the selection's edges and grouped into
/// runs of siblings.
///
/// The same shape as `lexical_link`'s: splitting the boundary nodes is what
/// makes an annotation cover exactly what was selected instead of the whole
/// text node it started in. The duplication is deliberate for now — both
/// packages are self-contained — and the primitive belongs in the core the
/// moment a third one needs it.
List<List<TextNode>> _selectedRuns(RangeSelection selection) {
  final (start, end) = selection.orderedPoints;
  final startNode = start.getNode();
  final endNode = end.getNode();
  if (startNode is! TextNode || endNode is! TextNode) {
    return _group(selection.getNodes().whereType<TextNode>().toList());
  }

  if (start.key == end.key) {
    final size = startNode.getTextContentSize();
    // Offsets before splits: a split carries the selection into the parts it
    // produced, so these points then describe the parts, not the request.
    final from = start.offset;
    final to = end.offset;
    var target = startNode;
    if (from > 0 || to < size) {
      final parts = startNode.splitText([from, to]);
      target = from > 0 ? parts[1] : parts[0];
    }
    selection.anchor.set(target.key, 0, PointType.text);
    selection.focus.set(
      target.key,
      target.getTextContentSize(),
      PointType.text,
    );
    return [
      [target],
    ];
  }

  final endOffset = end.offset;
  final startOffset = start.offset;
  var last = endNode;
  if (endOffset > 0 && endOffset < endNode.getTextContentSize()) {
    last = endNode.splitText([endOffset])[0];
  }
  var first = startNode;
  if (startOffset > 0 && startOffset < startNode.getTextContentSize()) {
    first = startNode.splitText([startOffset])[1];
  }

  selection.anchor.set(first.key, 0, PointType.text);
  selection.focus.set(last.key, last.getTextContentSize(), PointType.text);
  return _group(selection.getNodes().whereType<TextNode>().toList());
}

/// Splits [nodes] into runs that share a parent and sit next to each other.
List<List<TextNode>> _group(List<TextNode> nodes) {
  final runs = <List<TextNode>>[];
  for (final node in nodes) {
    final parent = node.getParent();
    if (parent == null) continue;
    final run = runs.isEmpty ? null : runs.last;
    if (run != null &&
        run.last.getParent()?.key == parent.key &&
        run.last.getNextSibling()?.key == node.key) {
      run.add(node);
    } else {
      runs.add([node]);
    }
  }
  return runs;
}
