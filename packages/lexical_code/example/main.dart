// Run it with:  dart run example/main.dart
//
// Code blocks. This package models code; it does not tokenize it. Shipping a
// highlighter would mean shipping a grammar for every language and a
// dependency for all of them — so the node holds the runs, and whichever
// highlighter the application already uses produces them.
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';

void main() {
  final editor = LexicalEditor(nodes: codeNodes);
  registerRichText(editor);
  registerCode(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createCodeNode('dart')
          ..append($createCodeHighlightNode('void', 'keyword'))
          ..append($createCodeHighlightNode(' main() {'))
          ..append($createLineBreakNode())
          ..append($createCodeHighlightNode('  print', 'function'))
          ..append($createCodeHighlightNode("('hallo');"))
          ..append($createLineBreakNode())
          ..append($createCodeHighlightNode('}')),
      );
  }, discrete: true);

  editor.read(() {
    final code = $getRoot().getFirstChild()! as CodeNode;
    print('language: ${code.language}');
    print('content:\n${code.getTextContent()}');
    print('\nruns:');
    for (final run in code.children.whereType<CodeHighlightNode>()) {
      print(
        '  ${(run.highlightType ?? '—').padRight(10)} ${run.getTextContent()}',
      );
    }
  });

  // Enter inside a code block stays inside it: a line break, not a new
  // paragraph. Leaving is Enter on an empty last line, or the toolbar.
  editor.update(() {
    final code = $getRoot().getFirstChild()! as CodeNode;
    (code.getLastChild()! as TextNode).selectEnd();
  }, discrete: true);
  editor.dispatchCommand(insertParagraphCommand, null);

  print(
    '\nafter Enter at the end of the code block: '
    '${editor.read(() => $getRoot().children.map((n) => n.type).toList())}',
  );

  // Tab inserts real indentation rather than moving focus.
  editor.dispatchCommand(insertTabCommand, null);
  print(
    'the block still holds ${editor.read(() {
      final code = $getRoot().getFirstChild()! as CodeNode;
      return code.getTextContent().split('\n').length;
    })} lines',
  );
}
