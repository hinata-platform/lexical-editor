/// The node registry — this port's replacement for static polymorphism.
library;

import 'errors.dart';
import 'nodes/lexical_node.dart';

/// Declares one node type to an editor.
///
/// Upstream Lexical dispatches through `static getType()`, `static clone()`
/// and `static importJSON()`. **Dart has neither inherited statics nor
/// virtual static dispatch**, so that pattern cannot be transliterated; an
/// explicit registry replaces it. The substitution is an improvement rather
/// than a workaround — the extension point becomes visible, and adding a
/// node type no longer means editing the core.
///
/// [create] must be a zero-argument constructor call. That is what upstream
/// requires too, and it is a precondition for collaboration support later,
/// where a remote peer materializes nodes it has never seen configured.
final class NodeSpec<T extends LexicalNode> {
  /// Declares node type [type], constructed by [create].
  const NodeSpec({required this.type, required this.create});

  /// The wire-format `type` string. Must be unique within one editor.
  final String type;

  /// Constructs an empty instance, into which JSON is then applied.
  final T Function() create;

  /// Constructs an instance and checks that it agrees about its own type.
  ///
  /// A spec registered under the wrong string produces documents that
  /// decode on this client and fail on every other one, so it is worth
  /// catching at the first import rather than in production data.
  LexicalNode instantiate() {
    final node = create();
    if (node.type != type) {
      throw LexicalStateError(
        'NodeSpec("$type") created a node whose type is "${node.type}".',
      );
    }
    return node;
  }
}

/// Substitutes a different implementation for a registered node type.
///
/// This is how a consumer swaps a built-in for its own subclass — upstream's
/// node *replacement*. It is keyed on the replaced type string rather than
/// modelled as inheritance, and the replacement never inherits the original
/// node's key.
final class NodeReplacement {
  /// Replaces nodes of type [replacedType] with the result of [replaceWith].
  const NodeReplacement({
    required this.replacedType,
    required this.replaceWith,
  });

  /// The `type` string being replaced.
  final String replacedType;

  /// Produces the substitute for a freshly created node.
  final LexicalNode Function(LexicalNode original) replaceWith;
}

/// The set of node types one editor understands.
///
/// The registry is **per editor**, not global. Two editors in one app may
/// legitimately support different node sets, and a global registry makes
/// tests order-dependent — a failure mode that only shows up once the suite
/// is sharded. It is also **closed before first use**: registration happens
/// when the editor is constructed, so a document cannot decode differently
/// depending on when a plugin happened to load.
final class NodeRegistry {
  /// Builds a registry from [specs] and optional [replacements].
  factory NodeRegistry(
    List<NodeSpec<LexicalNode>> specs, {
    List<NodeReplacement> replacements = const [],
  }) {
    final byType = <String, NodeSpec<LexicalNode>>{};
    for (final spec in specs) {
      if (byType.containsKey(spec.type)) {
        throw LexicalStateError(
          'NodeRegistry: type "${spec.type}" registered twice.',
        );
      }
      byType[spec.type] = spec;
    }
    final byReplaced = <String, NodeReplacement>{};
    for (final replacement in replacements) {
      if (!byType.containsKey(replacement.replacedType)) {
        throw LexicalStateError(
          'NodeRegistry: cannot replace unregistered type '
          '"${replacement.replacedType}".',
        );
      }
      byReplaced[replacement.replacedType] = replacement;
    }
    return NodeRegistry._(
      Map.unmodifiable(byType),
      Map.unmodifiable(byReplaced),
    );
  }

  const NodeRegistry._(this._specs, this._replacements);

  final Map<String, NodeSpec<LexicalNode>> _specs;
  final Map<String, NodeReplacement> _replacements;

  /// The registered type strings.
  Iterable<String> get types => _specs.keys;

  /// The spec for [type], or `null` when unregistered.
  NodeSpec<LexicalNode>? specFor(String type) => _specs[type];

  /// Whether [type] is registered.
  bool knows(String type) => _specs.containsKey(type);

  /// The replacement declared for [type], or `null`.
  NodeReplacement? replacementFor(String type) => _replacements[type];
}
