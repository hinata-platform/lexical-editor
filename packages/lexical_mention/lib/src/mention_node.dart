/// The mention node.
library;

import 'package:lexical_core/lexical_core.dart';

/// A reference to an entity: a person, an issue, a document, anything.
///
/// A mention is a **token-mode `TextNode`**, not a decorator, and that choice
/// is the reason a document can hold thousands of them without slowing down.
/// Token mode makes it atomic — edited as a unit, deleted whole — while
/// keeping it part of the ordinary text run, so it costs one span rather than
/// one widget, one placeholder layout and one render-object child. A decorator
/// buys an avatar and pays for it on every frame; if you need that, render a
/// specific mention type as a `WidgetSpan` and leave the rest as text.
///
/// The kind of thing referenced is data, not a subclass: [mentionType] is a
/// free-form string, so an application adds `sprint` or `release` without
/// touching this package or registering a new node type.
///
/// ## Wire format
///
/// ```json
/// { "detail": 0, "format": 0, "mode": "token", "style": "",
///   "text": "@Rebar", "type": "mention", "version": 1,
///   "mentionType": "user", "mentionId": "u_42", "trigger": "@" }
/// ```
///
/// `mention` is not an upstream Lexical type, so this schema is ours and the
/// web counterpart must match it. Anything beyond these three fields belongs
/// in the node state (`"$"`), which round-trips untouched and needs no schema
/// change on either side — see [MentionNode.data].
class MentionNode extends TextNode {
  /// Creates a mention displayed as [text].
  MentionNode({
    String text = '',
    String mentionType = 'user',
    String mentionId = '',
    String trigger = '@',
  }) : _mentionType = mentionType,
       _mentionId = mentionId,
       _trigger = trigger,
       // Atomic by construction. A mention that could be edited character by
       // character would drift out of step with the entity it names.
       super(text, TextMode.token);

  String _mentionType;
  String _mentionId;
  String _trigger;

  @override
  String get type => 'mention';

  @override
  MentionNode clone() => MentionNode(
    text: getTextContent(),
    mentionType: _mentionType,
    mentionId: _mentionId,
    trigger: _trigger,
  );

  @override
  void afterCloneFrom(covariant MentionNode prev) {
    super.afterCloneFrom(prev);
    _mentionType = prev._mentionType;
    _mentionId = prev._mentionId;
    _trigger = prev._trigger;
  }

  /// What kind of thing is referenced — `user`, `issue`, `doc`, or your own.
  String get mentionType => getLatest<MentionNode>()._mentionType;

  /// The referenced entity's stable identifier.
  String get mentionId => getLatest<MentionNode>()._mentionId;

  /// The character that introduced this mention, usually `@`.
  String get trigger => getLatest<MentionNode>()._trigger;

  /// Extra per-mention data, serialized under the reserved `"$"` key.
  ///
  /// Use this for anything the referencing application needs — an avatar URL,
  /// a project key, a status colour. It round-trips untouched, so adding a
  /// field needs no coordination with other clients.
  Map<String, Object?> get data => nodeState.nested;

  /// Sets one entry of [data].
  MentionNode setData(String key, Object? value) {
    final writable = getWritable<MentionNode>();
    writable.nodeState[key] = value;
    return writable;
  }

  /// Points this mention at a different entity.
  MentionNode retarget({
    String? mentionType,
    String? mentionId,
    String? label,
  }) {
    final writable = getWritable<MentionNode>();
    if (mentionType != null) writable._mentionType = mentionType;
    if (mentionId != null) writable._mentionId = mentionId;
    if (label != null) writable.setTextContent(label);
    return writable;
  }

  /// A mention is never merged into the text around it.
  ///
  /// Token mode already prevents it, but stating it here makes the intent
  /// explicit at the place a reader will look.
  @override
  bool get isSimpleText => false;

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'mentionType': _mentionType,
    'mentionId': _mentionId,
    'trigger': _trigger,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    final mentionType = json['mentionType'];
    _mentionType = mentionType is String ? mentionType : 'user';
    final mentionId = json['mentionId'];
    _mentionId = mentionId is String ? mentionId : '';
    final trigger = json['trigger'];
    _trigger = trigger is String ? trigger : '@';
    // Mode is structural, not authored: a document claiming a mention is
    // editable text would let it drift from the entity it names.
    setMode(TextMode.token);
  }

  @override
  String toString() =>
      'MentionNode($mentionType:$mentionId, "${getTextContent()}")';
}

/// Creates a mention, applying any registered node replacement.
MentionNode $createMentionNode({
  required String text,
  required String mentionType,
  required String mentionId,
  String trigger = '@',
}) => $applyNodeReplacement(
  MentionNode(
    text: text,
    mentionType: mentionType,
    mentionId: mentionId,
    trigger: trigger,
  ),
);

/// The node specs this package contributes.
List<NodeSpec<LexicalNode>> get mentionNodes => <NodeSpec<LexicalNode>>[
  NodeSpec<MentionNode>(type: 'mention', create: MentionNode.new),
];
