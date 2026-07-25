# Changelog

## 0.1.0-dev.1

First development release.

### Added

- `MentionNode`: a token-mode `TextNode` carrying `mentionType`, `mentionId`
  and `trigger`, with arbitrary extra data in the node state.
- `matchMentionTrigger`, whose cost is bounded by the configured query length
  rather than by the length of the paragraph.
- `MentionSearchController` with debouncing, stale-response rejection, an LRU
  query cache and keyboard highlight movement — all pure Dart, so the parts
  that are hard to get right are testable without a widget.
