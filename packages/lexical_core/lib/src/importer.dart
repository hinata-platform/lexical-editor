/// Decoding a serialized document into an editor state.
///
/// The decoder treats its input as hostile. It walks with an explicit
/// worklist rather than recursion, so a deeply nested document cannot blow
/// the stack, and every node passes through the registry — there is no
/// dynamic dispatch on the `type` string.
library;

import 'package:meta/meta.dart';

import 'editor.dart';
import 'editor_state.dart';
import 'errors.dart';
import 'json/import_limits.dart';
import 'keys.dart';
import 'nodes/element_node.dart';
import 'nodes/lexical_node.dart';
import 'nodes/text_node.dart';
import 'nodes/unknown_node.dart';
import 'updates.dart';

/// Decodes [json] into a frozen editor state for [editor].
@internal
EditorState importEditorState(LexicalEditor editor, Map<String, Object?> json) {
  final rootJson = json['root'];
  if (rootJson is! Map) {
    throw const MalformedDocumentException(
      'document must have a "root" object',
    );
  }
  final rootMap = _asJsonObject(rootJson);
  if (rootMap['type'] != 'root') {
    throw const MalformedDocumentException(
      'document root must have type "root"',
    );
  }

  final state = EditorState.empty();
  final budget = ImportBudget(editor.config.importLimits);

  // Parsing allocates keys and marks nodes dirty, so it must run in an
  // update context — but against its own dirty bookkeeping, or it would
  // pollute an update that happens to be in flight.
  final savedLeaves = editor.dirtyLeaves;
  final savedElements = editor.dirtyElements;
  final savedClone = editor.cloneNotNeeded;
  final savedType = editor.dirtyType;
  editor
    ..dirtyLeaves = <NodeKey>{}
    ..dirtyElements = <NodeKey, bool>{}
    ..cloneNotNeeded = <NodeKey>{}
    ..dirtyType = DirtyType.none;
  try {
    runInUpdateContext(editor, state, () {
      _decodeInto(editor, rootMap, budget);
    });
  } finally {
    editor
      ..dirtyLeaves = savedLeaves
      ..dirtyElements = savedElements
      ..cloneNotNeeded = savedClone
      ..dirtyType = savedType;
  }

  state.freeze();
  return state;
}

class _Frame {
  _Frame(this.parent, this.children, this.depth);

  final ElementNode parent;
  final List<Object?> children;
  final int depth;
  int index = 0;
}

void _decodeInto(
  LexicalEditor editor,
  Map<String, Object?> rootJson,
  ImportBudget budget,
) {
  final root = $getRoot();
  budget.countNode();
  root.updateFromJson(rootJson);

  final stack = <_Frame>[_Frame(root, _childrenOf(rootJson), 1)];
  while (stack.isNotEmpty) {
    final frame = stack.last;
    if (frame.index >= frame.children.length) {
      stack.removeLast();
      continue;
    }
    final childJson = frame.children[frame.index++];
    if (childJson is! Map) {
      throw const MalformedDocumentException(
        'children entries must be JSON objects',
      );
    }
    final childMap = _asJsonObject(childJson);
    final node = _createNode(editor, childMap, budget);
    frame.parent.append(node);
    if (node is ElementNode) {
      final children = _childrenOf(childMap);
      if (children.isNotEmpty) {
        budget.checkDepth(frame.depth + 1);
        stack.add(_Frame(node, children, frame.depth + 1));
      }
    }
  }
}

List<Object?> _childrenOf(Map<String, Object?> json) {
  final children = json['children'];
  if (children == null) return const [];
  if (children is! List) {
    throw const MalformedDocumentException('"children" must be an array');
  }
  return children;
}

LexicalNode _createNode(
  LexicalEditor editor,
  Map<String, Object?> json,
  ImportBudget budget,
) {
  budget.countNode();
  final type = json['type'];
  if (type is! String || type.isEmpty) {
    throw const MalformedDocumentException('every node must have a "type"');
  }
  if (type == 'root') {
    // A second root would collide with the reserved `root` key and detach
    // part of the document. Reject it rather than repairing it.
    throw const MalformedDocumentException(
      'a "root" node may only appear at the top level',
    );
  }

  final spec = editor.registry.specFor(type);
  if (spec == null) {
    switch (editor.config.unknownNodePolicy) {
      case UnknownNodePolicy.preserve:
        return UnknownNode(json);
      case UnknownNodePolicy.throwError:
        throw UnknownNodeTypeException(type);
    }
  }

  final node = spec.instantiate();
  node.updateFromJson(json);
  if (node is TextNode) {
    budget.countText(node.textInternal.length);
    if (node.textInternal.contains('\n')) {
      throw const MalformedDocumentException(
        'text nodes must not contain newlines; use a linebreak node',
      );
    }
  }
  return node;
}

Map<String, Object?> _asJsonObject(Map<Object?, Object?> map) {
  if (map is Map<String, Object?>) return map;
  final result = <String, Object?>{};
  for (final entry in map.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const MalformedDocumentException(
        'JSON object keys must be strings',
      );
    }
    result[key] = entry.value;
  }
  return result;
}
