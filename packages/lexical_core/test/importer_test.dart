import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _doc(List<Object?> children) => {
  'root': {
    'children': children,
    'direction': null,
    'format': '',
    'indent': 0,
    'type': 'root',
    'version': 1,
  },
};

Map<String, Object?> _paragraph(List<Object?> children) => {
  'children': children,
  'direction': null,
  'format': '',
  'indent': 0,
  'type': 'paragraph',
  'version': 1,
  'textFormat': 0,
  'textStyle': '',
};

Map<String, Object?> _text(String text) => {
  'detail': 0,
  'format': 0,
  'mode': 'normal',
  'style': '',
  'text': text,
  'type': 'text',
  'version': 1,
};

void main() {
  group('unknown node types', () {
    final document = _doc([
      _paragraph([
        {'type': 'voellig-unbekannt', 'version': 1, 'payload': 42},
      ]),
    ]);

    test('throw by default, naming the type', () {
      final editor = LexicalEditor();
      expect(
        () => editor.parseEditorState(document),
        throwsA(
          isA<UnknownNodeTypeException>().having(
            (error) => error.type,
            'type',
            'voellig-unbekannt',
          ),
        ),
      );
    });

    test('are preserved verbatim when configured to', () {
      final editor = LexicalEditor(
        config: const EditorConfig(
          unknownNodePolicy: UnknownNodePolicy.preserve,
        ),
      );
      final state = editor.parseEditorState(document);
      final encoded = state.toJson();
      expect(jsonFirstDifference(document, encoded), isNull);
    });

    test('are never silently dropped', () {
      final editor = LexicalEditor(
        config: const EditorConfig(
          unknownNodePolicy: UnknownNodePolicy.preserve,
        ),
      );
      final state = editor.parseEditorState(document);
      state.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        expect(paragraph.childrenSize, 1);
        expect(paragraph.getFirstChild(), isA<UnknownNode>());
      });
    });
  });

  group('malformed documents', () {
    test('a missing root is rejected', () {
      final editor = LexicalEditor();
      expect(
        () => editor.parseEditorState(const {}),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('a nested root node is rejected', () {
      final editor = LexicalEditor();
      expect(
        () => editor.parseEditorState(
          _doc([
            {
              'children': <Object?>[],
              'direction': null,
              'format': '',
              'indent': 0,
              'type': 'root',
              'version': 1,
            },
          ]),
        ),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('a node without a type is rejected', () {
      final editor = LexicalEditor();
      expect(
        () => editor.parseEditorState(
          _doc([
            {'version': 1},
          ]),
        ),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('a newline inside a text node is preserved, not rejected', () {
      // Lexical's editing paths avoid newlines in text nodes, but its
      // serializer preserves them: a code block built by appending a
      // multi-line text node round-trips through real Lexical unchanged.
      // Rejecting or splitting them would make this port unable to open
      // documents Lexical itself produces.
      final editor = LexicalEditor();
      final document = _doc([
        _paragraph([_text('zwei\nzeilen')]),
      ]);
      final encoded = editor.parseEditorState(document).toJson();
      expect(jsonFirstDifference(document, encoded), isNull);
    });

    test('invalid JSON is rejected with a typed error', () {
      final editor = LexicalEditor();
      expect(
        () => editor.parseEditorStateFromString('{not json'),
        throwsA(isA<MalformedDocumentException>()),
      );
    });
  });

  group('import limits', () {
    test('deep nesting is bounded rather than overflowing the stack', () {
      final editor = LexicalEditor(
        config: const EditorConfig(importLimits: ImportLimits(maxDepth: 8)),
      );
      Object? nested = _paragraph([]);
      for (var i = 0; i < 40; i++) {
        nested = _paragraph([nested]);
      }
      expect(
        () => editor.parseEditorState(_doc([nested])),
        throwsA(
          isA<ImportLimitExceededException>().having(
            (error) => error.limit,
            'limit',
            'maxDepth',
          ),
        ),
      );
    });

    test('very deep nesting does not crash with generous limits', () {
      final editor = LexicalEditor();
      Object? nested = _paragraph([]);
      for (var i = 0; i < 120; i++) {
        nested = _paragraph([nested]);
      }
      final state = editor.parseEditorState(_doc([nested]));
      expect(state.read(() => $getRoot().childrenSize), 1);
    });

    test('the node count is bounded', () {
      final editor = LexicalEditor(
        config: const EditorConfig(importLimits: ImportLimits(maxNodeCount: 5)),
      );
      expect(
        () => editor.parseEditorState(
          _doc(List.generate(20, (_) => _paragraph([_text('x')]))),
        ),
        throwsA(
          isA<ImportLimitExceededException>().having(
            (error) => error.limit,
            'limit',
            'maxNodeCount',
          ),
        ),
      );
    });

    test('text length is bounded', () {
      final editor = LexicalEditor(
        config: const EditorConfig(
          importLimits: ImportLimits(maxTextLength: 10),
        ),
      );
      expect(
        () => editor.parseEditorState(
          _doc([
            _paragraph([_text('x' * 100)]),
          ]),
        ),
        throwsA(
          isA<ImportLimitExceededException>().having(
            (error) => error.limit,
            'limit',
            'maxTextLength',
          ),
        ),
      );
    });
  });

  group('node state', () {
    test('nested state under "\$" round-trips verbatim', () {
      final editor = LexicalEditor();
      final document = _doc([
        _paragraph([
          {
            ..._text('mit state'),
            r'$': {'meineDaten': 7, 'flag': true},
          },
        ]),
      ]);
      final encoded = editor.parseEditorState(document).toJson();
      expect(jsonFirstDifference(document, encoded), isNull);
    });

    test('unregistered flat keys are dropped, matching upstream', () {
      final editor = LexicalEditor();
      final document = _doc([
        _paragraph([
          {..._text('mit extra'), 'unbekanntesFeld': 'verloren'},
        ]),
      ]);
      final encoded = editor.parseEditorState(document).toJson();
      final paragraph =
          ((encoded['root']! as Map)['children']! as List).first as Map;
      final text = (paragraph['children']! as List).first as Map;
      expect(text.containsKey('unbekanntesFeld'), isFalse);
    });
  });

  test('imported documents keep the tree consistent', () {
    final editor = LexicalEditor();
    final state = editor.parseEditorState(
      _doc([
        _paragraph([_text('eins'), _text('zwei')]),
        _paragraph([_text('drei')]),
      ]),
    );
    expect(state.read(() => assertTreeIntegrity($getRoot())), isTrue);
  });
}
