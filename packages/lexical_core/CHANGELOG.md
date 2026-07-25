# Changelog

## 0.1.0-dev.2

Milestone M1 — the behaviour layer. Still no Flutter dependency.

### Added

- **Commands** with the full ten-name, five-level priority ladder.
  `before*` registrations prepend within their level, so they run
  most-recently-registered first while plain registrations run in
  registration order — verified against lexical 0.48, where the `before`
  constants are negative and normalize into the same five buckets.
  Dispatch opens an update if none is active and is bounded against runaway
  recursion.
- **Transforms** with upstream's fixed-point loop: leaves before elements,
  the root last as an update finalizer, and a convergence cap that throws
  naming the offending node types rather than hanging.
- **Normalization** built into the transform pass: adjacent identical text
  runs merge, empty runs are dropped, and unmergeable nodes such as tabs are
  left alone. A newline reaching a text node is split into runs separated by
  line breaks — a deliberate strengthening over upstream, which relies on its
  insertion paths never producing one.
- **Listeners**: update, per-type mutation (created/updated/destroyed, root
  excluded), text content, and editable. `EditorUpdate` carries both states,
  the update tags and the dirty sets.
- Detached nodes are now garbage collected at commit, bounded by the dirty
  set rather than by document size.
- `setEditorState` notifies listeners with `isFullReconcile`, and may be
  called from inside a command handler — the enclosing update is abandoned
  in favour of the replacement, which is how undo works.

### Fixed

- An update that changes nothing no longer commits. Beyond wasted work, a
  no-op commit woke every listener, and a listener that dispatched a command
  opened another empty update and never stopped.

## 0.1.0-dev.1

First development release — milestone M0 of the port.

### Added

- `EditorState`: immutable, double-buffered node map with structural sharing
  between commits, and a frozen public view.
- `LexicalNode` with sibling pointers (`prev`/`next`/`parent`) and element
  pointers (`first`/`last`/`size`), `getLatest`/`getWritable` versioning, and
  a clone contract that supplies keys automatically.
- Built-in node types: `root`, `paragraph`, `text`, `linebreak`, `tab`, plus
  the `DecoratorNode` base class.
- `NodeRegistry` with per-editor registration, closed at construction, and
  node replacement keyed on the replaced type.
- `NodeState` preserving nested (`"$"`) extension data verbatim across a
  round trip.
- JSON import/export verified as a fixed point against fixtures generated
  from Lexical 0.48.0.
- Bounded, non-recursive importer: depth, node-count and text-length limits;
  typed errors for malformed documents; a configurable policy for unknown
  node types that never drops them silently.
- `assertTreeIntegrity`, a debug-only structural walk run after every commit.
- `RangeSelection` / `NodeSelection` model. Selection is part of the state
  and, matching the wire format, is never serialized.

### Known limitations

- Commands, transforms, listeners and history land in M1.
- Heading, quote, list, link, code, table, mark and hashtag node types land
  with their feature packages; fixtures using them are skipped for now.
- Text nodes containing a newline are rejected at import rather than
  normalized. Upstream tolerates them; splitting them into line breaks
  arrives with the normalization transforms in M1.

### Added — editing

- Every editing operation on `RangeSelection`: `insertText`, `removeText`,
  `deleteCharacter`, `deleteWord`, `deleteLine`, `insertParagraph`,
  `insertLineBreak`, `insertNodes`, `formatText`, `setTextStyle`, `moveCaret`,
  `moveTo`, `selectWord`, `getBlocks` and `getTextContent`. A replacement is
  one operation throughout, never a delete followed by an insert.
- Movement by **grapheme cluster**, so a skin-toned emoji is one press of
  backspace rather than four.
- Atomic token handling: a range that reaches into a token takes all of it,
  which is what makes a mention behave like the entity it names.
- `registerPlainText` and `registerRichText`, wiring the commands to those
  operations at the lowest priority, plus a root transform that keeps the
  document from ever being left without somewhere to put the caret.
- `ElementNode.insertNewAfter`, the extension point deciding which block Enter
  produces; `TextNode.spliceText`; selection helpers on every node type.
- `LexicalEditor.runUpdate`, for code reachable both from a command handler —
  which is already inside an update — and directly.

### Fixed

- Text nodes preserve newlines, matching upstream. The canonical code-block
  fixture contains them, so rejecting or splitting them broke real documents.
