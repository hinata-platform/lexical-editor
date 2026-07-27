# Changelog

## 1.6.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.5.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.4.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_flutter` for what changed.

## 1.3.0

Ports the useful half of `@lexical/selection` into the core, where the rest of
the selection model already lives. Not a separate package, because it was never
a separate concern: everything in it operates on the `RangeSelection` the core
defines, and splitting it would only produce two packages that cannot be used
apart.

**Style over a selection.** `$patchStyleText(selection, patch)` changes the
declarations you name and leaves the rest of a node's `style` alone — the
difference between a colour picker and a colour picker that silently drops the
font size the writer set a minute ago. A partially covered node is split so the
patch lands on exactly the covered run; a token node is styled whole or not at
all; a collapsed selection records the patch as *pending*, so it applies to the
next character typed rather than to nothing. `StyleValue` says which of the
three things an entry does — set, drop, or derive the new value from the
current one. `$getSelectionStyleValueForProperty` reads back the other way and
distinguishes "every covered node agrees", "they disagree" and "nothing sets
it"; a picker needs all three, and they are not the same answer.

`style` is an untyped CSS string on the wire and stays one, so
`getStyleObjectFromCss` and `getCssFromStyleObject` are the conversion those
two need. They do not implement CSS: a property they have never heard of is
carried through untouched, and a `;` or `:` inside quotes or parentheses is
content rather than a separator, which is what keeps `url(a;b)` in one piece.

**Where a point sits.** `$isAtNodeEnd(point)`, and its generalization to an
ancestor, `$isAtStartOfNode` / `$isAtEndOfNode` — true only when nothing of the
element's content lies between the point and that edge, at every level.
`$forEachSelectedTextNode` and `$ensureForwardRangeSelection` are the two
building blocks the style functions are written on, exposed because anything
applying a per-run change wants them.

**Taking content out.** `$sliceSelectedTextContent(selection, textNode)` is
what an exporter needs and a node cannot answer: how much of this node did the
selection actually cover. `$trimTextContentFromAnchor(editor, anchor, count)`
enforces a maximum length, walking backwards out of the anchor through text,
then whole nodes, then the blocks holding them — and counting the two
characters a block boundary is worth in `getTextContent()`, so the accounting
matches whatever measured the document in the first place. A node whose text
changed in the same update is restored rather than trimmed, which is what makes
a length limit *reject* an overlong paste instead of truncating it.

**Direction.** `$isParentRtl` / `$isParentElementRtl`, answered from the
model's own `direction` rather than from a computed style, which does not exist
outside a browser.

Two functions are deliberately **not** ported. `createDOMRange` and
`createRectsFromDOMRange` describe a DOM range; `$moveCaretSelection` and
`$moveCharacter` are `selection.modify()` plus a writing-mode flip that Flutter
does not have — `RangeSelection.moveCaret` is the same operation here. The
functions upstream marks deprecated (`$addNodeStyle`, `$wrapNodes`,
`trimTextContentFromAnchor`) are not ported at all. And
`$sliceSelectedTextNodeContent` returns text rather than a node: a clone would
carry the original's key, so every accessor on it would resolve through the
node map back to the original, and writing into the live node instead would
edit the committed document from inside a read.

**`$setBlocksType`, two fixes.** A selection that stops exactly at the start of
the next block no longer converts that block — dragging from the middle of one
paragraph to the start of the next covers no character of the second one, and a
writer who sees nothing of it highlighted does not expect it to become a
heading. And `afterCreateElement` is now a parameter, defaulting to the new
`$copyBlockFormatIndent`, so what survives a conversion is the caller's to
decide.

**`replace()` carries the selection.** A point that addressed the replaced node
is moved onto the replacement instead of being left naming a key that is no
longer in the document. Converting an *empty* paragraph — press Enter, then
click Heading — used to throw for exactly that reason.

**A faster selection drag.** `RangeSelection.getBlocks()` walks block to block
rather than leaf to leaf. Same blocks, but a selection over a long document
holds thousands of leaves and dozens of blocks, and this runs on every pointer
move of a drag.

Additions to the node API, all upstream's: `ElementNode.getFirstDescendant`,
`getLastDescendant` and `getDescendantByIndex`, and `TextNode.canHaveFormat`
for a node type that renders something other than its own characters and should
not be restyled into something that no longer reads as what it is.

## 1.2.0

Added `$setBlocksType(selection, createElement)` — the operation behind a
toolbar's heading, quote and paragraph buttons, and the counterpart to
`@lexical/selection`'s function of the same name. It was missing, so every
consumer wrote it themselves, and writing it correctly turns out to be harder
than it looks: `createElement` is called once per block, so a three-block
selection becomes three elements rather than one holding everything run
together, and the children move across rather than being flattened.

Added `$isBlock(node)`, the predicate that decides what may be converted. A
paragraph, a heading, a quote or a list item holding text is a block; a table,
a list, or anything whose first child is itself a block is a container, and
converting one dissolves it — every cell run together into one element, the
rows gone, all the words still present so nothing downstream reports a problem.
`$setBlocksType` skips containers for exactly that reason, which is why a caret
in a table cell converts the paragraph in that cell and leaves the table alone.

## 1.1.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

## 1.0.0

First stable release; semantic versioning applies from here.
The model: immutable double-buffered state, sibling-pointer tree, commands,
transforms, listeners and JSON that is a fixed point against Lexical 0.48.

The entries below record how it got here.

## 0.1.0-dev.3

`ensureNonEmpty` no longer opens an update when the document already has
children — it committed, and notified every listener, for nothing.

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
