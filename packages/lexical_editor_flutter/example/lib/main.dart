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
// bar of table actions appears — see table_actions.dart. The panel on the
// right shows the document as markdown, as JSON, or as a .lexical file.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_file/lexical_file.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

import 'comments.dart';
import 'insert_media.dart';
import 'selection_toolbar.dart';
import 'table_actions.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'lexical_editor_flutter',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF4DA3FF),
      brightness: Brightness.light,
      useMaterial3: true,
    ),
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
  _Panel _panel = _Panel.markdown;

  @override
  void initState() {
    super.initState();
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createHeadingNode(HeadingTag.h1)
            ..append($createTextNode('Lexical, auf Flutter')),
        )
        ..append(
          $createParagraphNode()
            ..append($createTextNode('Tippe hier. Alles ist echt: '))
            ..append($createTextNode('fett')..setFormat(TextFormat.bold.bit))
            ..append($createTextNode(', '))
            ..append(
              $createTextNode('kursiv')..setFormat(TextFormat.italic.bit),
            )
            ..append($createTextNode(', Listen, Zitate, Code, Tabellen.')),
        )
        ..append(
          $createListNode(ListType.check)
            ..append(
              $createListItemNode(true)
                ..append($createTextNode('Tab verschachtelt eine Liste')),
            )
            ..append(
              $createListItemNode(false)..append(
                $createTextNode('Enter auf einem leeren Punkt verlässt sie'),
              ),
            ),
        )
        ..append(
          $createQuoteNode()
            ..append($createTextNode('Ein Zitat, mit ⌘Z rückgängig.')),
        )
        // An image lives *inside* a paragraph, because upstream's is inline.
        // Drag its corners; the size is written once, when the drag ends.
        ..append(
          $createParagraphNode()..append(
            $createImageNode(
              src: 'https://picsum.photos/seed/lexical/900/600',
              altText: 'Ein Beispielbild',
              width: 420,
              height: 280,
            )..setCaptionText('Ziehbar an den Ecken'),
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
      ['Paket', 'Was es kann', 'Rein Dart'],
      ['lexical_table', 'Zeilen, Spalten, Merges', 'ja'],
      ['lexical_embed', 'YouTube, Tweets, Figma', 'nein'],
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

  void _format(TextFormat format) =>
      editor.dispatchCommand(formatTextCommand, format);

  /// Marks the selection and opens a thread on it.
  ///
  /// The id is the only thing that reaches the document; the comment itself
  /// lives in [comments], which is why writing one does not change the
  /// document and resolving one does not leave anything behind.
  void _comment() {
    final id = comments.startThread();
    editor.dispatchCommand(addMarkCommand, id);
    setState(() => _panel = _Panel.comments);
  }

  /// Replaces every block the selection touches with a fresh one.
  void _turnInto(ElementNode Function() create) {
    editor.update(() {
      final selection = $getSelection();
      if (selection is! RangeSelection) return;
      for (final block in selection.getBlocks()) {
        block.replace(create()..appendAll(block.children.toList()));
      }
    });
  }

  /// Markdown with the rules images and embeds bring along.
  ///
  /// Neither is part of the default set, and neither is upstream: the
  /// playground adds its own the same way. Without them an image and a video
  /// simply do not appear in the markdown.
  MarkdownTransformers get _transformers => defaultMarkdownTransformers.extend(
    elements: embedTransformers,
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
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('lexical_editor_flutter'),
        actions: [
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: () => editor.dispatchCommand(undoCommand, null),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Wiederherstellen',
            onPressed: () => editor.dispatchCommand(redoCommand, null),
            icon: const Icon(Icons.redo),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            onFormat: _format,
            onTurnInto: _turnInto,
            onList: (type) => _turnInto(
              () => $createListNode(type)
                ..append(
                  $createListItemNode(type == ListType.check ? false : null),
                ),
            ),
            onTable: () => editor.dispatchCommand(
              insertTableCommand,
              const TableShape(rows: 3, columns: 3),
            ),
            onImage: () => showInsertImageDialog(context, editor),
            onEmbed: () => showInsertEmbedDialog(context, editor),
          ),
          TableActions(editor: editor),
          const Divider(height: 1),
          Expanded(
            child: Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              children: [
                Expanded(
                  flex: 3,
                  child: SelectionToolbar(
                    editor: editor,
                    editableKey: _editableKey,
                    onComment: _comment,
                    child: LexicalEditorField(
                      editor: editor,
                      editableKey: _editableKey,
                      autofocus: true,
                      padding: const EdgeInsets.all(24),
                      // This example draws its own toolbar over the
                      // selection, so the platform's cut/copy/paste menu
                      // would be a second overlay on the same gesture.
                      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                      baseTextStyle: Theme.of(context).textTheme.bodyLarge!,
                      // Images and embeds are decorators: without a builder
                      // they draw their text stand-in instead of themselves.
                      decoratorBuilders: lexicalDecoratorBuilders(
                        editor: editor,
                        imageLimits: const ImageSizeLimits(
                          minWidth: 120,
                          maxWidth: 720,
                        ),
                        // No url_launcher in an example; a real application
                        // opens the video here.
                        onOpenEmbed: (kind, url) =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${kind.name}: $url')),
                            ),
                      ),
                      // Links are tappable here too; the toolbar is what
                      // creates them.
                      interaction: LexicalInteraction(
                        types: interactiveNodeTypes,
                        onTap: (hit) =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${hit.type}: '
                                  '${hit.json['url'] ?? hit.text}',
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  // Rebuilds after every commit — and safely, which a bare
                  // update listener calling setState would not be: a commit
                  // can land during a build.
                  child: LexicalBuilder(
                    editor: editor,
                    builder: (context, state, _) => _SidePanel(
                      panel: _panel,
                      onSelect: (value) => setState(() => _panel = value),
                      text: switch (_panel) {
                        _Panel.markdown => _markdown,
                        _Panel.json => editor.toJsonString(),
                        _Panel.file => _lexicalFile,
                        _Panel.comments => '',
                      },
                      comments: CommentsPanel(
                        editor: editor,
                        store: comments,
                        author: 'Du',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onFormat,
    required this.onTurnInto,
    required this.onList,
    required this.onTable,
    required this.onImage,
    required this.onEmbed,
  });

  final void Function(TextFormat) onFormat;
  final void Function(ElementNode Function()) onTurnInto;
  final void Function(ListType) onList;
  final VoidCallback onTable;
  final VoidCallback onImage;
  final VoidCallback onEmbed;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final (icon, format) in const [
            (Icons.format_bold, TextFormat.bold),
            (Icons.format_italic, TextFormat.italic),
            (Icons.format_underlined, TextFormat.underline),
            (Icons.strikethrough_s, TextFormat.strikethrough),
            (Icons.code, TextFormat.code),
          ])
            IconButton(onPressed: () => onFormat(format), icon: Icon(icon)),
          const VerticalDivider(width: 16),
          for (final (label, create) in <(String, ElementNode Function())>[
            ('H1', () => $createHeadingNode(HeadingTag.h1)),
            ('H2', () => $createHeadingNode(HeadingTag.h2)),
            ('¶', $createParagraphNode),
          ])
            TextButton(onPressed: () => onTurnInto(create), child: Text(label)),
          IconButton(
            onPressed: () => onTurnInto($createQuoteNode),
            icon: const Icon(Icons.format_quote),
          ),
          const VerticalDivider(width: 16),
          IconButton(
            onPressed: () => onList(ListType.bullet),
            icon: const Icon(Icons.format_list_bulleted),
          ),
          IconButton(
            onPressed: () => onList(ListType.number),
            icon: const Icon(Icons.format_list_numbered),
          ),
          IconButton(
            onPressed: () => onList(ListType.check),
            icon: const Icon(Icons.checklist),
          ),
          IconButton(
            tooltip: 'Tabelle',
            onPressed: onTable,
            icon: const Icon(Icons.grid_on),
          ),
          const VerticalDivider(width: 16),
          IconButton(
            tooltip: 'Bild oder GIF',
            onPressed: onImage,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Video, Tweet oder Figma',
            onPressed: onEmbed,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
    ),
  );
}

/// What the right-hand panel is showing.
enum _Panel { markdown, json, file, comments }

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.panel,
    required this.onSelect,
    required this.text,
    required this.comments,
  });

  final _Panel panel;
  final ValueChanged<_Panel> onSelect;
  final String text;
  final Widget comments;

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Panel>(
              segments: const [
                ButtonSegment(value: _Panel.markdown, label: Text('Markdown')),
                ButtonSegment(value: _Panel.json, label: Text('JSON')),
                ButtonSegment(value: _Panel.file, label: Text('.lexical')),
                ButtonSegment(
                  value: _Panel.comments,
                  label: Text('Kommentare'),
                ),
              ],
              selected: {panel},
              onSelectionChanged: (value) => onSelect(value.first),
            ),
          ),
        ),
        Expanded(
          child: panel == _Panel.comments
              ? comments
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}
