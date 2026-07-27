/// The ambient editor context and the update lifecycle.
///
/// Upstream's `$`-prefixed functions read an ambient "currently active editor
/// state". This port keeps that convention — so upstream documentation and
/// community examples transfer — and implements it with library-private
/// statics plus loud assertions rather than zones. Updates are synchronous by
/// contract, so the async-safety a zone would buy does not apply, and an
/// `await` inside an update closure is a bug the assertion should catch
/// anyway: an update that yields can commit against a state that has since
/// been replaced.
library;

import 'package:meta/meta.dart';

import 'editor.dart';
import 'editor_state.dart';
import 'errors.dart';
import 'keys.dart';
import 'nodes/decorator_node.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/root_node.dart';
import 'nodes/text_node.dart';
import 'selection.dart';

EditorState? _activeEditorState;
LexicalEditor? _activeEditor;
bool _isReadOnlyMode = true;
LexicalNode? _pendingNodeToClone;

// ---------------------------------------------------------------------------
// Ambient context
// ---------------------------------------------------------------------------

/// The editor state the current `$` call should read or write.
///
/// Throws outside an update or read — the same failure upstream produces,
/// and a much better outcome than silently operating on a stale state.
EditorState $getActiveEditorState() {
  final state = _activeEditorState;
  if (state == null) {
    throw const LexicalStateError(
      r'No active editor state. Node methods and $ helpers are only valid '
      'inside editor.update() or editorState.read().',
    );
  }
  return state;
}

/// The editor the current `$` call belongs to.
LexicalEditor $getActiveEditor() {
  final editor = _activeEditor;
  if (editor == null) {
    throw const LexicalStateError(
      'No active editor. Node mutation is only valid inside editor.update().',
    );
  }
  return editor;
}

/// Whether there is an active context at all.
@internal
bool hasActiveEditorState() => _activeEditorState != null;

/// Whether the active context forbids mutation.
bool isCurrentlyReadOnlyMode() =>
    _isReadOnlyMode || (_activeEditorState?.isFrozen ?? true);

/// Throws when called outside an update.
void errorOnReadOnly() {
  if (isCurrentlyReadOnlyMode()) {
    throw const LexicalStateError(
      'Cannot mutate the document outside editor.update().',
    );
  }
}

/// The node with [key] in the active state, or `null`.
LexicalNode? $getNodeByKey(NodeKey key) => $getActiveEditorState().nodeMap[key];

/// The root of the active state.
RootNode $getRoot() => $getActiveEditorState().root;

// ---------------------------------------------------------------------------
// Node identity and cloning
// ---------------------------------------------------------------------------

/// Assigns [node] its key and registers it in the pending state.
///
/// When [existingKey] is null and a clone is in progress, the key of the node
/// being cloned is adopted. That is what lets `clone()` implementations in
/// this port ignore keys entirely, removing upstream's "pass `node.__key` as
/// the last constructor argument" footgun.
@internal
void $setNodeKey(LexicalNode node, NodeKey? existingKey) {
  final pending = _pendingNodeToClone;
  final key = existingKey ?? pending?.key;
  if (key != null) {
    // Consume it: a clone() implementation that constructs additional nodes
    // must not hand them the cloned node's key.
    if (existingKey == null) _pendingNodeToClone = null;
    node.key = key;
    return;
  }
  errorOnReadOnly();
  final editor = $getActiveEditor();
  final state = $getActiveEditorState();
  final fresh = generateNodeKey();
  state.nodeMapInternal[fresh] = node;
  if (node is ElementNode) {
    editor.dirtyElements[fresh] = true;
  } else {
    editor.dirtyLeaves.add(fresh);
  }
  editor.cloneNotNeeded.add(fresh);
  if (editor.dirtyType == DirtyType.none) {
    editor.dirtyType = DirtyType.hasDirtyNodes;
  }
  node.key = fresh;
}

/// Clones [latest] into a writable copy carrying the same key.
@internal
T $cloneWithProperties<T extends LexicalNode>(T latest) {
  final previous = _pendingNodeToClone;
  _pendingNodeToClone = latest;
  final LexicalNode created;
  try {
    created = latest.clone();
  } finally {
    _pendingNodeToClone = previous;
  }
  assert(
    created.runtimeType == latest.runtimeType,
    '${latest.runtimeType}.clone() returned ${created.runtimeType}. Every '
    'subclass must override clone() and return its own type, or nodes '
    'silently downgrade on the next edit.',
  );
  if (created is! T) {
    throw LexicalStateError(
      '${latest.runtimeType}.clone() returned ${created.runtimeType}, '
      'which is not a $T.',
    );
  }
  assert(
    created.key == latest.key,
    '${latest.runtimeType}.clone() did not preserve the node key.',
  );
  created.afterCloneFrom(latest);
  assert(
    created.parentKey == latest.parentKey &&
        created.nextKey == latest.nextKey &&
        created.prevKey == latest.prevKey,
    '${latest.runtimeType}.afterCloneFrom() did not call super, so the '
    'clone lost its tree pointers.',
  );
  return created;
}

