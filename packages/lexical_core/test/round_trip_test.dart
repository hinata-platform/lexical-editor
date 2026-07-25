import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The compatibility contract, stated precisely.
///
/// Equality is *semantic deep-equality of decoded JSON against the canonical
/// form*, never byte-equality against raw input. Lexical normalizes on import
/// — `paragraph.textFormat` and `textStyle` are derived from the first text
/// child on export and overwrite whatever the input claimed — so upstream
/// itself fails a byte-identity round-trip on hand-written JSON. It does
/// reach a fixed point after one pass, and that fixed point is what these
/// fixtures record and what the port must reproduce.
void main() {
  final fixtures = loadFixtures();

  test('the fixture corpus was generated', () {
    expect(fixtures, isNotEmpty);
    printOnFailure('lexical ${fixtureLexicalVersion()}');
  });

  group('fixed point on canonical fixtures', () {
    for (final fixture in fixtures) {
      final editor = LexicalEditor();
      final known = editor.registry.types.toSet();
      final missing = fixture.types.difference(known);

      test(
        fixture.name,
        () {
          final state = editor.parseEditorState(fixture.json);
          final encoded = state.toJson();
          final difference = jsonFirstDifference(fixture.json, encoded);
          expect(
            difference,
            isNull,
            reason:
                'encode(decode(f)) must equal f — first difference at '
                '$difference',
          );
          expect(jsonDeepEquals(fixture.json, encoded), isTrue);
        },
        skip: missing.isEmpty
            ? null
            : 'node types not implemented yet: ${missing.join(", ")}',
      );
    }
  });

  group('re-encoding is stable', () {
    for (final fixture in fixtures) {
      final editor = LexicalEditor();
      final missing = fixture.types.difference(editor.registry.types.toSet());

      test(
        '${fixture.name} survives a second pass',
        () {
          final once = editor.parseEditorState(fixture.json).toJson();
          final twice = editor.parseEditorState(once).toJson();
          expect(
            jsonFirstDifference(once, twice),
            isNull,
            reason: 'a second decode/encode pass must change nothing',
          );
        },
        skip: missing.isEmpty
            ? null
            : 'node types not implemented yet: ${missing.join(", ")}',
      );
    }
  });

  test('numbers stay integers on the wire', () {
    final editor = LexicalEditor();
    final state = editor.parseEditorState({
      'root': {
        'children': [
          {
            'children': [
              {
                'detail': 0,
                'format': 3,
                'mode': 'normal',
                'style': '',
                'text': 'x',
                'type': 'text',
                'version': 1,
              },
            ],
            'direction': null,
            'format': '',
            'indent': 2,
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
    final json = state.toJson();
    final root = json['root']! as Map<String, Object?>;
    final paragraph = (root['children']! as List).first as Map<String, Object?>;
    final text = (paragraph['children']! as List).first as Map<String, Object?>;

    expect(paragraph['indent'], isA<int>());
    expect(text['format'], isA<int>());
    expect(text['detail'], isA<int>());
    expect(root['version'], isA<int>());
  });

  test('selection is never serialized', () {
    final editor = LexicalEditor();
    editor.update(() {
      final paragraph = $createParagraphNode();
      final text = $createTextNode('hallo');
      paragraph.append(text);
      $getRoot().append(paragraph);
      $setSelection(RangeSelection.collapsedText(text.key, 2));
    }, discrete: true);

    final json = editor.toJson();
    expect(json.keys, equals(['root']));
    expect(editor.editorState.selection, isNotNull);
  });

  test('an empty document round-trips as an empty children array', () {
    final editor = LexicalEditor();
    final json = editor.toJson();
    final root = json['root']! as Map<String, Object?>;
    expect(root['children'], isEmpty);

    final reparsed = editor.parseEditorState(json);
    expect(jsonDeepEquals(reparsed.toJson(), json), isTrue);
  });
}
