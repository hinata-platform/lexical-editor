// The toolbar over the writing surface.
//
// Two things make it a toolbar rather than a row of buttons, and both come
// from reading the document rather than from remembering what was pressed:
// the block menu names the block the caret is in, and a format button is lit
// while the selection carries that format. Press bold in bold text and the
// button goes out, because the *document* said so.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'app_theme.dart';

/// The block kinds the menu can turn a block into.
enum BlockKind {
  paragraph('Normal', Icons.notes),
  h1('Heading 1', Icons.title),
  h2('Heading 2', Icons.title),
  h3('Heading 3', Icons.title),
  quote('Quote', Icons.format_quote),
  bullet('Bullet list', Icons.format_list_bulleted),
  numbered('Numbered list', Icons.format_list_numbered),
  check('Check list', Icons.checklist),
  code('Code block', Icons.code);

  const BlockKind(this.label, this.icon);

  /// What the menu calls it.
  final String label;

  /// The icon beside it in the menu.
  final IconData icon;
}

/// The toolbar strip at the top of the editor card.
class EditorToolbar extends StatelessWidget {
  /// Creates the toolbar over [editor].
  const EditorToolbar({
    required this.editor,
    required this.onBlock,
    required this.onTable,
    required this.onImage,
    required this.onEmbed,
    super.key,
  });

  /// The editor whose state the buttons reflect and act on.
  final LexicalEditor editor;

  /// Turns the blocks the selection touches into [BlockKind].
  final ValueChanged<BlockKind> onBlock;

  /// Inserts a table.
  final VoidCallback onTable;

  /// Opens the image dialog.
  final VoidCallback onImage;

  /// Opens the embed dialog.
  final VoidCallback onEmbed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Palette.bar,
      border: Border(bottom: BorderSide(color: Palette.line)),
    ),
    // Rebuilt after every commit, which is what keeps the lit buttons honest.
    // `LexicalBuilder` rather than an update listener calling setState: a
    // commit can land during a build, and setState from there is an error.
    child: LexicalBuilder(
      editor: editor,
      builder: (context, state, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // The keyboard must stay up and the selection must survive: a toolbar
        // button that takes focus takes the selection it is about to act on.
        child: ExcludeFocus(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                _BlockMenu(current: _currentBlock(), onSelected: onBlock),
                const _Separator(),
                _ToolButton(
                  icon: Icons.undo,
                  tooltip: 'Undo',
                  onPressed: () => editor.dispatchCommand(undoCommand, null),
                ),
                _ToolButton(
                  icon: Icons.redo,
                  tooltip: 'Redo',
                  onPressed: () => editor.dispatchCommand(redoCommand, null),
                ),
                const _Separator(),
                for (final (icon, tooltip, format) in const [
                  (Icons.format_bold, 'Bold', TextFormat.bold),
                  (Icons.format_italic, 'Italic', TextFormat.italic),
                  (Icons.format_underlined, 'Underline', TextFormat.underline),
                  (
                    Icons.strikethrough_s,
                    'Strikethrough',
                    TextFormat.strikethrough,
                  ),
                  (Icons.code, 'Inline code', TextFormat.code),
                ])
                  _ToolButton(
                    icon: icon,
                    tooltip: tooltip,
                    active: _hasFormat(format),
                    onPressed: () =>
                        editor.dispatchCommand(formatTextCommand, format),
                  ),
                const _Separator(),
                for (final (icon, tooltip, align) in const [
                  (Icons.format_align_left, 'Left', ElementFormat.left),
                  (Icons.format_align_center, 'Centre', ElementFormat.center),
                  (Icons.format_align_right, 'Right', ElementFormat.right),
                  (
                    Icons.format_align_justify,
                    'Justify',
                    ElementFormat.justify,
                  ),
                ])
                  _ToolButton(
                    icon: icon,
                    tooltip: tooltip,
                    active: _alignment() == align,
                    onPressed: () =>
                        editor.dispatchCommand(formatElementCommand, align),
                  ),
                const _Separator(),
                _ToolButton(
                  icon: Icons.grid_on,
                  tooltip: 'Table',
                  onPressed: onTable,
                ),
                _ToolButton(
                  icon: Icons.image_outlined,
                  tooltip: 'Image or GIF',
                  onPressed: onImage,
                ),
                _ToolButton(
                  icon: Icons.play_circle_outline,
                  tooltip: 'Video, tweet or Figma',
                  onPressed: onEmbed,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // -------------------------------------------------------------------
  // Reading the document
  // -------------------------------------------------------------------

  /// Whether the whole selection carries [format].
  ///
  /// The whole selection, not its first node: a button lit because the
  /// selection *starts* in bold lies about what pressing it will do.
  bool _hasFormat(TextFormat format) => editor.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return false;
    if (selection.isCollapsed) {
      return selection.format & format.bit == format.bit;
    }
    final texts = selection.getNodes().whereType<TextNode>();
    return texts.isNotEmpty && texts.every((node) => node.hasFormat(format));
  });

  /// The alignment shared by every block the selection touches, or `null`.
  ElementFormat? _alignment() => editor.read(() {
    final blocks = _selectedBlocks();
    if (blocks.isEmpty) return null;
    final first = blocks.first.getFormat();
    return blocks.every((block) => block.getFormat() == first) ? first : null;
  });

  /// What the block menu shows, or `null` when the selection spans kinds.
  BlockKind? _currentBlock() => editor.read(() {
    final kinds = _selectedBlocks().map(_kindOf).toSet();
    return kinds.length == 1 ? kinds.first : null;
  });

  /// Must be called inside a read.
  List<ElementNode> _selectedBlocks() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return const [];
    return selection.getBlocks().toList();
  }

  /// Must be called inside a read.
  BlockKind _kindOf(ElementNode block) {
    // A list item's kind is its list's: "bullet list" is what the user sees,
    // and `listitem` is not a word the toolbar should ever say.
    final parent = block.getParent();
    if (block is ListItemNode && parent is ListNode) {
      return switch (parent.listType) {
        ListType.bullet => BlockKind.bullet,
        ListType.number => BlockKind.numbered,
        ListType.check => BlockKind.check,
      };
    }
    return switch (block) {
      HeadingNode(:final tag) => switch (tag) {
        HeadingTag.h1 => BlockKind.h1,
        HeadingTag.h2 => BlockKind.h2,
        _ => BlockKind.h3,
      },
      QuoteNode() => BlockKind.quote,
      CodeNode() => BlockKind.code,
      _ => BlockKind.paragraph,
    };
  }
}

