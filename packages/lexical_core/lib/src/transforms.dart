/// Node transforms: the fixed-point pass that runs after every update.
///
/// A transform is registered per node type and runs during the update, after
/// the closure completes, only for dirty nodes of that type, looping until
/// nothing further changes. That is what makes the model self-healing: an
/// invariant expressed once as a transform holds no matter how an edit
/// arrived.
library;

import 'package:meta/meta.dart';

import 'commands.dart';
import 'editor.dart';
import 'editor_state.dart';
import 'errors.dart';
import 'keys.dart';
import 'nodes/lexical_node.dart';
import 'nodes/text_node.dart';
import 'normalization.dart';

/// Runs over one dirty node of the type it was registered for.
///
/// A transform may mutate the node — that is the point — but must converge:
/// a transform that always marks its own node dirty loops forever.
typedef NodeTransform = void Function(LexicalNode node);

/// How many times the transform loop may repeat before it is called a bug.
///
/// An unbounded loop presents as a frozen UI with no clue as to cause; a
/// named exception points straight at the culprit. Enforced in release too,
/// because a hang in production is worse than an error.
const int maxTransformCycles = 100;

/// Per-editor transform storage, keyed by node type.
@internal
final class TransformRegistry {
  final Map<String, List<NodeTransform>> _byType =
      <String, List<NodeTransform>>{};

  /// Registers [transform] for nodes of [type].
  Unsubscribe register(String type, NodeTransform transform) {
    final list = _byType.putIfAbsent(type, () => <NodeTransform>[]);
    list.add(transform);
    return () {
      list.remove(transform);
      if (list.isEmpty) _byType.remove(type);
    };
  }

  /// The transforms registered for [type], or an empty list.
  List<NodeTransform> forType(String type) => _byType[type] ?? const [];

  /// Whether anything is registered at all.
  bool get isEmpty => _byType.isEmpty;

  /// The types that have at least one transform.
  Iterable<String> get types => _byType.keys;
}

/// Runs transforms to a fixed point over [editor]'s dirty sets.
///
/// The order is deliberate and matches upstream: leaves first, because
/// marking a leaf dirty also marks its ancestors, and only once no leaf is
/// left dirty do element transforms run. The root's transform runs **last**
/// in each element pass, which makes it the place for document-level
/// invariants such as "the document always ends with a paragraph".
@internal
void applyAllTransforms(EditorState state, LexicalEditor editor) {
  final transforms = editor.transforms;
  final dirtyLeaves = editor.dirtyLeaves;
  final dirtyElements = editor.dirtyElements;
  final nodeMap = state.nodeMapInternal;

  var untransformedLeaves = dirtyLeaves;
  var untransformedElements = dirtyElements;
  var cycles = 0;

  while (untransformedLeaves.isNotEmpty || untransformedElements.isNotEmpty) {
    if (++cycles > maxTransformCycles) {
      final stuck = _describeStuck(
        nodeMap,
        untransformedLeaves,
        untransformedElements,
      );
      throw LexicalStateError(
        'Transforms did not converge after $maxTransformCycles cycles. One '
        'or more transforms keep marking nodes dirty. Still dirty: $stuck',
      );
    }

    if (untransformedLeaves.isNotEmpty) {
      editor.dirtyLeaves = <NodeKey>{};
      for (final key in untransformedLeaves.toList()) {
        final node = nodeMap[key];
        if (node is TextNode &&
            node.isAttached &&
            node.isSimpleText &&
            !node.isUnmergeable) {
          $normalizeTextNode(node);
        }
        if (node != null && node.isAttached) {
          _applyTransforms(transforms, node);
        }
        dirtyLeaves.add(key);
      }
      untransformedLeaves = editor.dirtyLeaves;
      // Leaves take priority: an element transform should never see a tree
      // whose text runs have not settled yet.
      if (untransformedLeaves.isNotEmpty) continue;
    }

    editor.dirtyLeaves = <NodeKey>{};
    editor.dirtyElements = <NodeKey, bool>{};

    // Move the root to the end so its transform runs after every other
    // element in this pass — it is the update finalizer.
    final rootDirty = untransformedElements.remove(NodeKey.root);
    final pass = untransformedElements.entries.toList();
    if (rootDirty != null) pass.add(const MapEntry(NodeKey.root, true));

    for (final entry in pass) {
      dirtyElements[entry.key] = entry.value;
      // A node dirty only because a descendant changed does not run its own
      // transform; otherwise every ancestor would transform on every edit.
      if (!entry.value) continue;
      final node = nodeMap[entry.key];
      if (node != null && node.isAttached) {
        _applyTransforms(transforms, node);
      }
    }

    untransformedLeaves = editor.dirtyLeaves;
    untransformedElements = editor.dirtyElements;
  }

  editor.dirtyLeaves = dirtyLeaves;
  editor.dirtyElements = dirtyElements;
}

void _applyTransforms(TransformRegistry registry, LexicalNode node) {
  final transforms = registry.forType(node.type);
  if (transforms.isEmpty) return;
  for (final transform in List<NodeTransform>.of(transforms)) {
    transform(node);
    // A transform is allowed to remove its own node; the rest must not run.
    if (!node.isAttached) break;
  }
}

String _describeStuck(
  Map<NodeKey, LexicalNode> nodeMap,
  Set<NodeKey> leaves,
  Map<NodeKey, bool> elements,
) {
  final types = <String>{};
  for (final key in leaves) {
    final node = nodeMap[key];
    if (node != null) types.add(node.type);
  }
  for (final key in elements.keys) {
    final node = nodeMap[key];
    if (node != null) types.add(node.type);
  }
  return types.isEmpty ? '(none)' : types.join(', ');
}
