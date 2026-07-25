// Verifies `.github/publish-order.txt` against the packages on disk.
//
// Run it with:  dart tool/check_publish_order.dart
//
// Publishing is irreversible and ordered: `lexical_flutter` cannot resolve
// until `lexical_core` is on pub.dev. The order therefore lives in a file the
// release workflow reads — and a file is exactly the kind of thing that goes
// stale the first time someone adds a package. This is what keeps it honest:
// every publishable package listed once, and never before something it
// depends on.
import 'dart:io';

void main(List<String> args) {
  final packages =
      Directory('packages')
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();

  final publishable = <String, Set<String>>{};
  for (final name in packages) {
    final pubspec = File('packages/$name/pubspec.yaml').readAsStringSync();
    if (RegExp(r'^publish_to:\s*none', multiLine: true).hasMatch(pubspec)) {
      continue;
    }
    publishable[name] = RegExp(
      r'^  (lexical_\w+):',
      multiLine: true,
    ).allMatches(pubspec).map((match) => match.group(1)!).toSet();
  }

  final listed = File('.github/publish-order.txt')
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();

  final problems = <String>[];

  final missing = publishable.keys.toSet().difference(listed.toSet());
  if (missing.isNotEmpty) {
    problems.add(
      'not in publish-order.txt, so it would never be released: '
      '${(missing.toList()..sort()).join(', ')}',
    );
  }
  final unknown = listed.toSet().difference(publishable.keys.toSet());
  if (unknown.isNotEmpty) {
    problems.add(
      'listed but not publishable: ${(unknown.toList()..sort()).join(', ')}',
    );
  }
  if (listed.length != listed.toSet().length) {
    problems.add('listed twice: publishing the same package again fails');
  }

  final seen = <String>{};
  for (final name in listed) {
    for (final dependency in publishable[name] ?? const <String>{}) {
      if (publishable.containsKey(dependency) && !seen.contains(dependency)) {
        problems.add('$name is published before its dependency $dependency');
      }
    }
    seen.add(name);
  }

  // One tag releases the set, so one version has to describe it.
  final versions = <String, String>{};
  for (final name in publishable.keys) {
    final pubspec = File('packages/$name/pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    versions[name] = match?.group(1) ?? '<none>';
  }
  final distinct = versions.values.toSet();
  if (distinct.length > 1) {
    problems.add(
      'packages disagree about the version, but one tag releases them all: '
      '${versions.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
    );
  }

  if (problems.isEmpty) {
    stdout.writeln(
      '${listed.length} packages, version ${distinct.single}, order valid.',
    );
    return;
  }
  for (final problem in problems) {
    stderr.writeln('error: $problem');
  }
  exit(1);
}
