/// The base node type.
library;

import 'package:meta/meta.dart';

import '../errors.dart';
import '../keys.dart';
import '../node_state.dart';
import '../updates.dart';
import 'element_node.dart';
import 'root_node.dart';

/// Base class of every node in the document tree.
///
/// A node is an immutable, versioned snapshot addressed by its [key].
/// Reading goes through [getLatest] so a stale local variable cannot return
/// stale data; writing goes through [getWritable], which clones the node
/// into the pending state on first write.
///
/// Children are **sibling pointers**, not a list: an element records only
/// its first and last child keys plus a size, and every node records its
/// previous, next, and parent keys. That is what makes an edit cost
/// O(changed nodes) rather than O(document), and it is what lets two
/// committed states share every untouched node by reference.
///
/// Never override `==` or `hashCode` on a node. Identity is the key: two
/// versions of the same node must remain distinguishable, and structural
/// equality would make a stale reference compare equal to a fresh one.
abstract class LexicalNode {
  /// Creates a node and assigns it a fresh key.
  ///
  /// Construction registers the node in the pending editor state, so it is
  /// only valid inside an update. That mirrors upstream and is what allows
  /// `clone()` implementations to ignore keys entirely.
  LexicalNode() {
    $setNodeKey(this, null);
  }

  /// Creates a node with a caller-supplied key.
  ///
  /// Only the root uses this: its key is fixed rather than generated.
  LexicalNode.withKey(NodeKey key) {
    $setNodeKey(this, key);
  }

  late NodeKey _key;

  /// Key of this node's parent element, or `null` when detached.
  @internal
  NodeKey? parentKey;

  /// Key of the previous sibling, or `null` when this is the first child.
  @internal
  NodeKey? prevKey;

  /// Key of the next sibling, or `null` when this is the last child.
  @internal
  NodeKey? nextKey;

  /// Extension data, allocated lazily.
  @internal
  NodeState? state;

  /// The wire-format `type` string of this node.
  ///
  /// Must be unique among the node types registered on one editor and must
  /// match the type its `NodeSpec` was registered under.
  String get type;

  /// This node's identity within the editor state.
  NodeKey get key => _key;

  @internal
  set key(NodeKey value) => _key = value;

  /// Whether this node participates in inline text flow.
  ///
  /// Text and line breaks are inline; paragraphs and headings are not.
  bool get isInline;

  /// Extension data for this node, created on first access.
  NodeState get nodeState => state ??= NodeState();

  // ---------------------------------------------------------------------
  // Versioning
  // ---------------------------------------------------------------------

  /// Resolves this node's current version from the active editor state.
  ///
  /// Always read through this. A node reference captured before an edit
  /// points at an older version; reading its fields directly returns stale
  /// data, and the bug surfaces far from its cause.
  T getLatest<T extends LexicalNode>() {
    final latest = $getActiveEditorState().nodeMap[_key];
    if (latest == null) {
      throw LexicalStateError(
        'Node $_key does not exist in the active editor state. Do not reuse '
        'node references across editor.update() / editorState.read() calls.',
      );
    }
    if (latest is! T) {
      throw LexicalStateError(
        'Node $_key resolved to ${latest.runtimeType}, expected $T. This '
        'usually means clone() returned the wrong subclass.',
      );
    }
    return latest;
  }

  /// Returns a mutable version of this node, cloning it if necessary.
  ///
  /// Only valid inside an update. The first write in an update clones the
  /// node into the pending state and marks it dirty; subsequent writes in
  /// the same update reuse that clone.
  T getWritable<T extends LexicalNode>() {
    errorOnReadOnly();
    final editor = $getActiveEditor();
    final state = $getActiveEditorState();
    final latest = getLatest<T>();
    if (editor.cloneNotNeeded.contains(_key)) {
      internalMarkNodeAsDirty(latest);
      return latest;
    }
    final mutable = $cloneWithProperties<T>(latest);
    editor.cloneNotNeeded.add(_key);
    internalMarkNodeAsDirty(mutable);
    state.nodeMapInternal[_key] = mutable;
    return mutable;
  }

