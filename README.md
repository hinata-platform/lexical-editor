# lexical-editor for Dart & Flutter

A native Dart/Flutter reimplementation of [Lexical](https://lexical.dev),
Meta's extensible text-editor framework. Documents authored on Lexical web
open losslessly in Flutter and go back unchanged.

> Compatible with **Lexical 0.48.x**. This project is not affiliated with or
> endorsed by Meta Platforms, Inc. See [NOTICE](NOTICE).

## Why a port and not a wrapper

Lexical's core is a dependency-free, DOM-free state machine; only its
outermost layer touches the browser. That split is what makes a native port
tractable. The model translates to Dart almost verbatim, which is where the
wire compatibility comes from — and the browser-facing edge (reconciliation,
input, selection) has no Flutter counterpart and is designed rather than
translated.

The alternative — a WebView — gives up native input, native selection,
native scrolling and native performance to keep code no user ever sees.

## Packages

| Package | Status | What it is |
|---|---|---|
| [`lexical_core`](packages/lexical_core) | **done** | Pure Dart. Editor state, node map, sibling-pointer tree, registry, JSON, commands, transforms, listeners. No Flutter import. |
| [`lexical_history`](packages/lexical_history) | **done** | Undo/redo over state snapshots, deterministic tag-driven coalescing |
| [`lexical_rich_text`](packages/lexical_rich_text) | **done** | Heading, quote |
| [`lexical_list`](packages/lexical_list) | **done** | Bullet, ordered and check lists, with derived item numbering |
| [`lexical_link`](packages/lexical_link) | **done** | Link and auto-link, with URL scheme validation at the point of use |
| [`lexical_code`](packages/lexical_code) | **done** | Code blocks and syntax-highlight runs |
| [`lexical_table`](packages/lexical_table) | **done** | Table, row, cell with bitmask header state |
| [`lexical_mark`](packages/lexical_mark) | **done** | Annotation and comment ranges |
| [`lexical_hashtag`](packages/lexical_hashtag) | **done** | Hashtags |
| [`lexical_mention`](packages/lexical_mention) | **done** | Typed `@mentions`, bounded trigger matching, debounced search |
| [`lexical_flutter`](packages/lexical_flutter) | **read-only done** | Dirty-set reconciler, one render object per block, spans, offset map, theme |
| `lexical_mention_flutter` | planned (after M3) | Typeahead popover with keyboard navigation |
| `lexical_editor_flutter` | planned (after M3) | Umbrella: default theme and block presenters for every node type |
| `lexical_markdown` / `lexical_html` | planned (M5) | Import/export and clipboard interop |

Every node type in the fixture corpus is implemented: all 20 canonical
documents from Lexical 0.48 round-trip as a fixed point. The suite lives in
[`lexical_conformance`](packages/lexical_conformance), which is test-only —
consumers depend on the feature packages they actually need.

The layering is enforced, not aspirational: `lexical_core` has a test that
fails if any file in it imports `package:flutter/`. A single Flutter import
in the core would make the model untestable headlessly and drag the widget
lifecycle into state management.

## The compatibility contract

Stated precisely, because the naive formulation is wrong:

> Equality is **semantic deep-equality of decoded JSON against the canonical
> form**, not byte-equality against raw input.

Lexical normalizes on import. `paragraph.textFormat` and `paragraph.textStyle`
are *derived from the first text child on export* and overwrite whatever the
input claimed — so upstream itself fails a byte-identity round-trip on
hand-written JSON, while reaching a fixed point after one pass. Accordingly:

1. Fixtures are canonicalized once, by running real Lexical
   (`tool/fixtures/gen_fixtures.mjs`).
2. The port must be a **fixed point** on canonical fixtures:
   `encode(decode(f)) ≡ f`.
3. Comparison is on decoded structures, never strings — JSON key order
   carries no meaning, and an absent key is not equal to a `null` one.

If you report "the editor changed my `textFormat`", that is this rule, not a
bug. Copying those fields through instead of re-deriving them would make a
document edited in Flutter show the wrong active format when reopened on the
web.

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| **M0** | Core model, pure Dart: state, keys, pointers, clone semantics, registry, JSON | done |
| **M1** | Commands with the full priority ladder, transforms, listeners, normalization, history | done |
| **M4** | Feature node packages — pulled forward so the whole fixture corpus round-trips | done |
| **M2** | Read-only Flutter renderer — shippable on its own as a viewer for web-authored documents | done |
| **M3** | Editable: `DeltaTextInputClient`, selection mapping, caret, keyboard | next |
| **M5** | Tables, markdown, collaboration, HTML clipboard | |

Versioning stays pre-1.0 until M3 is trustworthy.

## Development

```sh
dart pub get                                  # workspace resolve
dart analyze                                  # must be clean
dart format --output=none --set-exit-if-changed .
cd packages/lexical_core && dart test         # headless, no Flutter binding
```

Regenerating fixtures against upstream (needs Node):

```sh
cd tool/fixtures
npm install
node gen_fixtures.mjs --generate ../../packages/lexical_core/test/fixtures
node gen_fixtures.mjs --check ../../packages/lexical_core/test/fixtures
```

`--check` is what CI runs on a schedule: it turns a silent compatibility
drift after an upstream release into a dated build failure.

## Security posture

An editor document is untrusted input, and this package is meant to be
consumed by third-party apps.

- The importer is **bounded** — nesting depth, node count and text length —
  and walks with an explicit worklist rather than recursion, so a hostile
  document cannot exhaust the stack.
- Node types resolve **through the registry only**. There is no dynamic
  dispatch on the `type` string.
- Unknown node types **throw by default** and can be configured to be
  preserved verbatim. They are never silently dropped: that would turn a
  version skew into permanent data loss the moment the user saves.
- `style` and `url` are kept **verbatim in the model** for round-trip
  fidelity and validated at the point of use, not mutated on import.

## Licence

MIT — see [LICENSE](LICENSE). Portions derived from Lexical, © Meta
Platforms, Inc., also MIT; see [NOTICE](NOTICE).
