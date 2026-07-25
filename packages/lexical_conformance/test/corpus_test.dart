import 'dart:convert';
import 'dart:io';

import 'package:lexical_conformance/lexical_conformance.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

/// One canonical document produced by real Lexical.
final class _Fixture {
  _Fixture(this.name, this.json);

  final String name;
  final Map<String, Object?> json;

  Set<String> get types {
    final result = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        final type = node['type'];
        if (type is String) result.add(type);
        final children = node['children'];
        if (children is List) children.forEach(walk);
      }
    }

    walk(json['root']);
    return result;
  }
}

List<_Fixture> _loadFixtures() {
  // The corpus lives with lexical_core, which is where a Dart-only consumer
  // would look for it; this package only borrows it.
  final dir = Directory('../lexical_core/test/fixtures');
  if (!dir.existsSync()) {
    throw StateError('fixture corpus missing at ${dir.path}');
  }
  final fixtures = <_Fixture>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.json') || name == 'manifest.json') continue;
    final decoded = jsonDecode(entity.readAsStringSync());
    fixtures.add(
      _Fixture(
        name.substring(0, name.length - 5),
        decoded! as Map<String, Object?>,
      ),
    );
  }
  fixtures.sort((a, b) => a.name.compareTo(b.name));
  return fixtures;
}

void main() {
  final fixtures = _loadFixtures();

  test('the corpus is complete', () {
    expect(fixtures, hasLength(20));
  });

  test('every type in the corpus is implemented', () {
    final known = createFullEditor().registry.types.toSet();
    final used = <String>{for (final fixture in fixtures) ...fixture.types};
    expect(
      used.difference(known),
      isEmpty,
      reason: 'a node type appears in the corpus but is not registered',
    );
  });

  group('fixed point on canonical fixtures', () {
    for (final fixture in fixtures) {
      test(fixture.name, () {
        final editor = createFullEditor();
        final encoded = editor.parseEditorState(fixture.json).toJson();
        expect(
          jsonFirstDifference(fixture.json, encoded),
          isNull,
          reason: 'encode(decode(f)) must equal f',
        );
      });
    }
  });

  group('re-encoding is stable', () {
    for (final fixture in fixtures) {
      test('${fixture.name} survives a second pass', () {
        final editor = createFullEditor();
        final once = editor.parseEditorState(fixture.json).toJson();
        final twice = editor.parseEditorState(once).toJson();
        expect(jsonFirstDifference(once, twice), isNull);
      });
    }
  });

  group('imported documents are structurally sound', () {
    for (final fixture in fixtures) {
      test(fixture.name, () {
        final editor = createFullEditor();
        final state = editor.parseEditorState(fixture.json);
        expect(state.read(() => assertTreeIntegrity($getRoot())), isTrue);
      });
    }
  });

  test('a document survives being installed and re-serialized', () {
    for (final fixture in fixtures) {
      final editor = createFullEditor();
      final state = editor.parseEditorState(fixture.json);
      editor.setEditorState(state);
      expect(
        jsonFirstDifference(fixture.json, editor.toJson()),
        isNull,
        reason: '${fixture.name} changed when installed on an editor',
      );
    }
  });

  test('an unimplemented type still fails loudly by default', () {
    final editor = createFullEditor();
    expect(
      () => editor.parseEditorState({
        'root': {
          'children': [
            {'type': 'noch-nicht-erfunden', 'version': 1},
          ],
          'direction': null,
          'format': '',
          'indent': 0,
          'type': 'root',
          'version': 1,
        },
      }),
      throwsA(isA<UnknownNodeTypeException>()),
    );
  });
}
