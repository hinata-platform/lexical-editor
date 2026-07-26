// Run it with:  dart run example/main.dart
//
// Links, and the security rule that goes with them: a URL is stored exactly
// as it arrived and validated where it is *used*. Rewriting it on import
// would silently change the document; refusing to store it would lose it.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_link/lexical_link.dart';

void main() {
  final editor = LexicalEditor(nodes: linkNodes);
  registerRichText(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('see '))
          ..append(
            $createLinkNode('https://example.org', title: 'The docs')
              ..append($createTextNode('the docs')),
          )
          ..append($createTextNode(' over there')),
      );
  }, discrete: true);

  editor.read(() {
    final link = ($getRoot().getFirstChild()! as ElementNode).children
        .whereType<LinkNode>()
        .single;
    print('link:   ${link.url}');
    print('title:  ${link.title}');
    print('label:  ${link.getTextContent()}');
    print('inline: ${link.isInline}  (it sits *in* the line, not around it)');
  });

  // A document is allowed to hold a link this application will refuse to
  // open. That is the whole point of validating at the point of use.
  for (final url in [
    'https://example.org',
    'mailto:hello@example.org',
    'javascript:alert(1)',
    'data:text/html;base64,PHNjcmlwdD4=',
  ]) {
    print('${isSafeUrl(url) ? 'may open ' : 'refuses  '} $url');
  }

  // An auto-link is the same node with a flag: it was made by recognizing a
  // URL as it was typed, so re-typing around it may un-make it.
  editor.update(() {
    $getRoot().append(
      $createParagraphNode()..append(
        $createAutoLinkNode('https://dart.dev')
          ..append($createTextNode('https://dart.dev')),
      ),
    );
  }, discrete: true);

  editor.read(() {
    final auto = ($getRoot().getLastChild()! as ElementNode).children
        .whereType<LinkNode>()
        .single;
    print('\nauto-link type on the wire: ${auto.type}');
  });
}
