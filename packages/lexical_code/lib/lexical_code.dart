/// Code block and syntax-highlight nodes for `lexical_core`.
///
/// This package models code; it does not tokenize it. Syntax highlighting is
/// a per-language concern with its own dependency weight, so producing
/// [CodeHighlightNode]s is left to whatever highlighter the application
/// already uses — the wire format only needs the classification string.
///
/// ```dart
/// final editor = LexicalEditor(nodes: codeNodes);
/// editor.update(() {
///   $getRoot().append(
///     $createCodeNode('dart')
///       ..append($createCodeHighlightNode('void', 'keyword'))
///       ..append($createTextNode(' main() {}')),
///   );
/// }, discrete: true);
/// ```
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/code_node.dart';

export 'src/code_node.dart'
    show CodeHighlightNode, CodeNode, $createCodeHighlightNode, $createCodeNode;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get codeNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<CodeNode>(type: 'code', create: CodeNode.new),
  NodeSpec<CodeHighlightNode>(
    type: 'code-highlight',
    create: CodeHighlightNode.new,
  ),
];
