/// Real-time collaborative editing for `lexical_core`.
///
/// A conflict-free replicated document, an editor binding and presence
/// awareness. Pure Dart, and **transport-agnostic**: everything crossing the
/// wire is a `Uint8List`, and nothing here knows what carries it. A
/// WebSocket, a WebRTC channel, a shared file, a message queue and a test
/// harness are all the same to it.
///
/// ```dart
/// final collab = LexicalCollab(editor: editor)..start();
///
/// collab.updates.listen(socket.add);        // outbound
/// socket.listen(collab.applyRemoteUpdate);  // inbound
/// ```
///
/// Two peers that exchange updates converge on the same document, whatever
/// order the messages arrive in and however often they are repeated. There is
/// no server in the model: a relay is a convenience, not a source of truth.
///
/// The merge is not magic and the rules are worth knowing: text merges
/// character by character, node properties are last-writer-wins, and a node
/// moved by two peers at once ends up where exactly one of them put it. See
/// `CollabDoc` for why each is the way it is.
library;

export 'src/awareness.dart'
    show Awareness, AwarenessChange, AwarenessEntry, awarenessSelectionField;
export 'src/binding.dart' show CollabSelection, LexicalCollab, collaborationTag;
export 'src/codec.dart' show CollabDecodeException;
export 'src/doc.dart' show CollabDoc, CollabUpdateLimits;
export 'src/id.dart' show CollabId, StateVector;