  /// Creates a new instance of this node's class carrying its constructor
  /// state.
  ///
  /// Every subclass must override this and return its own type. The
  /// framework supplies the key, so implementations never mention it:
  ///
  /// ```dart
  /// @override
  /// HeadingNode clone() => HeadingNode(_tag);
  /// ```
  ///
  /// A subclass that inherits its parent's `clone()` silently downgrades to
  /// the parent type on the next edit — data loss with no error. That is
  /// asserted against in debug builds.
  LexicalNode clone();

  /// Copies mutable state that the constructor does not carry.
  ///
  /// Overrides **must** call `super.afterCloneFrom(prev)`, or the clone
  /// loses its tree pointers and the document falls apart.
  @mustCallSuper
  void afterCloneFrom(covariant LexicalNode prev) {
    if (_key == prev._key) {
      parentKey = prev.parentKey;
      nextKey = prev.nextKey;
      prevKey = prev.prevKey;
      state = prev.state;
    } else if (prev.state != null) {
      state = prev.state!.copy();
    }
  }

  /// Marks this node dirty so the next commit reconciles it.
  void markDirty() {
    getWritable<LexicalNode>();
  }

  /// Whether this node was modified during the current update.
  bool get isDirty {
    final editor = $getActiveEditor();
    return editor.dirtyLeaves.contains(_key) ||
        editor.dirtyElements.containsKey(_key);
  }

  // ---------------------------------------------------------------------
  // Traversal
  // ---------------------------------------------------------------------

  /// Whether a path exists from this node to the root.
  ///
  /// Detached nodes are not reconciled and are eventually collected.
  bool get isAttached {
    NodeKey? nodeKey = _key;
    while (nodeKey != null) {
      if (nodeKey == NodeKey.root) return true;
      final node = $getNodeByKey(nodeKey);
      if (node == null) return false;
      nodeKey = node.parentKey;
    }
    return false;
  }

  /// This node's parent element, or `null` when detached.
  ElementNode? getParent() {
    final parent = getLatest<LexicalNode>().parentKey;
    if (parent == null) return null;
    return $getNodeByKey(parent) as ElementNode?;
  }

  /// This node's parent element, or throws when detached.
  ElementNode getParentOrThrow() {
    final parent = getParent();
    if (parent == null) {
      throw LexicalTreeError('Expected node $_key to have a parent.');
    }
    return parent;
  }

  /// The ancestors of this node, closest first.
  List<ElementNode> getParents() {
    final parents = <ElementNode>[];
    var parent = getParent();
    while (parent != null) {
      parents.add(parent);
      parent = parent.getParent();
    }
    return parents;
  }

  /// The top-level block containing this node, or `null` for the root.
  LexicalNode? getTopLevelElement() {
    LexicalNode? node = getLatest<LexicalNode>();
    while (node != null) {
      final parent = node.getParent();
      if (parent is RootNode) return node;
      node = parent;
    }
    return null;
  }

  /// The previous sibling, or `null` when this is the first child.
  LexicalNode? getPreviousSibling() {
    final key = getLatest<LexicalNode>().prevKey;
    return key == null ? null : $getNodeByKey(key);
  }

  /// The next sibling, or `null` when this is the last child.
  LexicalNode? getNextSibling() {
    final key = getLatest<LexicalNode>().nextKey;
    return key == null ? null : $getNodeByKey(key);
  }

  /// All siblings before this node, in document order.
  List<LexicalNode> getPreviousSiblings() {
    final parent = getParent();
    if (parent == null) return const [];
    final result = <LexicalNode>[];
    for (final child in parent.children) {
      if (child.key == _key) break;
      result.add(child);
    }
    return result;
  }

  /// All siblings after this node, in document order.
  List<LexicalNode> getNextSiblings() {
    final result = <LexicalNode>[];
    var node = getNextSibling();
    while (node != null) {
      result.add(node);
      node = node.getNextSibling();
    }
    return result;
  }

  /// This node's position among its parent's children.
  ///
  /// O(n) in the number of preceding siblings — the price of pointers over
  /// an indexable list. Prefer sibling traversal in hot paths.
  int get indexWithinParent {
    final parent = getParent();
    if (parent == null) return -1;
    var index = 0;
    var node = parent.getFirstChild();
    while (node != null) {
      if (node.key == _key) return index;
      index++;
      node = node.getNextSibling();
    }
    return -1;
  }

