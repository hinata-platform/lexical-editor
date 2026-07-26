/// Code blocks, syntax highlighting and the editing behaviour code needs.
///
/// The model is [CodeNode] and [CodeHighlightNode]; the highlighting is a
/// self-contained tokenizer with no dependencies, covering the languages in
/// `builtInCodeLanguages` and extensible with `CodeLanguage.register`.
///
/// ```dart
/// final editor = LexicalEditor(nodes: codeNodes);
/// registerCode(editor);              // Enter and Tab inside a code block
/// registerCodeHighlighting(editor);  // colour, kept in step with the text
///
/// editor.update(() {
///   $getRoot().append(
///     $createCodeNode('dart')..append($createTextNode('void main() {}')),
///   );
/// }, discrete: true);
/// ```
///
/// The classification each run carries is a Prism token name, which is what
/// Lexical web writes into `highlightType` — so a block highlighted here is
/// coloured by the playground's stylesheet, and one highlighted there is
/// coloured by the Flutter theme. Rendering it is the render layer's job: map
/// the token name to a `TextStyle`, as `lexical_editor_flutter`'s default
/// theme does.
library;

import 'package:lexical_core/lexical_core.dart';

import 'src/code_node.dart';

export 'src/code_commands.dart' show registerCode;
export 'src/code_highlighting.dart'
    show $highlightCode, registerCodeHighlighting;
export 'src/code_language.dart' show CodeLanguage, builtInCodeLanguages;
export 'src/code_node.dart'
    show CodeHighlightNode, CodeNode, $createCodeHighlightNode, $createCodeNode;
export 'src/code_tokenizer.dart' show CodeToken, tokenizeCode;

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get codeNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<CodeNode>(type: 'code', create: CodeNode.new),
  NodeSpec<CodeHighlightNode>(
    type: 'code-highlight',
    create: CodeHighlightNode.new,
  ),
];
