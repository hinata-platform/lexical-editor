// Run it with:  dart run example/main.dart
//
// Markdown in and out. Each rule describes *both* directions in one
// declaration, which is what keeps them from drifting apart: an import rule
// added without its export half would silently lose content on the way back.
import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_markdown/lexical_markdown.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';

const source = '''
# Title

A paragraph with **bold**, *italic* and [a link](https://example.org).

> A quotation

- one
- two
  - two-a

1. first
2. second

- [x] done
- [ ] open

```dart
void main() => print("*no* formatting in here");
```''';

void main() {
  final editor = LexicalEditor(
    nodes: [...richTextNodes, ...listNodes, ...linkNodes, ...codeNodes],
  );

  editor.update(() {
    $convertFromMarkdown(source, transformers: defaultMarkdownTransformers);
  }, discrete: true);

  final blocks = editor.read(
    () => $getRoot().children.map((node) => node.type).toList(),
  );
  print('blocks: $blocks\n');

  final back = editor.read(
    () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
  );
  print('exported again:\n$back\n');

  // The property that actually matters is not "the output equals the input"
  // — markdown has many spellings of the same document — but that a second
  // pass changes nothing. Anything else means repeated saves keep mutating.
  final second = editor.read(() {
    final round = LexicalEditor(
      nodes: [...richTextNodes, ...listNodes, ...linkNodes, ...codeNodes],
    );
    round.update(() {
      $convertFromMarkdown(back, transformers: defaultMarkdownTransformers);
    }, discrete: true);
    return round.read(
      () => $convertToMarkdown(transformers: defaultMarkdownTransformers),
    );
  });
  print('a second pass changes nothing: ${second == back}');

  // Nothing inside a fence is parsed: those asterisks stayed asterisks.
  print('the fence kept its asterisks: ${back.contains('*no*')}');

  // A URL is preserved exactly as written, even one this application would
  // refuse to open — validating belongs where the link is made tappable.
  final dodgy = LexicalEditor(nodes: [...richTextNodes, ...linkNodes]);
  dodgy.update(() {
    $convertFromMarkdown(
      '[click](javascript:alert)',
      transformers: defaultMarkdownTransformers,
    );
  }, discrete: true);
  dodgy.read(() {
    final link = ($getRoot().getFirstChild()! as ElementNode).children
        .whereType<LinkNode>()
        .single;
    print('kept verbatim: ${link.url}  (isSafeUrl: ${isSafeUrl(link.url)})');
  });
}
