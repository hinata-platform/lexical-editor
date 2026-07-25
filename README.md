![lexical-editor](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/banner.png)

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

| Package | What it is |
|---|---|
| [`lexical_core`](packages/lexical_core) | Pure Dart. Editor state, node map, sibling-pointer tree, registry, JSON, commands, transforms, selection and every editing operation. No Flutter import. |
| [`lexical_history`](packages/lexical_history) | Undo/redo over state snapshots, deterministic tag-driven coalescing |
| [`lexical_collab`](packages/lexical_collab) | Real-time collaboration: a transport-agnostic CRDT, an editor binding, presence |
| [`lexical_rich_text`](packages/lexical_rich_text) | Heading, quote |
| [`lexical_list`](packages/lexical_list) | Bullet, ordered and check lists; nesting, numbering, Enter and Tab behaviour |
| [`lexical_link`](packages/lexical_link) | Link and auto-link, with URL scheme validation at the point of use |
| [`lexical_code`](packages/lexical_code) | Code blocks, syntax-highlight runs, and code-shaped Enter and Tab |
| [`lexical_table`](packages/lexical_table) | Table, row, cell; the grid, spans, cell-range selection and the structural commands |
| [`lexical_mark`](packages/lexical_mark) | Annotation and comment ranges |
| [`lexical_hashtag`](packages/lexical_hashtag) | Hashtags |
| [`lexical_mention`](packages/lexical_mention) | Typed `@mentions`: atomic nodes, bounded trigger matching, debounced search |
| [`lexical_markdown`](packages/lexical_markdown) | Markdown in and out, from transformers that describe both directions at once |
| [`lexical_html`](packages/lexical_html) | HTML in and out, for text that has to leave the editor |
| [`lexical_flutter`](packages/lexical_flutter) | Dirty-set reconciler, one render object per block, spans, offset map, theme, IME, selection, caret, keyboard, drag handles, context menu |
| [`lexical_mention_flutter`](packages/lexical_mention_flutter) | Caret-anchored typeahead popover with keyboard navigation |
| [`lexical_editor_flutter`](packages/lexical_editor_flutter) | Batteries included: every node type, a theme presenting all of them, undo, one widget |

Start with `lexical_editor_flutter` and drop to the narrower packages when a
document must *not* contain something — the registry is closed at
construction, so a type that was never registered cannot be created, pasted or
imported.

```dart
final editor = createLexicalEditor();

LexicalEditorField(
  editor: editor,
  baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
)
```

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
| **M3** | Editable: selection operations, `DeltaTextInputClient`, caret, gestures, keyboard | done |
| **M5** | Markdown and HTML conversion, mention typeahead, the batteries-included bundle | done |
| **M6** | Table editing, selection handles and the context menu, collaboration | done |

Versioning stays pre-1.0 while the API settles.

Handles and the context menu come from Flutter's own `TextSelectionControls`
and `AdaptiveTextSelectionToolbar`, so they look native everywhere without
this package having an opinion about how a handle should look. The raw
geometry stays exposed — `LexicalEditableState.caretRect`, `.selectionRects`,
`.selectionEndpoints` — for a design system that wants to draw its own.

## Try it

Every package has a runnable example. The pure-Dart ones are console
programs that narrate what they do:

```sh
cd packages/lexical_collab && dart run example/main.dart
cd packages/lexical_table  && dart run example/main.dart
```

The three Flutter packages ship an app, with the web target checked in so it
runs without any setup:

```sh
cd packages/lexical_editor_flutter/example && flutter run -d chrome
```

VS Code users get the same thing from the Run panel — `.vscode/launch.json`
has a web configuration for each of them.

## Development

```sh
flutter pub get                               # workspace resolve
flutter analyze                               # must be clean
dart format --output=none --set-exit-if-changed .
cd packages/lexical_core && dart test         # headless, no Flutter binding
cd packages/lexical_flutter && flutter test   # widget and render tests
```

`lexical_core` and every pure-Dart feature package run under `dart test` with
no Flutter binding. If one of them only passes under `flutter test`, the
layering has broken — that is the finding, not a reason to switch runners.

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
  fidelity and validated at the point of use, not mutated on import. The
  markdown and HTML importers follow the same rule: a document is allowed to
  contain a link this application will refuse to open, and rewriting it on
  import would silently change the document.
- The HTML importer is bounded the same way the JSON one is — depth, node
  count and text length — because pasted markup is untrusted input too.
- Keystrokes do not train the platform's personalized keyboard model by
  default. An editor holds documents its user did not choose to share with a
  keyboard vendor, and the opposite default makes that decision for them.

## Licence

MIT — see [LICENSE](LICENSE). Portions derived from Lexical, © Meta
Platforms, Inc., also MIT; see [NOTICE](NOTICE).
