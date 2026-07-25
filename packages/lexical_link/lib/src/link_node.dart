/// Links.
library;

import 'package:lexical_core/lexical_core.dart';

/// URL schemes that are safe to follow from an editor document.
///
/// A document is untrusted input, and a link is the one place where that
/// input becomes an *action*. `javascript:` is script execution; `data:` can
/// carry HTML that runs in the same origin; `file:` reaches the local disk.
const Set<String> safeUrlSchemes = {
  'http',
  'https',
  'mailto',
  'tel',
  'sms',
  'ftp',
};

/// Whether [url] is safe to make tappable.
///
/// Validation happens **at the point of use**, never on import. The model
/// keeps the URL byte-for-byte so a document round-trips unchanged; a
/// renderer calls this before wiring up a gesture, and shows the link inert
/// when it returns false. Sanitizing on import would silently rewrite user
/// documents and break wire compatibility, while trusting the value at the
/// point of use would turn a stored document into a script-injection vector.
///
/// A relative URL is treated as safe: it cannot name a scheme.
bool isSafeUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  // Control characters are used to smuggle a scheme past naive checks
  // ("java\tscript:"), so reject them outright rather than stripping them.
  for (final unit in trimmed.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return false;
  if (!parsed.hasScheme) return true;
  return safeUrlSchemes.contains(parsed.scheme.toLowerCase());
}

/// A hyperlink wrapping inline content.
class LinkNode extends ElementNode {
  /// Creates a link to [url].
  LinkNode([this._url = '', this._rel, this._target, this._title]);

  String _url;
  String? _rel;
  String? _target;
  String? _title;

  @override
  String get type => 'link';

  @override
  bool get isInline => true;

  @override
  LinkNode clone() => LinkNode(_url, _rel, _target, _title);

  @override
  void afterCloneFrom(covariant LinkNode prev) {
    super.afterCloneFrom(prev);
    _url = prev._url;
    _rel = prev._rel;
    _target = prev._target;
    _title = prev._title;
  }

  /// The target URL, exactly as stored.
  String get url => getLatest<LinkNode>()._url;

  /// The `rel` attribute, or `null`.
  String? get rel => getLatest<LinkNode>()._rel;

  /// The `target` attribute, or `null`.
  String? get target => getLatest<LinkNode>()._target;

  /// The `title` attribute, or `null`.
  String? get title => getLatest<LinkNode>()._title;

  /// Whether this link is safe to make tappable. See [isSafeUrl].
  bool get isSafe => isSafeUrl(url);

  /// Sets the target URL.
  LinkNode setUrl(String value) => getWritable<LinkNode>().._url = value;

  /// Sets the `rel` attribute.
  LinkNode setRel(String? value) => getWritable<LinkNode>().._rel = value;

  /// Sets the `target` attribute.
  LinkNode setTarget(String? value) => getWritable<LinkNode>().._target = value;

  /// Sets the `title` attribute.
  LinkNode setTitle(String? value) => getWritable<LinkNode>().._title = value;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    // All three are written unconditionally, including as explicit nulls.
    // That is not a style choice: upstream's exportJSON writes them without
    // a guard, so omitting them fails a strict fixed-point comparison.
    'rel': _rel,
    'target': _target,
    'title': _title,
    'url': _url,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _url = json['url'] is String ? json['url']! as String : '';
    _rel = json['rel'] is String ? json['rel']! as String : null;
    _target = json['target'] is String ? json['target']! as String : null;
    _title = json['title'] is String ? json['title']! as String : null;
  }
}

/// A link the editor created automatically from typed text.
///
/// It differs from a plain link in one field: [isUnlinked] records that the
/// user dismissed the automatic link, so it is not recreated on the next
/// pass over the same text.
class AutoLinkNode extends LinkNode {
  /// Creates an auto-detected link to [url].
  AutoLinkNode([
    super.url,
    super.rel,
    super.target,
    super.title,
    this._isUnlinked = false,
  ]);

  bool _isUnlinked;

  @override
  String get type => 'autolink';

  @override
  AutoLinkNode clone() => AutoLinkNode(url, rel, target, title, _isUnlinked);

  @override
  void afterCloneFrom(covariant AutoLinkNode prev) {
    super.afterCloneFrom(prev);
    _isUnlinked = prev._isUnlinked;
  }

  /// Whether the user dismissed this automatic link.
  bool get isUnlinked => getLatest<AutoLinkNode>()._isUnlinked;

  /// Records whether the user dismissed this automatic link.
  AutoLinkNode setUnlinked({required bool value}) =>
      getWritable<AutoLinkNode>().._isUnlinked = value;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'isUnlinked': _isUnlinked,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final unlinked = json['isUnlinked'];
    _isUnlinked = unlinked is bool && unlinked;
  }
}

/// Creates a link, applying any registered node replacement.
LinkNode $createLinkNode(
  String url, {
  String? rel,
  String? target,
  String? title,
}) => $applyNodeReplacement(LinkNode(url, rel, target, title));

/// Creates an auto-detected link, applying any registered node replacement.
AutoLinkNode $createAutoLinkNode(
  String url, {
  String? rel,
  String? target,
  String? title,
  bool isUnlinked = false,
}) => $applyNodeReplacement(AutoLinkNode(url, rel, target, title, isUnlinked));
