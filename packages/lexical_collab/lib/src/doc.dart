/// The replicated document.
///
/// A tree of nodes, each holding one sequence — a text node's characters, an
/// element's children — plus a map of properties. Three merge strategies, one
/// per kind of data, because no single one is right for all three:
///
/// * **Sequences use RGA.** Every character carries an id and the id of the
///   character it was typed after; document order is the pre-order walk of
///   that causal tree, siblings sorted by descending timestamp. Deletes leave
///   a tombstone, so an id stays meaningful after the text is gone.
/// * **Properties use last-writer-wins**, tie-broken by client. A bold toggle
///   is not mergeable, and pretending otherwise produces text that is
///   half-bold in a way neither peer asked for.
/// * **The tree is insert and delete only.** Moving a node re-references it,
///   so the node keeps its subtree; two peers moving the same node at once
///   resolve to the later move, on every peer alike.
///
/// ## Two numbers, not one
///
/// Every operation carries a per-client **sequence number** and a **Lamport
/// timestamp**, and they cannot be the same number:
///
/// * The sequence number identifies the operation. It counts only this
///   client's own work, with no gaps, which is what lets a peer describe
///   everything it holds as one integer per client — the state vector, and
///   the whole of the sync protocol.
/// * The timestamp orders it. It advances past every id ever seen, which
///   gives the invariant the merge rests on: **an item's timestamp is always
///   greater than that of the item it was inserted after**. It is what lets
///   the insertion scan — walk right while the neighbour outranks us — skip
///   whole subtrees without knowing where they end.
///
/// Trying to serve both purposes with one counter is the mistake worth
/// naming: a clock that jumps to stay ahead of remote work leaves gaps, and a
/// state vector cannot then tell a gap from the end.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'codec.dart';
import 'id.dart';

const List<int> _magic = [0x4c, 0x58, 0x43, 0x31];

/// Bounds applied while decoding an update.
///
/// An update arrives over the network from a peer that may be hostile. The
/// shape that hurts is not a large document but an absurd count — a header
/// claiming a billion items would allocate until the process dies before a
/// single byte of content is read.
final class CollabUpdateLimits {
  /// Creates limits.
  const CollabUpdateLimits({
    this.maxItems = 1 << 20,
    this.maxProperties = 1 << 20,
    this.maxTextLength = 1 << 20,
    this.maxDeleteRanges = 1 << 20,
  });

  /// The default bounds.
  static const CollabUpdateLimits defaults = CollabUpdateLimits();

  /// Greatest number of sequence items in one update.
  final int maxItems;

  /// Greatest number of property assignments in one update.
  final int maxProperties;

  /// Greatest length of one text run, in UTF-16 code units.
  final int maxTextLength;

  /// Greatest number of delete ranges in one update.
  final int maxDeleteRanges;
}

/// One run of a sequence: characters, or one child reference.
final class _Item {
  _Item({
    required this.id,
    required this.owner,
    required this.length,
    required this.lamport,
    this.originId,
    this.text,
    this.nodeId,
    this.nodeType,
    this.deleted = false,
  });

  /// The id of this run's first unit.
  final CollabId id;

  /// The node whose sequence holds it.
  final CollabId owner;

  /// How many ids the run covers.
  int length;

  /// When it was made, in logical time.
  final int lamport;

  /// The last id of the run this one was inserted after.
  final CollabId? originId;

  /// The characters, for a text run.
  String? text;

  /// The referenced node, for a child reference.
  final CollabId? nodeId;

  /// The referenced node's type, when this reference creates it.
  final String? nodeType;

  /// Whether the run has been removed.
  bool deleted;

  /// Whether this is a child reference rather than text.
  bool get isNode => nodeId != null;

  /// The id of the run's last unit.
  CollabId get lastId => CollabId(id.client, id.clock + length - 1);

  /// Whether this item sorts after [other] in logical time.
  bool outranks(_Item other) => lamport != other.lamport
      ? lamport > other.lamport
      : id.client > other.id.client;
}

final class _Register {
  _Register(this.value, this.stamp, this.lamport);

  Object? value;
  CollabId stamp;
  int lamport;

  bool outranks(_Register other) => lamport != other.lamport
      ? lamport > other.lamport
      : stamp.client > other.stamp.client;
}

final class _Node {
  _Node(this.id, this.type);

