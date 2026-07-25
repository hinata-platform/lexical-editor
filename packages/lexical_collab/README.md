![lexical_collab](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_collab.png)

# lexical_collab

Real-time collaborative editing for
[`lexical_core`](https://pub.dev/packages/lexical_core). A conflict-free
replicated document, an editor binding and presence awareness. Pure Dart.

```yaml
dependencies:
  lexical_collab: ^0.1.0
```

```dart
final collab = LexicalCollab(editor: editor)..start();

collab.updates.listen(socket.add);        // outbound
socket.listen(collab.applyRemoteUpdate);  // inbound
```

Two peers that exchange updates converge on the same document — whatever
order the messages arrive in, however often they repeat, and with no server
in the model. A relay is a convenience, not a source of truth.

## Transport-agnostic

Everything crossing the wire is a `Uint8List`. A WebSocket, a WebRTC channel,
a message queue, a shared file and a test harness are all the same to this
package, and none of them appear in it.

Joining a session that already exists:

```dart
final collab = LexicalCollab(editor: editor)
  ..join(await fetchDocumentState());
```

The order matters, which is why `join` exists as its own method: a peer that
calls `start()` before it has the session's document publishes its own empty
starting paragraph into the room, and everyone ends up with a spare blank
block.

## How it merges

Three strategies, one per kind of data, because no single one is right for
all three.

| Data | Strategy | Why |
|---|---|---|
| Text | RGA — every character carries an id and the id of the character it follows | Two people typing in the same word both keep their characters, in an order both agree on |
| Node properties | Last writer wins, tie-broken by client | A bold toggle is not mergeable; averaging it produces text that is half-bold in a way neither peer asked for |
| The tree | Insert and delete only; a move is a re-reference | The node keeps its identity, so it keeps its subtree |

A node moved by two peers at once ends up where the **later** move put it —
on every peer alike, because every peer computes "later" from the same
timestamps.

### Two numbers, not one

Every operation carries a per-client **sequence number** and a **Lamport
timestamp**, and they cannot be the same number:

- The sequence number *identifies* it. It counts only that client's own work,
  with no gaps, which is what lets a peer describe everything it holds as one
  integer per client — the state vector, and the whole of the sync protocol.
- The timestamp *orders* it. It advances past every id ever seen, which gives
  the invariant the merge rests on: an item always outranks the item it was
  inserted after.

Serving both purposes with one counter is the mistake worth naming: a clock
that jumps to stay ahead of remote work leaves gaps, and a state vector cannot
then tell a gap from the end.

## What it does to the editor

Remote changes land as a commit tagged `collaboration`, so undo steps over
your own work rather than your colleague's. The editor's nodes are **reused**
rather than rebuilt: a keystroke somewhere else does not re-key the paragraph
you are typing in, which is what keeps your caret, your selection and your
scroll position where you left them. A remote insert ahead of your caret
moves it along; one behind it leaves it alone.

Node **keys are never sent**. They are ephemeral by design — regenerated on
every import — so they cannot identify anything across peers; the binding
keeps a local map between them and the document's stable ids.

## Presence

```dart
collab.awareness.setLocalField('name', 'Rebar');
collab.publishSelection();

collab.awareness.changes.listen((_) => setState(() {}));
peerSocket.listen(collab.awareness.applyUpdate);
```

Presence is deliberately **not** part of the document: a caret position is
worth nothing an hour later, and storing it in the CRDT would grow the
document forever with data nobody wants back. Call `removeOutdated` on a
timer — a peer that shut its laptop never says goodbye, and its caret would
otherwise sit in the document for good.

`collab.remoteSelections` resolves everyone's published selection into this
editor's own nodes, ready to hand to `LexicalEditable.remoteSelections` from
[`lexical_flutter`](https://pub.dev/packages/lexical_flutter).

## Version skew

A peer running a newer build can send a node type this one has never heard
of. It is kept in the replicated document and simply not rendered, so it
reappears the moment the application ships the package that defines it.
Inventing a substitute node would be the version-skew failure that destroys
content.

## Security

An update arrives from the network, so it is untrusted input. Every read is
bounds-checked, counts are capped before anything is allocated, and a
malformed message raises `CollabDecodeException` rather than a range error
from somewhere deep inside the parser. Tune the caps with
`CollabUpdateLimits`.

Client ids must be unique among the peers sharing a document; a collision
makes two peers claim the same identities and is the one failure this design
cannot detect. They are random by default, from a range wide enough that a
collision is not a practical concern.

## Licence

MIT — see [LICENSE](LICENSE). Portions derived from Lexical, © Meta
Platforms, Inc., also MIT; see [NOTICE](NOTICE).
