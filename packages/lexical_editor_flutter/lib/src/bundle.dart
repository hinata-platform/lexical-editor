/// Everything registered at once, and the widget that puts it together.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_embed/lexical_embed.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';
import 'package:lexical_history/lexical_history.dart';
import 'package:lexical_image/lexical_image.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_mark/lexical_mark.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_mention_flutter/lexical_mention_flutter.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:lexical_table/lexical_table.dart';

import 'default_theme.dart';
import 'mentions.dart';

/// Every node type this bundle knows, on top of the core types.
///
/// Pass a narrower list when a document must not contain something — the
/// registry is closed at construction, so a type that is not here cannot be
/// created, pasted or imported, and an unknown one is refused loudly rather
/// than dropped.
List<NodeSpec<LexicalNode>> get lexicalNodes => <NodeSpec<LexicalNode>>[
  ...richTextNodes,
  ...listNodes,
  ...linkNodes,
  ...codeNodes,
  ...tableNodes,
  ...markNodes,
  ...hashtagNodes,
  ...mentionNodes,
  ...imageNodes,
  ...embedNodes,
];

/// The node types that can point somewhere: links, mentions, hashtags.
///
/// The `types` a [LexicalInteraction] usually wants. It is a plain set, so
/// narrow it — `interactiveNodeTypes.difference({'hashtag'})` for an app whose
/// hashtags are not clickable — or add your own type to it.
const Set<String> interactiveNodeTypes = {
  'link',
  'autolink',
  'mention',
  'hashtag',
};

/// Creates an editor understanding every type in [lexicalNodes].
LexicalEditor createLexicalEditor({
  List<NodeSpec<LexicalNode>> nodes = const [],
  List<NodeReplacement> replacements = const [],
  EditorConfig config = const EditorConfig(),
  EditorState? initialEditorState,
}) => LexicalEditor(
  nodes: [...lexicalNodes, ...nodes],
  replacements: replacements,
  config: config,
  initialEditorState: initialEditorState,
);

