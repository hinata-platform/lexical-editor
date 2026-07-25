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
| [`lexical_core`](packages/lexical_core) | **M0 + M1 complete** | Pure Dart. Editor state, node map, sibling-pointer tree, registry, JSON, commands, transforms, listeners. No Flutter import. |
| [`lexical_history`](packages/lexical_history) | **complete** | Undo/redo over state snapshots, deterministic tag-driven coalescing |
| `lexical_flutter` | planned (M2) | Reconciler, block render objects, spans, theme, IME, selection |
| `lexical_rich_text` | planned (M4) | Heading, quote, rich-text command defaults |
| `lexical_list` / `_link` / `_code` / `_table` / `_mark` / `_hashtag` | planned (M4) | One concern per package |
| `lexical_markdown` / `lexical_html` | planned (M5) | Import/export and clipboard interop |

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
| **M2** | Read-only Flutter renderer — already useful on its own for viewing web-authored documents | next |
| **M3** | Editable: `DeltaTextInputClient`, selection mapping, caret, keyboard | |
| **M4** | Feature node packages | |
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
