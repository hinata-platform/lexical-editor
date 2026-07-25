/// Who else is here, and where they are looking.
///
/// Presence is **not** part of the document. A caret position, a display name
/// and a colour are worth nothing an hour later, and storing them in the CRDT
/// would grow the document forever with data nobody wants back. Awareness is
/// therefore a separate, last-writer-wins map per client that expires.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'codec.dart';

/// The field [Awareness] state carries a published selection in.
const String awarenessSelectionField = 'selection';

/// One peer's presence.
final class AwarenessEntry {
  /// Records [state] as [clientId]'s presence at [clock].
  const AwarenessEntry({
    required this.clientId,
    required this.clock,
    required this.state,
    required this.updatedAt,
  });

  /// Whose presence this is.
  final int clientId;

  /// That peer's presence counter; only a greater one replaces this.
  final int clock;

  /// Whatever the peer published — a name, a colour, a selection.
  final Map<String, Object?> state;

  /// When this entry last arrived, for expiry.
  final DateTime updatedAt;
}

/// What changed in one awareness update.
final class AwarenessChange {
  /// Records the three kinds of change.
  const AwarenessChange({
    this.added = const [],
    this.updated = const [],
    this.removed = const [],
  });

  /// Clients heard from for the first time.
  final List<int> added;

  /// Clients whose state changed.
  final List<int> updated;

  /// Clients that left or timed out.
  final List<int> removed;

  /// Whether anything at all changed.
  bool get isEmpty => added.isEmpty && updated.isEmpty && removed.isEmpty;

  @override
  String toString() =>
      'AwarenessChange(added: $added, updated: $updated, removed: $removed)';
}

/// Presence for one session.
///
/// Like the document, this is transport-agnostic: [encodeUpdate] produces
/// bytes and [applyUpdate] consumes them.
final class Awareness {
  /// Creates presence for [clientId].
  ///
  /// [clock] is injectable so expiry can be tested without waiting.
  Awareness({required this.clientId, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// This peer's identity, matching its document's.
  final int clientId;

  final DateTime Function() _now;
  final Map<int, AwarenessEntry> _states = <int, AwarenessEntry>{};
  final StreamController<AwarenessChange> _changes =
      StreamController<AwarenessChange>.broadcast();

  int _clock = 0;

  /// Every peer heard from, including this one.
  Map<int, AwarenessEntry> get states => Map.unmodifiable(_states);

  /// What this peer is publishing, if anything.
  Map<String, Object?>? get localState => _states[clientId]?.state;

  /// Changes as they arrive.
  Stream<AwarenessChange> get changes => _changes.stream;

  /// Replaces what this peer publishes. `null` announces leaving.
  void setLocalState(Map<String, Object?>? state) {
    _clock++;
    if (state == null) {
      final existed = _states.remove(clientId) != null;
      _emit(AwarenessChange(removed: existed ? [clientId] : const []));
      return;
    }
    final existed = _states.containsKey(clientId);
    _states[clientId] = AwarenessEntry(
      clientId: clientId,
      clock: _clock,
      state: Map.unmodifiable(<String, Object?>{...state}),
      updatedAt: _now(),
    );
    _emit(
      AwarenessChange(
        added: existed ? const [] : [clientId],
        updated: existed ? [clientId] : const [],
      ),
    );
  }

  /// Sets one field of the local state, leaving the rest alone.
  void setLocalField(String key, Object? value) =>
      setLocalState(<String, Object?>{...?localState, key: value});

  /// Encodes the presence of [clients], or of everyone.
  Uint8List encodeUpdate([Iterable<int>? clients]) {
    final selected = (clients ?? _states.keys).toList();
    final writer = ByteWriter()..uint(selected.length);
    for (final client in selected) {
      final entry = _states[client];
      writer
        ..uint(client)
        ..uint(entry?.clock ?? _clock)
        ..string(entry == null ? 'null' : jsonEncode(entry.state));
    }
    return writer.toBytes();
  }

  /// Applies a peer's presence update.
  void applyUpdate(Uint8List update) {
    final reader = ByteReader(update);
    final count = reader.uint();
    final added = <int>[];
    final updated = <int>[];
    final removed = <int>[];

    for (var i = 0; i < count; i++) {
      final client = reader.uint();
      final clock = reader.uint();
      final payload = reader.string();
      final existing = _states[client];
      if (existing != null && clock <= existing.clock) continue;

      // A peer announcing its own state is authoritative about it, but never
      // about ours: an echo from a relay must not overwrite what we published
      // half a second ago.
      if (client == clientId) {
        if (clock > _clock) _clock = clock;
        continue;
      }

      final decoded = _decodeState(payload);
      if (decoded == null) {
        if (_states.remove(client) != null) removed.add(client);
        continue;
      }
      _states[client] = AwarenessEntry(
        clientId: client,
        clock: clock,
        state: Map.unmodifiable(decoded),
        updatedAt: _now(),
      );
      (existing == null ? added : updated).add(client);
    }

    _emit(AwarenessChange(added: added, updated: updated, removed: removed));
  }

  /// Drops peers not heard from within [timeout].
  ///
  /// Call it on a timer. A peer that closed its laptop lid never sends a
  /// goodbye, and its caret would otherwise sit in the document forever.
  void removeOutdated(Duration timeout) {
    final now = _now();
    final removed = <int>[];
    for (final entry in _states.values.toList()) {
      if (entry.clientId == clientId) continue;
      if (now.difference(entry.updatedAt) < timeout) continue;
      _states.remove(entry.clientId);
      removed.add(entry.clientId);
    }
    _emit(AwarenessChange(removed: removed));
  }

  /// Announces that this peer is leaving, and closes the stream.
  void dispose() {
    _states.clear();
    unawaited(_changes.close());
  }

  void _emit(AwarenessChange change) {
    if (change.isEmpty || _changes.isClosed) return;
    _changes.add(change);
  }

  Map<String, Object?>? _decodeState(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const CollabDecodeException('malformed awareness state');
    }
    if (decoded == null) return null;
    if (decoded is! Map) {
      throw const CollabDecodeException('awareness state is not a map');
    }
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  }
}