  final CollabId id;
  String type;
  final List<_Item> items = <_Item>[];
  final Map<String, _Register> props = <String, _Register>{};
}

/// A document that merges with any other copy of itself.
///
/// Transport-agnostic on purpose: it produces and consumes byte strings, and
/// knows nothing about sockets, servers or rooms. Hand [encodeStateVector] to
/// a peer, hand its reply to [applyUpdate], and the two documents converge —
/// whatever order the bytes arrive in, and however many times.
final class CollabDoc {
  /// Creates an empty document for [clientId].
  ///
  /// The client id must be unique among the peers sharing a document; a
  /// collision makes two peers claim the same identities and is the one
  /// failure this design cannot detect. Random by default, from a range wide
  /// enough that a collision is not a practical concern.
  CollabDoc({int? clientId, this.limits = CollabUpdateLimits.defaults})
    : clientId = clientId ?? _randomClientId() {
    _nodes[CollabId.root] = _Node(CollabId.root, 'root');
  }

  /// This peer's identity.
  final int clientId;

  /// Bounds applied while decoding.
  final CollabUpdateLimits limits;

  final Map<CollabId, _Node> _nodes = <CollabId, _Node>{};
  final Map<int, List<_Item>> _byClient = <int, List<_Item>>{};
  final Map<CollabId, List<_Item>> _refsTo = <CollabId, List<_Item>>{};
  final Map<int, List<int>> _covered = <int, List<int>>{};
  final List<_Item> _pendingItems = <_Item>[];
  final List<_PendingProp> _pendingProps = <_PendingProp>[];
  final List<(int, int, int)> _pendingDeletes = <(int, int, int)>[];
  final List<(int, int, int)> _localDeletes = <(int, int, int)>[];
  final Map<int, int> _sentSeq = <int, int>{};
  final Set<CollabId> _changed = <CollabId>{};

  int _seq = 0;
  int _lamport = 0;

  static int _randomClientId() => Random().nextInt(1 << 31) + 1;

  /// The root node's id.
  CollabId get root => CollabId.root;

  /// Whether [id] names a node this document knows.
  bool has(CollabId id) => _nodes.containsKey(id);

  /// The node type registered for [id], or `null`.
  String? typeOf(CollabId id) => _nodes[id]?.type;

  /// The node [id] currently hangs under, or `null` when it hangs nowhere.
  CollabId? parentOf(CollabId id) => _winningRef(id)?.owner;

  /// The visible text of the text node [id].
  String textOf(CollabId id) {
    final node = _nodes[id];
    if (node == null) return '';
    final buffer = StringBuffer();
    for (final item in node.items) {
      if (item.deleted || item.text == null) continue;
      buffer.write(item.text);
    }
    return buffer.toString();
  }

  /// The visible children of the element node [id], in order.
  ///
  /// A node with live references from two parents — which two peers moving it
  /// at the same time produce — appears under exactly one of them: the one
  /// whose reference was made later. Every peer computes that from the same
  /// timestamps, so every peer picks the same parent.
  List<CollabId> childrenOf(CollabId id) {
    final node = _nodes[id];
    if (node == null) return const [];
    final children = <CollabId>[];
    for (final item in node.items) {
      final child = item.nodeId;
      if (item.deleted || child == null) continue;
      if (!_nodes.containsKey(child)) continue;
      if (!identical(_winningRef(child), item)) continue;
      children.add(child);
    }
    return children;
  }

  /// The properties of [id].
  Map<String, Object?> propsOf(CollabId id) {
    final node = _nodes[id];
    if (node == null) return const {};
    return <String, Object?>{
      for (final entry in node.props.entries) entry.key: entry.value.value,
    };
  }

  // -------------------------------------------------------------------
  // Local edits
  // -------------------------------------------------------------------

