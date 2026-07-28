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
  final constraints = <String, Map<String, String>>{};
  for (final name in packages) {
    final pubspec = File('packages/$name/pubspec.yaml').readAsStringSync();
    if (RegExp(r'^publish_to:\s*none', multiLine: true).hasMatch(pubspec)) {
      continue;
    }
    constraints[name] = {
      for (final match in RegExp(
        r'^  (lexical_\w+):[ \t]*(\S*)',
        multiLine: true,
      ).allMatches(pubspec))
        match.group(1)!: match.group(2)!,
    };
    publishable[name] = constraints[name]!.keys.toSet();
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

  // Versions are allowed to diverge. Lockstep is still the default — the
  // packages are one library split up — but a fix that touches one package
  // would otherwise cost nineteen of pub.dev's two hundred daily uploads to
  // deliver one, so a tag releases whichever packages carry its version.
  //
  // What has to hold instead is that the set still resolves: a package that
  // moved ahead of a constraint another package places on it would publish a
  // version nothing in the repository is allowed to use.
  final versions = <String, String>{};
  for (final name in publishable.keys) {
    final pubspec = File('packages/$name/pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    versions[name] = match?.group(1) ?? '<none>';
  }
  for (final entry in constraints.entries) {
    for (final dependency in entry.value.entries) {
      final version = versions[dependency.key];
      if (version == null) continue;
      if (_satisfiesCaret(version, dependency.value)) continue;
      problems.add(
        '${entry.key} wants ${dependency.key} ${dependency.value}, but it is '
        'at $version — widen the constraint or hold the version back',
      );
    }
  }

  if (problems.isEmpty) {
    final distinct = versions.values.toSet();
    final summary = distinct.length == 1
        ? 'version ${distinct.single}'
        : 'versions ${(distinct.toList()..sort()).join(', ')}';
    stdout.writeln('${listed.length} packages, $summary, order valid.');
    return;
  }
  for (final problem in problems) {
    stderr.writeln('error: $problem');
  }
  exit(1);
}

/// Whether [version] satisfies a `^x.y.z` [constraint].
///
/// Only the caret form is judged, because it is the only one these packages
/// use on each other. Anything else — a path, a git ref, `any` — is left to
/// `pub` rather than half-parsed here.
bool _satisfiesCaret(String version, String constraint) {
  if (!constraint.startsWith('^')) return true;
  final lower = _parse(constraint.substring(1));
  final actual = _parse(version);
  if (lower == null || actual == null) return true;
  // A caret constraint never crosses a major, in either direction.
  if (actual[0] != lower[0]) return false;
  for (var i = 0; i < 3; i++) {
    if (actual[i] != lower[i]) return actual[i] > lower[i];
  }
  return true;
}

List<int>? _parse(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return null;
  return [
    for (var group = 1; group <= 3; group++) int.parse(match.group(group)!),
  ];
}
