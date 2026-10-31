/// Drawing a layout container as columns.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_layout/lexical_layout.dart';

/// The block layout that draws a `layout-container` as columns.
///
/// Without it a layout is drawn the way every other block is — its items
/// stacked — which is also what it falls back to on purpose when the width is
/// below the sum of its fixed `px` columns: a mail built for 600 pixels
/// stacks its columns on a phone through a media query, and this makes the
/// same decision without one.
///
/// Column widths come from `resolveTemplateColumns`, the same pure-Dart
/// reading of `templateColumns` a test or a server sees. [gap] is the space
/// between columns; it is 0 by default, because a mail's columns are table
/// cells that touch, and their spacing is their own padding.
///
/// A container whose block style says `--stack-below:<N>px` also stacks
/// when the whole document is narrower than `N` pixels — how a converted
/// mail keeps the phone layout its media query gave it. Like a media query
/// it reads the document's width (`LexicalViewport`), not the container's.
///
/// Items are stretched to the height of the row, so a column's background
/// reaches the bottom of its neighbours the way a table cell's does.
///
/// ```dart
/// LexicalTheme(
///   baseTextStyle: …,
///   blockLayouts: {...tableBlockLayouts(), ...layoutBlockLayouts()},
/// )
/// ```
///
/// `defaultLexicalTheme` already includes it.
Map<String, BlockLayoutBuilder> layoutBlockLayouts({double gap = 0}) => {
  'layout-container': (context, element, buildChild) {
    if (element is! LayoutContainerNode) return const SizedBox.shrink();
    final items = element.children.toList();
    if (items.isEmpty) return const SizedBox.shrink();
    var tracks = parseTemplateColumns(element.templateColumns);
    // A template that names fewer columns than there are items gets `1fr`
    // for the rest, and one that names more draws the ones that exist: the
    // items are the content, the template only says how wide they are.
    if (tracks.length != items.length) {
      tracks = [
        for (var i = 0; i < items.length; i++)
          i < tracks.length ? tracks[i] : LayoutTrack.oneFraction,
      ];
    }
    // A mail's media query, carried as data: below this width the columns
    // stack whatever their tracks say. See `BlockCss.stackBelow`.
    final stackBelow = BlockCss.parse($getBlockStyle(element)).stackBelow;
    return _LayoutColumns(
      tracks: tracks,
      gap: gap,
      stackBelow: stackBelow,
      children: [
        for (var i = 0; i < items.length; i++)
          GridCell(
            key: ValueKey<String>('lexical-column-${items[i].key.value}'),
            placement: GridPlacement(row: 0, column: i),
            child: buildChild(items[i]),
          ),
      ],
    );
  },
};

/// The columns of one layout container.
///
/// A widget of its own, rather than the grid straight from the builder,
/// because `--stack-below` is a media query: it compares with the width of
/// the whole document, which only a widget below the document can read —
/// and it is rebuilt when that width changes, which a cached block is not.
/// The fixed-pixel rule stays the container's own: its columns cannot fit
/// in less than their sum, wherever it sits.
class _LayoutColumns extends StatelessWidget {
  const _LayoutColumns({
    required this.tracks,
    required this.gap,
    required this.stackBelow,
    required this.children,
  });

  final List<LayoutTrack> tracks;
  final double gap;
  final double? stackBelow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final below = stackBelow;
    final viewport = LexicalViewport.widthOf(context);
    final stacked = below != null && viewport != null && viewport < below;
    return LexicalGrid(
      columnCount: children.length,
      spacing: gap,
      columnWidths: (available) =>
          stacked ? null : resolveTemplateColumns(tracks, available, gap: gap),
      // What the closure is computed from: equal on a rebuild with the same
      // template, so the grid is not laid out again for a new closure.
      columnWidthsKey: <Object?>[gap, stacked, ...tracks],
      children: children,
    );
  }
}
