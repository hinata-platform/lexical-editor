import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

/// A minimal custom node, used to exercise the registry contract.
class CalloutNode extends ElementNode {
  CalloutNode([this._tone = 'info']);

  String _tone;

  @override
  String get type => 'callout';

  @override
  CalloutNode clone() => CalloutNode(_tone);

  @override
  void afterCloneFrom(covariant CalloutNode prev) {
    super.afterCloneFrom(prev);
    _tone = prev._tone;
  }

  String get tone => getLatest<CalloutNode>()._tone;

  @override
  Map<String, Object?> exportJson() => {...super.exportJson(), 'tone': _tone};

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final tone = json['tone'];
    _tone = tone is String ? tone : 'info';
  }
}

/// A node whose declared type disagrees with its registration.
class MislabelledNode extends ElementNode {
  @override
  String get type => 'actually-different';

  @override
  MislabelledNode clone() => MislabelledNode();
}

/// A subclass that forgets to override clone(), which must be caught.
class BrokenCloneNode extends ParagraphNode {
  @override
  String get type => 'broken-clone';
}

/// A well-formed paragraph subclass, suitable as a replacement.
class FancyParagraphNode extends ParagraphNode {
  @override
  String get type => 'fancy-paragraph';

  @override
  FancyParagraphNode clone() => FancyParagraphNode();
}

void main() {
  group('registration', () {
    test('a custom node type round-trips once registered', () {
      final editor = LexicalEditor(
        nodes: [
          NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new),
        ],
      );
      editor.update(() {
        final callout = CalloutNode('warning')
          ..append($createParagraphNode()..append($createTextNode('achtung')));
        $getRoot().append(callout);
      }, discrete: true);

      final json = editor.toJson();
      final reparsed = editor.parseEditorState(json);
      expect(jsonFirstDifference(json, reparsed.toJson()), isNull);
      expect(
        reparsed.read(() => ($getRoot().getFirstChild()! as CalloutNode).tone),
        'warning',
      );
    });

    test('registering a type twice is rejected', () {
      expect(
        () => LexicalEditor(
          nodes: [
            NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new),
            NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new),
          ],
        ),
        throwsA(isA<LexicalStateError>()),
      );
    });

    test('shadowing a core type is rejected', () {
      expect(
        () => LexicalEditor(
          nodes: [NodeSpec<CalloutNode>(type: 'text', create: CalloutNode.new)],
        ),
        throwsA(isA<LexicalStateError>()),
      );
    });

    test('a spec whose node disagrees about its type is caught', () {
      final editor = LexicalEditor(
        nodes: [
          NodeSpec<MislabelledNode>(
            type: 'mislabelled',
            create: MislabelledNode.new,
          ),
        ],
      );
      expect(
        () => editor.parseEditorState({
          'root': {
            'children': [
              {
                'children': <Object?>[],
                'direction': null,
                'format': '',
                'indent': 0,
                'type': 'mislabelled',
                'version': 1,
              },
            ],
            'direction': null,
            'format': '',
            'indent': 0,
            'type': 'root',
            'version': 1,
          },
        }),
        throwsA(isA<LexicalStateError>()),
      );
    });
  });

  group('clone discipline', () {
    test('a subclass inheriting clone() is caught in debug', () {
      final editor = LexicalEditor(
        nodes: [
          NodeSpec<BrokenCloneNode>(
            type: 'broken-clone',
            create: BrokenCloneNode.new,
          ),
        ],
      );
      editor.update(() {
        $getRoot().append(BrokenCloneNode());
      }, discrete: true);
      expect(
        () => editor.update(() {
          // The first write in a *later* update clones, and the inherited
          // clone() silently produces a ParagraphNode.
          ($getRoot().getFirstChild()! as ElementNode).setIndent(1);
        }, discrete: true),
        throwsA(anyOf(isA<AssertionError>(), isA<LexicalStateError>())),
      );
    });
  });

  group('node replacement', () {
    test('replaces a built-in with a subclass', () {
      final editor = LexicalEditor(
        nodes: [
          NodeSpec<FancyParagraphNode>(
            type: 'fancy-paragraph',
            create: FancyParagraphNode.new,
          ),
        ],
        replacements: [
          NodeReplacement(
            replacedType: 'paragraph',
            replaceWith: (_) => FancyParagraphNode(),
          ),
        ],
      );
      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);

      expect(
        editor.read(() => $getRoot().getFirstChild()),
        isA<FancyParagraphNode>(),
      );
      final json = editor.toJson();
      final child = ((json['root']! as Map)['children']! as List).first as Map;
      expect(child['type'], 'fancy-paragraph');
    });

    test('a replacement that is not assignable to the replaced type is '
        'rejected', () {
      final editor = LexicalEditor(
        nodes: [
          NodeSpec<CalloutNode>(type: 'callout', create: CalloutNode.new),
        ],
        replacements: [
          NodeReplacement(
            replacedType: 'paragraph',
            replaceWith: (_) => CalloutNode('nicht-erlaubt'),
          ),
        ],
      );
      expect(
        () => editor.update(() {
          $getRoot().append($createParagraphNode());
        }, discrete: true),
        throwsA(isA<LexicalStateError>()),
      );
    });

    test('replacing an unregistered type is rejected', () {
      expect(
        () => LexicalEditor(
          replacements: [
            NodeReplacement(
              replacedType: 'nicht-registriert',
              replaceWith: (node) => node,
            ),
          ],
        ),
        throwsA(isA<LexicalStateError>()),
      );
    });
  });
}
