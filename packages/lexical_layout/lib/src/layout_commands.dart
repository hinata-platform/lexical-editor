/// Inserting and reshaping layouts, and the rules that keep them well formed.
library;

import 'package:lexical_core/lexical_core.dart';

import 'layout_nodes.dart';
import 'template_columns.dart';

/// Inserts a layout with the payload as its grid template — `"1fr 1fr"` —
/// and one empty column per track.
const LexicalCommand<String> insertLayoutCommand = LexicalCommand(
  'INSERT_LAYOUT',
);

/// Changes a layout's template, adding or removing columns to match.
const LexicalCommand<LayoutUpdate> updateLayoutCommand = LexicalCommand(
  'UPDATE_LAYOUT',
);

/// The payload of [updateLayoutCommand].
final class LayoutUpdate {
  /// Retemplates the container [nodeKey] to [template].
  const LayoutUpdate({required this.nodeKey, required this.template});

  /// The container to change.
  final NodeKey nodeKey;

  /// Its new grid template.
  final String template;
}

/// Wires layout editing onto [editor]: the two commands above and the
/// structural transforms upstream's `LayoutExtension` registers.
///
/// * A `layout-item` outside a `layout-container` is unwrapped into its
///   blocks — a paste or a block conversion can leave one stranded.
/// * A `layout-item` left empty gets a paragraph, so the column keeps a place
///   for the caret.
/// * A `layout-container` holding anything but items is unwrapped: the shape
///   is wrong, and its content is worth more than its columns.
///
/// The editor must have [layoutNodes] registered.
Unsubscribe registerLayout(LexicalEditor editor) {
  final unsubscribes = <Unsubscribe>[
    editor.registerCommand<String>(
      insertLayoutCommand,
      _insertLayout,
      CommandPriority.editor,
    ),
    editor.registerCommand<LayoutUpdate>(
      updateLayoutCommand,
      _updateLayout,
      CommandPriority.editor,
    ),
    editor.registerNodeTransform('layout-item', (node) {
      if (node is! LayoutItemNode) return;
      if (_removeIsolatedItem(node)) return;
      if (node.isEmpty) node.append($createParagraphNode());
    }),
    editor.registerNodeTransform('layout-container', (node) {
      if (node is! LayoutContainerNode) return;
      final children = node.children.toList();
      if (children.every($isLayoutItemNode)) return;
      for (final child in children) {
        node.insertBefore(child);
      }
      node.remove();
    }),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

bool _removeIsolatedItem(LayoutItemNode node) {
  if (node.getParent() is LayoutContainerNode) return false;
  for (final child in node.children.toList()) {
    node.insertBefore(child);
  }
  node.remove();
  return true;
}

/// How many columns [template] declares.
int layoutColumnCount(String template) {
  final count = parseTemplateColumns(template).length;
  return count == 0 ? 1 : count;
}

/// Creates a container for [template] with one empty column per track.
LayoutContainerNode $createLayoutWithColumns(String template) {
  final container = $createLayoutContainerNode(template);
  for (var i = 0; i < layoutColumnCount(template); i++) {
    container.append($createLayoutItemNode()..append($createParagraphNode()));
  }
  return container;
}

bool _insertLayout(String template) {
  final container = $createLayoutWithColumns(template);
  final selection = $getSelection();
  final block = selection is RangeSelection
      ? $getNearestBlock(selection.focus.getNode() ?? $getRoot())
      : $getRoot();
  if (block is RootNode) {
    $getRoot().append(container);
  } else if (block.getTextContent().isEmpty && block.getParent() is RootNode) {
    block.replace(container);
  } else {
    // Into the nearest root: a layout is a top-level block of whatever
    // shadow root the caret is in, never a child of a paragraph.
    var anchor = block;
    while (true) {
      final parent = anchor.getParent();
      if (parent == null || parent is RootNode || parent.isShadowRoot) break;
      anchor = parent;
    }
    anchor.insertAfter(container);
  }
  // Somewhere to go after the last column, which upstream offers through an
  // arrow-key escape; a trailing paragraph is the same thing, always there.
  if (container.getNextSibling() == null) {
    container.insertAfter($createParagraphNode());
  }
  final first = container.getFirstChild();
  if (first is ElementNode) first.selectStart();
  return true;
}

bool _updateLayout(LayoutUpdate update) {
  final container = $getNodeByKey(update.nodeKey);
  if (container is! LayoutContainerNode) return false;
  final wanted = layoutColumnCount(update.template);
  final had = container.childrenSize;
  if (wanted > had) {
    for (var i = had; i < wanted; i++) {
      container.append($createLayoutItemNode()..append($createParagraphNode()));
    }
  } else {
    for (var i = had - 1; i >= wanted; i--) {
      final item = container.getChildAtIndex(i);
      if (item is LayoutItemNode) item.remove();
    }
  }
  container.setTemplateColumns(update.template);
  return true;
}