/// The `Normal ▾` menu at the left of the toolbar.
class _BlockMenu extends StatelessWidget {
  const _BlockMenu({required this.current, required this.onSelected});

  final BlockKind? current;
  final ValueChanged<BlockKind> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<BlockKind>(
    tooltip: 'Block type',
    position: PopupMenuPosition.under,
    offset: const Offset(0, 6),
    color: Palette.surface,
    elevation: 3,
    shape: const RoundedRectangleBorder(
      borderRadius: Radii.control,
      side: BorderSide(color: Palette.line),
    ),
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final kind in BlockKind.values)
        PopupMenuItem<BlockKind>(
          value: kind,
          height: 38,
          child: Row(
            children: [
              Icon(
                kind.icon,
                size: 17,
                color: kind == current ? Palette.accent : Palette.muted,
              ),
              const SizedBox(width: 10),
              Text(
                kind.label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: kind == current ? Palette.accent : Palette.text,
                  fontWeight: kind == current
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
    ],
    // A fixed width, not a minimum: the toolbar scrolls horizontally, so its
    // children are laid out unbounded — and a flexible child in an unbounded
    // row is a layout error rather than a wide button.
    child: Container(
      height: 34,
      width: 148,
      padding: const EdgeInsets.only(left: 10, right: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        border: Border.all(color: Palette.line),
        color: Palette.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              // No single kind — the selection covers a heading and a
              // paragraph, say. Saying "Normal" there would be a lie.
              current?.label ?? 'Mixed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: Palette.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(Icons.expand_more, size: 18, color: Palette.faint),
        ],
      ),
    ),
  );
}

/// One toolbar button, lit while what it does is already true.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: Radii.control,
        hoverColor: const Color(0x0F1B2333),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: Radii.control,
            color: active ? Palette.accent.withValues(alpha: 0.12) : null,
          ),
          child: Icon(
            icon,
            size: 19,
            color: active ? Palette.accent : Palette.muted,
          ),
        ),
      ),
    ),
  );
}

/// The hairline between two groups of buttons.
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 7),
    color: Palette.lineSoft,
  );
}
