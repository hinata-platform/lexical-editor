![lexical_file](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_file.png)

# lexical_file

The `.lexical` document envelope for
[`lexical_core`](https://pub.dev/packages/lexical_core) — wire-compatible with
`@lexical/file`, so a file saved here opens in the Lexical playground and the
other way round. Pure Dart.

```yaml
dependencies:
  lexical_file: ^1.0.0
```

```dart
// Save.
final document = serializedDocumentFromEditorState(
  editor.editorState,
  source: 'Hinata',
);
await File(suggestedDocumentFileName()).writeAsString(document.encode());

// Open.
final opened = SerializedDocument.parse(await file.readAsString());
editor.setEditorState(editorStateFromSerializedDocument(editor, opened));
```

## The format

```json
{
  "editorState": { "root": { "children": [], "type": "root", "version": 1 } },
  "lastSaved": 1753488000000,
  "source": "Lexical",
  "version": "0.48.0"
}
```

Four fields, and only `editorState` carries content. `lastSaved` is epoch
milliseconds in UTC, `source` names the application that wrote the file, and
`version` records the Lexical version whose format it is. A file missing the
metadata still opens: losing the name of the writer is not worth losing the
user's text over.

## Why parsing and installing are two calls

```dart
final opened = SerializedDocument.parse(text);            // may throw
editor.setEditorState(editorStateFromSerializedDocument(editor, opened));
```

A file that turns out to be corrupt should leave the document the user already
has open exactly as it was. Every failure is a typed
`MalformedDocumentException`, thrown before anything is installed.

Node types are resolved through the **editor's** registry, which is why
`editorStateFromSerializedDocument` takes one: the same `image` type may be a
different class in two applications. A type the editor does not know follows
its `UnknownNodePolicy` — `preserve` lets an older client round-trip a newer
document without losing what it cannot render.

## What this package deliberately does not do

`@lexical/file` also ships the browser half: a download link and a file input.
There is no Flutter counterpart to those, and the right answer differs per
platform — `dart:io` on a server, a share sheet on iOS, an anchor element on
web. So this package is the data and nothing else; the bytes are yours to move.

## Licence

MIT. Derived from Lexical, © Meta Platforms, Inc. See `NOTICE`.
