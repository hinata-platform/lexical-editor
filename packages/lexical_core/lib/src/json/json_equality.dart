/// Structural comparison of decoded JSON.
library;

/// Deep-compares two decoded JSON values.
///
/// Use this instead of comparing encoded strings: JSON object key order is
/// insignificant and Dart's map iteration order will not match the order a
/// JavaScript encoder produced, so string comparison reports differences
/// that do not exist on the wire.
///
/// Two details matter for wire compatibility:
///
/// * An **absent key is not equal to a key present with value `null`**. The
///   Lexical wire format relies on that distinction (`link.title` is emitted
///   as an explicit `null`, while `tablerow.height` is omitted entirely), so
///   the comparison uses [Map.containsKey] rather than indexing.
/// * `1` and `1.0` are **not** equal. A Dart encoder that lets an `int` pass
///   through a `double` silently produces `1.0`, which no JavaScript-produced
///   fixture will match.
bool jsonDeepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!jsonDeepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) {
    // int and double are distinct on the wire even when numerically equal.
    if (a is int != b is int) return false;
    return a == b;
  }
  return a == b;
}

/// Returns a human-readable path to the first difference between [a] and [b],
/// or `null` when they are deeply equal.
///
/// Intended for test failure messages: a bare `false` from [jsonDeepEquals]
/// on a large document is close to undebuggable.
String? jsonFirstDifference(Object? a, Object? b, [String path = r'$']) {
  if (identical(a, b)) return null;
  if (a is Map && b is Map) {
    for (final key in a.keys) {
      if (!b.containsKey(key)) return '$path.$key: present in A, absent in B';
      final diff = jsonFirstDifference(a[key], b[key], '$path.$key');
      if (diff != null) return diff;
    }
    for (final key in b.keys) {
      if (!a.containsKey(key)) return '$path.$key: absent in A, present in B';
    }
    return null;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return '$path: length ${a.length} vs ${b.length}';
    }
    for (var i = 0; i < a.length; i++) {
      final diff = jsonFirstDifference(a[i], b[i], '$path[$i]');
      if (diff != null) return diff;
    }
    return null;
  }
  if (jsonDeepEquals(a, b)) return null;
  return '$path: ${_describe(a)} vs ${_describe(b)}';
}

String _describe(Object? value) {
  if (value == null) return 'null';
  if (value is String) return '"$value" (String)';
  return '$value (${value.runtimeType})';
}