/// Applies any registered replacement for [node]'s type.
///
/// The replacement never inherits the original node's key: two nodes sharing
/// a key would corrupt the node map.
T $applyNodeReplacement<T extends LexicalNode>(T node) {
  final editor = _activeEditor;
  if (editor == null) return node;
  final replacement = editor.registry.replacementFor(node.type);
  if (replacement == null) return node;
  final replaced = replacement.replaceWith(node);
  if (replaced.key == node.key) {
    throw LexicalStateError(
      'Node replacement for "${node.type}" reused the original node key.',
    );
  }
  if (replaced is! T) {
    throw LexicalStateError(
      'Node replacement for "${node.type}" returned ${replaced.runtimeType}, '
      'which is not a $T.',
    );
  }
  return replaced;
}

// ---------------------------------------------------------------------------
// Dirty marking
// ---------------------------------------------------------------------------

/// Marks [node] dirty. Never call directly — use `getWritable()`.
@internal
void internalMarkNodeAsDirty(LexicalNode node) {
  final latest = node.getLatest<LexicalNode>();
  final editor = $getActiveEditor();
  final state = $getActiveEditorState();
  final parent = latest.parentKey;
  if (parent != null) {
    _markParentElementsAsDirty(parent, state, editor.dirtyElements);
  }
  if (editor.dirtyType == DirtyType.none) {
    editor.dirtyType = DirtyType.hasDirtyNodes;
  }
  if (latest is ElementNode) {
    editor.dirtyElements[latest.key] = true;
  } else {
    editor.dirtyLeaves.add(latest.key);
  }
}

void _markParentElementsAsDirty(
  NodeKey parentKey,
  EditorState state,
  Map<NodeKey, bool> dirtyElements,
) {
  NodeKey? next = parentKey;
  while (next != null) {
    if (dirtyElements.containsKey(next)) return;
    final node = state.nodeMap[next];
    if (node == null) return;
    // false: dirty only because a descendant changed, not intentionally.
    dirtyElements[next] = false;
    next = node.parentKey;
  }
}

/// Marks [node]'s neighbours dirty, so a renderer can re-evaluate merging.
@internal
void internalMarkSiblingsAsDirty(LexicalNode node) {
  node.getPreviousSibling()?.markDirty();
  node.getNextSibling()?.markDirty();
}

// ---------------------------------------------------------------------------
// Tree mutation primitives
// ---------------------------------------------------------------------------

/// Throws when [insert] may not be a child of [parent].
@internal
void errorOnInsertTextNodeOnRoot(ElementNode parent, LexicalNode insert) {
  if (parent is RootNode &&
      insert is! ElementNode &&
      insert is! DecoratorNode) {
    throw LexicalTreeError(
      'Only element or decorator nodes may be children of the root; got '
      '"${insert.type}".',
    );
  }
}

/// Unlinks [node] from its parent, repairing the sibling chain.
///
/// This is the only place the pointer invariants are relaxed and restored, so
/// every structural mutator goes through it rather than editing pointers by
/// hand.
@internal
void $removeFromParent(LexicalNode node) {
  final oldParent = node.getParent();
  if (oldParent == null) return;
  final writableNode = node.getWritable<LexicalNode>();
  final writableParent = oldParent.getWritable<ElementNode>();
  final prevSibling = node.getPreviousSibling();
  final nextSibling = node.getNextSibling();
  final prevKey = prevSibling?.key;
  final nextKey = nextSibling?.key;

  if (prevSibling == null) writableParent.firstKey = nextKey;
  if (nextSibling == null) writableParent.lastKey = prevKey;
  if (prevSibling != null) {
    prevSibling.getWritable<LexicalNode>().nextKey = nextKey;
  }
  if (nextSibling != null) {
    nextSibling.getWritable<LexicalNode>().prevKey = prevKey;
  }

  writableNode
    ..prevKey = null
    ..nextKey = null
    ..parentKey = null;
  writableParent.sizeInternal--;
}

/// Removes [node] from the document.
@internal
void $removeNode(LexicalNode node, {bool preserveEmptyParent = false}) {
  errorOnReadOnly();
  final parent = node.getParent();
  if (parent == null) return;
  _relocateSelectionOffRemovedNode(node, parent);
  $removeFromParent(node);
  if (!preserveEmptyParent &&
      !parent.isShadowRoot &&
      !parent.canBeEmpty &&
      parent.isEmpty) {
    $removeNode(parent);
  }
}

