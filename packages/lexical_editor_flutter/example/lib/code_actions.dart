// The language a code block is written in, and how to change it.
//
// Highlighting is not a widget and not a command: it is a transform on the
// document. Setting the language is the *only* thing this file does — the
// runs re-colour themselves on the next commit, which is why there is no
// "re-highlight" button here and no highlighter to hold on to.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'app_theme.dart';

/// A bar naming the caret's code block, shown only while it is in one.
class CodeActions extends StatelessWidget {
  const CodeActions({required this.editor, super.key});

  final LexicalEditor editor;

  /// The language of the code block the caret is in, or `null` when it is not
  /// in one. Read as a plain value: the node must not escape the read scope.
  ({String? language, bool inCode}) get _state => editor.read(() {
    final selection = $getSelection();
    final node = switch (selection) {
      final RangeSelection range => range.focus.getNode(),
      final NodeSelection nodes => nodes.getNodes().firstOrNull,
      _ => null,
    };
    for (var current = node; current != null; current = current.getParent()) {
      if (current is CodeNode) {
        return (language: current.language, inCode: true);
      }
    }
    return (language: null, inCode: false);
  });

  void _setLanguage(String id) => editor.update(() {
    final node = ($getSelection() as RangeSelection?)?.focus.getNode();
    for (var current = node; current != null; current = current.getParent()) {
      if (current is CodeNode) {
        current.setLanguage(id);
        return;
      }
    }
  });

  @override
  Widget build(BuildContext context) => LexicalBuilder(
    editor: editor,
    builder: (context, state, _) {
      final current = _state;
      if (!current.inCode) return const SizedBox.shrink();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.accent.withValues(alpha: 0.05),
          border: const Border(bottom: BorderSide(color: Palette.line)),
        ),
        child: ExcludeFocus(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                const Text(
                  'Code',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: Palette.accent,
                  ),
                ),
                const SizedBox(width: 10),
                _LanguageMenu(
                  current: current.language,
                  onSelected: _setLanguage,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Type in it — the colours follow',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Palette.faint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The language picker: everything `lexical_code` can highlight.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.current, required this.onSelected});

  final String? current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    // Sorted by name rather than by registration order: a picker is read, and
    // a reader looks a language up alphabetically.
    final languages = [for (final language in builtInCodeLanguages) language.id]
      ..sort();

    return PopupMenuButton<String>(
      tooltip: 'Language',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: Palette.surface,
      elevation: 3,
      constraints: const BoxConstraints(maxHeight: 340),
      shape: const RoundedRectangleBorder(
        borderRadius: Radii.control,
        side: BorderSide(color: Palette.line),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final id in languages)
          PopupMenuItem<String>(
            value: id,
            height: 34,
            child: Text(
              id,
              style: TextStyle(
                fontFamilyFallback: monoFallback,
                fontSize: 12.5,
                color: id == current ? Palette.accent : Palette.text,
                fontWeight: id == current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 9, right: 4),
        decoration: BoxDecoration(
          borderRadius: Radii.control,
          border: Border.all(color: Palette.line),
          color: Palette.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // A block with no language is not highlighted at all, and the
              // picker should say so rather than pretend one is selected.
              current ?? 'plain text',
              style: TextStyle(
                fontFamilyFallback: monoFallback,
                fontSize: 12,
                color: current == null ? Palette.faint : Palette.text,
              ),
            ),
            const Icon(Icons.expand_more, size: 16, color: Palette.faint),
          ],
        ),
      ),
    );
  }
}
