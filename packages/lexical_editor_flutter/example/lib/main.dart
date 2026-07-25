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
// opens a thread in the right-hand panel — see comments.dart.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

import 'comments.dart';
import 'selection_toolbar.dart';

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
        ..append($createParagraphNode());
    }, discrete: true);
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

  String get _markdown => editor.read(
    () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
  );

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
          ),
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
  });

  final void Function(TextFormat) onFormat;
  final void Function(ElementNode Function()) onTurnInto;
  final void Function(ListType) onList;
  final VoidCallback onTable;

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
          IconButton(onPressed: onTable, icon: const Icon(Icons.grid_on)),
        ],
      ),
    ),
  );
}

/// What the right-hand panel is showing.
enum _Panel { markdown, json, comments }

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
          child: SegmentedButton<_Panel>(
            segments: const [
              ButtonSegment(value: _Panel.markdown, label: Text('Markdown')),
              ButtonSegment(value: _Panel.json, label: Text('JSON')),
              ButtonSegment(value: _Panel.comments, label: Text('Kommentare')),
            ],
            selected: {panel},
            onSelectionChanged: (value) => onSelect(value.first),
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
