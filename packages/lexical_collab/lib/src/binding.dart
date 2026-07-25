/// Keeping an editor and a replicated document in step.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:lexical_core/lexical_core.dart';

import 'awareness.dart';
import 'doc.dart';
import 'id.dart';

/// The tag every commit made from a remote change carries.
///
/// The same string upstream uses, so history and any other listener that
/// already knows to ignore collaborative commits keeps working. Undo must not
/// step over someone else's typing.
const String collaborationTag = 'collaboration';

/// How deep a remote document may nest before materialization stops.
const int _maxMaterializeDepth = 128;

/// A peer's selection, resolved into this editor's nodes.
final class CollabSelection {
  /// Records a selection running from [anchor] to [focus].
  const CollabSelection({required this.anchor, required this.focus});

  /// Where the peer's selection started.
  final Point anchor;

  /// Where the peer's caret sits.
  final Point focus;

  /// Whether the peer has a caret rather than a range.
  bool get isCollapsed =>
      anchor.key == focus.key &&
      anchor.offset == focus.offset &&
      anchor.type == focus.type;

  @override
  String toString() => 'CollabSelection($anchor -> $focus)';
}

/// Binds a [LexicalEditor] to a [CollabDoc].
///
/// Local commits become updates on [updates]; updates from peers go into
/// [applyRemoteUpdate] and land in the editor as a commit tagged
/// [collaborationTag].
///
/// Node **keys are never sent**. They are ephemeral by design — regenerated
/// on every import — so they cannot identify anything across peers. This
/// class keeps a local map between keys and the document's stable ids, which
/// is what lets a remote change touch one paragraph without disturbing the
/// caret in another.
final class LexicalCollab {
  /// Binds [editor] to [doc], creating an empty document when none is given.
  ///
  /// The awareness channel defaults to one sharing the document's client id,
  /// which is what lets a peer's caret be matched to the changes it makes.
  factory LexicalCollab({
    required LexicalEditor editor,
    CollabDoc? doc,
    Awareness? awareness,
  }) {
    final document = doc ?? CollabDoc();
    return LexicalCollab._(
      editor,
      document,
      awareness ?? Awareness(clientId: document.clientId),
    );
  }

  LexicalCollab._(this.editor, this.doc, this.awareness) {
    _bind(NodeKey.root, CollabId.root);
  }

  /// The editor being edited.
  final LexicalEditor editor;

  /// The replicated document behind it.
  final CollabDoc doc;

  /// Presence for this session.
  final Awareness awareness;

  final Map<NodeKey, CollabId> _keyToId = <NodeKey, CollabId>{};
  final Map<CollabId, NodeKey> _idToKey = <CollabId, NodeKey>{};
  final StreamController<Uint8List> _updates =
      StreamController<Uint8List>.broadcast();

  Unsubscribe? _unsubscribe;
  bool _started = false;

  /// Updates to send to every peer, one per local commit.
  Stream<Uint8List> get updates => _updates.stream;

  /// Starts syncing.
  ///
  /// An empty document adopts the editor's current content; a document that
  /// already has content replaces it. That asymmetry is deliberate: joining a
  /// session must not push your empty starting document over everyone else's
  /// work, and starting one must not throw away what you had open.
  void start() {
    if (_started) return;
    _started = true;

    if (doc.childrenOf(doc.root).isEmpty) {
      editor.read(() => _captureNode($getRoot(), null));
      final seed = doc.takeUpdate();
      if (seed != null) _updates.add(seed);
    } else {
      _materialize(null);
    }
    _unsubscribe = editor.registerUpdateListener(_onCommit);
  }

  /// Joins a session already in progress from a peer's [state].
  ///
  /// The order matters and this is why the method exists: a peer that calls
  /// [start] before it has the session's document publishes its own empty
  /// starting paragraph into the room, and everyone ends up with an extra
  /// blank block. Take the state first, then start.
  void join(Uint8List state) {
    doc.applyUpdate(state);
    start();
  }

