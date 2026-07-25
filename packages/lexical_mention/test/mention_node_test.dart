import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:test/test.dart';

LexicalEditor _editor() => LexicalEditor(nodes: mentionNodes);

void main() {
  group('node', () {
    test('is a token, so it is atomic and never merges', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createParagraphNode()
            ..append($createTextNode('cc '))
            ..append(
              $createMentionNode(
                text: '@Rebar',
                mentionType: 'user',
                mentionId: 'u_42',
              ),
            )
            ..append($createTextNode(' bitte')),
        );
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 3);
        final mention = paragraph.getChildAtIndex(1)! as MentionNode;
        expect(mention.isToken, isTrue);
        expect(mention.isSimpleText, isFalse);
        expect(mention.getMode(), TextMode.token);
      });
    });

    test('round-trips its typed fields', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append(
            $createMentionNode(
              text: '#IT-32',
              mentionType: 'issue',
              mentionId: 'IT-32',
              trigger: '#',
            ),
          ),
        );
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      final mention = (paragraph['children']! as List).first as Map;
      expect(mention['type'], 'mention');
      expect(mention['mode'], 'token');
      expect(mention['mentionType'], 'issue');
      expect(mention['mentionId'], 'IT-32');
      expect(mention['trigger'], '#');

      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });

    test('extra data rides in the node state and round-trips', () {
      final editor = _editor();
      editor.update(() {
        final mention = $createMentionNode(
          text: '@Rebar',
          mentionType: 'user',
          mentionId: 'u_42',
        )..setData('avatarUrl', 'https://example.org/a.png');
        $getRoot().append($createParagraphNode()..append(mention));
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      final mention = (paragraph['children']! as List).first as Map;
      expect((mention[r'$']! as Map)['avatarUrl'], 'https://example.org/a.png');
      expect(
        jsonFirstDifference(json, editor.parseEditorState(json).toJson()),
        isNull,
      );
    });

    test('stays a mention across an edit', () {
      final editor = _editor();
      editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append(
            $createMentionNode(
              text: '@alt',
              mentionType: 'user',
              mentionId: 'u_1',
            ),
          ),
        );
      }, discrete: true);

      editor.update(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        (paragraph.getFirstChild()! as MentionNode).retarget(
          mentionId: 'u_2',
          label: '@neu',
        );
      }, discrete: true);

      editor.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final mention = paragraph.getFirstChild();
        expect(mention, isA<MentionNode>());
        expect((mention! as MentionNode).mentionId, 'u_2');
        expect(mention.getTextContent(), '@neu');
        expect((mention as MentionNode).isToken, isTrue);
      });
    });

    test('a document claiming an editable mention is corrected', () {
      // Mode is structural. A document that says a mention is normal text
      // would let it be edited character by character and drift away from the
      // entity it names.
      final editor = _editor();
      final state = editor.parseEditorState({
        'root': {
          'children': [
            {
              'children': [
                {
                  'detail': 0,
                  'format': 0,
                  'mode': 'normal',
                  'style': '',
                  'text': '@Rebar',
                  'type': 'mention',
                  'version': 1,
                  'mentionType': 'user',
                  'mentionId': 'u_42',
                  'trigger': '@',
                },
              ],
              'direction': null,
              'format': '',
              'indent': 0,
              'type': 'paragraph',
              'version': 1,
              'textFormat': 0,
              'textStyle': '',
            },
          ],
          'direction': null,
          'format': '',
          'indent': 0,
          'type': 'root',
          'version': 1,
        },
      });
      state.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect((paragraph.getFirstChild()! as MentionNode).isToken, isTrue);
      });
    });
  });
}
