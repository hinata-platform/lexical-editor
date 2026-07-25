# lexical_core

Pure-Dart editor state model, wire-compatible with
[Lexical](https://lexical.dev) 0.48.x. No Flutter dependency — it runs under
`dart test` and on the server just as well as in an app.

This is the engine, not the editor. Rendering, input and selection live in
`lexical_flutter`; node types beyond the built-ins live in their own
packages.

## Install

```yaml
dependencies:
  lexical_core: ^0.1.0
```

## Use

```dart
import 'package:lexical_core/lexical_core.dart';

final editor = LexicalEditor();

editor.update(() {
  final paragraph = $createParagraphNode()
    ..append($createTextNode('Hallo ')) 
    ..append($createTextNode('Welt')..toggleFormat(TextFormat.bold));
  $getRoot().append(paragraph);
}, discrete: true);

print(editor.toJsonString());

// Reading needs a read context: nodes resolve their current version through
// the active state, which is what makes stale references harmless.
final text = editor.read(() => $getRoot().getTextContent());
```

Opening a document authored on the web:

```dart
final state = editor.parseEditorStateFromString(jsonFromServer);
editor.setEditorState(state);
```

## What it gives you

- **Immutable, double-buffered state.** Committed states are frozen and share
  every untouched node with their predecessor, so an edit costs O(changed
  nodes) and an undo stack is a list of state references.
- **Sibling-pointer tree.** Elements track first/last/size; nodes track
  prev/next/parent — all as keys resolved through the node map. Inserting a
  node touches four objects regardless of how many children there are.
- **A node registry** in place of upstream's static polymorphism, which Dart
  cannot express. Registration is per editor and closed at construction.
- **Wire-exact JSON.** Integers stay integers, omit-vs-explicit-null is
  matched per field, and derived paragraph fields are re-derived rather than
  copied.
- **A bounded, non-recursive importer** with a configurable policy for
  unknown node types.

## Things worth knowing

**Node accessors need a context.** `node.getFirstChild()` resolves the node's
current version through the *active* editor state, so it only works inside
`editor.update()`, `editor.read()` or `editorState.read()`. This is upstream's
design and it is what makes a captured node reference safe to keep.

**`clone()` must be overridden by every subclass** and return its own type.
The framework supplies the key, so implementations never mention it. A
subclass that inherits `clone()` silently downgrades its own type on the next
edit; that is caught by an assertion in debug builds.

**Never override `==` or `hashCode` on a node.** Identity is the key. Two
versions of one node must stay distinguishable.

**Keys are ephemeral.** They are not serialized, importing the same document
twice produces different keys, and any test asserting a key value is broken
by construction.

**`editorState` flushes pending updates** — a deliberate divergence from
upstream, which returns the pre-update state until a microtask runs. Pass
`discrete: true` when you want the commit to happen inside the `update` call.

## Adding a node type

```dart
class CalloutNode extends ElementNode {
  CalloutNode([this._tone = 'info']);
  String _tone;

  @override
  String get type => 'callout';

  @override
  CalloutNode clone() => CalloutNode(_tone);

  @override
  void afterCloneFrom(covariant CalloutNode prev) {
    super.afterCloneFrom(prev);   // required: the clone loses its pointers otherwise
    _tone = prev._tone;
  }

  @override
  Map<String, Object?> exportJson() => {...super.exportJson(), 'tone': _tone};

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _tone = json['tone'] is String ? json['tone']! as String : 'info';
  }
}

final editor = LexicalEditor(
  nodes: [NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new)],
);
```

Write the model and its round-trip test before any renderer. Rendering bugs
are visible and local; serialization bugs corrupt user documents silently and
are found weeks later in production data.

## Compatibility

See the [repository README](https://github.com/hinata-platform/lexical-editor)
for the exact compatibility contract, including why `paragraph.textFormat`
changes on a round-trip and why that is correct.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc., also MIT. See `NOTICE` in
the repository root.
