/// Removing detached nodes from the pending state at commit.
///
/// Nodes are removed from the tree by unlinking their pointers, which leaves
/// them in the node map. Without a sweep they would be copied into every
/// subsequent state for the lifetime of the editor — unbounded growth over a
/// long editing session, and one that is invisible until a profiler is
/// pointed at it.
///
/// The sweep is O(dirty nodes), not O(document): only a node that changed
/// this update can have become detached.
library;

import 'package:meta/meta.dart';

import 'editor_state.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';

/// Drops nodes that became unreachable from the root during this update.
///
/// Must run inside the update context, while [pending] is the active state.
@internal
void garbageCollectDetachedNodes(
  EditorState previous,
  EditorState pending,
  Set<NodeKey> dirtyLeaves,
  Map<NodeKey, bool> dirtyElements,
) {
  final previousMap = previous.nodeMap;
  final map = pending.nodeMapInternal;

  for (final key in dirtyElements.keys.toList()) {
    final node = map[key];
    if (node == null || node.isAttached) continue;
    if (node is ElementNode) {
      _collectSubtree(node, map, previousMap, dirtyLeaves, dirtyElements);
    }
    // A node created and dereferenced within the same update never existed
    // for a listener, so it should not be reported as dirty either.
    if (!previousMap.containsKey(key)) dirtyElements.remove(key);
    map.remove(key);
  }

  for (final key in dirtyLeaves.toList()) {
    final node = map[key];
    if (node == null || node.isAttached) continue;
    if (!previousMap.containsKey(key)) dirtyLeaves.remove(key);
    map.remove(key);
  }
}

/// Removes every descendant of a detached element.
///
/// Iterative rather than recursive: a detached subtree can be arbitrarily
/// deep, and the sweep must not be the thing that overflows the stack.
void _collectSubtree(
  ElementNode root,
  Map<NodeKey, LexicalNode> map,
  Map<NodeKey, LexicalNode> previousMap,
  Set<NodeKey> dirtyLeaves,
  Map<NodeKey, bool> dirtyElements,
) {
  final queue = <NodeKey>[];
  _enqueueChildren(root, map, queue);

  while (queue.isNotEmpty) {
    final key = queue.removeLast();
    final node = map[key];
    if (node == null) continue;
    if (node is ElementNode) {
      _enqueueChildren(node, map, queue);
      if (!previousMap.containsKey(key)) dirtyElements.remove(key);
    } else if (!previousMap.containsKey(key)) {
      dirtyLeaves.remove(key);
    }
    map.remove(key);
  }
}

void _enqueueChildren(
  ElementNode element,
  Map<NodeKey, LexicalNode> map,
  List<NodeKey> queue,
) {
  var childKey = element.firstKey;
  while (childKey != null) {
    queue.add(childKey);
    childKey = map[childKey]?.nextKey;
  }
}
