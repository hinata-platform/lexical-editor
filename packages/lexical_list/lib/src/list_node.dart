/// List containers.
library;

import 'package:lexical_core/lexical_core.dart';

import 'list_item_node.dart';

/// The kinds of list Lexical serializes.
enum ListType {
  /// Unordered.
  bullet('bullet', 'ul'),

  /// Ordered.
  number('number', 'ol'),

  /// A checklist. Its items carry a `checked` flag.
  check('check', 'ul');

  const ListType(this.wire, this.tag);

  /// The wire-format `listType` value.
  final String wire;

  /// The wire-format `tag` value that accompanies it.
  ///
  /// It is derived rather than authored — a check list is `ul` — so it is
  /// recomputed on export instead of being copied through.
  final String tag;

  /// Parses a wire-format list type, defaulting to [bullet].
  static ListType fromWire(Object? value) {
    for (final type in ListType.values) {
      if (type.wire == value) return type;
    }
    return ListType.bullet;
  }
}

/// A list container.
class ListNode extends ElementNode {
  /// Creates a list of [listType] numbered from [start].
  ListNode([this._listType = ListType.bullet, this._start = 1]);

  ListType _listType;
  int _start;

  @override
  String get type => 'list';

  @override
  ListNode clone() => ListNode(_listType, _start);

  @override
  void afterCloneFrom(covariant ListNode prev) {
    super.afterCloneFrom(prev);
    _listType = prev._listType;
    _start = prev._start;
  }

  /// The kind of list.
  ListType get listType => getLatest<ListNode>()._listType;

  /// The number the first item is labelled with.
  int get start => getLatest<ListNode>()._start;

  /// Changes the kind of list, renumbering its items.
  ListNode setListType(ListType value) {
    final writable = getWritable<ListNode>().._listType = value;
    renumberItems(writable);
    return writable;
  }

  /// Changes the starting number, renumbering its items.
  ListNode setStart(int value) {
    final writable = getWritable<ListNode>().._start = value;
    renumberItems(writable);
    return writable;
  }

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'listType': _listType.wire,
    'start': _start,
    'tag': _listType.tag,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _listType = ListType.fromWire(json['listType']);
    final start = json['start'];
    _start = start is int ? start : 1;
  }
}

/// Renumbers [list]'s direct item children from its start value.
///
/// `listitem.value` is derived — `start + index` — not authored. It is
/// maintained by a transform rather than recomputed on export, because
/// import must stay verbatim: a document whose values disagree with its
/// positions is upstream's problem to have created, and silently rewriting
/// it on load would break the fixed-point round-trip.
void renumberItems(ListNode list) {
  final start = list.start;
  var index = 0;
  for (final child in list.children) {
    if (child is ListItemNode) {
      final expected = start + index;
      if (child.value != expected) child.setValue(expected);
      index++;
    }
  }
}

/// Registers the transform that keeps item numbering in step with positions.
Unsubscribe registerListNumbering(LexicalEditor editor) =>
    editor.registerNodeTransform('list', (node) {
      if (node is ListNode) renumberItems(node);
    });

/// Creates a list, applying any registered node replacement.
ListNode $createListNode([
  ListType listType = ListType.bullet,
  int start = 1,
]) => $applyNodeReplacement(ListNode(listType, start));
