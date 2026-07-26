import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

LexicalEditor _editor({bool highlight = true}) {
  final editor = LexicalEditor(nodes: codeNodes);
  registerRichText(editor);
  registerCode(editor);
  if (highlight) registerCodeHighlighting(editor);
  return editor;
}

void _seed(LexicalEditor editor, String source, {String? language = 'dart'}) {
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createCodeNode(language)..append($createTextNode(source)));
  }, discrete: true);
}

CodeNode _block(LexicalEditor editor) =>
    editor.editorState.read(() => $getRoot().getFirstChild()! as CodeNode);

/// The block's children as `(text, highlightType)`, line breaks as `\n`.
List<(String, String?)> _runs(LexicalEditor editor) => editor.read(() {
  final code = $getRoot().getFirstChild()! as ElementNode;
  return [
    for (final child in code.children)
      if (child is CodeHighlightNode)
        (child.getTextContent(), child.highlightType)
      else
        (child.getTextContent(), child.type),
  ];
});

String _text(LexicalEditor editor) =>
    editor.read(() => $getRoot().getFirstChild()!.getTextContent());

/// Where the caret sits, counted in characters from the start of the block.
int _caret(LexicalEditor editor) => editor.read(() {
  final selection = $getSelection()! as RangeSelection;
  final code = $getRoot().getFirstChild()! as ElementNode;
  var offset = 0;
  for (final child in code.children) {
    if (child.key == selection.anchor.key) {
      return offset + selection.anchor.offset;
    }
    offset += child.getTextContent().length;
  }
  return -1;
});

/// The classification of the run the caret is in.
String? _caretType(LexicalEditor editor) => editor.read(() {
  final node = ($getSelection()! as RangeSelection).anchor.getNode();
  return node is CodeHighlightNode ? node.highlightType : null;
});

/// Every token name the Lexical playground's theme has a colour for.
///
/// Copied from `PlaygroundEditorTheme.codeHighlight` at 0.48.0. The tokenizer
/// must stay inside this set: a classification the web has no entry for is a
/// run that arrives there uncoloured.
const _playgroundTokenNames = {
  'atrule',
  'attr',
  'boolean',
  'builtin',
  'cdata',
  'char',
  'class',
  'class-name',
  'comment',
  'constant',
  'deleted',
  'doctype',
  'entity',
  'function',
  'important',
  'inserted',
  'keyword',
  'namespace',
  'number',
  'operator',
  'prolog',
  'property',
  'punctuation',
  'regex',
  'selector',
  'string',
  'symbol',
  'tag',
  'unchanged',
  'url',
  'variable',
};

/// A snippet per language, exercising the rules each one differs by.
const _samples = {
  'c': '#include <stdio.h>\nint main(void) { printf("hi %d", 1); }',
  'cpp': '// a note\nclass Foo { std::string name = "x"; };',
  'csharp': 'public class Foo { private int x = 1; /* set */ }',
  'dart': "void main() {\n  print('hi'); // 1\n}",
  'go': 'func main() {\n\tfmt.Println("hi")\n}',
  'java': '@Override\npublic String toString() { return "Foo"; }',
  'javascript': "const x = `t${1}`; // note\nconsole.log('hi');",
  'json': '{"name": "lexical", "count": 20, "ok": true}',
  'kotlin': 'fun main() {\n  println("hi")\n}',
  'python': '# note\ndef main():\n    print("hi", True, None)',
  'rust': 'fn main() {\n    println!("hi");\n}',
  'shell': '# note\nexport PATH="\$HOME/bin"\necho \${PATH}',
  'sql': 'SELECT count(*) FROM users WHERE name = \'x\'; -- note',
  'swift': '@MainActor\nfunc main() { print("hi", nil) }',
  'typescript': 'type X = { a: number };\nexport const x: X = { a: 1 };',
};

