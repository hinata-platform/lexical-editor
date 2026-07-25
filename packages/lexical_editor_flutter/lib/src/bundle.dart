/// Everything registered at once, and the widget that puts it together.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';
import 'package:lexical_history/lexical_history.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_mark/lexical_mark.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:lexical_table/lexical_table.dart';

import 'default_theme.dart';

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
    registerList(editor),
    registerCode(editor),
    registerHistory(editor, state: history),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

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
    this.decoratorBuilders = const {},
    this.tabBehaviour = TabBehaviour.indent,
    this.registerBehaviour = true,
    this.history,
    this.interaction,
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
  final Map<String, DecoratorBuilder> decoratorBuilders;

  /// What the Tab key does.
  final TabBehaviour tabBehaviour;

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
    return LexicalEditable(
      editor: widget.editor,
      theme: theme,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      padding: widget.padding,
      scrollable: widget.scrollable,
      scrollController: widget.scrollController,
      decoratorBuilders: widget.decoratorBuilders,
      tabBehaviour: widget.tabBehaviour,
      interaction: widget.interaction,
      cursorColor: theme.caretColor,
      cursorWidth: theme.caretWidth,
      selectionColor: theme.selectionColor,
    );
  }
}
