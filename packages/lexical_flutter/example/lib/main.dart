// The rendering and input layer on its own.
//
//   cd packages/lexical_flutter/example
//   flutter create .        # once, to add the platform folders
//   flutter run
//
// No node packages, no bundle: a paragraph, a caret, an input connection and
// a selection. Everything on screen here is what `lexical_flutter` provides
// by itself — which is also what shows you where the seams are.
import 'package:flutter/material.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'lexical_flutter',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF4DA3FF)),
    home: const EditablePage(),
  );
}

class EditablePage extends StatefulWidget {
  const EditablePage({super.key});

  @override
  State<EditablePage> createState() => _EditablePageState();
}

class _EditablePageState extends State<EditablePage> {
  final GlobalKey<LexicalEditableState> _editable =
      GlobalKey<LexicalEditableState>();
  final LexicalEditor editor = LexicalEditor();

  bool _readOnly = false;
  bool _showPeer = false;

  @override
  void initState() {
    super.initState();
    // registerRichText is the whole of the editing behaviour: typing,
    // deleting, splitting blocks, moving the caret.
    registerRichText(editor);
    editor.update(() {
      $getRoot()
        ..clear()
        ..append(
          $createParagraphNode()..append(
            $createTextNode(
              'Select something: on a phone the handles and the context '
              'menu appear, on a desktop the right-click menu does.',
            ),
          ),
        )
        ..append(
          $createParagraphNode()
            ..append($createTextNode('A second paragraph, with '))
            ..append($createTextNode('bold')..setFormat(TextFormat.bold.bit))
            ..append($createTextNode(' text in it.')),
        );
    }, discrete: true);
    editor.registerUpdateListener((_) => setState(() {}));
  }

  /// A second person's caret, built by hand from two points.
  ///
  /// `lexical_flutter` has no idea where a remote selection comes from — a
  /// collaborative session, a review marker, a test. It paints two points and
  /// a colour, and that is the whole contract.
  List<RemoteSelection> get _peers {
    if (!_showPeer) return const [];
    return editor.read(() {
      final paragraph = $getRoot().getFirstChild()! as ElementNode;
      final text = paragraph.getFirstChild();
      if (text is! TextNode) return const <RemoteSelection>[];
      final length = text.getTextContent().length;
      return [
        RemoteSelection(
          anchor: Point(text.key, 0, PointType.text),
          focus: Point(text.key, length < 9 ? length : 9, PointType.text),
          color: const Color(0xFF37D3A0),
          label: 'Grace',
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('lexical_flutter'),
      actions: [
        IconButton(
          tooltip: 'Show the selection menu',
          onPressed: () => _editable.currentState?.showToolbar(),
          icon: const Icon(Icons.more_horiz),
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 16,
            children: [
              _Switch(
                label: 'read only',
                value: _readOnly,
                onChanged: (value) => setState(() => _readOnly = value),
              ),
              _Switch(
                label: 'second caret',
                value: _showPeer,
                onChanged: (value) => setState(() => _showPeer = value),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LexicalEditable(
            key: _editable,
            editor: editor,
            readOnly: _readOnly,
            autofocus: true,
            padding: const EdgeInsets.all(20),
            remoteSelections: _peers,
            theme: LexicalTheme(
              baseTextStyle: Theme.of(context).textTheme.bodyLarge!,
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'characters: '
            '${editor.read(() => $getRoot().getTextContent().length)}'
            ' · blocks: ${editor.read(() => $getRoot().childrenSize)}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      Text(label),
    ],
  );
}
