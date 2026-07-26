// What you can do to a table, and when.
//
// Every button here is one command dispatch. The interesting part is not the
// buttons but the question they all depend on: *is the caret in a table?* A
// cell's position is not its index in its row — a rowSpan above it pushes it
// right — so "the column left of this one" is a question only the resolved
// grid can answer, and the package answers it. This file just asks.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'app_theme.dart';

/// A bar of table actions, shown only while the caret is inside a table.
class TableActions extends StatelessWidget {
  const TableActions({required this.editor, super.key});

  final LexicalEditor editor;

  /// Whether the caret is inside a table.
  ///
  /// Read inside the editor's read scope and answered as a `bool`: the node
  /// itself must not escape into a widget that builds later.
  bool get _inTable => editor.read(() {
    final selection = $getSelection();
    final node = switch (selection) {
      final RangeSelection range => range.focus.getNode(),
      final NodeSelection nodes => nodes.getNodes().firstOrNull,
      _ => null,
    };
    return node != null && $getTableForNode(node) != null;
  });

  // LexicalBuilder rather than an update listener calling setState: a commit
  // can land *during* a build — a selection change from a tap, for one — and
  // setState from there is an error. The builder defers it safely.
  @override
  Widget build(BuildContext context) => LexicalBuilder(
    editor: editor,
    builder: (context, state, _) =>
        _inTable ? _bar(context) : const SizedBox.shrink(),
  );

  Widget _bar(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.accent.withValues(alpha: 0.05),
      border: const Border(bottom: BorderSide(color: Palette.line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ExcludeFocus(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text(
                  'Table',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: Palette.accent,
                  ),
                ),
              ),
              _Action(
                icon: Icons.add,
                label: 'Row above',
                onPressed: () =>
                    editor.dispatchCommand(insertTableRowCommand, false),
              ),
              _Action(
                icon: Icons.add,
                label: 'Row below',
                onPressed: () =>
                    editor.dispatchCommand(insertTableRowCommand, true),
              ),
              _Action(
                icon: Icons.add,
                label: 'Column left',
                onPressed: () =>
                    editor.dispatchCommand(insertTableColumnCommand, false),
              ),
              _Action(
                icon: Icons.add,
                label: 'Column right',
                onPressed: () =>
                    editor.dispatchCommand(insertTableColumnCommand, true),
              ),
              const _Separator(),
              _Action(
                icon: Icons.remove,
                label: 'Delete row',
                onPressed: () =>
                    editor.dispatchCommand(deleteTableRowCommand, null),
              ),
              _Action(
                icon: Icons.remove,
                label: 'Delete column',
                onPressed: () =>
                    editor.dispatchCommand(deleteTableColumnCommand, null),
              ),
              const _Separator(),
              _Action(
                icon: Icons.vertical_align_top,
                label: 'Header row',
                onPressed: () =>
                    editor.dispatchCommand(toggleTableRowHeaderCommand, null),
              ),
              _Action(
                icon: Icons.vertical_align_bottom,
                label: 'Header column',
                onPressed: () => editor.dispatchCommand(
                  toggleTableColumnHeaderCommand,
                  null,
                ),
              ),
              const _Separator(),
              // Merging needs several cells selected — drag across them.
              _Action(
                icon: Icons.call_merge,
                label: 'Merge cells',
                onPressed: () =>
                    editor.dispatchCommand(mergeTableCellsCommand, null),
              ),
              _Action(
                icon: Icons.call_split,
                label: 'Split cell',
                onPressed: () =>
                    editor.dispatchCommand(unmergeTableCellCommand, null),
              ),
              const _Separator(),
              _Action(
                icon: Icons.delete_outline,
                label: 'Delete table',
                onPressed: () =>
                    editor.dispatchCommand(deleteTableCommand, null),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: Palette.muted,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(borderRadius: Radii.control),
      ),
    ),
  );
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      // A bare VerticalDivider has no intrinsic height and stretches its
      // parent to fill whatever it is given.
      const SizedBox(
        height: 18,
        child: VerticalDivider(width: 13, color: Palette.line),
      );
}
