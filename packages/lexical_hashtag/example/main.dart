// Run it with:  dart run example/main.dart
//
// A hashtag is a `TextNode` subclass with no extra fields — only its type
// distinguishes it. That is deliberate: it means every text operation works
// on it unchanged, and the *only* thing that has to be decided is when a run
// of text becomes one.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';

/// A crude tokenizer, standing in for the transform an application registers.
///
/// The separator is its own text node, so a hashtag node holds the tag and
/// nothing else — which is what makes editing one behave.
List<TextNode> tokenize(String line) {
  final nodes = <TextNode>[];
  final words = line.split(' ');
  for (var i = 0; i < words.length; i++) {
    if (i > 0) nodes.add($createTextNode(' '));
    final word = words[i];
    nodes.add(
      word.startsWith('#') ? $createHashtagNode(word) : $createTextNode(word),
    );
  }
  return nodes;
}

void main() {
  final editor = LexicalEditor(nodes: hashtagNodes);
  registerRichText(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..appendAll(tokenize('Gebaut mit #dart und #flutter heute')),
      );
  }, discrete: true);

  editor.read(() {
    final paragraph = $getRoot().getFirstChild()! as ElementNode;
    print('text: ${paragraph.getTextContent()}\n');
    for (final child in paragraph.children.cast<TextNode>()) {
      final kind = child is HashtagNode ? 'hashtag' : 'text   ';
      print('  $kind "${child.getTextContent()}"');
    }
    final tags = paragraph.children
        .whereType<HashtagNode>()
        .map((node) => node.getTextContent())
        .toList();
    print('\ntags: $tags');
  });

  // It survives the wire format as its own type, so a document written here
  // reopens with its tags intact — on Lexical web too.
  print(
    '\nJSON contains the hashtag type: '
    '${editor.toJsonString().contains('"type":"hashtag"')}',
  );

  // And because it is a plain text node underneath, ordinary text editing
  // applies to it with no special case.
  editor.update(() {
    final tag = $getRoot().getAllTextNodes().whereType<HashtagNode>().first;
    tag.setTextContent('#dart3');
  }, discrete: true);
  print('after editing: ${editor.read(() => $getRoot().getTextContent())}');
}
