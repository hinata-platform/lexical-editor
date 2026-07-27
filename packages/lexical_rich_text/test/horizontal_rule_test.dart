import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: richTextNodes);

void main() {
  group('horizontal rule', () {
    test('is registered, so a document holding one opens', () {
      // The reason this node exists at all. The registry is closed: an
      // unregistered type is refused loudly rather than dropped, which is the
      // right default and the wrong outcome for a construct people write.
      const json =
          '{"root":{"type":"root","version":1,"indent":0,'
          '"format":"","direction":null,"children":['
          '{"type":"horizontalrule","version":1}]}}';

      final editor = _editor()
        ..setEditorState(_editor().parseEditorStateFromString(json));

      expect(
        editor.read(() => $getRoot().getFirstChild()!.type),
        'horizontalrule',
      );
    });

    test('serializes to the shape upstream writes', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createHorizontalRuleNode());
      }, discrete: true);

      final rule =
          ((editor.editorState.toJson()['root']!
                      as Map<String, Object?>)['children']!
                  as List<Object?>)
              .single;

      // No fields of its own: a rule that invented one would not open on a
      // Lexical web client, and this is the whole wire contract for it.
      expect(rule, {'type': 'horizontalrule', 'version': 1});
    });

    test('is a block, not something that sits inside a line', () {
      final editor = _editor();
      editor.update(() {
        final rule = $createHorizontalRuleNode();
        $getRoot()
          ..clear()
          ..append(rule);
        expect(rule.isInline, isFalse);
        expect($isHorizontalRuleNode(rule), isTrue);
        expect($isHorizontalRuleNode($createParagraphNode()), isFalse);
      }, discrete: true);
    });

    test('a document with one is a fixed point', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('davor')))
          ..append($createHorizontalRuleNode())
          ..append($createParagraphNode()..append($createTextNode('danach')));
      }, discrete: true);

      final once = editor.toJsonString();
      final reopened = _editor()
        ..setEditorState(_editor().parseEditorStateFromString(once));

      expect(reopened.toJsonString(), once);
    });
  });
}
