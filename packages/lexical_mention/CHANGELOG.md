# Changelog

## 1.4.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_flutter` for what changed.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

## 1.0.0

First stable release; semantic versioning applies from here.
Mentions: an atomic token node, bounded trigger detection and a debounced,
stale-answer-dropping search.

The entries below record how it got here.

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
