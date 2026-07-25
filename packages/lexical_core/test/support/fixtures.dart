/// Helpers for loading the canonical fixture corpus.
library;

import 'dart:convert';
import 'dart:io';

/// One canonical document produced by real Lexical.
final class Fixture {
  /// Wraps a decoded fixture.
  Fixture(this.name, this.json);

  /// File name without the extension.
  final String name;

  /// The decoded document.
  final Map<String, Object?> json;

  /// Every `type` string that appears in the document.
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

  @override
  String toString() => name;
}

/// Loads every fixture in `test/fixtures`.
///
/// The corpus is generated from real Lexical by `tool/fixtures/gen_fixtures.mjs`
/// and committed so the Dart suite runs without a Node toolchain. Regenerate
/// it after an upstream version bump; `--check` in CI turns silent
/// compatibility drift into a dated build failure.
List<Fixture> loadFixtures() {
  final dir = Directory('test/fixtures');
  if (!dir.existsSync()) {
    throw StateError(
      'test/fixtures is missing. Run: '
      'node tool/fixtures/gen_fixtures.mjs --generate '
      'packages/lexical_core/test/fixtures',
    );
  }
  final fixtures = <Fixture>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('.json') || name == 'manifest.json') continue;
    final decoded = jsonDecode(entity.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw StateError('fixture $name is not a JSON object');
    }
    fixtures.add(Fixture(name.substring(0, name.length - 5), decoded));
  }
  fixtures.sort((a, b) => a.name.compareTo(b.name));
  return fixtures;
}

/// The upstream Lexical version the corpus was generated from.
String fixtureLexicalVersion() {
  final file = File('test/fixtures/manifest.json');
  if (!file.existsSync()) return 'unknown';
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map && decoded['lexicalVersion'] is String) {
    return decoded['lexicalVersion']! as String;
  }
  return 'unknown';
}
