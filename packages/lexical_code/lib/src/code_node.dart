/// Code blocks and their syntax-highlight runs.
library;

import 'package:lexical_core/lexical_core.dart';

/// A block of source code.
///
/// Its children are ordinary text nodes, [CodeHighlightNode]s, and line
/// breaks. Note that a code block authored by appending a multi-line text
/// node keeps the newlines *inside* that node — Lexical preserves them, so
/// this port does too, and a renderer must handle them rather than assuming
/// every break is a `LineBreakNode`.
class CodeNode extends ElementNode {
  /// Creates a code block for [language].
  CodeNode([this._language]);

  String? _language;

  @override
  String get type => 'code';

  @override
  CodeNode clone() => CodeNode(_language);

  @override
  void afterCloneFrom(covariant CodeNode prev) {
    super.afterCloneFrom(prev);
    _language = prev._language;
  }

  /// The language identifier, or `null` when unset.
  String? get language => getLatest<CodeNode>()._language;

  /// Sets the language identifier.
  CodeNode setLanguage(String? value) =>
      getWritable<CodeNode>().._language = value;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'language': _language,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final language = json['language'];
    _language = language is String ? language : null;
  }
}

/// A run of code carrying a syntax-highlight classification.
///
/// It is a `TextNode` subclass, so it never merges with plain text: merging
/// requires equal types, which is what keeps highlight runs addressable.
class CodeHighlightNode extends TextNode {
  /// Creates a highlighted run of [text] classified as [highlightType].
  CodeHighlightNode([super.text, this._highlightType]);

  String? _highlightType;

  @override
  String get type => 'code-highlight';

  // The base class's fields are restored by afterCloneFrom, so a subclass
  // only has to carry its own. The text is passed anyway because it reads
  // clearly and costs one map lookup.
  @override
  CodeHighlightNode clone() =>
      CodeHighlightNode(getTextContent(), _highlightType);

  @override
  void afterCloneFrom(covariant CodeHighlightNode prev) {
    super.afterCloneFrom(prev);
    _highlightType = prev._highlightType;
  }

  /// The token class, such as `keyword` or `string`.
  String? get highlightType => getLatest<CodeHighlightNode>()._highlightType;

  /// Sets the token class.
  CodeHighlightNode setHighlightType(String? value) =>
      getWritable<CodeHighlightNode>().._highlightType = value;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'highlightType': _highlightType,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final highlightType = json['highlightType'];
    _highlightType = highlightType is String ? highlightType : null;
  }
}

/// Creates a code block, applying any registered node replacement.
CodeNode $createCodeNode([String? language]) =>
    $applyNodeReplacement(CodeNode(language));

/// Creates a highlight run, applying any registered node replacement.
CodeHighlightNode $createCodeHighlightNode(
  String text, [
  String? highlightType,
]) => $applyNodeReplacement(CodeHighlightNode(text, highlightType));
