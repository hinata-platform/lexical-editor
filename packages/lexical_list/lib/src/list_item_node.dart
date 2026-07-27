/// List items.
library;

import 'package:lexical_core/lexical_core.dart';

import 'list_node.dart';

/// One entry in a list.
///
/// A list item holds either inline content or a nested list — the latter is
/// how Lexical represents nesting, rather than by nesting lists directly.
class ListItemNode extends ElementNode {
  /// Creates an item, optionally with a [checked] state.
  ///
  /// [checked] is `null` for items outside a check list, which is exactly
  /// how it is serialized: the key is **absent**, not present with value
  /// `null`. Those are different things on the wire.
  ListItemNode([this._checked, this._value = 1]);

  bool? _checked;
  int _value;

  @override
  String get type => 'listitem';

  @override
  ListItemNode clone() => ListItemNode(_checked, _value);

  @override
  void afterCloneFrom(covariant ListItemNode prev) {
    super.afterCloneFrom(prev);
    _checked = prev._checked;
    _value = prev._value;
  }

  /// Whether the item is ticked, or `null` outside a check list.
  bool? get checked => getLatest<ListItemNode>()._checked;

  /// The number this item is labelled with.
  int get value => getLatest<ListItemNode>()._value;

  /// Sets the ticked state. Pass `null` to leave the check list.
  ListItemNode setChecked(bool? value) =>
      getWritable<ListItemNode>().._checked = value;

  /// Toggles the ticked state, treating an unticked item as `false`.
  ListItemNode toggleChecked() => setChecked(!(checked ?? false));

  /// Sets the label number. Normally maintained by `renumberItems`.
  ListItemNode setValue(int value) =>
      getWritable<ListItemNode>().._value = value;

  @override
  ElementNode insertNewAfter({required bool isAtEnd}) {
    // A new item continues the list. Inside a check list it starts unticked
    // rather than inheriting the state above, which would silently mark work
    // as done that nobody did.
    final item = $createListItemNode(checked == null ? null : false);
    insertAfter(item);
    return item;
  }

  @override
  bool collapseAtStart() {
    // Backspace at the start of the first item is the way out of a list. With
    // nothing before it there is no character to delete, so without this the
    // key does nothing and a list at the top of a document cannot be undone
    // with the keyboard at all.
    final list = getParent();
    if (list is! ListNode) return false;
    if (isNestedListHolder) return false;

    // A nested item steps out one level rather than leaving the list
    // altogether — the same ladder Shift-Tab and Enter on an empty item walk.
    var outer = list.getParent();
    while (outer != null && outer is! ListItemNode) {
      outer = outer.getParent();
    }
    if (outer is ListItemNode) {
      final following = getNextSiblings();
      if (following.isNotEmpty) {
        append($createListNode(list.listType)..appendAll(following));
      }
      outer.insertAfter(this);
      if (list.isEmpty) list.remove();
      if (outer.isEmpty) outer.remove();
      selectStart();
      return true;
    }

    final paragraph = $createParagraphNode()..appendAll(children.toList());
    final following = getNextSiblings();
    if (following.isNotEmpty) {
      // The items below stay a list of their own rather than being dragged
      // into the paragraph.
      list.insertAfter(
        $createListNode(list.listType, list.start)..appendAll(following),
      );
    }
    list.insertAfter(paragraph);
    remove();
    if (list.isEmpty) list.remove();
    paragraph.selectStart();
    return true;
  }

  /// An item holding only a nested list is a structural wrapper, not content.
  bool get isNestedListHolder {
    final first = getFirstChild();
    return childrenSize == 1 && first != null && first.type == 'list';
  }

  @override
  Map<String, Object?> exportJson() {
    final json = {...super.exportJson(), 'value': _value};
    // Present only inside a check list — an omit-vs-null case that a blanket
    // "skip nulls" or "write everything" rule gets wrong in one direction or
    // the other.
    if (_checked != null) json['checked'] = _checked;
    return json;
  }

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final checked = json['checked'];
    _checked = checked is bool ? checked : null;
    final value = json['value'];
    _value = value is int ? value : 1;
  }
}

/// Creates a list item, applying any registered node replacement.
ListItemNode $createListItemNode([bool? checked]) =>
    $applyNodeReplacement(ListItemNode(checked));
