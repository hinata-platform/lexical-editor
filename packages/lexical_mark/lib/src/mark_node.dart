/// The mark node.
library;

import 'package:lexical_core/lexical_core.dart';

/// Inline content tagged with one or more annotation identifiers.
class MarkNode extends ElementNode {
  /// Creates a mark carrying [ids].
  MarkNode([List<String>? ids]) : _ids = [...?ids];

  List<String> _ids;

  @override
  String get type => 'mark';

  @override
  bool get isInline => true;

  @override
  MarkNode clone() => MarkNode(_ids);

  @override
  void afterCloneFrom(covariant MarkNode prev) {
    super.afterCloneFrom(prev);
    _ids = [...prev._ids];
  }

  /// The annotation identifiers, in wire order.
  List<String> get ids => List.unmodifiable(getLatest<MarkNode>()._ids);

  /// Adds an identifier if it is not already present.
  MarkNode addId(String id) {
    final writable = getWritable<MarkNode>();
    if (!writable._ids.contains(id)) writable._ids.add(id);
    return writable;
  }

  /// Removes an identifier.
  MarkNode removeId(String id) {
    final writable = getWritable<MarkNode>();
    writable._ids.remove(id);
    return writable;
  }

  /// Whether this mark carries [id].
  bool hasId(String id) => getLatest<MarkNode>()._ids.contains(id);

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'ids': [..._ids],
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final ids = json['ids'];
    _ids = ids is List ? ids.whereType<String>().toList() : <String>[];
  }
}

/// Creates a mark, applying any registered node replacement.
MarkNode $createMarkNode([List<String>? ids]) =>
    $applyNodeReplacement(MarkNode(ids));