/// Moves any selection point that addressed [from] onto [to].
///
/// [childOffset] is how many children [to] already held when [from]'s were
/// appended to them, so an element point keeps addressing the same child.
@internal
void $moveSelectionPointsToReplacement(
  LexicalNode from,
  LexicalNode to, {
  int childOffset = 0,
}) {
  final selection = $getActiveEditorState().selection;
  if (selection is! RangeSelection) return;
  for (final point in [selection.anchor, selection.focus]) {
    if (point.key != from.key) continue;
    if (to is TextNode) {
      final size = to.getTextContentSize();
      point.set(to.key, point.offset.clamp(0, size), PointType.text);
    } else if (to is ElementNode) {
      final offset = childOffset + point.offset;
      point.set(to.key, offset.clamp(0, to.childrenSize), PointType.element);
    }
  }
}

/// Carries selection points into the pieces [parts] a split produced.
///
/// [parts] are the runs one text node became, in document order; the first of
/// them still carries the original key. A point past the first split point
/// therefore names a node at an offset longer than that node now is, and the
/// next keystroke lands in the wrong run — which is how a hashtag being typed
/// loses the characters after it, or a caret jumps backwards when a transform
/// splits a run underneath it.
///
/// The bias is upstream's: the end of a range is left-biased, and so is the
/// start except that a start sitting exactly on a border moves on with the
/// end, so the range does not straddle a boundary it need not.
@internal
void $moveSelectionPointsAfterSplit(NodeKey original, List<TextNode> parts) {
  final selection = $getActiveEditorState().selection;
  if (selection is! RangeSelection) return;

  final held = [
    for (final point in [selection.anchor, selection.focus])
      if (point.type == PointType.text && point.key == original) point,
  ];
  if (held.isEmpty) return;
  // Both ends inside one run order by offset alone — no tree walk needed.
  if (held.length == 2 && held[1].offset < held[0].offset) {
    held.insert(0, held.removeLast());
  }
  Point? startPoint = held.first;
  final endPoint = held.last;
  final startOffset = startPoint.offset;
  final endOffset = endPoint.offset;

  var consumed = 0;
  for (final part in parts) {
    final end = consumed + part.getTextContentSize();
    if (startPoint != null && startOffset >= consumed && startOffset <= end) {
      startPoint.set(part.key, startOffset - consumed, PointType.text);
      // Exactly on a border: keep looking, so it can join the end on the
      // next part rather than leaving the range straddling the boundary.
      if (startOffset < end) startPoint = null;
    }
    if (endOffset >= consumed && endOffset <= end) {
      endPoint.set(part.key, endOffset - consumed, PointType.text);
      break;
    }
    consumed = end;
  }
}

/// Moves any selection point that addressed [node] onto a surviving node.
///
/// Without this, removing the node the caret sits in leaves a selection
/// pointing at a key that is no longer in the node map, which fails at commit
/// with an error far from the removal that caused it.
void _relocateSelectionOffRemovedNode(LexicalNode node, ElementNode parent) {
  final selection = $getActiveEditorState().selection;
  if (selection is! RangeSelection) return;
  final prev = node.getPreviousSibling();
  final next = node.getNextSibling();
  final index = node.indexWithinParent;
  for (final point in [selection.anchor, selection.focus]) {
    if (point.key != node.key) continue;
    if (prev is TextNode) {
      point.set(prev.key, prev.getTextContentSize(), PointType.text);
    } else if (next is TextNode) {
      point.set(next.key, 0, PointType.text);
    } else {
      point.set(parent.key, index < 0 ? 0 : index, PointType.element);
    }
  }
}

// ---------------------------------------------------------------------------
// Read and update
// ---------------------------------------------------------------------------

/// Runs [fn] with [state] active and read-only.
@internal
T readEditorState<T>(
  EditorState state,
  T Function() fn, {
  LexicalEditor? editor,
}) {
  final previousState = _activeEditorState;
  final previousEditor = _activeEditor;
  final previousReadOnly = _isReadOnlyMode;
  _activeEditorState = state;
  _activeEditor = editor ?? previousEditor;
  _isReadOnlyMode = true;
  try {
    return fn();
  } finally {
    _activeEditorState = previousState;
    _activeEditor = previousEditor;
    _isReadOnlyMode = previousReadOnly;
  }
}

/// Runs [fn] against [editor]'s pending state with mutation allowed.
///
/// Framework-internal: [LexicalEditor.update] wraps this with the batching
/// and commit policy.
@internal
void runInUpdateContext(
  LexicalEditor editor,
  EditorState pending,
  void Function() fn,
) {
  final previousState = _activeEditorState;
  final previousEditor = _activeEditor;
  final previousReadOnly = _isReadOnlyMode;
  final previousPendingClone = _pendingNodeToClone;
  _activeEditorState = pending;
  _activeEditor = editor;
  _isReadOnlyMode = false;
  _pendingNodeToClone = null;
  try {
    fn();
  } finally {
    _activeEditorState = previousState;
    _activeEditor = previousEditor;
    _isReadOnlyMode = previousReadOnly;
    _pendingNodeToClone = previousPendingClone;
  }
}
