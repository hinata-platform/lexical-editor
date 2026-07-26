// The panel beside the editor: the same document, four ways.
//
// It is the reason the demo is worth looking at rather than only typing in.
// Every keystroke changes the markdown, the JSON and the `.lexical` file at
// the same time, so what the model is doing stays visible.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'editor_card.dart';

/// What the panel is showing.
enum Panel {
  markdown('Markdown'),
  json('JSON'),
  file('.lexical'),
  comments('Comments');

  const Panel(this.label);

  /// The tab's label.
  final String label;
}

/// The inspector card.
class SidePanel extends StatelessWidget {
  /// Shows [panel], with [text] for the three textual ones.
  const SidePanel({
    required this.panel,
    required this.onSelect,
    required this.text,
    required this.comments,
    super.key,
  });

  /// The selected tab.
  final Panel panel;

  /// Called with the tab the user picked.
  final ValueChanged<Panel> onSelect;

  /// The document, rendered for the selected tab.
  final String text;

  /// The comments panel, shown under its own tab.
  final Widget comments;

  @override
  Widget build(BuildContext context) => PanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          decoration: const BoxDecoration(
            color: Palette.bar,
            border: Border(bottom: BorderSide(color: Palette.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final value in Panel.values)
                        _Tab(
                          label: value.label,
                          selected: value == panel,
                          onTap: () => onSelect(value),
                        ),
                    ],
                  ),
                ),
              ),
              if (panel != Panel.comments)
                IconButton(
                  tooltip: 'Copy',
                  iconSize: 17,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${panel.label} copied'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                ),
            ],
          ),
        ),
        Expanded(
          child: panel == Panel.comments
              ? comments
              : Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        fontFamilyFallback: monoFallback,
                        fontSize: 12,
                        height: 1.55,
                        color: Palette.muted,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

/// One tab: a pill that fills in when it is the selected one.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: InkWell(
      onTap: onTap,
      borderRadius: Radii.pill,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: Radii.pill,
          color: selected ? Palette.accent.withValues(alpha: 0.1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Palette.accent : Palette.muted,
          ),
        ),
      ),
    ),
  );
}
