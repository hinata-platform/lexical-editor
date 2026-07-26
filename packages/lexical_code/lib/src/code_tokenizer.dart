/// Turning source text into classified runs.
library;

import 'package:meta/meta.dart';

import 'code_language.dart';

/// One run of source text and what it was classified as.
///
/// [type] is a Prism token name — `keyword`, `string`, `comment` — or `null`
/// for text that carries no classification, which is what whitespace and
/// ordinary identifiers are.
@immutable
class CodeToken {
  /// Creates a run of [text] classified as [type].
  const CodeToken(this.text, [this.type]);

  /// The source text of this run.
  final String text;

  /// The Prism token name, or `null` for unclassified text.
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is CodeToken && other.text == text && other.type == type;

  @override
  int get hashCode => Object.hash(text, type);

  @override
  String toString() => 'CodeToken(${type ?? 'plain'}: ${text.trim()})';
}

/// Splits [source] into classified runs for [language].
///
/// The result is **lossless**: concatenating every token's text returns
/// [source] exactly. That is the property the whole feature rests on — the
/// tokens replace the code block's children, so a tokenizer that dropped a
/// space would delete it from the user's document.
///
/// An unknown [language] yields one unclassified run, so a caller can always
/// use the result without checking first.
List<CodeToken> tokenizeCode(String source, {String? language}) {
  if (source.isEmpty) return const <CodeToken>[];
  final rules = CodeLanguage.find(language);
  if (rules == null) return [CodeToken(source)];
  return _Lexer(source, rules).run();
}

const String _identifierExtras = r'_$';
const String _punctuation = '{}[]();,.:';
const String _operators = '+-*/%=!<>&|^~?';

/// A single left-to-right pass; the first rule that matches wins.
///
/// No backtracking and no regular expressions: the pass runs on every commit
/// that touches a code block, and a hand-written scan over code units is both
/// predictable and fast enough to be invisible while typing.
class _Lexer {
  _Lexer(this.source, this.language);

  final String source;
  final CodeLanguage language;
  final List<CodeToken> tokens = <CodeToken>[];

  /// Where the run currently being scanned starts.
  int index = 0;

  /// Where the unclassified text before [index] starts.
  int plain = 0;

  List<CodeToken> run() {
    while (index < source.length) {
      final matched =
          _comment() ||
          _stringLiteral() ||
          _directive() ||
          _variable() ||
          _annotation() ||
          _number() ||
          _word() ||
          _symbols();
      // Nothing claimed this character, so it belongs to the plain run and is
      // emitted when the next token — or the end of the source — arrives.
      if (!matched) index++;
    }
    _flush(source.length);
    return tokens;
  }

  /// Emits the text from [index] to [end] as [type].
  void _emit(int end, String type) {
    _flush(index);
    tokens.add(CodeToken(source.substring(index, end), type));
    index = end;
    plain = end;
  }

  void _flush(int end) {
    if (end > plain) tokens.add(CodeToken(source.substring(plain, end)));
    plain = end;
  }

  bool _startsWith(String value, [int? at]) =>
      source.startsWith(value, at ?? index);

  bool _comment() {
    for (final opener in language.lineComments) {
      if (!_startsWith(opener)) continue;
      final newline = source.indexOf('\n', index);
      // The line break itself stays out of the comment: it separates lines
      // rather than belonging to one, and keeping it plain means the run
      // structure of a document does not depend on whether it ends in one.
      _emit(newline == -1 ? source.length : newline, 'comment');
      return true;
    }
    for (final (opener, closer) in language.blockComments) {
      if (!_startsWith(opener)) continue;
      final close = source.indexOf(closer, index + opener.length);
      _emit(close == -1 ? source.length : close + closer.length, 'comment');
      return true;
    }
    return false;
  }

  bool _stringLiteral() {
    // Longest delimiter first: `"""` must not be read as an empty `"` twice.
    for (final delimiter in language.multilineStrings) {
      if (!_startsWith(delimiter)) continue;
      final close = source.indexOf(delimiter, index + delimiter.length);
      _emit(close == -1 ? source.length : close + delimiter.length, 'string');
      return true;
    }
    for (final quote in language.strings) {
      if (!_startsWith(quote)) continue;
      final end = _closeQuote(quote);
      final key = language.stringKeys && _followedByColon(end);
      _emit(end, key ? 'property' : 'string');
      return true;
    }
    for (final quote in language.chars) {
      if (!_startsWith(quote)) continue;
      _emit(_closeQuote(quote), 'char');
      return true;
    }
    return false;
  }

  /// Where the literal opened at [index] with [quote] ends.
  ///
  /// An unterminated one ends at the line break rather than eating the rest of
  /// the file — which is the common case while the string is still being
  /// typed, and the reason a half-written quote does not turn the document
  /// green below the caret.
  int _closeQuote(String quote) {
    var at = index + quote.length;
    while (at < source.length) {
      final char = source[at];
      if (char == '\n') return at;
      if (char == r'\') {
        at += 2;
        continue;
      }
      if (source.startsWith(quote, at)) return at + quote.length;
      at++;
    }
    return source.length;
  }

