/// Identity and causality.
library;

import 'package:meta/meta.dart';

/// The identity of one operation, and of everything it created.
///
/// A pair of the originating client and that client's logical clock. The pair
/// is what makes concurrent work mergeable: two peers editing at the same
/// wall-clock instant still produce different, totally ordered identifiers,
/// with no coordination and no server.
///
/// [clock] is a **Lamport clock** — it advances past every id ever seen, not
/// only past this client's own. That is what gives the one invariant the
/// merge algorithm rests on: *an item's id is always greater than the id of
/// the item it was inserted after*. Without it, an insert made after
/// receiving a batch of remote work could carry a smaller id than the text it
/// follows, and two peers would order the same document differently.
@immutable
final class CollabId implements Comparable<CollabId> {
  /// Creates an id for [client] at [clock].
  const CollabId(this.client, this.clock);

  /// The document root, which exists before any operation.
  static const CollabId root = CollabId(0, 0);

  /// Which peer produced it.
  final int client;

  /// That peer's logical clock at the time.
  final int clock;

  /// The id [offset] positions further along the same operation's run.
  CollabId operator +(int offset) => CollabId(client, clock + offset);

  /// Total order: by clock, then by client to break ties.
  @override
  int compareTo(CollabId other) {
    final byClock = clock.compareTo(other.clock);
    return byClock != 0 ? byClock : client.compareTo(other.client);
  }

  /// Whether this id sorts after [other].
  bool operator >(CollabId other) => compareTo(other) > 0;

  /// Whether this id sorts before [other].
  bool operator <(CollabId other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is CollabId && other.client == client && other.clock == clock;

  @override
  int get hashCode => Object.hash(client, clock);

  @override
  String toString() => '$client:$clock';
}

/// How much of every peer's work a document already holds.
///
/// One entry per client: the first clock **not** yet seen. Handing yours to a
/// peer is the whole of the sync protocol — it replies with exactly what you
/// are missing, and nothing else crosses the wire.
final class StateVector {
  /// Creates a vector from [clocks].
  StateVector([Map<int, int>? clocks]) : _clocks = {...?clocks};

  final Map<int, int> _clocks;

  /// The first clock not yet seen from [client].
  int operator [](int client) => _clocks[client] ?? 0;

  /// Records that everything below [clock] from [client] is present.
  void observe(int client, int clock) {
    if (clock > this[client]) _clocks[client] = clock;
  }

  /// Every client this vector knows about.
  Iterable<int> get clients => _clocks.keys;

  /// The underlying map.
  Map<int, int> get clocks => Map.unmodifiable(_clocks);

  /// Whether nothing at all has been observed.
  bool get isEmpty => _clocks.isEmpty;

  @override
  String toString() => 'StateVector($_clocks)';
}
