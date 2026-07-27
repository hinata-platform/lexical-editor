/// Markdown text into a document.
library;

import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';

import 'transformers.dart';

/// Replaces the document with [markdown].
///
/// Parsing is **line-based** for blocks and recursive for inline content,
/// which is the shape that keeps the two independent: a rule that recognizes
/// a heading never has to know what bold looks like.
///
/// Fenced code is handled ahead of the line rules because it is the one
/// construct that spans lines and whose contents must not be parsed at all —
/// a `*` inside code is an asterisk.
///
/// Must be called inside an update.
void $convertFromMarkdown(
  String markdown, {
  MarkdownTransformers transformers = const MarkdownTransformers(),
}) {
  final root = $getRoot()..clear();
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];

    final fence = _fenceStart(line);
    if (fence != null) {
      final body = <String>[];
      index++;
      while (index < lines.length && _fenceEnd(lines[index]) == null) {
        body.add(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      root.append(
        $createCodeNode(fence.isEmpty ? null : fence)
          ..append($createTextNode(body.join('\n'))),
      );
      continue;
    }

    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    _appendLine(root, line, transformers);
    index++;
  }

  if (root.isEmpty) root.append($createParagraphNode());
}

/// Parses [markdown] as **inline** content: text, formats, links, images.
///
/// The piece an [ElementTransformer] needs when the text it has to parse is
/// not the last captured group — a table row, where every cell is its own
/// inline run and the rule alone knows where the boundaries are.
///
/// Block constructs are not recognized: a `# ` here is a literal hash.
///
/// Must be called inside an update, since it creates nodes.
List<LexicalNode> $parseMarkdownInline(
  String markdown, {
  MarkdownTransformers transformers = const MarkdownTransformers(),
}) => _parseInline(markdown, 0, transformers);

String? _fenceStart(String line) {
  final match = RegExp(r'^```([a-zA-Z0-9_+-]*)\s*$').firstMatch(line.trim());
  return match?.group(1);
}

String? _fenceEnd(String line) =>
    RegExp(r'^```\s*$').hasMatch(line.trim()) ? '' : null;

void _appendLine(
  ElementNode root,
  String line,
  MarkdownTransformers transformers,
) {
  for (final transformer in transformers.elements) {
    final match = transformer.regExp.firstMatch(line);
    if (match == null) continue;
    final block = $createParagraphNode();
    root.append(block);
    // The rule reads the captured content itself, so it decides which group
    // carries text and which carries structure.
    final children = _parseInline(
      match.groupCount >= 1 ? (match.group(match.groupCount) ?? '') : line,
      0,
      transformers,
    );
    transformer.replace(block, children, match);
    return;
  }

  final paragraph = $createParagraphNode();
  root.append(paragraph);
  paragraph.appendAll(_parseInline(line, 0, transformers));
}

/// How deep a rule's own content may itself be parsed as markdown.
///
/// A link inside a link label inside a link label is not a document anyone
/// writes; it is what a rule whose output re-matches its own pattern produces,
/// forever. Two levels is more than the constructs that exist need.
const int _maxContentDepth = 2;

