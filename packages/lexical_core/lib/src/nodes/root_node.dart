/// The document root.
library;

import '../errors.dart';
import '../keys.dart';
import 'decorator_node.dart';
import 'element_node.dart';
import 'lexical_node.dart';

/// The single top-level node of a document.
///
/// The root is special in three ways: its key is the fixed string `root`
/// rather than a generated one, it cannot be removed or re-parented, and it
/// accepts only block-level children — a text node directly under the root
/// is a structural error, not merely unusual.
final class RootNode extends ElementNode {
  /// Creates the root node.
  RootNode() : super.withKey(NodeKey.root);

  @override
  String get type => 'root';

  /// The root terminates upward traversal, like any shadow root.
  @override
  bool get isShadowRoot => true;

  @override
  RootNode clone() => RootNode();

  @override
  ElementNode splice(
    int start,
    int deleteCount,
    List<LexicalNode> nodesToInsert,
  ) {
    for (final node in nodesToInsert) {
      if (node is! ElementNode && node is! DecoratorNode) {
        throw LexicalTreeError(
          'RootNode: only element or decorator nodes may be children of the '
          'root, got ${node.type}.',
        );
      }
    }
    return super.splice(start, deleteCount, nodesToInsert);
  }

  @override
  void remove({bool preserveEmptyParent = false}) =>
      throw const LexicalTreeError('remove: cannot be called on the root');

  @override
  T replace<T extends LexicalNode>(
    T replaceWith, {
    bool includeChildren = false,
  }) => throw const LexicalTreeError('replace: cannot be called on the root');

  @override
  T insertBefore<T extends LexicalNode>(T nodeToInsert) =>
      throw const LexicalTreeError(
        'insertBefore: cannot be called on the root',
      );

  @override
  T insertAfter<T extends LexicalNode>(T nodeToInsert) =>
      throw const LexicalTreeError('insertAfter: cannot be called on the root');
}
