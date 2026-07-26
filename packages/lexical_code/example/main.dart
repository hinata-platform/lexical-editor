// Run it with:  dart run example/main.dart
//
// Code blocks, and the highlighting that keeps them coloured. The tokenizer is
// part of this package and depends on nothing: a table of rules per language,
// not a grammar, because telling a keyword from a string from a comment is all
// a highlighter has to do.
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';

const _source = '''
// A comment, a keyword and a string.
void main() {
  print('hello');
}''';

void main() {
  final editor = LexicalEditor(nodes: codeNodes);
  registerRichText(editor);
  registerCode(editor);
  // The whole feature. Nothing else in this file mentions highlighting again:
  // the text goes in, and the runs follow on every commit.
  registerCodeHighlighting(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createCodeNode('dart')..append($createTextNode(_source)));
  }, discrete: true);

  editor.read(() {
    final code = $getRoot().getFirstChild()! as CodeNode;
    print('language: ${code.language}');
    print('runs:');
    for (final run in code.children) {
      final type = run is CodeHighlightNode ? run.highlightType : run.type;
      final text = run.getTextContent().replaceAll('\n', r'\n');
      print('  ${(type ?? '—').padRight(11)} $text');
    }
  });

  // The same text, read by different rules. `void` is a keyword in Dart and an
  // ordinary word in Python, so changing the language re-colours the block —
  // without touching a character of it.
  editor.update(() {
    ($getRoot().getFirstChild()! as CodeNode).setLanguage('python');
  }, discrete: true);

  editor.read(() {
    final code = $getRoot().getFirstChild()! as CodeNode;
    final keywords = code.children
        .whereType<CodeHighlightNode>()
        .where((run) => run.highlightType == 'keyword')
        .map((run) => run.getTextContent());
    // Read as Python, `void` is an ordinary word and `//` is not a comment at
    // all — so the only keyword left is the `and` inside that first line.
    print('\nas python, the keywords are: ${keywords.join(', ')}');
    print('and the text is unchanged: ${code.getTextContent() == _source}');
  });

  // Tokenizing without an editor, for anyone who only wants the classification.
  print('\ndirect: ${tokenizeCode('SELECT 1;', language: 'sql')}');
  print('languages: ${builtInCodeLanguages.map((l) => l.id).join(' ')}');

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
}
