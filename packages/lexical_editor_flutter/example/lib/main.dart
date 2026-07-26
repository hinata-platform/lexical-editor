// A runnable editor with everything wired up.
//
//   cd packages/lexical_editor_flutter/example
//   flutter create .        # once, to add the platform folders
//   flutter run
//
// The whole editor is `createLexicalEditor()` plus `LexicalEditorField`. The
// rest of this file is a toolbar and a panel showing the document's markdown
// and JSON, so that what the model is doing stays visible while you type.
//
// Select some text and a second toolbar appears over it, with the link editor
// behind its link button — see selection_toolbar.dart. Its comment button
// opens a thread in the right-hand panel — see comments.dart. The image and
// media buttons are in insert_media.dart. Put the caret in a table cell and a
// bar of table actions appears — see table_actions.dart. Type `@` and the
// mention picker opens, over the list of people at the bottom of this file.
// The panel on the right shows the document as markdown, as JSON, or as a
// .lexical file.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_file/lexical_file.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

import 'app_theme.dart';
import 'brand_header.dart';
import 'comments.dart';
import 'editor_card.dart';
import 'editor_toolbar.dart';
import 'insert_media.dart';
import 'selection_toolbar.dart';
import 'side_panel.dart';
import 'table_actions.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'lexical_editor_flutter',
    debugShowCheckedModeBanner: false,
    theme: demoTheme(),
    home: const EditorPage(),
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  // Every node type, the behaviour each of them needs, and undo.
  final LexicalEditor editor = createLexicalEditor();

  /// Reaches `LexicalEditableState` — where the selection's geometry lives,
  /// which is all a floating toolbar needs.
  final GlobalKey<LexicalEditableState> _editableKey =
      GlobalKey<LexicalEditableState>();
  final CommentStore comments = CommentStore();
  Panel _panel = Panel.markdown;

  @override
  void initState() {
    super.initState();
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createHeadingNode(HeadingTag.h1)
            ..append($createTextNode('Lexical, on Flutter')),
        )
        ..append(
          $createParagraphNode()
            ..append($createTextNode('Type here. All of it is real: '))
            ..append($createTextNode('bold')..setFormat(TextFormat.bold.bit))
            ..append($createTextNode(', '))
            ..append(
              $createTextNode('italic')..setFormat(TextFormat.italic.bit),
            )
            ..append($createTextNode(', lists, quotes, code, tables.')),
        )
        ..append(
          $createListNode(ListType.check)
            ..append(
              $createListItemNode(true)
                ..append($createTextNode('Tab nests a list')),
            )
            ..append(
              $createListItemNode(false)
                ..append($createTextNode('Enter on an empty item leaves it')),
            ),
        )
        ..append(
          $createQuoteNode()
            ..append($createTextNode('A quotation — undo it with ⌘Z.')),
        )
        // An image lives *inside* a paragraph, because upstream's is inline.
        // Drag its corners; the size is written once, when the drag ends.
        ..append(
          $createParagraphNode()..append(
            $createImageNode(
              src: 'https://picsum.photos/seed/lexical/900/600',
              altText: 'An example image',
              width: 420,
              height: 280,
            )..setCaptionText('Drag it by the corners'),
          ),
        )
        // A video is a block of its own — and in Lexical, "video" means
        // YouTube. See insert_media.dart for what happens to anything else.
        ..append($createYouTubeNode('dQw4w9WgXcQ'))
        // Put the caret in a cell and a second bar appears with everything
        // that can be done to a table — see table_actions.dart. Tab walks
        // the cells, and dragging across cells selects a rectangle.
        ..append(_sampleTable())
        ..append($createParagraphNode());
    }, discrete: true);
  }

  /// A 3x3 table with a header row, filled so the grid is readable.
  TableNode _sampleTable() {
    const rows = [
      ['Package', 'What it does', 'Pure Dart'],
      ['lexical_table', 'Rows, columns, merges', 'yes'],
      ['lexical_embed', 'YouTube, tweets, Figma', 'no'],
    ];
    final table = $createTableNodeWithDimensions(
      rows.length,
      rows.first.length,
      includeHeaders: true,
    );
    final grid = $computeTableGrid(table);
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final cell = grid.at(row, column)?.cell;
        final paragraph = cell?.getFirstChild();
        if (paragraph is ElementNode) {
          paragraph.append($createTextNode(rows[row][column]));
        }
      }
    }
    return table;
  }

  /// Marks the selection and opens a thread on it.
  ///
  /// The id is the only thing that reaches the document; the comment itself
  /// lives in [comments], which is why writing one does not change the
  /// document and resolving one does not leave anything behind.
  void _comment() {
    final id = comments.startThread();
    editor.dispatchCommand(addMarkCommand, id);
    setState(() => _panel = Panel.comments);
  }

  /// Turns every block the selection touches into [kind].
  ///
  /// Lists are the case worth reading: a list *item* is the block, so leaving
  /// a list replaces the list around it, and switching between bullet and
  /// numbered only changes the list's type. Replacing the item itself would
  /// leave a paragraph inside a list, which is not a shape any Lexical client
  /// knows what to do with.
  void _turnInto(BlockKind kind) {
    editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      final wantedList = _listTypeOf(kind);

      for (final block in selection.getBlocks()) {
        final parent = block.getParent();
        final children = block.children.toList();

        if (block is ListItemNode && parent is ListNode) {
          if (wantedList != null) {
            parent.setListType(wantedList);
          } else {
            parent.replace(_createBlock(kind)..appendAll(children));
          }
          continue;
        }

        if (wantedList != null) {
          block.replace(
            $createListNode(wantedList)..append(
              $createListItemNode(wantedList == ListType.check ? false : null)
                ..appendAll(children),
            ),
          );
          continue;
        }

        block.replace(_createBlock(kind)..appendAll(children));
      }
    });
  }

  /// The list a block kind stands for, or `null` when it is not a list.
  ListType? _listTypeOf(BlockKind kind) => switch (kind) {
    BlockKind.bullet => ListType.bullet,
    BlockKind.numbered => ListType.number,
    BlockKind.check => ListType.check,
    _ => null,
  };

  /// Must be called inside an update.
  ElementNode _createBlock(BlockKind kind) => switch (kind) {
    BlockKind.h1 => $createHeadingNode(HeadingTag.h1),
    BlockKind.h2 => $createHeadingNode(HeadingTag.h2),
    BlockKind.h3 => $createHeadingNode(HeadingTag.h3),
    BlockKind.quote => $createQuoteNode(),
    BlockKind.code => $createCodeNode(),
    _ => $createParagraphNode(),
  };

  /// Markdown with the rules tables, images and embeds bring along.
  ///
  /// None of the three is part of the default set, and none is upstream
  /// either: the playground adds its own the same way. Without them an image
  /// and a video simply do not appear in the markdown — and a table appears
  /// as its cells, one per line, which reads like a document and is not one.
  MarkdownTransformers get _transformers => defaultMarkdownTransformers.extend(
    elements: [tableTransformer, ...embedTransformers],
    textMatches: [imageTransformer],
  );

  String get _markdown =>
      editor.read(() => $convertToMarkdown(transformers: _transformers));

  /// The document as a `.lexical` file — what the playground's Export writes.
  String get _lexicalFile => serializedDocumentFromEditorState(
    editor.editorState,
    source: 'lexical_editor_flutter example',
  ).encode();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 1040;
    final editorCard = EditorCard(
      editor: editor,
      toolbar: EditorToolbar(
        editor: editor,
        onBlock: _turnInto,
        onTable: () => editor.dispatchCommand(
          insertTableCommand,
          const TableShape(rows: 3, columns: 3),
        ),
        onImage: () => showInsertImageDialog(context, editor),
        onEmbed: () => showInsertEmbedDialog(context, editor),
      ),
      // Appears only while the caret is in a table — see table_actions.dart.
      contextBar: TableActions(editor: editor),
      child: SelectionToolbar(
        editor: editor,
        editableKey: _editableKey,
        onComment: _comment,
        child: LexicalEditorField(
          editor: editor,
          editableKey: _editableKey,
          autofocus: true,
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
          palette: const LexicalPalette(
            text: Palette.text,
            muted: Palette.muted,
            accent: Palette.accent,
            border: Palette.line,
            surface: Color(0xFFF6F8FB),
          ),
          // This example draws its own toolbar over the selection, so the
          // platform's cut/copy/paste menu would be a second overlay on the
          // same gesture.
          contextMenuBuilder: (_, _) => const SizedBox.shrink(),
          baseTextStyle: const TextStyle(
            fontSize: 16,
            height: 1.65,
            color: Palette.text,
          ),
          // Images and embeds are decorators: without a builder they draw
          // their text stand-in instead of themselves.
          decoratorBuilders: lexicalDecoratorBuilders(
            editor: editor,
            imageLimits: const ImageSizeLimits(minWidth: 120, maxWidth: 720),
            // No url_launcher in an example; a real application opens the
            // video here.
            onOpenEmbed: (kind, url) => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('${kind.name}: $url'))),
          ),
          // Type `@` and the picker opens. A source is the only thing
          // mentions cannot have a default for: nothing but the application
          // knows who can be mentioned.
          mentions: LexicalMentions(source: CallbackMentionSource(_people)),
          // Links are tappable here too; the toolbar is what creates them.
          interaction: LexicalInteraction(
            types: interactiveNodeTypes,
            onTap: (hit) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${hit.type}: ${hit.json['url'] ?? hit.text}'),
              ),
            ),
          ),
        ),
      ),
    );

    // Rebuilt after every commit — and safely, which a bare update listener
    // calling setState would not be: a commit can land during a build.
    final panel = LexicalBuilder(
      editor: editor,
      builder: (context, state, _) => SidePanel(
        panel: _panel,
        onSelect: (value) => setState(() => _panel = value),
        text: switch (_panel) {
          Panel.markdown => _markdown,
          Panel.json => editor.toJsonString(),
          Panel.file => _lexicalFile,
          Panel.comments => '',
        },
        comments: CommentsPanel(editor: editor, store: comments, author: 'You'),
      ),
    );

    return Scaffold(
      appBar: const BrandAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: width > 720 ? 24 : 12,
              vertical: 20,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: editorCard),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: panel),
                    ],
                  )
                // Under a laptop's width the panel goes below the editor,
                // where it is still readable rather than 200 pixels wide.
                : Column(
                    children: [
                      Expanded(flex: 3, child: editorCard),
                      const SizedBox(height: 16),
                      Expanded(flex: 2, child: panel),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The people `@` can find, standing in for a backend.
///
/// A real source calls one — that is why [MentionSource] is asynchronous and
/// why the controller debounces, drops stale answers and caches. Here it is a
/// list, so the example has no network to explain.
Future<List<MentionSuggestion>> _people(MentionQuery query) async {
  const everyone = [
    ('u_1', 'Rebar Ahmad', 'rebar@example.dev'),
    ('u_2', 'Mira Sørensen', 'mira@example.dev'),
    ('u_3', 'Jonas Weber', 'jonas@example.dev'),
    ('u_4', 'Aylin Kaya', 'aylin@example.dev'),
  ];
  final needle = query.text.toLowerCase();
  return [
    for (final (id, name, email) in everyone)
      if (name.toLowerCase().contains(needle))
        MentionSuggestion(
          id: id,
          label: name,
          mentionType: query.mentionType,
          subtitle: email,
        ),
  ].take(query.limit).toList();
}
