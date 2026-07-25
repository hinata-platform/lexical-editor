/// Debug-only structural verification of the node tree.
library;

import 'errors.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/root_node.dart';
import 'nodes/text_node.dart';
import 'updates.dart';

/// Walks the tree from [root] and throws on the first broken invariant.
///
/// Sibling pointers buy O(changed nodes) edits at the cost of making the
/// invariants — `first.prev == null`, `last.next == null`, `size` matching the
/// chain, parents agreeing with children, no cycles — the caller's
/// responsibility. Structural corruption discovered late is close to
/// undebuggable, because the state that would explain it has been discarded;
/// running this after every commit under `assert` catches it at the mutation
/// that caused it and costs nothing in release.
///
/// Returns `true` so it composes with `assert(() { ...; return true; }())`.
bool assertTreeIntegrity(RootNode root) {
  final seen = <NodeKey>{};
  _checkElement(root, seen, 0);
  return true;
}

void _checkElement(ElementNode element, Set<NodeKey> seen, int depth) {
  if (!seen.add(element.key)) {
    throw LexicalTreeError(
      'Cycle detected: node ${element.key} is its own ancestor.',
    );
  }
  final first = element.firstKey;
  final last = element.lastKey;
  final size = element.sizeInternal;

  if (size == 0) {
    if (first != null || last != null) {
      throw LexicalTreeError(
        'Element ${element.key} has size 0 but first=$first last=$last.',
      );
    }
    return;
  }
  if (first == null || last == null) {
    throw LexicalTreeError(
      'Element ${element.key} has size $size but first=$first last=$last.',
    );
  }

  var count = 0;
  NodeKey? expectedPrev;
  NodeKey? cursor = first;
  LexicalNode? lastNode;
  while (cursor != null) {
    final child = $getNodeByKey(cursor);
    if (child == null) {
      throw LexicalTreeError(
        'Element ${element.key} references missing child $cursor.',
      );
    }
    if (child.parentKey != element.key) {
      throw LexicalTreeError(
        'Child ${child.key} of ${element.key} has parent ${child.parentKey}.',
      );
    }
    if (child.prevKey != expectedPrev) {
      throw LexicalTreeError(
        'Child ${child.key} has prev ${child.prevKey}, expected $expectedPrev.',
      );
    }
    if (element is RootNode && child is TextNode) {
      throw LexicalTreeError(
        'Text node ${child.key} is a direct child of the root.',
      );
    }
    // Newlines inside a text node are *not* an integrity violation. Lexical's
    // editing paths avoid them, but its serializer preserves them, and a code
    // block authored on the web arrives with them. Failing here would reject
    // a document real Lexical considers canonical.
    if (child is ElementNode) {
      _checkElement(child, seen, depth + 1);
    } else if (!seen.add(child.key)) {
      throw LexicalTreeError(
        'Node ${child.key} appears more than once in the tree.',
      );
    }
    count++;
    if (count > size) {
      throw LexicalTreeError(
        'Element ${element.key} declares size $size but its chain is longer.',
      );
    }
    expectedPrev = cursor;
    lastNode = child;
    cursor = child.nextKey;
  }

  if (count != size) {
    throw LexicalTreeError(
      'Element ${element.key} declares size $size but has $count children.',
    );
  }
  if (lastNode == null || lastNode.key != last) {
    throw LexicalTreeError(
      'Element ${element.key} declares last=$last but the chain ends at '
      '${lastNode?.key}.',
    );
  }
  if (lastNode.nextKey != null) {
    throw LexicalTreeError(
      'Last child ${lastNode.key} of ${element.key} has a next pointer.',
    );
  }
}