/// Registers the editing behaviour every node type in this bundle needs.
///
/// Order matters and is the reason this exists rather than a list in a
/// README: list and code behaviour register at [CommandPriority.beforeEditor]
/// and must sit in front of the rich-text defaults, and history has to see
/// commits that the others have already shaped.
///
/// Returns one unsubscribe covering all of it.
Unsubscribe registerLexical(LexicalEditor editor, {HistoryState? history}) {
  final unsubscribes = <Unsubscribe>[
    registerRichText(editor),
    // Before the list: Tab arrives as indent/outdent, both packages claim it
    // at `beforeEditor`, and same-priority handlers run in registration
    // order. The table's handler falls through the moment the caret is
    // outside a table, so first refusal is the right place for it.
    registerTable(editor),
    registerList(editor),
    registerCode(editor),
    registerCodeHighlighting(editor),
    registerLink(editor),
    registerMark(editor),
    registerHashtag(editor),
    registerImage(editor),
    registerEmbed(editor),
    registerHistory(editor, state: history),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

/// Widget builders for every decorator type in this bundle.
///
/// A decorator without a builder draws its text stand-in instead of itself, so
/// an editor that registers the image and embed nodes — as this bundle does —
/// wants these too:
///
/// ```dart
/// LexicalEditorField(
///   editor: editor,
///   baseTextStyle: …,
///   decoratorBuilders: lexicalDecoratorBuilders(
///     editor: editor,
///     onOpenEmbed: (kind, url) => launchUrlString(url),
///   ),
/// )
/// ```
///
/// The parameters are the policies that genuinely differ per application: how
/// large an image may be dragged, which sources may be loaded, and what
/// tapping a video does. An embed with no [onOpenEmbed] draws a card that is
/// not tappable, which is the right default for a viewer.
Map<String, DecoratorBuilder> lexicalDecoratorBuilders({
  required LexicalEditor editor,
  ImageSizeLimits imageLimits = const ImageSizeLimits(),
  ImageResolver imageResolver = defaultImageResolver,
  bool editable = true,
  bool captionsEnabled = true,
  EmbedOpener? onOpenEmbed,
  EmbedThumbnailResolver embedThumbnails = defaultEmbedThumbnailResolver,
}) => <String, DecoratorBuilder>{
  ...imageDecoratorBuilders(
    editor: editor,
    limits: imageLimits,
    resolver: imageResolver,
    editable: editable,
    captionsEnabled: captionsEnabled,
  ),
  ...embedDecoratorBuilders(
    onOpen: onOpenEmbed,
    thumbnailResolver: embedThumbnails,
  ),
};

/// A ready-to-use editor: every node type, the default theme, history.
///
/// The convenience layer, and the one to reach for first. Everything it does
/// is available separately — this widget only makes the common arrangement
/// one line instead of thirty.
///
/// ```dart
/// final editor = createLexicalEditor();
///
/// LexicalEditorField(
///   editor: editor,
///   baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
/// )
/// ```
class LexicalEditorField extends StatefulWidget {
  /// Creates an editor field over [editor].
  const LexicalEditorField({
    required this.editor,
    required this.baseTextStyle,
    super.key,
    this.palette = const LexicalPalette(),
    this.theme,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = true,
    this.scrollController,
    this.decoratorBuilders,
    this.tabBehaviour = TabBehaviour.indent,
    this.registerBehaviour = true,
    this.history,
    this.interaction,
    this.editableKey,
    this.mentions,
    this.contextMenuBuilder = defaultLexicalContextMenu,
  });

  /// The editor to edit.
  final LexicalEditor editor;

  /// The style body text inherits. Everything else is derived from it.
  final TextStyle baseTextStyle;

  /// The colours the document is drawn with.
  final LexicalPalette palette;

  /// A complete theme, overriding [baseTextStyle] and [palette].
  final LexicalTheme? theme;

  /// Focus node to use; one is created when omitted.
  final FocusNode? focusNode;

  /// Whether to take focus on first build.
  final bool autofocus;

  /// Whether the document rejects edits but stays selectable.
  final bool readOnly;

  /// Padding around the document.
  final EdgeInsetsGeometry padding;

  /// Whether to scroll, culling off-screen blocks.
  final bool scrollable;

  /// Controller for the internal scroll view.
  final ScrollController? scrollController;

  /// Widget builders for decorator node types.
  ///
  /// Defaults to [lexicalDecoratorBuilders] for this editor, because a
  /// batteries-included widget that registers the image and embed nodes and
  /// then draws neither is not batteries-included. Pass a map to override —
  /// `const {}` for a field that renders every decorator as its text stand-in.
  final Map<String, DecoratorBuilder>? decoratorBuilders;

  /// What the Tab key does.
  final TabBehaviour tabBehaviour;

  /// A key on the editable underneath.
  ///
  /// The way to reach `LexicalEditableState` — `selectionRects`, `caretRect`,
  /// `requestFocus` — which is what anything drawn *around* the selection
  /// needs: a floating format toolbar, a link editor, a comment marker. This
  /// widget deliberately draws none of them, so it has to hand over the
  /// geometry that would make them possible.
  final GlobalKey<LexicalEditableState>? editableKey;

  /// The `@mention` typeahead, and where its suggestions come from.
  ///
  /// Left null the mention *node* still works — it is registered, styled,
  /// round-trips and deletes as one unit, so a document written elsewhere
  /// opens correctly. What is missing is the picker, and it is missing
  /// because only the application knows who can be mentioned.
  ///
  /// ```dart
  /// mentions: LexicalMentions(
  ///   source: CallbackMentionSource((query) async => search(query.text)),
  /// )
  /// ```
  final LexicalMentions? mentions;

  /// The selection menu — cut, copy, paste — shown after a selection.
  ///
  /// An application that draws its own floating toolbar wants this gone:
  /// otherwise both appear on the same gesture, one over the other. Return an
  /// empty widget to suppress it:
  ///
  /// ```dart
  /// contextMenuBuilder: (context, editable) => const SizedBox.shrink(),
  /// ```
  final LexicalContextMenuBuilder contextMenuBuilder;

  /// Which node types respond to hover and tap.
  ///
  /// Pass [interactiveNodeTypes] as `types` to cover everything this bundle
  /// ships that can point somewhere.
  final LexicalInteraction? interaction;

  /// Whether to call [registerLexical] for the lifetime of this widget.
  ///
  /// Turn it off when the application registers behaviour itself — doing both
  /// would install every handler twice.
  final bool registerBehaviour;

  /// Undo state to share between fields, or to keep across a rebuild.
  final HistoryState? history;

  @override
  State<LexicalEditorField> createState() => _LexicalEditorFieldState();
}

class _LexicalEditorFieldState extends State<LexicalEditorField> {
  Unsubscribe? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(LexicalEditorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editor, widget.editor) ||
        oldWidget.registerBehaviour != widget.registerBehaviour) {
      _unsubscribe?.call();
      _unsubscribe = null;
      _register();
    }
  }

  void _register() {
    if (!widget.registerBehaviour) return;
    _unsubscribe = registerLexical(widget.editor, history: widget.history);
    // A document with no block has nowhere to put the caret; the rich-text
    // root transform maintains that afterwards.
    //
    // This runs from `initState`, which is inside a build. Seeding the
    // paragraph there would commit — and notify every listener — mid-build,
    // and a listener that calls `setState` is the most ordinary thing an
    // application writes. So an empty document waits for the frame to end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.editor.ensureNonEmpty();
      });
      return;
    }
    widget.editor.ensureNonEmpty();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        widget.theme ??
        defaultLexicalTheme(
          baseTextStyle: widget.baseTextStyle,
          palette: widget.palette,
        );
    final mentions = widget.mentions;
    if (mentions == null) return _editable(theme, widget.editableKey);
    // The picker anchors itself to the editable's caret, and reaches it
    // through the key it hands to the builder.
    return MentionScope(
      editor: widget.editor,
      triggers: mentions.triggers,
      source: mentions.source,
      editableKey: widget.editableKey,
      itemBuilder: mentions.resolveItemBuilder(
        widget.baseTextStyle,
        widget.palette,
      ),
      decoration: mentions.resolveDecoration(widget.palette),
      emptyBuilder: mentions.emptyBuilder,
      loadingBuilder: mentions.loadingBuilder,
      debounce: mentions.debounce,
      limit: mentions.limit,
      width: mentions.width,
      maxHeight: mentions.maxHeight,
      label: mentions.label,
      trailingSpace: mentions.trailingSpace,
      onInserted: mentions.onInserted,
      builder: (context, key) => _editable(theme, key),
    );
  }

  Widget _editable(
    LexicalTheme theme,
    GlobalKey<LexicalEditableState>? editableKey,
  ) {
    return LexicalEditable(
      key: editableKey,
      editor: widget.editor,
      theme: theme,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      padding: widget.padding,
      scrollable: widget.scrollable,
      scrollController: widget.scrollController,
      decoratorBuilders:
          widget.decoratorBuilders ??
          lexicalDecoratorBuilders(editor: widget.editor),
      tabBehaviour: widget.tabBehaviour,
      interaction: widget.interaction,
      contextMenuBuilder: widget.contextMenuBuilder,
      cursorColor: theme.caretColor,
      cursorWidth: theme.caretWidth,
      selectionColor: theme.selectionColor,
    );
  }
}
