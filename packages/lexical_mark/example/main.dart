// Run it with:  dart run example/main.dart
//
// Marks: annotations and comment ranges. The interesting case is overlap —
// two comments covering the same words — and it is handled by *nesting*
// rather than by letting one node belong to two ranges. That is why `ids` is
// a list: the innermost mark of an overlap carries every id covering it.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_mark/lexical_mark.dart';

void main() {
  final editor = LexicalEditor(nodes: markNodes);
  registerRichText(editor);

  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('A '))
          ..append(
            $createMarkNode(['comment-1'])
              ..append($createTextNode('marked '))
              ..append(
                $createMarkNode(['comment-1', 'comment-2'])
                  ..append($createTextNode('overlapping')),
              ),
          )
          ..append($createTextNode(' text.')),
      );
  }, discrete: true);

  print('text: ${editor.read(() => $getRoot().getTextContent())}\n');

  editor.read(() {
    void walk(ElementNode node, int depth) {
      for (final child in node.children) {
        if (child is MarkNode) {
          print(
            '${'  ' * depth}mark ${child.ids} → "${child.getTextContent()}"',
          );
        }
        if (child is ElementNode) {
          walk(child, child is MarkNode ? depth + 1 : depth);
        }
      }
    }

    walk($getRoot(), 0);
  });

  // Resolving "which comments cover this word" is a walk up the ancestors.
  editor.read(() {
    final deepest = $getRoot().getAllTextNodes().firstWhere(
      (node) => node.getTextContent() == 'overlapping',
    );
    final ids = <String>{
      for (final parent in deepest.getParents())
        if (parent is MarkNode) ...parent.ids,
    };
    print('\ncomments covering "overlapping": $ids');
  });

  // Ids are added and removed without rebuilding the range.
  editor.update(() {
    final mark = ($getRoot().getFirstChild()! as ElementNode).children
        .whereType<MarkNode>()
        .single;
    mark.addId('comment-3');
  }, discrete: true);
  editor.read(() {
    final mark = ($getRoot().getFirstChild()! as ElementNode).children
        .whereType<MarkNode>()
        .single;
    print('outer mark now carries: ${mark.ids}');
  });
}