  /// Whether [other] refers to the same node, ignoring version.
  bool isSameNode(LexicalNode? other) => other != null && other._key == _key;

  /// Whether this node is an ancestor of [target].
  bool isParentOf(LexicalNode target) {
    if (_key == target._key) return false;
    var parent = target.getParent();
    while (parent != null) {
      if (parent.key == _key) return true;
      parent = parent.getParent();
    }
    return false;
  }

  /// The closest element that contains both this node and [other].
  ElementNode? getCommonAncestor(LexicalNode other) {
    final a = getParents();
    final b = other.getParents();
    final self = this;
    if (self is ElementNode) a.insert(0, self);
    if (other is ElementNode) b.insert(0, other);
    final bKeys = {for (final node in b) node.key};
    for (final node in a) {
      if (bKeys.contains(node.key)) return node;
    }
    return null;
  }

  /// Whether this node precedes [target] in document order.
  bool isBefore(LexicalNode target) {
    if (_key == target._key) return false;
    if (target.isParentOf(this)) return true;
    if (isParentOf(target)) return false;
    final common = getCommonAncestor(target);
    if (common == null) {
      throw LexicalTreeError(
        'isBefore: $_key and ${target._key} are not in the same tree.',
      );
    }
    final indexA = _indexUnder(this, common);
    final indexB = _indexUnder(target, common);
    return indexA < indexB;
  }

  static int _indexUnder(LexicalNode node, ElementNode ancestor) {
    var current = node;
    while (true) {
      final parent = current.getParentOrThrow();
      if (parent.key == ancestor.key) return current.indexWithinParent;
      current = parent;
    }
  }

  /// Every node between this one and [target], inclusive, in document order.
  List<LexicalNode> getNodesBetween(LexicalNode target) {
    final forwards = isBefore(target);
    final nodes = <LexicalNode>[];
    final visited = <NodeKey>{};
    LexicalNode? node = this;
    while (node != null) {
      final key = node._key;
      if (visited.add(key)) nodes.add(node);
      if (key == target._key) break;
      final child = node is ElementNode
          ? (forwards ? node.getFirstChild() : node.getLastChild())
          : null;
      if (child != null) {
        node = child;
        continue;
      }
      final sibling = forwards
          ? node.getNextSibling()
          : node.getPreviousSibling();
      if (sibling != null) {
        node = sibling;
        continue;
      }
      final parent = node.getParentOrThrow();
      if (visited.add(parent.key)) nodes.add(parent);
      if (parent.key == target._key) break;
      LexicalNode? parentSibling;
      ElementNode? ancestor = parent;
      do {
        if (ancestor == null) {
          throw const LexicalTreeError('getNodesBetween: ancestor is null');
        }
        parentSibling = forwards
            ? ancestor.getNextSibling()
            : ancestor.getPreviousSibling();
        ancestor = ancestor.getParent();
        if (ancestor == null) break;
        if (parentSibling == null && visited.add(ancestor.key)) {
          nodes.add(ancestor);
        }
      } while (parentSibling == null);
      node = parentSibling;
    }
    if (!forwards) {
      return nodes.reversed.toList();
    }
    return nodes;
  }

  // ---------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------

  /// The plain-text projection of this node.
  String getTextContent() => '';

  /// Length of [getTextContent] in UTF-16 code units.
  int getTextContentSize() => getTextContent().length;

  // ---------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------

  /// Serializes this node to its wire-format JSON object.
  ///
  /// Overrides must call `super.exportJson()` and add their own fields; the
  /// base supplies `type`, `version`, and any node state.
  @mustCallSuper
  Map<String, Object?> exportJson() {
    final json = <String, Object?>{'type': type, 'version': 1};
    state?.writeTo(json);
    return json;
  }

  /// Applies a serialized node's fields to this instance.
  ///
  /// Overrides must call `super.updateFromJson(json)` first.
  @mustCallSuper
  void updateFromJson(Map<String, Object?> json) {
    final imported = NodeState.readFrom(json);
    if (imported != null) state = imported;
  }

  // ---------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------

