/// The editing behaviour a list needs beyond its node shape.
library;

import 'package:lexical_core/lexical_core.dart';

import 'list_item_node.dart';
import 'list_node.dart';

/// Wires list behaviour on top of [registerListNumbering].
///
/// Two rules, both registered at [CommandPriority.beforeEditor] so they
/// pre-empt the core defaults only where they apply and fall through
/// everywhere else:
///
/// * **Enter on an empty item ends the list.** Without it there is no way out
///   of a list except the mouse, and the second Enter — the one everybody
///   presses — silently adds another blank bullet.
/// * **Tab and Shift-Tab nest and un-nest.** They arrive as the indent and
///   outdent commands, so a host that binds those keys differently keeps
///   working.
Unsubscribe registerList(LexicalEditor editor) {
  final unsubscribes = <Unsubscribe>[
    registerListNumbering(editor),
    editor.registerCommand<void>(
      insertParagraphCommand,
      (_) => _endListOnEmptyItem(),
      CommandPriority.beforeEditor,
    ),
    editor.registerCommand<void>(
      outdentContentCommand,
      (_) => _outdentItems(),
      CommandPriority.beforeEditor,
    ),
    editor.registerCommand<void>(
      indentContentCommand,
      (_) => _indentItems(),
      CommandPriority.beforeEditor,
    ),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

ListItemNode? _itemAtCaret() {
  final selection = $getSelection();
  if (selection is! RangeSelection || !selection.isCollapsed) return null;
  return _enclosingItem(selection.anchor.getNode());
}

ListItemNode? _enclosingItem(LexicalNode? node) {
  var current = node;
  while (current != null) {
    if (current is ListItemNode) return current;
    current = current.getParent();
  }
  return null;
}

bool _endListOnEmptyItem() {
  final item = _itemAtCaret();
  if (item == null) return false;
  if (item.getTextContent().isNotEmpty || item.childrenSize > 0) return false;

  final list = item.getParent();
  if (list is! ListNode) return false;

  // A nested item un-nests one level first; only a top-level empty item
  // leaves the list altogether. That is the ladder people expect from Enter.
  final outerItem = _enclosingItem(list.getParent());
  if (outerItem != null) {
    item.remove();
    final promoted = $createListItemNode(
      (list.listType == ListType.check) ? false : null,
    );
    outerItem.insertAfter(promoted);
    promoted.selectStart();
    return true;
  }

  final paragraph = $createParagraphNode();
  final following = item.getNextSiblings();
  if (following.isEmpty) {
    list.insertAfter(paragraph);
  } else {
    // Splitting the list keeps the items below it in a list of their own,
    // rather than dropping them into the paragraph.
    final tail = $createListNode(list.listType, list.start)
      ..appendAll(following);
    list
      ..insertAfter(tail)
      ..insertAfter(paragraph);
  }
  item.remove();
  paragraph.selectStart();
  return true;
}

bool _indentItems() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return false;
  final items = _selectedItems(selection);
  if (items.isEmpty) return false;

  for (final item in items) {
    final previous = item.getPreviousSibling();
    if (previous is! ListItemNode) continue;
    final list = item.getParentOrThrow();
    if (list is! ListNode) continue;
    // Nesting is a list inside the *previous* item, which is how Lexical
    // represents it — not by increasing an indent counter.
    final existing = previous.getLastChild();
    if (existing is ListNode) {
      existing.append(item);
    } else {
      previous.append($createListNode(list.listType)..append(item));
    }
  }
  return true;
}

bool _outdentItems() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return false;
  final items = _selectedItems(selection);
  if (items.isEmpty) return false;

  var handled = false;
  for (final item in items) {
    final list = item.getParent();
    if (list is! ListNode) continue;
    final outerItem = _enclosingItem(list.getParent());
    if (outerItem == null) continue;
    final following = item.getNextSiblings();
    if (following.isNotEmpty) {
      // Items below the one being promoted stay nested, under it.
      item.append($createListNode(list.listType)..appendAll(following));
    }
    outerItem.insertAfter(item);
    if (list.isEmpty) list.remove();
    if (outerItem.isEmpty) outerItem.remove();
    handled = true;
  }
  return handled;
}

List<ListItemNode> _selectedItems(RangeSelection selection) {
  final items = <NodeKey, ListItemNode>{};
  for (final block in selection.getBlocks()) {
    final item = _enclosingItem(block);
    if (item != null) items[item.key] = item;
  }
  return items.values.toList();
}
