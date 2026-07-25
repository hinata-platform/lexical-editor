/// Node identity.
library;

import 'package:meta/meta.dart';

/// Opaque identifier of a node within an `EditorState`.
///
/// A [NodeKey] is an `extension type` over [String]: nominally typed at
/// compile time, erased to a plain `String` at run time, so using it as a
/// map key costs nothing.
///
/// Keys are **ephemeral**. They are generated when a node is constructed,
/// they are not part of the wire format, and importing the same document
/// twice produces different keys. Never persist a key, never parse one, and
/// never assert on a key value in a test.
extension type const NodeKey(String value) {
  /// The key of the document root, which is fixed rather than generated.
  static const NodeKey root = NodeKey('root');
}

int _counter = 1;

/// Allocates a fresh, process-unique [NodeKey].
///
/// Monotonic rather than random: keys never leave the process, so
/// unguessability buys nothing and a counter keeps them short and cheap
/// to compare.
@internal
NodeKey generateNodeKey() => NodeKey('${_counter++}');

/// Resets the key counter. Test-only; keys are not observable behaviour.
@visibleForTesting
void resetNodeKeyCounter() => _counter = 1;