  /// Detaches this node from its parent.
  ///
  /// When [preserveEmptyParent] is false (the default) a parent left empty
  /// that cannot be empty is removed too.
  void remove({bool preserveEmptyParent = false}) {
    $removeNode(this, preserveEmptyParent: preserveEmptyParent);
  }

  /// Replaces this node with [replaceWith], optionally moving children over.
  ///
  /// A selection point that addressed this node is moved onto the
  /// replacement. It takes over this node's place in the tree, so it takes
  /// over its role in the selection too — a caret on the empty paragraph
  /// being turned into a heading belongs on the heading, and a point left
  /// naming a key that is no longer in the document is a lost selection.
  T replace<T extends LexicalNode>(
    T replaceWith, {
    bool includeChildren = false,
  }) {
    errorOnReadOnly();
    final self = getLatest<LexicalNode>();
    final toReplace = replaceWith.getWritable<T>();
    if (identical(toReplace, self) || toReplace.key == self.key) {
      return toReplace;
    }
    final parent = self.getParentOrThrow();
    final prev = self.getPreviousSibling();
    // How many children the replacement already had: this node's children are
    // appended after them, so an element point that addressed child *k* here
    // addresses child *existing + k* there.
    final existingChildren = toReplace is ElementNode
        ? toReplace.childrenSize
        : 0;
    $removeFromParent(toReplace);
    if (prev == null) {
      parent.insertChildAtStart(toReplace);
    } else {
      prev.insertAfter(toReplace);
    }
    if (includeChildren) {
      if (self is! ElementNode || toReplace is! ElementNode) {
        throw const LexicalTreeError(
          'replace: includeChildren requires both nodes to be elements.',
        );
      }
      for (final child in self.children.toList()) {
        toReplace.append(child);
      }
    }
    $moveSelectionPointsToReplacement(
      self,
      toReplace,
      childOffset: includeChildren ? existingChildren : 0,
    );
    $removeFromParent(self);
    return toReplace;
  }

  /// Inserts [nodeToInsert] directly after this node.
  T insertAfter<T extends LexicalNode>(T nodeToInsert) {
    errorOnReadOnly();
    final parent = getParentOrThrow();
    errorOnInsertTextNodeOnRoot(parent, nodeToInsert);
    final writableSelf = getWritable<LexicalNode>();
    final writableInsert = nodeToInsert.getWritable<T>();
    $removeFromParent(writableInsert);
    final writableParent = writableSelf
        .getParentOrThrow()
        .getWritable<ElementNode>();
    final nextSibling = writableSelf.getNextSibling();
    if (nextSibling == null) {
      writableParent.lastKey = writableInsert.key;
    } else {
      nextSibling.getWritable<LexicalNode>().prevKey = writableInsert.key;
    }
    writableInsert
      ..nextKey = writableSelf.nextKey
      ..prevKey = writableSelf.key
      ..parentKey = writableParent.key;
    writableSelf.nextKey = writableInsert.key;
    writableParent.sizeInternal++;
    return nodeToInsert;
  }

  /// Inserts [nodeToInsert] directly before this node.
  T insertBefore<T extends LexicalNode>(T nodeToInsert) {
    errorOnReadOnly();
    final parent = getParentOrThrow();
    errorOnInsertTextNodeOnRoot(parent, nodeToInsert);
    final writableSelf = getWritable<LexicalNode>();
    final writableInsert = nodeToInsert.getWritable<T>();
    $removeFromParent(writableInsert);
    final writableParent = writableSelf
        .getParentOrThrow()
        .getWritable<ElementNode>();
    final prevSibling = writableSelf.getPreviousSibling();
    if (prevSibling == null) {
      writableParent.firstKey = writableInsert.key;
    } else {
      prevSibling.getWritable<LexicalNode>().nextKey = writableInsert.key;
    }
    writableInsert
      ..prevKey = writableSelf.prevKey
      ..nextKey = writableSelf.key
      ..parentKey = writableParent.key;
    writableSelf.prevKey = writableInsert.key;
    writableParent.sizeInternal++;
    return nodeToInsert;
  }

  @override
  String toString() => '$runtimeType($type, key: $_key)';
}
