/// Lossless preservation of node types this client does not implement.
library;

import 'lexical_node.dart';

/// A node whose type is not registered on this editor.
///
/// Upstream throws on an unregistered type, and so does this port by
/// default. But a mobile client whose web counterpart ships new node types
/// first would then hard-fail on documents its own users can already create,
/// and the alternative most ports reach for — dropping the node — turns a
/// version skew into permanent data loss the moment the user saves.
///
/// With `EditorConfig.preserveUnknownNodes` enabled, an unrecognized node
/// decodes into this: the original JSON is retained byte-for-byte, re-emitted
/// unchanged on export, and rendered as inert placeholder content.
///
/// The node is treated as a leaf even when the original had children. Its
/// children are *inside* the preserved JSON rather than decoded into the node
/// map, which guarantees exact re-emission and makes it impossible to edit
/// half of a structure this client does not understand.
final class UnknownNode extends LexicalNode {
  /// Wraps [raw], the verbatim serialized form of an unknown node.
  UnknownNode(Map<String, Object?> raw)
    : _raw = Map<String, Object?>.unmodifiable(raw),
      _type = raw['type'] is String ? raw['type']! as String : 'unknown';

  UnknownNode._(this._raw, this._type);

  final Map<String, Object?> _raw;
  final String _type;

  @override
  String get type => _type;

  /// Inline unless the original declared children, since a node with
  /// children is a block in every built-in type.
  @override
  bool get isInline => !_raw.containsKey('children');

  /// The preserved JSON, exactly as it was decoded.
  Map<String, Object?> get raw => _raw;

  @override
  UnknownNode clone() => UnknownNode._(_raw, _type);

  // Deliberately does not call super: the preserved JSON is the complete
  // serialized form, and letting the base class contribute `type`, `version`
  // or node state would rewrite a node whose entire contract is that it comes
  // back out exactly as it went in.
  @override
  // ignore: must_call_super
  Map<String, Object?> exportJson() => Map<String, Object?>.of(_raw);

  // Deliberately does not call super, for the same reason: the state is set
  // at construction and must not be re-derived from the JSON.
  @override
  // ignore: must_call_super
  void updateFromJson(Map<String, Object?> json) {}

  @override
  String getTextContent() => '';
}
