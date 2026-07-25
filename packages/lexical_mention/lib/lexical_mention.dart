/// Typed `@mention` nodes for `lexical_core`.
///
/// A mention references an entity — a person, an issue, a document — and the
/// kind is **data, not a subclass**: `mentionType` is a free-form string, so
/// an application adds a new kind without a new node type, a registry change
/// or a schema migration.
///
/// ```dart
/// final editor = LexicalEditor(nodes: mentionNodes);
///
/// editor.update(() {
///   $getRoot().append(
///     $createParagraphNode()
///       ..append($createTextNode('cc '))
///       ..append($createMentionNode(
///         text: '@Rebar',
///         mentionType: 'user',
///         mentionId: 'u_42',
///       )),
///   );
/// }, discrete: true);
/// ```
///
/// The interactive picker lives in `lexical_mention_flutter`; everything
/// here — the node, trigger detection and the search controller with its
/// debouncing, stale-response rejection and caching — is pure Dart and runs
/// under `dart test`.
library;

export 'src/mention_node.dart'
    show MentionNode, mentionNodes, $createMentionNode;
export 'src/mention_search.dart'
    show
        CallbackMentionSource,
        MentionQuery,
        MentionSearchController,
        MentionSearchState,
        MentionSource,
        MentionSuggestion;
export 'src/mention_trigger.dart'
    show MentionMatch, MentionTrigger, matchMentionTrigger;