  /// Inserts [text] at visible [index] of the text node [nodeId].
  void insertText(CollabId nodeId, int index, String text) {
    if (text.isEmpty) return;
    final node = _nodes[nodeId];
    if (node == null) return;
    final origin = _originForIndex(node, index);

    // Typing one character at a time would otherwise cost one item per
    // keystroke forever. A run continuing our own most recent allocation is
    // extended in place instead, so the item count follows typing *runs*. The
    // ids handed out are the ones separate items would have had, so nothing
    // about the merge changes.
    if (origin != null) {
      final left = _find(origin);
      if (left != null &&
          !left.deleted &&
          left.text != null &&
          left.owner == nodeId &&
          left.id.client == clientId &&
          left.lastId == origin &&
          left.id.clock + left.length == _seq) {
        left
          ..text = left.text! + text
          ..length += text.length;
        _cover(clientId, _seq, text.length);
        _seq += text.length;
        _changed.add(nodeId);
        return;
      }
    }

    _integrate(
      _Item(
        id: _nextId(text.length),
        owner: nodeId,
        length: text.length,
        lamport: _nextLamport(),
        originId: origin,
        text: text,
      ),
    );
  }

  /// Removes [length] units from visible [index] of [nodeId]'s sequence.
  void deleteRange(CollabId nodeId, int index, int length) {
    final node = _nodes[nodeId];
    if (node == null || length <= 0) return;

    var remaining = length;
    var position = 0;
    var cursor = index;
    var i = 0;
    while (i < node.items.length && remaining > 0) {
      final item = node.items[i];
      if (item.deleted) {
        i++;
        continue;
      }
      final start = position;
      if (start + item.length <= cursor) {
        position = start + item.length;
        i++;
        continue;
      }
      final local = cursor - start;
      if (local > 0) {
        _splitAt(item, local);
        position = start + local;
        i++;
        continue;
      }
      final take = item.length < remaining ? item.length : remaining;
      if (take < item.length) _splitAt(item, take);
      _markDeleted(item, local: true);
      remaining -= take;
      cursor += take;
      position += take;
      i++;
    }
  }

  /// Creates a child node of [type] at [index] of [parentId], and returns it.
  CollabId insertNode(CollabId parentId, int index, String type) {
    final parent = _nodes[parentId];
    if (parent == null) throw StateError('unknown parent $parentId');
    final id = _nextId(1);
    _integrate(
      _Item(
        id: id,
        owner: parentId,
        length: 1,
        lamport: _nextLamport(),
        originId: _originForIndex(parent, index),
        nodeId: id,
        nodeType: type,
      ),
    );
    return id;
  }

  /// Re-references the existing node [nodeId] at [index] of [parentId].
  ///
  /// This is how a move is expressed: [detachNode] from the old parent, then
  /// this. The node keeps its identity, and so keeps its whole subtree.
  void attachNode(CollabId parentId, int index, CollabId nodeId) {
    final parent = _nodes[parentId];
    if (parent == null) return;
    _integrate(
      _Item(
        id: _nextId(1),
        owner: parentId,
        length: 1,
        lamport: _nextLamport(),
        originId: _originForIndex(parent, index),
        nodeId: nodeId,
      ),
    );
  }

  /// Removes the reference to [nodeId] from [parentId].
  void detachNode(CollabId parentId, CollabId nodeId) {
    final parent = _nodes[parentId];
    if (parent == null) return;
    for (final item in parent.items) {
      if (item.deleted || item.nodeId != nodeId) continue;
      _markDeleted(item, local: true);
    }
  }

  /// Sets the property [key] of [nodeId].
  void setProperty(CollabId nodeId, String key, Object? value) {
    final node = _nodes[nodeId];
    if (node == null) return;
    node.props[key] = _Register(value, _nextId(1), _nextLamport());
    _changed.add(nodeId);
  }

  /// The nodes touched since this was last called.
  Set<CollabId> takeChanged() {
    final changed = <CollabId>{..._changed};
    _changed.clear();
    return changed;
  }

  // -------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------

  /// Encodes how much of every peer's work this document holds.
  Uint8List encodeStateVector() {
    final writer = ByteWriter();
    final clients = _covered.keys.toList();
    writer.uint(clients.length);
    for (final client in clients) {
      writer
        ..uint(client)
        ..uint(_coveredEnd(client));
    }
    return writer.toBytes();
  }

  /// Everything produced since this was last called, or `null` for nothing.
  ///
  /// This is the message a live session broadcasts after each local edit. It
  /// suits a relay — a peer that hears it will not hear it again — and pairs
  /// with [encodeStateAsUpdate] for anyone catching up. Broadcasting the full
  /// state after every keystroke would also work, since the merge is
  /// idempotent, but the delete set alone grows for the document's lifetime.
  Uint8List? takeUpdate() {
    final deletes = <int, List<(int, int)>>{};
    for (final (client, clock, length) in _localDeletes) {
      (deletes[client] ??= <(int, int)>[]).add((clock, length));
    }
    _localDeletes.clear();

    final update = _encode(StateVector(_sentSeq), deletes);
    _markSent();
    return update;
  }

