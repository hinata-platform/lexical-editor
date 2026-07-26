import 'dart:convert';

import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_file/lexical_file.dart';
import 'package:test/test.dart';

/// A file as the Lexical playground's Export button writes it, reformatted
/// but otherwise untouched.
const String _playgroundFile =
    '{"editorState":{"root":{"children":[{"children":[{"detail":0,'
    '"format":0,"mode":"normal","style":"","text":"Hallo Welt","type":"text",'
    '"version":1}],"direction":"ltr","format":"","indent":0,'
    '"type":"paragraph","version":1,"textFormat":0,"textStyle":""}],'
    '"direction":"ltr","format":"","indent":0,"type":"root","version":1}},'
    '"lastSaved":1785024000000,"source":"Playground","version":"0.48.0"}';

LexicalEditor _editor() => LexicalEditor();

void main() {
  group('reading', () {
    test('a file from the playground opens', () {
      final document = SerializedDocument.parse(_playgroundFile);
      expect(document.source, 'Playground');
      expect(document.version, '0.48.0');
      expect(
        document.lastSavedAt.toIso8601String(),
        '2026-07-26T00:00:00.000Z',
      );

      final editor = _editor();
      editor.setEditorState(
        editorStateFromSerializedDocument(editor, document),
      );
      expect(editor.read(() => $getRoot().getTextContent()), 'Hallo Welt');
    });

    test('it is a fixed point: what came in is what goes out', () {
      final document = SerializedDocument.parse(_playgroundFile);
      expect(jsonDecode(document.encode()), jsonDecode(_playgroundFile));
    });

    test('missing metadata is not a reason to refuse a document', () {
      // Everything but the state is metadata about the writer. Losing it is
      // not worth losing the user's text over.
      final document = SerializedDocument.parse(
        '{"editorState":{"root":{"children":[],"direction":null,"format":"",'
        '"indent":0,"type":"root","version":1}}}',
      );
      expect(document.source, defaultDocumentSource);
      expect(document.version, lexicalCompatibleVersion);
      expect(document.lastSaved, 0);
    });

    test('a fractional timestamp still lands somewhere sensible', () {
      final document = SerializedDocument.fromJson(<String, Object?>{
        'editorState': <String, Object?>{'root': <String, Object?>{}},
        'lastSaved': 1785024000000.0,
      });
      expect(document.lastSaved, 1785024000000);
    });
  });

  group('rejecting', () {
    test('text that is not JSON', () {
      expect(
        () => SerializedDocument.parse('not a document'),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('JSON that is not an object', () {
      expect(
        () => SerializedDocument.parse('[1, 2, 3]'),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('an envelope with no state in it', () {
      expect(
        () => SerializedDocument.parse('{"source":"Hinata"}'),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('an editorState that is a string, as an over-eager writer sends', () {
      expect(
        () => SerializedDocument.parse('{"editorState":"{\\"root\\":{}}"}'),
        throwsA(isA<MalformedDocumentException>()),
      );
    });

    test('a corrupt file leaves the open document alone', () {
      // The reason parsing and installing are separate calls.
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('sicher')));
      }, discrete: true);

      expect(
        () => SerializedDocument.parse('}{'),
        throwsA(isA<MalformedDocumentException>()),
      );
      expect(editor.read(() => $getRoot().getTextContent()), 'sicher');
    });

    test(
      'an unknown node type is the editor\'s policy, not this package\'s',
      () {
        final document = SerializedDocument.parse(
          '{"editorState":{"root":{"children":[{"children":['
          '{"type":"quantum","version":1}],"direction":null,"format":"",'
          '"indent":0,"type":"paragraph","version":1,"textFormat":0,'
          '"textStyle":""}],"direction":null,"format":"","indent":0,'
          '"type":"root","version":1}}}',
        );
        final strict = LexicalEditor();
        expect(
          () => editorStateFromSerializedDocument(strict, document),
          throwsA(isA<UnknownNodeTypeException>()),
        );

        final lenient = LexicalEditor(
          config: const EditorConfig(
            unknownNodePolicy: UnknownNodePolicy.preserve,
          ),
        );
        final state = editorStateFromSerializedDocument(lenient, document);
        lenient.setEditorState(state);
        expect(
          lenient.editorState.toJson(),
          document.editorState,
          reason: 'a preserved unknown node has to survive re-export verbatim',
        );
      },
    );
  });

  group('writing', () {
    test('a saved document carries the state and the metadata', () {
      final editor = _editor();
      editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('Notiz')));
      }, discrete: true);

      final document = serializedDocumentFromEditorState(
        editor.editorState,
        source: 'Hinata',
        lastSaved: DateTime.utc(2026, 7, 26, 12),
      );
      expect(document.source, 'Hinata');
      expect(document.version, lexicalCompatibleVersion);
      expect(document.editorState, editor.editorState.toJson());

      final reopened = SerializedDocument.parse(document.encode());
      expect(reopened, document);
    });

    test('a local timestamp is written in UTC', () {
      final local = DateTime(2026, 7, 26, 12);
      final document = serializedDocumentFromEditorState(
        _editor().editorState,
        lastSaved: local,
      );
      expect(document.lastSaved, local.toUtc().millisecondsSinceEpoch);
      expect(document.lastSavedAt.isUtc, isTrue);
    });

    test('the suggested name sorts and survives a file system', () {
      final name = suggestedDocumentFileName(DateTime.utc(2026, 7, 26, 12));
      expect(name, '2026-07-26T12:00:00.000Z.lexical');
    });
  });
}
