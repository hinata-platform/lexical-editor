/// Keeping a code block's highlight runs in step with its text.
///
/// The structure produced here is upstream's: a code block's children are a
/// **flat** list of [CodeHighlightNode], `LineBreakNode` and `TabNode` — no
/// nesting, one node per run, line breaks as nodes rather than as `\n` inside
/// the text. Both of Lexical's highlighters (`@lexical/code-prism` and
/// `@lexical/code-shiki`) build exactly that, and a document that matches it
/// opens on the web with its structure intact.
///
/// Where they differ is *how a run says what it is*, and this port follows the
/// Prism one: a token class in `highlightType`, coloured by the theme. Shiki
/// instead bakes its palette into each node's `style` as inline CSS, which
/// makes a document remember a light theme forever — the wrong trade for a
/// stored document, though it renders here too, since the style string is
/// honoured by the CSS resolver.
library;

import 'package:lexical_core/lexical_core.dart';

import 'code_language.dart';
import 'code_node.dart';
import 'code_tokenizer.dart';

/// Re-highlights a code block whenever its text or its language changes.
///
/// Three transforms rather than one, and the reason is worth knowing: an
/// element is handed to its own transform only when it was marked dirty
/// *intentionally*, not when a descendant changed. Typing dirties the run
/// being typed into, so without the leaf transforms a block would only ever be
/// highlighted at the moment it was created.
///
/// Registration marks every existing node of these types dirty, so a document
/// loaded before this call is highlighted on the next commit.
///
/// ```dart
/// final editor = LexicalEditor(nodes: [...codeNodes]);
/// registerCode(editor);              // Enter and Tab inside code
/// registerCodeHighlighting(editor);  // colour, kept up to date
/// ```
Unsubscribe registerCodeHighlighting(LexicalEditor editor) {
  void fromLeaf(LexicalNode node) {
    final parent = node.getParent();
    if (parent is CodeNode) {
      $highlightCode(parent);
    } else if (node is CodeHighlightNode) {
      // The block was turned into a paragraph and took its children with it.
      // A highlight run outside a code block is a run of code colours in the
      // middle of prose, so it becomes ordinary text again.
      node.replace($createTextNode(node.getTextContent()));
    }
  }

  final unsubscribes = <Unsubscribe>[
    editor.registerNodeTransform('code', (node) {
      if (node is CodeNode) $highlightCode(node);
    }),
    editor.registerNodeTransform('code-highlight', fromLeaf),
    // Plain text appears inside a code block whenever one is typed into before
    // it has been highlighted for the first time — a new block, or a paste.
    editor.registerNodeTransform('text', fromLeaf),
  ];
  return () {
    for (final unsubscribe in unsubscribes) {
      unsubscribe();
    }
  };
}

/// Brings [node]'s children in line with the tokens its text produces.
///
/// Returns whether anything changed. A block whose language is unknown is left
/// exactly as it is: another Lexical client may have highlighted it for a
/// language this build does not know, and flattening it into one grey run
/// would throw that work away.
///
/// Must be called inside an update.
bool $highlightCode(CodeNode node) {
  if (CodeLanguage.find(node.language) == null) return false;

  final runs = _runsOf(
    tokenizeCode(node.getTextContent(), language: node.language),
  );
  final children = node.children.toList();

  // Only the changed middle is replaced. Typing one character in a long block
  // otherwise rebuilds every run in it — and, worse, destroys the node the
  // caret is in on every keystroke.
  var head = 0;
  while (head < children.length &&
      head < runs.length &&
      runs[head].matches(children[head])) {
    head++;
  }
  if (head == children.length && head == runs.length) return false;

  var tail = 0;
  while (tail < children.length - head &&
      tail < runs.length - head &&
      runs[runs.length - 1 - tail].matches(
        children[children.length - 1 - tail],
      )) {
    tail++;
  }

  // Read the caret before the children it may point into are removed.
  final selection = $getSelection();
  final anchor = selection is RangeSelection
      ? _offsetOf(node, selection.anchor)
      : null;
  final focus = selection is RangeSelection
      ? _offsetOf(node, selection.focus)
      : null;

  node.splice(head, children.length - head - tail, [
    for (final run in runs.sublist(head, runs.length - tail)) run.create(),
  ]);

  if (selection is RangeSelection) {
    // Only a point whose node was among the replaced ones needs moving; the
    // rest are still exactly where the user put them.
    if (anchor != null && !_isLive(selection.anchor)) {
      _placeAt(node, selection.anchor, anchor);
    }
    if (focus != null && !_isLive(selection.focus)) {
      _placeAt(node, selection.focus, focus);
    }
  }
  return true;
}

