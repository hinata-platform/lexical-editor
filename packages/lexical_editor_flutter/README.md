![lexical_editor_flutter](https://raw.githubusercontent.com/hinata-platform/lexical-editor/main/doc/preview/lexical_editor_flutter.png)

# lexical_editor_flutter

A [Lexical](https://lexical.dev)-compatible editor for Flutter with everything
already wired up.

```yaml
dependencies:
  lexical_editor_flutter: ^1.0.0
```

```dart
final editor = createLexicalEditor();

LexicalEditorField(
  editor: editor,
  baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
)
```

That is the whole setup: every node type registered, the editing behaviour each
of them needs, undo, and a theme that presents all of them.

## What it assembles

Headings, quotes, bullet / ordered / check lists with nesting, links, code
blocks, tables, marks, hashtags and mentions — plus the rich-text command set,
list and code behaviour for Enter and Tab, and history.

Everything is available separately. The other packages in this family are
deliberately narrow so an application pays only for what it uses; this one is
the opposite, and is the right place to start.

## When to drop to the narrower packages

When a document must **not** contain something. The node registry is closed at
construction, so a type that was never registered cannot be created, pasted or
imported — and an unknown type in a stored document is refused loudly rather
than silently dropped.

```dart
final editor = LexicalEditor(nodes: [...richTextNodes, ...listNodes]);
registerRichText(editor);
registerList(editor);
```

## Theming

`defaultLexicalTheme` derives everything from a body text style and a
six-colour `LexicalPalette`, so an app gets its own typography by passing its
body style in and changing nothing else. `LexicalPalette.dark()` is provided;
any `LexicalTheme` can be passed instead.

## Mentions

The one feature that cannot have a default: only the application knows who can
be mentioned. Give it a source and the picker, the trigger, the insertion and
the node are handled here.

```dart
LexicalEditorField(
  editor: editor,
  baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
  mentions: LexicalMentions(
    source: CallbackMentionSource((query) async => search(query.text)),
  ),
)
```

`@` for people by default; a `#` for issues is a second `MentionTrigger` and
needs nothing else, because the kind is data on the node rather than a node
type. Without `mentions` the mention *node* still works — registered, styled,
round-tripping — so a document written elsewhere opens correctly. What is
missing is the picker.

## Smart links

Everything in the bundle that can point somewhere — links, autolinks, mentions,
hashtags — is named by `interactiveNodeTypes`:

```dart
LexicalEditorField(
  editor: editor,
  baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
  interaction: LexicalInteraction(
    types: interactiveNodeTypes,
    onEnter: (hit) => preview.show(hit),
    onExit: (_) => preview.hide(),
    onTap: (hit) => router.open(hit.type, hit.json),
  ),
)
```

It is a plain set: narrow it with `.difference({'hashtag'})`, or add a type of
your own.

## What is deliberately not here

Selection handles, a context toolbar, and a floating format bar. Material and
Cupertino disagree about what those look like, and so will your design system —
so the geometry is exposed and the design is left to the application. Pass
`editableKey` to reach it:

```dart
final editableKey = GlobalKey<LexicalEditableState>();

LexicalEditorField(editor: editor, editableKey: editableKey, …);

editableKey.currentState!.selectionRects;   // where the selection is
editableKey.currentState!.caretRect;        // where the caret is
```

The example's `selection_toolbar.dart` is a complete floating toolbar with a
link editor built on exactly that — about a hundred lines, including refusing
`javascript:` URLs.

## Licence

MIT. Portions derived from Lexical, © Meta Platforms, Inc. See the
[repository](https://github.com/hinata-platform/lexical-editor).