  /// Stops syncing and releases the stream.
  void dispose() {
    _unsubscribe?.call();
    _unsubscribe = null;
    awareness.dispose();
    unawaited(_updates.close());
  }

  /// Applies a peer's update and reflects it in the editor.
  void applyRemoteUpdate(Uint8List update) {
    final changed = doc.applyUpdate(update);
    if (changed.isEmpty) return;
    _materialize(changed);
  }

  /// Everything a peer that has nothing would need.
  Uint8List encodeState() => doc.encodeStateAsUpdate();

  /// This document's state vector, to hand to a peer.
  Uint8List encodeStateVector() => doc.encodeStateVector();

  /// Everything the peer at [stateVector] is missing.
  Uint8List encodeStateSince(Uint8List stateVector) =>
      doc.encodeStateAsUpdate(stateVector);

  // -------------------------------------------------------------------
  // Selection sharing
  // -------------------------------------------------------------------

  /// Publishes the local selection into [awareness].
  ///
  /// Call it from a selection listener. Offsets travel against **stable node
  /// ids**, so a peer's caret stays where they put it even after the text
  /// around it has been re-keyed by an import.
  void publishSelection() {
    final encoded = editor.read(_encodeSelection);
    awareness.setLocalField(awarenessSelectionField, encoded);
  }

  /// Resolves a peer's published selection against this editor.
  ///
  /// Returns `null` when the nodes it names are not present here — which is
  /// normal while an update is still in flight, not an error.
  CollabSelection? resolveSelection(Object? published) {
    if (published is! Map) return null;
    final anchor = _decodePoint(published['a']);
    final focus = _decodePoint(published['f']);
    if (anchor == null || focus == null) return null;
    return CollabSelection(anchor: anchor, focus: focus);
  }

  /// Every peer's selection, keyed by client id, excluding this one.
  Map<int, CollabSelection> get remoteSelections {
    final result = <int, CollabSelection>{};
    for (final entry in awareness.states.entries) {
      if (entry.key == awareness.clientId) continue;
      final selection = resolveSelection(
        entry.value.state[awarenessSelectionField],
      );
      if (selection != null) result[entry.key] = selection;
    }
    return result;
  }