void main() {
  group('tokenizer', () {
    test('is lossless for every language it knows', () {
      for (final language in builtInCodeLanguages) {
        final source = _samples[language.id] ?? 'let x = 1; // note';
        final tokens = tokenizeCode(source, language: language.id);
        expect(
          tokens.map((token) => token.text).join(),
          source,
          reason: 'tokenizing ${language.id} changed the text',
        );
      }
    });

    test('classifies only names the web has a colour for', () {
      for (final language in builtInCodeLanguages) {
        final source = _samples[language.id] ?? 'let x = 1; // note';
        for (final token in tokenizeCode(source, language: language.id)) {
          if (token.type == null) continue;
          expect(
            _playgroundTokenNames,
            contains(token.type),
            reason: '${language.id} emitted "${token.type}"',
          );
        }
      }
    });

    test('finds something to say about every language it ships', () {
      for (final language in builtInCodeLanguages) {
        final source = _samples[language.id] ?? 'let x = 1; // note';
        final types = tokenizeCode(
          source,
          language: language.id,
        ).map((token) => token.type).whereType<String>().toSet();
        expect(
          types,
          isNotEmpty,
          reason: '${language.id} produced no classified runs at all',
        );
      }
    });

    test('reads Dart the way a Dart programmer would', () {
      final tokens = tokenizeCode(
        "// greet\nvoid greet(String name) => print('hi \$name');",
        language: 'dart',
      );
      String? typeOf(String text) => tokens
          .where((token) => token.text == text)
          .map((token) => token.type)
          .firstOrNull;

      expect(typeOf('// greet'), 'comment');
      expect(typeOf('void'), 'keyword');
      expect(typeOf('greet'), 'function');
      expect(typeOf('String'), 'builtin');
      expect(typeOf("'hi \$name'"), 'string');
    });

    test('an unterminated string stops at the line break', () {
      // What a half-typed quote looks like, and the reason it must not turn
      // the rest of the block green.
      final tokens = tokenizeCode('"open\nint x = 1;', language: 'c');
      expect(tokens.first, const CodeToken('"open', 'string'));
      expect(tokens.map((token) => token.text).join(), '"open\nint x = 1;');
    });

    test('a hash is a comment in Python and a directive in C', () {
      expect(
        tokenizeCode('#include <x>', language: 'c').first.type,
        'property',
      );
      expect(
        tokenizeCode('#include <x>', language: 'python').first.type,
        'comment',
      );
    });

    test('SQL keywords match whatever case they are shouted in', () {
      for (final source in ['SELECT', 'select', 'SeLeCt']) {
        expect(tokenizeCode(source, language: 'sql').first.type, 'keyword');
      }
      // …and the same word in a case-sensitive language is not a keyword.
      expect(tokenizeCode('SELECT', language: 'dart').first.type, 'class-name');
    });

    test('a JSON key is a property and a JSON value is a string', () {
      final tokens = tokenizeCode('{"a": "b"}', language: 'json');
      expect(tokens, contains(const CodeToken('"a"', 'property')));
      expect(tokens, contains(const CodeToken('"b"', 'string')));
    });

    test('a shell variable is a variable, in both spellings', () {
      final types = tokenizeCode(
        r'echo $HOME ${PATH}',
        language: 'shell',
      ).where((token) => token.type == 'variable').map((t) => t.text);
      expect(types, [r'$HOME', r'${PATH}']);
    });

    test('an alias finds the same language as its name', () {
      expect(
        tokenizeCode('const x = 1;', language: 'js'),
        tokenizeCode('const x = 1;', language: 'javascript'),
      );
    });

    test('an unknown language yields one unclassified run', () {
      expect(tokenizeCode('void main()', language: 'brainfuck'), [
        const CodeToken('void main()'),
      ]);
      expect(tokenizeCode('void main()'), [const CodeToken('void main()')]);
    });
  });

  group('highlighting a block', () {
    test('replaces the text with classified runs', () {
      final editor = _editor();
      _seed(editor, "void main() { print('hi'); }");
      expect(_runs(editor), contains(('void', 'keyword')));
      expect(_runs(editor), contains(("'hi'", 'string')));
      expect(_text(editor), "void main() { print('hi'); }");
    });

    test('line breaks and tabs become nodes, as they do upstream', () {
      final editor = _editor();
      _seed(editor, 'void main() {\n\tprint(1);\n}');
      expect(_runs(editor), contains(('\n', 'linebreak')));
      expect(_runs(editor), contains(('\t', 'tab')));
      // Flat: every child is a leaf, so no run is nested inside another.
      expect(
        editor.read(() {
          final code = $getRoot().getFirstChild()! as ElementNode;
          return code.children.every((child) => child is! ElementNode);
        }),
        isTrue,
      );
      expect(_text(editor), 'void main() {\n\tprint(1);\n}');
    });

    test('is a fixed point: a second pass changes nothing', () {
      // The property the transform loop depends on. Without it, replacing the
      // runs marks them dirty, which highlights again, forever.
      final editor = _editor(highlight: false);
      _seed(editor, 'void main() {}');

      final changed = <bool>[];
      editor.update(() {
        changed.add($highlightCode(_block(editor)));
      }, discrete: true);
      final first = _runs(editor);

      editor.update(() {
        changed
          ..add($highlightCode(_block(editor)))
          ..add($highlightCode(_block(editor)));
      }, discrete: true);

      expect(changed, [true, false, false]);
      expect(_runs(editor), first);
    });

    test('typing keeps the caret where the user put it', () {
      final editor = _editor();
      _seed(editor, 'voi main() {}');
      editor.update(() {
        final code = $getRoot().getFirstChild()! as ElementNode;
        (code.getFirstChild()! as TextNode).select(3, 3);
      }, discrete: true);

      editor.dispatchCommand(insertTextCommand, 'd');

      expect(_text(editor), 'void main() {}');
      expect(_caret(editor), 4);
      // The run it landed in is the keyword the fourth character completed.
      expect(_caretType(editor), 'keyword');
    });

    test('typing at the end of a block stays at the end', () {
      final editor = _editor();
      _seed(editor, 'const a = 1');
      editor.update(() {
        final code = $getRoot().getFirstChild()! as ElementNode;
        (code.getLastChild()! as TextNode).selectEnd();
      }, discrete: true);

      editor.dispatchCommand(insertTextCommand, '2');
      expect(_text(editor), 'const a = 12');
      expect(_caret(editor), 12);
    });

    test('changing the language re-colours the same text', () {
      final editor = _editor();
      _seed(editor, 'func main() { let x = 1 }', language: 'swift');
      expect(_runs(editor), contains(('func', 'keyword')));
      expect(_runs(editor), contains(('let', 'keyword')));

      editor.update(() => _block(editor).setLanguage('c'), discrete: true);
      // Neither word is a keyword in C, and the text is untouched.
      expect(_runs(editor), isNot(contains(('func', 'keyword'))));
      expect(_text(editor), 'func main() { let x = 1 }');
    });

    test('a block in an unknown language is left exactly as it was', () {
      // Another client may have highlighted it for a language this build does
      // not know; flattening it into one grey run would throw that away.
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createCodeNode('brainfuck')
              ..append($createCodeHighlightNode('++', 'operator'))
              ..append($createCodeHighlightNode('.', 'punctuation')),
          );
      }, discrete: true);
      expect(_runs(editor), [('++', 'operator'), ('.', 'punctuation')]);
    });

    test('a block with no language at all is left alone', () {
      final editor = _editor();
      _seed(editor, 'void main() {}', language: null);
      // Still the plain text node it was seeded with — not even flattened
      // into an unclassified highlight run.
      expect(_runs(editor), [('void main() {}', 'text')]);
    });

    test('runs become plain text when the block stops being code', () {
      final editor = _editor();
      _seed(editor, 'void main() {}');
      editor.update(() {
        final code = $getRoot().getFirstChild()! as ElementNode;
        code.replace($createParagraphNode()..appendAll(code.children.toList()));
      }, discrete: true);

      expect(
        editor.read(() {
          final paragraph = $getRoot().getFirstChild()! as ElementNode;
          return paragraph.children.every((child) => child.type == 'text');
        }),
        isTrue,
        reason: 'code colours would otherwise survive into the paragraph',
      );
      expect(_text(editor), 'void main() {}');
    });

    test('the highlighted block round-trips through JSON unchanged', () {
      final editor = _editor();
      _seed(editor, "void main() {\n  print('hi'); // 1\n}");
      final json = editor.toJsonString();

      final reopened = _editor();
      reopened.setEditorState(reopened.parseEditorStateFromString(json));
      expect(reopened.toJsonString(), json);
      expect(_runs(reopened), _runs(editor));
    });
  });
}