  bool _followedByColon(int from) {
    for (var at = from; at < source.length; at++) {
      final char = source[at];
      if (char == ' ' || char == '\t') continue;
      return char == ':';
    }
    return false;
  }

  bool _directive() {
    if (!language.directives || source[index] != '#') return false;
    if (!_atLineStart()) return false;
    final end = _identifierEnd(index + 1);
    if (end == index + 1) return false;
    _emit(end, 'property');
    return true;
  }

  bool _atLineStart() {
    for (var at = index - 1; at >= 0; at--) {
      final char = source[at];
      if (char == '\n') return true;
      if (char != ' ' && char != '\t') return false;
    }
    return true;
  }

  bool _variable() {
    if (!language.variables || source[index] != r'$') return false;
    if (_startsWith(r'${')) {
      final close = source.indexOf('}', index + 2);
      _emit(close == -1 ? source.length : close + 1, 'variable');
      return true;
    }
    final end = _identifierEnd(index + 1);
    if (end == index + 1) return false;
    _emit(end, 'variable');
    return true;
  }

  bool _annotation() {
    if (!language.annotations || source[index] != '@') return false;
    final end = _identifierEnd(index + 1);
    if (end == index + 1) return false;
    _emit(end, 'attr');
    return true;
  }

  bool _number() {
    final char = source[index];
    final isDigit = _isDigit(char);
    if (!isDigit && !(char == '.' && _isDigit(_charAt(index + 1)))) {
      return false;
    }
    var at = index;
    if (_startsWith('0x') || _startsWith('0X') || _startsWith('0b')) at += 2;
    var seenDot = false;
    while (at < source.length) {
      final current = source[at];
      if (_isHexDigit(current) || current == '_') {
        at++;
        continue;
      }
      if (current == '.' && !seenDot && _isDigit(_charAt(at + 1))) {
        seenDot = true;
        at++;
        continue;
      }
      // An exponent's sign is part of the number; a minus anywhere else is an
      // operator.
      if ((current == '+' || current == '-') &&
          at > index &&
          (source[at - 1] == 'e' || source[at - 1] == 'E')) {
        at++;
        continue;
      }
      break;
    }
    _emit(at, 'number');
    return true;
  }

  bool _word() {
    final end = _identifierEnd(index);
    if (end == index) return false;
    final word = source.substring(index, end);
    final type = _classify(word, end);
    if (type == null) {
      // Unclassified: leave it in the plain run rather than emitting a typed
      // node, but still step past it so the rules do not see it again.
      index = end;
      return true;
    }
    _emit(end, type);
    return true;
  }

  String? _classify(String word, int end) {
    final probe = language.ignoreCase ? word.toLowerCase() : word;
    if (language.keywords.contains(probe)) return 'keyword';
    if (language.booleans.contains(probe)) return 'boolean';
    if (language.constants.contains(probe)) return 'constant';
    if (language.builtins.contains(probe)) return 'builtin';
    if (_charAt(end) == '(') return 'function';
    if (language.capitalizedIsType && _isUpper(word[0])) return 'class-name';
    return null;
  }

  /// Runs of punctuation and runs of operator characters, each as one token.
  ///
  /// One token rather than one per character: `});` is three nodes' worth of
  /// nothing, and a code block is long enough already.
  bool _symbols() {
    final char = source[index];
    final punctuation = _punctuation.contains(char);
    final operator = !punctuation && _operators.contains(char);
    if (!punctuation && !operator) return false;
    final set = punctuation ? _punctuation : _operators;
    var at = index;
    while (at < source.length && set.contains(source[at])) {
      at++;
    }
    _emit(at, punctuation ? 'punctuation' : 'operator');
    return true;
  }

  int _identifierEnd(int from) {
    var at = from;
    while (at < source.length && _isIdentifier(source[at], at == from)) {
      at++;
    }
    return at;
  }

  String? _charAt(int at) => at >= 0 && at < source.length ? source[at] : null;

  static bool _isDigit(String? char) =>
      char != null && char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

  static bool _isHexDigit(String char) {
    if (_isDigit(char)) return true;
    final lower = char.toLowerCase().codeUnitAt(0);
    return lower >= 0x61 && lower <= 0x66;
  }

  static bool _isUpper(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x41 && code <= 0x5A;
  }

  static bool _isIdentifier(String char, bool first) {
    if (_identifierExtras.contains(char)) return true;
    if (!first && _isDigit(char)) return true;
    final code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        // Anything above ASCII is treated as a letter: identifiers are not
        // English-only, and misreading `ä` as punctuation is worse than
        // occasionally classifying a symbol as a word.
        code > 0x7F;
  }
}
