// Run it with:  dart run example/main.dart
//
// A two-column layout, and what its template means at two widths: side by
// side where there is room, stacked where there is not.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_layout/lexical_layout.dart';

void main() {
  final editor = LexicalEditor(nodes: layoutNodes);
  registerLayout(editor);

  editor.update(() {
    final layout = $createLayoutWithColumns('200px 1fr');
    final columns = layout.items.toList();
    (columns[0].getFirstChild()! as ElementNode).append(
      $createTextNode('Bild'),
    );
    (columns[1].getFirstChild()! as ElementNode).append(
      $createTextNode('Text daneben'),
    );
    $getRoot().append(layout);
  }, discrete: true);

  print(editor.toJsonString());

  final tracks = parseTemplateColumns('200px 1fr');
  print('\nat 600 px: ${resolveTemplateColumns(tracks, 600)}');
  print('at 150 px: ${resolveTemplateColumns(tracks, 150) ?? 'stacked'}');
}