/// One node the highlighted block should hold.
class _Run {
  const _Run.text(this.text, this.type) : nodeType = 'code-highlight';
  const _Run.lineBreak() : text = '\n', type = null, nodeType = 'linebreak';
  const _Run.tab() : text = '\t', type = null, nodeType = 'tab';

  final String text;
  final String? type;
  final String nodeType;

  /// Whether [node] already is this run, so it can be left alone.
  ///
  /// Text formats are not compared: the tokenizer has no opinion about them,
  /// and rewriting the run would silently drop a bolded word.
  bool matches(LexicalNode node) {
    if (node.type != nodeType) return false;
    if (node is! CodeHighlightNode) return true;
    return node.getTextContent() == text && node.highlightType == type;
  }

  LexicalNode create() => switch (nodeType) {
    'linebreak' => $createLineBreakNode(),
    'tab' => $createTabNode(),
    _ => $createCodeHighlightNode(text, type),
  };
}

/// Splits tokens at line breaks and tabs, which are nodes of their own.
///
/// A token keeps its classification across the split, so the second line of a
/// block comment is still a comment.
List<_Run> _runsOf(List<CodeToken> tokens) {
  final runs = <_Run>[];
  for (final token in tokens) {
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      runs.add(_Run.text(buffer.toString(), token.type));
      buffer.clear();
    }

    for (final character in token.text.split('')) {
      switch (character) {
        case '\n':
          flush();
          runs.add(const _Run.lineBreak());
        case '\t':
          flush();
          runs.add(const _Run.tab());
        default:
          buffer.write(character);
      }
    }
    flush();
  }
  return runs;
}

/// Whether [point] still addresses a node in the document.
bool _isLive(Point point) {
  final node = point.getNode();
  return node != null && node.isAttached;
}

/// Where [point] sits, counted in characters from the start of [node], or
/// `null` when the point is somewhere else in the document entirely.
int? _offsetOf(CodeNode node, Point point) {
  final target = point.getNode();
  if (target == null || !_isInside(node, target)) return null;

  if (point.type == PointType.element && point.key == node.key) {
    var offset = 0;
    for (final child in node.children.take(point.offset)) {
      offset += child.getTextContent().length;
    }
    return offset;
  }

  var offset = 0;
  for (final child in node.children) {
    if (child.key == point.key) return offset + point.offset;
    offset += child.getTextContent().length;
  }
  // Inside the block but not one of its direct children — a shape this pass is
  // about to flatten anyway. The start of the block is the one position
  // guaranteed to still exist afterwards.
  return 0;
}

/// Puts [point] at the character [offset], counted from the start of [node].
void _placeAt(CodeNode node, Point point, int offset) {
  var remaining = offset;
  var index = 0;
  for (final child in node.children) {
    final length = child.getTextContent().length;
    // A line break holds no position a caret can sit inside, so a caret that
    // lands on one addresses the block instead, by child index.
    if (child is! TextNode || child.type == 'tab') {
      if (remaining <= 0) {
        point.set(node.key, index, PointType.element);
        return;
      }
    } else if (remaining <= length) {
      // `<=` and not `<`: at a boundary the caret belongs to the end of the
      // run just typed, not to the start of the next one.
      point.set(child.key, remaining, PointType.text);
      return;
    }
    remaining -= length;
    index++;
  }
  point.set(node.key, node.childrenSize, PointType.element);
}

bool _isInside(CodeNode node, LexicalNode target) {
  LexicalNode? current = target;
  while (current != null) {
    if (current.key == node.key) return true;
    current = current.getParent();
  }
  return false;
}
