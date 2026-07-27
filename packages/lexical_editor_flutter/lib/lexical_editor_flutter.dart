/// A Lexical editor for Flutter with everything already wired up.
///
/// The other packages in this repository are deliberately narrow, so that an
/// application pays only for the node types it uses. This one is the opposite:
/// every node type, the editing behaviour each of them needs, undo, and a
/// theme that presents all of them.
///
/// ```dart
/// final editor = createLexicalEditor();
///
/// LexicalEditorField(
///   editor: editor,
///   baseTextStyle: Theme.of(context).textTheme.bodyMedium!,
/// )
/// ```
///
/// Everything it assembles is available on its own. Reach for the individual
/// packages when a document must *not* contain something: the node registry is
/// closed at construction, so a type that was never registered cannot be
/// created, pasted or imported — and an unknown one in a stored document is
/// refused loudly rather than silently dropped.
library;

export 'package:lexical_code/lexical_code.dart';
export 'package:lexical_core/lexical_core.dart';
export 'package:lexical_embed/lexical_embed.dart';
export 'package:lexical_flutter/lexical_flutter.dart';
export 'package:lexical_hashtag/lexical_hashtag.dart';
export 'package:lexical_history/lexical_history.dart';
export 'package:lexical_image/lexical_image.dart';
export 'package:lexical_link/lexical_link.dart';
export 'package:lexical_list/lexical_list.dart';
export 'package:lexical_mark/lexical_mark.dart';
export 'package:lexical_mention/lexical_mention.dart';
export 'package:lexical_mention_flutter/lexical_mention_flutter.dart';
export 'package:lexical_rich_text/lexical_rich_text.dart';
export 'package:lexical_table/lexical_table.dart';

export 'src/bundle.dart'
    show
        LexicalEditorField,
        createLexicalEditor,
        interactiveNodeTypes,
        lexicalDecoratorBuilders,
        lexicalNodes,
        registerLexical;
export 'src/default_theme.dart'
    show
        LexicalPalette,
        defaultCodeHighlightStyles,
        defaultHeadingStyles,
        defaultLexicalTheme;
export 'src/horizontal_rule_view.dart'
    show LexicalHorizontalRuleView, horizontalRuleDecoratorBuilders;
export 'src/mentions.dart' show LexicalMentions;
export 'src/table_layout.dart' show tableBlockLayouts;