/// Parses [text] into inline nodes, carrying [format] into everything it makes.
///
/// [contentDepth] counts only the recursion through
/// [TextMatchTransformer.parsesInlineContent] — the ordinary recursion into a
/// delimiter's body or the rest of the line is unbounded on purpose, because it
/// always consumes input and therefore always terminates.
List<LexicalNode> _parseInline(
  String text,
  int format,
  MarkdownTransformers transformers, {
  int contentDepth = 0,
}) {
  if (text.isEmpty) return const [];

  var earliest = text.length;
  TextFormatTransformer? formatHit;
  var formatEnd = -1;
  TextMatchTransformer? matchHit;
  RegExpMatch? matchResult;

  for (final transformer in transformers.textMatches) {
    final match = transformer.regExp.firstMatch(text);
    if (match == null || match.start >= earliest) continue;
    earliest = match.start;
    matchHit = transformer;
    matchResult = match;
    formatHit = null;
  }

  for (final transformer in transformers.textFormats) {
    if ((format & transformer.format.bit) != 0) continue;
    final open = text.indexOf(transformer.tag);
    if (open < 0 || open >= earliest) continue;
    final close = _findClose(
      text,
      transformer.tag,
      open + transformer.tag.length,
    );
    // An unpaired delimiter is a literal asterisk, not a parse error.
    if (close < 0 || close == open + transformer.tag.length) continue;
    earliest = open;
    formatHit = transformer;
    formatEnd = close;
    matchHit = null;
    matchResult = null;
  }

  final result = <LexicalNode>[];

  if (formatHit != null) {
    if (earliest > 0) {
      result.add(_text(text.substring(0, earliest), format));
    }
    final inner = text.substring(earliest + formatHit.tag.length, formatEnd);
    result.addAll(
      _parseInline(
        inner,
        format | formatHit.format.bit,
        transformers,
        contentDepth: contentDepth,
      ),
    );
    result.addAll(
      _parseInline(
        text.substring(formatEnd + formatHit.tag.length),
        format,
        transformers,
        contentDepth: contentDepth,
      ),
    );
    return result;
  }

  if (matchHit != null && matchResult != null) {
    if (earliest > 0) {
      result.add(_text(text.substring(0, earliest), format));
    }
    final node = matchHit.replace(matchResult, format);
    if (node != null) {
      if (matchHit.parsesInlineContent &&
          node is ElementNode &&
          contentDepth < _maxContentDepth) {
        _parseContentOf(node, transformers, contentDepth + 1);
      }
      result.add(node);
    } else {
      result.add(_text(matchResult.group(0)!, format));
    }
    result.addAll(
      _parseInline(
        text.substring(matchResult.end),
        format,
        transformers,
        contentDepth: contentDepth,
      ),
    );
    return result;
  }

  result.add(_text(text, format));
  return result;
}

/// Parses the text a rule put inside [element] as inline markdown.
///
/// Each text child is replaced by what its own content parses to. The child's
/// format is carried in rather than dropped: a link inside emphasis has that
/// emphasis on the label the rule made, and re-parsing it must add to that
/// rather than replace it.
void _parseContentOf(
  ElementNode element,
  MarkdownTransformers transformers,
  int contentDepth,
) {
  for (final child in element.children.toList()) {
    if (child is! TextNode) continue;
    final text = child.getTextContent();
    if (text.isEmpty) continue;

    final parsed = _parseInline(
      text,
      child.getFormat(),
      transformers,
      contentDepth: contentDepth,
    );
    // Nothing in it was markdown: leave the node the rule made, rather than
    // swapping it for an identical one.
    if (parsed.length == 1 && parsed.single is TextNode) continue;

    LexicalNode anchor = child;
    for (final node in parsed) {
      anchor.insertAfter(node);
      anchor = node;
    }
    child.remove();
  }
}

/// Finds the delimiter that closes [tag], skipping ones that only open.
///
/// The subtlety is `***bold and italic***`: a naive search for the next `**`
/// lands in the middle of the closing run and leaves an orphan `*`. A closing
/// delimiter is one that sits at the **end** of its run of delimiter
/// characters, which is exactly the rule that gets nesting right.
int _findClose(String text, String tag, int from) {
  final character = tag.codeUnitAt(0);
  var index = text.indexOf(tag, from);
  while (index >= 0) {
    var runEnd = index;
    while (runEnd < text.length && text.codeUnitAt(runEnd) == character) {
      runEnd++;
    }
    if (index + tag.length == runEnd) return index;
    index = text.indexOf(tag, index + 1);
  }
  return -1;
}

TextNode _text(String text, int format) {
  final node = $createTextNode(text);
  if (format != 0) node.setFormat(format);
  return node;
}