  /// Encodes everything a peer at [stateVector] is missing.
  ///
  /// Pass `null` for a peer that has nothing, which is what an initial sync
  /// is. The result is idempotent: applying it twice changes nothing.
  Uint8List encodeStateAsUpdate([Uint8List? stateVector]) => _encode(
    stateVector == null ? StateVector() : _decodeStateVector(stateVector),
    _deleteSet(),
    allowEmpty: true,
  )!;

  /// Applies [update] and returns the nodes it changed.
  ///
  /// Order-independent: an update whose dependencies have not arrived is held
  /// and retried after every later update, so a transport that reorders or
  /// duplicates messages still converges.
  Set<CollabId> applyUpdate(Uint8List update) {
    _changed.clear();
    final reader = ByteReader(update);
    for (final byte in _magic) {
      if (reader.byte() != byte) {
        throw const CollabDecodeException('not a lexical_collab update');
      }
    }

    final incoming = <_Item>[];
    final itemCount = reader.uint();
    if (itemCount > limits.maxItems) {
      throw const CollabDecodeException('item count over the limit');
    }
    for (var i = 0; i < itemCount; i++) {
      incoming.add(_readItem(reader));
    }
    _integrateAll(incoming);

    final propCount = reader.uint();
    if (propCount > limits.maxProperties) {
      throw const CollabDecodeException('property count over the limit');
    }
    final props = <_PendingProp>[];
    for (var i = 0; i < propCount; i++) {
      final node = CollabId(reader.uint(), reader.uint());
      final key = reader.string();
      final stamp = CollabId(reader.uint(), reader.uint());
      final lamport = reader.uint();
      final value = _decodeValue(reader.string());
      _observeLamport(lamport);
      props.add(_PendingProp(node, key, stamp, lamport, value));
    }
    _applyProps([..._pendingProps, ...props]);

    final clientCount = reader.uint();
    final deletes = <(int, int, int)>[];
    for (var i = 0; i < clientCount; i++) {
      final client = reader.uint();
      final rangeCount = reader.uint();
      if (rangeCount > limits.maxDeleteRanges) {
        throw const CollabDecodeException('delete range count over the limit');
      }
      for (var r = 0; r < rangeCount; r++) {
        deletes.add((client, reader.uint(), reader.uint()));
      }
    }
    final retry = [..._pendingDeletes, ...deletes];
    _pendingDeletes.clear();
    for (final (client, clock, length) in retry) {
      _deleteIds(client, clock, length);
    }

    // What a peer has just told us, it plainly has. Marking it sent keeps the
    // next local broadcast from echoing everyone's work back at them.
    _markSent();
    return <CollabId>{..._changed};
  }

  Uint8List? _encode(
    StateVector known,
    Map<int, List<(int, int)>> deletes, {
    bool allowEmpty = false,
  }) {
    final items = <_Item>[];
    final props = <(CollabId, String, _Register)>[];
    for (final node in _nodes.values) {
      for (final item in node.items) {
        if (item.id.clock + item.length <= known[item.id.client]) continue;
        items.add(item);
      }
      for (final entry in node.props.entries) {
        final register = entry.value;
        if (register.stamp.clock < known[register.stamp.client]) continue;
        props.add((node.id, entry.key, register));
      }
    }
    if (!allowEmpty && items.isEmpty && props.isEmpty && deletes.isEmpty) {
      return null;
    }
    // Ascending logical time is what makes the receiver's job easy: an item's
    // origin and its owning node were both made earlier, so they are always
    // already integrated by the time it arrives.
    items.sort((a, b) {
      final byTime = a.lamport.compareTo(b.lamport);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });

    final writer = ByteWriter();
    for (final byte in _magic) {
      writer.byte(byte);
    }

    writer.uint(items.length);
    for (final item in items) {
      final skip = known[item.id.client] - item.id.clock;
      _writeItem(writer, item, skip > 0 ? skip : 0);
    }

    writer.uint(props.length);
    for (final (nodeId, key, register) in props) {
      writer
        ..uint(nodeId.client)
        ..uint(nodeId.clock)
        ..string(key)
        ..uint(register.stamp.client)
        ..uint(register.stamp.clock)
        ..uint(register.lamport)
        ..string(jsonEncode(register.value));
    }

    writer.uint(deletes.length);
    for (final entry in deletes.entries) {
      writer
        ..uint(entry.key)
        ..uint(entry.value.length);
      for (final (clock, length) in entry.value) {
        writer
          ..uint(clock)
          ..uint(length);
      }
    }
    return writer.toBytes();
  }

