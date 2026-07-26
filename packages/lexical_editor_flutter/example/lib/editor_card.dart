// The frame around the editor: card, placeholder and the line of counts.
//
// None of it belongs in the package. `LexicalEditorField` draws a document
// and nothing else on purpose — the border, the empty-state text and the
// status line are things every design system disagrees about, so they live
// here, in about a hundred lines, as a worked example of doing it yourself.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'app_theme.dart';

/// A white card with a hairline border and a very soft shadow.
class PanelCard extends StatelessWidget {
  /// Wraps [child] in the demo's card.
  const PanelCard({required this.child, super.key, this.clip = true});

  /// What the card holds.
  final Widget child;

  /// Whether to clip the child to the card's corners.
  final bool clip;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: Radii.card,
      border: Border.all(color: Palette.line),
      boxShadow: cardShadow,
    ),
    child: clip ? ClipRRect(borderRadius: Radii.card, child: child) : child,
  );
}

/// The editor's card: a toolbar, an optional context bar, the document, and a
/// line of counts under it.
class EditorCard extends StatelessWidget {
  /// Assembles the card around [child].
  const EditorCard({
    required this.editor,
    required this.toolbar,
    required this.child,
    super.key,
    this.contextBar,
    this.placeholder = 'Enter some text…',
  });

  /// The editor being framed; the placeholder and counts are read from it.
  final LexicalEditor editor;

  /// The toolbar strip at the top.
  final Widget toolbar;

  /// A second strip under the toolbar, shown when it has something to say.
  final Widget? contextBar;

  /// The editor field itself.
  final Widget child;

  /// What to show while the document is empty.
  final String placeholder;

  @override
  Widget build(BuildContext context) => PanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        ?contextBar,
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: child),
              // Over the document, never in it: a placeholder that was text
              // in the model would be saved, exported and searched.
              Positioned(
                left: 26,
                top: 24,
                right: 26,
                child: LexicalBuilder(
                  editor: editor,
                  // Absent rather than transparent while there is text: an
                  // invisible placeholder is still read out by a screen
                  // reader and still found by a search.
                  builder: (context, state, _) => !_isEmpty
                      ? const SizedBox.shrink()
                      : IgnorePointer(
                          child: Text(
                            placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge!
                                .copyWith(color: Palette.faint),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _Counts(editor: editor),
      ],
    ),
  );

  /// Whether the document holds nothing but one empty block.
  bool get _isEmpty => editor.read(() {
    final root = $getRoot();
    return root.childrenSize <= 1 && root.getTextContent().isEmpty;
  });
}

/// Words, characters and blocks, and the shortcut that is worth knowing.
class _Counts extends StatelessWidget {
  const _Counts({required this.editor});

  final LexicalEditor editor;

  @override
  Widget build(BuildContext context) => LexicalBuilder(
    editor: editor,
    builder: (context, state, _) {
      final (words, characters, blocks) = editor.read(() {
        final text = $getRoot().getTextContent();
        final words = text
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .length;
        final characters = text.replaceAll('\n', '').length;
        return (words, characters, $getRoot().childrenSize);
      });
      return Container(
        height: 34,
        color: Palette.bar,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 11.5, color: Palette.faint),
          child: Row(
            children: [
              Text('$words words'),
              const _Dot(),
              Text('$characters characters'),
              const _Dot(),
              Text('$blocks blocks'),
              const Spacer(),
              // The hint is the first thing to go when the card is narrow:
              // it is a nicety, and the counts are the content.
              Flexible(
                child: Text(
                  'Select text for the format bar · @ mentions',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 7),
    child: Text('·'),
  );
}
