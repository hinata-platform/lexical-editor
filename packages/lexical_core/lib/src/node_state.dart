/// Per-node extension data that clones and serializes automatically.
library;

import 'package:meta/meta.dart';

/// The reserved JSON key under which non-flat node state is nested.
///
/// Custom fields must never collide with it.
const String nodeStateKey = r'$';

/// Arbitrary key/value data attached to a node.
///
/// Upstream Lexical uses `NodeState` both as its own extension mechanism and
/// as the container that preserves state a client does not understand. This
/// port implements the second role first, because it is the one the wire
/// format depends on: a document authored by a newer web client carries state
/// entries an older Dart client has never heard of, and dropping them would
/// destroy user data on the next save.
///
/// Two buckets, matching the wire format exactly:
///
/// * **flat** entries are top-level keys of the node's JSON object;
/// * **nested** entries live under the reserved [nodeStateKey] (`"$"`) key.
///
/// Values are stored as decoded JSON and re-emitted verbatim.
final class NodeState {
  /// Creates an empty state container.
  NodeState();

  NodeState._(this._flat, this._nested);

  Map<String, Object?>? _flat;
  Map<String, Object?>? _nested;

  /// Whether this container holds nothing and can be dropped entirely.
  bool get isEmpty =>
      (_flat == null || _flat!.isEmpty) &&
      (_nested == null || _nested!.isEmpty);

  /// The flat entries, or an empty map when there are none.
  Map<String, Object?> get flat => _flat ?? const {};

  /// The nested entries, or an empty map when there are none.
  Map<String, Object?> get nested => _nested ?? const {};

  /// Reads a nested state value.
  Object? operator [](String key) => _nested?[key];

  /// Writes a nested state value.
  void operator []=(String key, Object? value) {
    (_nested ??= <String, Object?>{})[key] = value;
  }

  /// Writes a flat state value, serialized as a top-level JSON key.
  void setFlat(String key, Object? value) {
    assert(
      key != nodeStateKey,
      'NodeState: "$nodeStateKey" is reserved for nested state',
    );
    (_flat ??= <String, Object?>{})[key] = value;
  }

  /// Returns an independent copy. Called when a node is cloned.
  NodeState copy() => NodeState._(
    _flat == null ? null : Map<String, Object?>.of(_flat!),
    _nested == null ? null : Map<String, Object?>.of(_nested!),
  );

  /// Merges this state into a node's serialized [json] map, in place.
  @internal
  void writeTo(Map<String, Object?> json) {
    final flatEntries = _flat;
    if (flatEntries != null && flatEntries.isNotEmpty) {
      json.addAll(flatEntries);
    }
    final nestedEntries = _nested;
    if (nestedEntries != null && nestedEntries.isNotEmpty) {
      json[nodeStateKey] = Map<String, Object?>.of(nestedEntries);
    }
  }

  /// Reads the nested bucket out of a node's serialized [json] map.
  ///
  /// Flat entries are *not* recovered here: upstream only restores flat keys
  /// that a node type has explicitly registered, and an unregistered
  /// top-level key is indistinguishable from a field of a node type this
  /// client does not fully implement. Adopting every unknown key would make
  /// two clients disagree about which fields exist.
  @internal
  static NodeState? readFrom(Map<String, Object?> json) {
    final nested = json[nodeStateKey];
    if (nested is! Map) return null;
    final copied = <String, Object?>{};
    for (final entry in nested.entries) {
      copied['${entry.key}'] = entry.value;
    }
    if (copied.isEmpty) return null;
    return NodeState._(null, copied);
  }
}