  // -------------------------------------------------------------------
  // Integration
  // -------------------------------------------------------------------

  void _integrateAll(List<_Item> incoming) {
    var pending = <_Item>[..._pendingItems, ...incoming];
    _pendingItems.clear();
    var progressed = true;
    while (progressed && pending.isNotEmpty) {
      progressed = false;
      final next = <_Item>[];
      for (final item in pending) {
        final trimmed = _trim(item);
        if (trimmed == null) {
          progressed = true;
          continue;
        }
        if (_integrate(trimmed)) {
          progressed = true;
        } else {
          next.add(trimmed);
        }
      }
      pending = next;
    }
    _pendingItems.addAll(pending);
  }

  bool _integrate(_Item item) {
    final owner = _nodes[item.owner];
    if (owner == null) return false;
    final nodeId = item.nodeId;
    if (nodeId != null &&
        item.nodeType == null &&
        !_nodes.containsKey(nodeId)) {
      // A reference to a node whose creating item has not arrived.
      return false;
    }

    var index = 0;
    final origin = item.originId;
    if (origin != null) {
      final left = _itemEndingAt(origin);
      if (left == null) return false;
      final at = owner.items.indexOf(left);
      if (at < 0) return false;
      index = at + 1;
    }
    // Walk right past everything that outranks this item. A higher-ranked
    // neighbour's descendants are themselves higher — that is the Lamport
    // invariant — so a whole subtree is skipped without being examined.
    while (index < owner.items.length && owner.items[index].outranks(item)) {
      index++;
    }

    owner.items.insert(index, item);
    _register(item);

    if (nodeId != null) {
      (_refsTo[nodeId] ??= <_Item>[]).add(item);
      _nodes[nodeId] ??= _Node(nodeId, item.nodeType!);
      _changed.add(nodeId);
    }
    _changed.add(item.owner);
    return true;
  }

  void _applyProps(List<_PendingProp> props) {
    _pendingProps.clear();
    for (final pending in props) {
      final node = _nodes[pending.node];
      if (node == null) {
        _pendingProps.add(pending);
        continue;
      }
      final incoming = _Register(pending.value, pending.stamp, pending.lamport);
      final existing = node.props[pending.key];
      if (existing != null && !incoming.outranks(existing)) continue;
      node.props[pending.key] = incoming;
      _cover(pending.stamp.client, pending.stamp.clock, 1);
      _changed.add(pending.node);
    }
  }

  /// Drops the part of [item] this document already holds.
  _Item? _trim(_Item item) {
    var current = item;
    while (true) {
      final known = _find(current.id);
      if (known == null) return current;
      final skip = known.id.clock + known.length - current.id.clock;
      if (skip >= current.length) return null;
      current = _slice(current, skip);
    }
  }

  _Item _slice(_Item item, int skip) => _Item(
    id: item.id + skip,
    owner: item.owner,
    length: item.length - skip,
    lamport: item.lamport,
    originId: item.id + (skip - 1),
    text: item.text?.substring(skip),
    nodeId: item.nodeId,
    nodeType: item.nodeType,
  );

  _Item _splitAt(_Item item, int offset) {
    final node = _nodes[item.owner]!;
    final right = _Item(
      id: item.id + offset,
      owner: item.owner,
      length: item.length - offset,
      lamport: item.lamport,
      originId: item.id + (offset - 1),
      text: item.text?.substring(offset),
      deleted: item.deleted,
    );
    item.length = offset;
    final text = item.text;
    if (text != null) item.text = text.substring(0, offset);
    node.items.insert(node.items.indexOf(item) + 1, right);
    _register(right);
    return right;
  }

