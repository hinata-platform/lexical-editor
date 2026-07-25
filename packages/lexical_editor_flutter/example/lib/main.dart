// A runnable editor with everything wired up.
//
//   cd packages/lexical_editor_flutter/example
//   flutter create .        # once, to add the platform folders
//   flutter run
//
// The whole editor is `createLexicalEditor()` plus `LexicalEditorField`. The
// rest of this file is a toolbar and a panel showing the document's markdown
// and JSON, so that what the model is doing stays visible while you type.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

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
  bool _showJson = false;

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
                  child: LexicalEditorField(
                    editor: editor,
                    autofocus: true,
                    padding: const EdgeInsets.all(24),
                    baseTextStyle: Theme.of(context).textTheme.bodyLarge!,
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
                    builder: (context, state, _) => _Inspector(
                      showJson: _showJson,
                      onToggle: (value) => setState(() => _showJson = value),
                      text: _showJson ? editor.toJsonString() : _markdown,
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

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.showJson,
    required this.onToggle,
    required this.text,
  });

  final bool showJson;
  final ValueChanged<bool> onToggle;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Markdown')),
              ButtonSegment(value: true, label: Text('JSON')),
            ],
            selected: {showJson},
            onSelectionChanged: (value) => onToggle(value.first),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );
}
