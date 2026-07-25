import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('layering', () {
    test('lexical_core does not import Flutter', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => file.readAsStringSync().contains('package:flutter/'))
          .map((file) => file.path)
          .toList();
      expect(
        offenders,
        isEmpty,
        reason:
            'Flutter imports found in the core. The core must stay testable '
            'without a Flutter binding; theming and rendering belong in '
            'lexical_flutter.',
      );
    });

    test('lexical_core depends only on meta', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final dependencies = pubspec.split('dev_dependencies:').first;
      expect(dependencies, isNot(contains('flutter')));
    });
  });
}