  /// The item whose last id is [id], splitting one open if it is not.
  _Item? _itemEndingAt(CollabId id) {
    final item = _find(id);
    if (item == null) return null;
    final offset = id.clock - item.id.clock;
    if (offset + 1 == item.length) return item;
    _splitAt(item, offset + 1);
    return item;
  }

  CollabId? _originForIndex(_Node node, int index) {
    if (index <= 0) return null;
    var remaining = index;
    for (final item in node.items) {
      if (item.deleted) continue;
      if (remaining <= item.length) return item.id + (remaining - 1);
      remaining -= item.length;
    }
    for (final item in node.items.reversed) {
      if (!item.deleted) return item.lastId;
    }
    return null;
  }

  /// The live reference that decides where a node hangs.
  ///
  /// Normally there is exactly one. Two peers moving the same node at the
  /// same time make two, and the later one wins — "whoever moved it last"
  /// being both the rule a person would expect and one every peer computes
  /// identically.
  _Item? _winningRef(CollabId nodeId) {
    _Item? best;
    for (final item in _refsTo[nodeId] ?? const <_Item>[]) {
      if (item.deleted) continue;
      if (best == null || item.outranks(best)) best = item;
    }
    return best;
  }

  /// Tombstones [item], recording it for the next outgoing update.
  ///
  /// Only local deletions are recorded. Echoing a peer's tombstones back at
  /// everyone would double the traffic of every delete in a room, and they
  /// are already in the full state anyone syncing from scratch receives.
  void _markDeleted(_Item item, {required bool local}) {
    if (item.deleted) return;
    item.deleted = true;
    if (local) _localDeletes.add((item.id.client, item.id.clock, item.length));
    _changed.add(item.owner);
    final nodeId = item.nodeId;
    if (nodeId != null) _changed.add(nodeId);
  }

  void _deleteIds(int client, int clock, int length) {
    var at = clock;
    var remaining = length;
    while (remaining > 0) {
      final found = _find(CollabId(client, at));
      if (found == null) {
        _pendingDeletes.add((client, at, remaining));
        return;
      }
      var target = found;
      final offset = at - found.id.clock;
      if (offset > 0) target = _splitAt(found, offset);
      if (target.length > remaining) _splitAt(target, remaining);
      _markDeleted(target, local: false);
      at += target.length;
      remaining -= target.length;
    }
  }

  Map<int, List<(int, int)>> _deleteSet() {
    final ranges = <int, List<(int, int)>>{};
    for (final entry in _byClient.entries) {
      final merged = <(int, int)>[];
      for (final item in entry.value) {
        if (!item.deleted) continue;
        if (merged.isNotEmpty) {
          final (start, length) = merged.last;
          if (start + length == item.id.clock) {
            merged[merged.length - 1] = (start, length + item.length);
            continue;
          }
        }
        merged.add((item.id.clock, item.length));
      }
      if (merged.isNotEmpty) ranges[entry.key] = merged;
    }
    return ranges;
  }

  // -------------------------------------------------------------------
  // The struct store
  // -------------------------------------------------------------------

