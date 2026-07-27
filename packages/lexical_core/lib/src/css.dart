/// Inline CSS declarations.
///
/// A node's `style` is an untyped CSS string on the wire, and the model keeps
/// it verbatim so a document round-trips through Lexical web unchanged.
/// Anything that wants to *reason* about it needs it as declarations instead:
/// a colour swatch reading the current colour, a size picker replacing one
/// property and leaving the rest alone.
///
/// These two functions are that conversion and nothing more. They do not
/// validate, resolve or normalize: `color: red` and `color:red` parse the
/// same, and both serialize back as `color: red;`, but an unknown property is
/// carried through untouched because the model is not the place to decide
/// what a renderer understands.
library;

/// Parses inline CSS text into its declarations, in source order.
///
/// Property names and values are returned trimmed and otherwise verbatim, so
/// `font-family: "Fira Code", monospace` keeps its quotes and its spacing.
/// Comments are dropped; a declaration with an empty name or value is
/// skipped; `;` and `:` inside quotes or parentheses are content, not
/// separators, which is what keeps `background: url(a;b)` in one piece.
///
/// ```dart
/// getStyleObjectFromCss('color: #f00; font-size: 12px');
/// // {'color': '#f00', 'font-size': '12px'}
/// ```
Map<String, String> getStyleObjectFromCss(String css) {
  final styles = <String, String>{};
  if (css.isEmpty) return styles;

  final property = StringBuffer();
  final value = StringBuffer();
  // Characters are accumulated as contiguous slices rather than one at a
  // time: `chunkStart` marks where the pending run began, or -1 when nothing
  // is pending. A run is flushed whenever a character is dropped (a comment)
  // or acts as a separator.
  var chunkStart = -1;
  var isParsingValue = false;
  var parenthesisDepth = 0;
  var inComment = false;
  var isEscaped = false;
  String? quote;

  void flush(int end) {
    if (chunkStart == -1) return;
    (isParsingValue ? value : property).write(css.substring(chunkStart, end));
    chunkStart = -1;
  }

  void commit() {
    final name = property.toString().trim();
    final declaration = value.toString().trim();
    if (name.isNotEmpty && declaration.isNotEmpty) styles[name] = declaration;
    property.clear();
    value.clear();
    isParsingValue = false;
  }

  for (var i = 0; i < css.length; i++) {
    final char = css[i];
    final next = i + 1 < css.length ? css[i + 1] : '';

    if (inComment) {
      if (char == '*' && next == '/') {
        inComment = false;
        i++;
      }
      continue;
    }

    if (isEscaped) {
      if (chunkStart == -1) chunkStart = i;
      isEscaped = false;
      continue;
    }

    if (quote != null) {
      if (chunkStart == -1) chunkStart = i;
      if (char == r'\') {
        isEscaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }

    if (char == '/' && next == '*') {
      flush(i);
      inComment = true;
      i++;
      continue;
    }

    if (char == '"' || char == "'") {
      if (chunkStart == -1) chunkStart = i;
      quote = char;
      continue;
    }

    if (char == '(') {
      if (chunkStart == -1) chunkStart = i;
      parenthesisDepth++;
      continue;
    }

    if (char == ')') {
      if (chunkStart == -1) chunkStart = i;
      if (parenthesisDepth > 0) parenthesisDepth--;
      continue;
    }

    if (!isParsingValue && char == ':' && parenthesisDepth == 0) {
      flush(i);
      isParsingValue = true;
      continue;
    }

    if (char == ';' && parenthesisDepth == 0) {
      flush(i);
      commit();
      continue;
    }

    if (chunkStart == -1) chunkStart = i;
  }

  flush(css.length);
  commit();
  return styles;
}

/// Serializes [styles] back into an inline CSS string.
///
/// The inverse of [getStyleObjectFromCss], to within whitespace: every
/// declaration is written as `name: value;`, in map order. An entry with an
/// empty name is skipped rather than emitting a `: value;` that no parser
/// would read back.
String getCssFromStyleObject(Map<String, String> styles) {
  final css = StringBuffer();
  for (final entry in styles.entries) {
    if (entry.key.isEmpty) continue;
    css.write('${entry.key}: ${entry.value};');
  }
  return css.toString();
}