  Map<String, Object?>? _encodeSelection() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return null;
    final anchor = _encodePoint(selection.anchor);
    final focus = _encodePoint(selection.focus);
    if (anchor == null || focus == null) return null;
    return <String, Object?>{'a': anchor, 'f': focus};
  }

  List<Object?>? _encodePoint(Point point) {
    final id = _keyToId[point.key];
    if (id == null) return null;
    return <Object?>[id.client, id.clock, point.offset, point.type.name];
  }

  Point? _decodePoint(Object? encoded) {
    if (encoded is! List || encoded.length < 4) return null;
    final client = encoded[0];
    final clock = encoded[1];
    final offset = encoded[2];
    if (client is! int || clock is! int || offset is! int) return null;
    final key = _idToKey[CollabId(client, clock)];
    if (key == null) return null;
    final type = encoded[3] == PointType.element.name
        ? PointType.element
        : PointType.text;
    return Point(key, offset, type);
  }

  // -------------------------------------------------------------------
  // Editor to document
  // -------------------------------------------------------------------

  void _onCommit(EditorUpdate update) {
    if (update.hasTag(collaborationTag)) return;
    final dirty = update.isFullReconcile
        ? null
        : <NodeKey>{...update.dirtyLeaves, ...update.dirtyElements.keys};
    editor.read(() => _captureNode($getRoot(), dirty));
    final bytes = doc.takeUpdate();
    if (bytes != null) _updates.add(bytes);
  }

  /// Mirrors [node] into the document, pruning subtrees nothing touched.
  ///
  /// A `null` [dirty] set means "everything", which is what a fresh capture
  /// and a full reconcile both need. Otherwise the dirty set is enough to
  /// prune with: the core marks every ancestor of a changed node, so a child
  /// that is absent from it cannot contain a change.
  void _captureNode(LexicalNode node, Set<NodeKey>? dirty) {
    final id = _keyToId[node.key];
    if (id == null) return;
    final touched = dirty == null || dirty.contains(node.key);

    if (node is TextNode) {
      if (touched) {
        _captureProps(id, node);
        _captureText(id, node);
      }
      return;
    }
    if (node is! ElementNode) {
      if (touched) _captureProps(id, node);
      return;
    }
    if (touched) {
      _captureProps(id, node);
      _captureChildren(id, node);
    }
    for (final child in node.children) {
      if (dirty != null && !dirty.contains(child.key)) continue;
      _captureNode(child, dirty);
    }
  }

  void _captureProps(CollabId id, LexicalNode node) {
    final json = node.exportJson()
      ..remove('children')
      ..remove('text')
      ..remove('type');
    final current = doc.propsOf(id);
    for (final entry in json.entries) {
      if (_jsonEquals(current[entry.key], entry.value)) continue;
      doc.setProperty(id, entry.key, entry.value);
    }
  }

  /// Turns a changed text node into one delete and one insert.
  ///
  /// Diffing by common prefix and suffix rather than character by character
  /// is what keeps a keystroke one operation. It also keeps the *right*
  /// characters: replacing the whole run would tombstone text a peer may have
  /// their caret in, and their caret would jump to the start of the word.
  void _captureText(CollabId id, TextNode node) {
    final before = doc.textOf(id);
    final after = node.getTextContent();
    if (before == after) return;

    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }

    final removed = before.length - prefix - suffix;
    if (removed > 0) doc.deleteRange(id, prefix, removed);
    final inserted = after.substring(prefix, after.length - suffix);
    if (inserted.isNotEmpty) doc.insertText(id, prefix, inserted);
  }

  void _captureChildren(CollabId id, ElementNode element) {
    final target = element.children.toList();
    final targetKeys = target.map((node) => node.key).toSet();

    for (final childId in doc.childrenOf(id)) {
      final key = _idToKey[childId];
      if (key == null || !targetKeys.contains(key)) doc.detachNode(id, childId);
    }

    for (var index = 0; index < target.length; index++) {
      final child = target[index];
      final present = doc.childrenOf(id);
      if (index < present.length && _idToKey[present[index]] == child.key) {
        continue;
      }

      final existing = _keyToId[child.key];
      if (existing != null && doc.has(existing)) {
        // Already somewhere in the document: a move, not a new node, so the
        // reference is re-hung and the whole subtree comes with it.
        if (present.contains(existing)) doc.detachNode(id, existing);
        doc.attachNode(id, index, existing);
        continue;
      }

      final created = doc.insertNode(id, index, child.type);
      _bind(child.key, created);
      _captureNode(child, null);
    }
  }

  // -------------------------------------------------------------------
  // Document to editor
  // -------------------------------------------------------------------

  void _materialize(Set<CollabId>? changed) {
    final affected = changed == null ? null : _withAncestors(changed);
    final snapshot = editor.read(_captureSelectionSnapshot);
    editor.update(
      () {
        _applyNode(doc.root, $getRoot(), affected, <CollabId>{}, 0);
        _restoreSelection(snapshot);
      },
      discrete: true,
      tags: {collaborationTag},
    );
  }

  Set<CollabId> _withAncestors(Set<CollabId> ids) {
    final affected = <CollabId>{};
    for (final id in ids) {
      var current = id;
      while (affected.add(current)) {
        final parent = doc.parentOf(current);
        if (parent == null) break;
        current = parent;
      }
    }
    return affected;
  }

  void _applyNode(
    CollabId id,
    LexicalNode node,
    Set<CollabId>? affected,
    Set<CollabId> seen,
    int depth,
  ) {
    if (depth > _maxMaterializeDepth) return;
    if (affected != null && !affected.contains(id)) return;

    final props = doc.propsOf(id);
    // Written onto a writable clone rather than the committed node: the
    // committed state is frozen, and `updateFromJson` assigns fields directly
    // because its usual caller is the importer, working on a fresh node.
    final writable = node.getWritable<LexicalNode>();

    if (writable is TextNode) {
      writable.updateFromJson(<String, Object?>{
        ...props,
        'text': doc.textOf(id),
        'type': writable.type,
      });
      return;
    }
    writable.updateFromJson(<String, Object?>{...props, 'type': writable.type});
    if (writable is! ElementNode) return;

    final pairs = <(CollabId, LexicalNode)>[];
    for (final childId in doc.childrenOf(id)) {
      // One node cannot be in two places. Concurrent moves of the same node
      // can produce two live references to it; the first in document order
      // wins, which is the same choice on every peer.
      if (!seen.add(childId)) continue;
      final child = _resolveNode(childId);
      if (child == null) continue;
      pairs.add((childId, child));
    }

    final current = writable.children.toList();
    final differs =
        current.length != pairs.length ||
        [
          for (var i = 0; i < current.length; i++)
            current[i].key != pairs[i].$2.key,
        ].contains(true);
    if (differs) {
      writable.splice(0, writable.childrenSize, [
        for (final pair in pairs) pair.$2,
      ]);
    }

    for (final (childId, child) in pairs) {
      _applyNode(childId, child, affected, seen, depth + 1);
    }
  }

  /// The Lexical node for [id], creating one when it is new here.
  ///
  /// Returns `null` for a type this build has never registered. The node is
  /// **not** lost: it stays in the replicated document and appears the moment
  /// the application ships the package that defines it. Inventing a
  /// substitute node would be the version-skew failure that destroys content.
  LexicalNode? _resolveNode(CollabId id) {
    final key = _idToKey[id];
    if (key != null) {
      final existing = $getNodeByKey(key);
      if (existing != null) return existing;
      _idToKey.remove(id);
      _keyToId.remove(key);
    }
    final type = doc.typeOf(id);
    if (type == null) return null;
    final spec = editor.registry.specFor(type);
    if (spec == null) return null;
    final node = $applyNodeReplacement(spec.instantiate());
    _bind(node.key, id);
    return node;
  }

  ({Point anchor, Point focus, String anchorText, String focusText})?
  _captureSelectionSnapshot() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return null;
    String textOf(Point point) {
      final node = point.getNode();
      return node is TextNode ? node.getTextContent() : '';
    }

    return (
      anchor: Point(
        selection.anchor.key,
        selection.anchor.offset,
        selection.anchor.type,
      ),
      focus: Point(
        selection.focus.key,
        selection.focus.offset,
        selection.focus.type,
      ),
      anchorText: textOf(selection.anchor),
      focusText: textOf(selection.focus),
    );
  }

  void _restoreSelection(
    ({Point anchor, Point focus, String anchorText, String focusText})?
    snapshot,
  ) {
    if (snapshot == null) return;
    final selection = $getSelection();
    if (selection is! RangeSelection) return;

    Point? adjust(Point point, String before) {
      final node = $getNodeByKey(point.key);
      if (node == null || !node.isAttached) return null;
      if (point.type != PointType.text || node is! TextNode) return point;
      return Point(
        point.key,
        _transformOffset(before, node.getTextContent(), point.offset),
        point.type,
      );
    }

    final anchor = adjust(snapshot.anchor, snapshot.anchorText);
    final focus = adjust(snapshot.focus, snapshot.focusText);
    if (anchor == null || focus == null) return;
    selection.anchor.set(anchor.key, anchor.offset, anchor.type);
    selection.focus.set(focus.key, focus.offset, focus.type);
  }

  /// Where [offset] ends up after [before] became [after].
  ///
  /// Text typed ahead of the caret pushes it along; text typed behind it
  /// leaves it alone. An edit that spans the caret has no right answer, and
  /// the start of the changed region is the least surprising of the wrong
  /// ones.
  static int _transformOffset(String before, String after, int offset) {
    if (before == after) return offset;
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    if (offset <= prefix) return offset;
    if (offset >= before.length - suffix) {
      return offset + after.length - before.length;
    }
    return prefix;
  }

  void _bind(NodeKey key, CollabId id) {
    _keyToId[key] = id;
    _idToKey[id] = key;
  }

  static bool _jsonEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_jsonEquals(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