  void _register(_Item item) {
    final list = _byClient.putIfAbsent(item.id.client, () => <_Item>[]);
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].id.clock < item.id.clock) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    list.insert(low, item);
    _cover(item.id.client, item.id.clock, item.length);
    _observeLamport(item.lamport);
  }

  _Item? _find(CollabId id) {
    final list = _byClient[id.client];
    if (list == null) return null;
    var low = 0;
    var high = list.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final item = list[mid];
      if (id.clock < item.id.clock) {
        high = mid - 1;
      } else if (id.clock >= item.id.clock + item.length) {
        low = mid + 1;
      } else {
        return item;
      }
    }
    return null;
  }

  /// Advances logical time past [lamport], whoever produced it.
  ///
  /// The one line the merge depends on. Anything made from here on outranks
  /// everything already seen, which is what lets the insertion scan read
  /// "higher rank" as "made later".
  void _observeLamport(int lamport) {
    if (lamport >= _lamport) _lamport = lamport + 1;
  }

  int _nextLamport() => _lamport++;

  CollabId _nextId(int length) {
    final id = CollabId(clientId, _seq);
    _seq += length;
    _cover(clientId, id.clock, length);
    return id;
  }

  /// Records that `[start, start + length)` of [client] is held.
  void _cover(int client, int start, int length) {
    final spans = _covered.putIfAbsent(client, () => <int>[]);
    var from = start;
    var to = start + length;
    final merged = <int>[];
    var i = 0;
    while (i < spans.length && spans[i + 1] < from) {
      merged
        ..add(spans[i])
        ..add(spans[i + 1]);
      i += 2;
    }
    while (i < spans.length && spans[i] <= to) {
      if (spans[i] < from) from = spans[i];
      if (spans[i + 1] > to) to = spans[i + 1];
      i += 2;
    }
    merged
      ..add(from)
      ..add(to);
    while (i < spans.length) {
      merged
        ..add(spans[i])
        ..add(spans[i + 1]);
      i += 2;
    }
    _covered[client] = merged;
  }

  /// How far [client]'s work is held **without a gap**.
  ///
  /// The state vector cannot describe a gap, so it must not step over one:
  /// claiming past a missing item is claiming that nobody needs to send it.
  int _coveredEnd(int client) {
    final spans = _covered[client];
    if (spans == null || spans.isEmpty || spans[0] != 0) return 0;
    return spans[1];
  }

  void _markSent() {
    for (final client in _covered.keys) {
      final end = _coveredEnd(client);
      if (end > (_sentSeq[client] ?? 0)) _sentSeq[client] = end;
    }
  }

  StateVector _decodeStateVector(Uint8List bytes) {
    final reader = ByteReader(bytes);
    final vector = StateVector();
    final count = reader.uint();
    for (var i = 0; i < count; i++) {
      vector.observe(reader.uint(), reader.uint());
    }
    return vector;
  }

  // -------------------------------------------------------------------
  // Item wire form
  // -------------------------------------------------------------------

  void _writeItem(ByteWriter writer, _Item item, int skip) {
    final emitted = skip > 0 ? _slice(item, skip) : item;
    final origin = emitted.originId;
    writer
      ..uint(emitted.id.client)
      ..uint(emitted.id.clock)
      ..uint(emitted.length)
      ..uint(emitted.lamport)
      ..uint(emitted.owner.client)
      ..uint(emitted.owner.clock)
      ..byte(
        (origin != null ? 1 : 0) |
            (emitted.isNode ? 2 : 0) |
            (emitted.nodeType != null ? 4 : 0),
      );
    if (origin != null) {
      writer
        ..uint(origin.client)
        ..uint(origin.clock);
    }
    final nodeId = emitted.nodeId;
    if (nodeId != null) {
      writer
        ..uint(nodeId.client)
        ..uint(nodeId.clock);
      final type = emitted.nodeType;
      if (type != null) writer.string(type);
    } else {
      writer.string(emitted.text ?? '');
    }
  }

  _Item _readItem(ByteReader reader) {
    final id = CollabId(reader.uint(), reader.uint());
    final length = reader.uint();
    if (length < 1 || length > limits.maxTextLength) {
      throw const CollabDecodeException('item length out of range');
    }
    final lamport = reader.uint();
    final owner = CollabId(reader.uint(), reader.uint());
    final flags = reader.byte();
    final origin = (flags & 1) != 0
        ? CollabId(reader.uint(), reader.uint())
        : null;

    CollabId? nodeId;
    String? nodeType;
    String? text;
    if ((flags & 2) != 0) {
      nodeId = CollabId(reader.uint(), reader.uint());
      if ((flags & 4) != 0) nodeType = reader.string();
      if (length != 1) {
        throw const CollabDecodeException('a node reference spans one id');
      }
    } else {
      text = reader.string();
      if (text.length != length) {
        throw const CollabDecodeException('text length disagrees with the id');
      }
    }

    _observeLamport(lamport);
    return _Item(
      id: id,
      owner: owner,
      length: length,
      lamport: lamport,
      originId: origin,
      text: text,
      nodeId: nodeId,
      nodeType: nodeType,
    );
  }

  Object? _decodeValue(String encoded) {
    try {
      return jsonDecode(encoded);
    } on FormatException {
      throw const CollabDecodeException('malformed property value');
    }
  }
}

final class _PendingProp {
  const _PendingProp(this.node, this.key, this.stamp, this.lamport, this.value);

  final CollabId node;
  final String key;
  final CollabId stamp;
  final int lamport;
  final Object? value;
}
