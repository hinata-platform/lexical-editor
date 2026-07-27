# Changelog

## 1.7.3

No changes in this package, but three things about editing at a link's edge
are fixed in `lexical_core` 1.7.3: backspace immediately behind a link now
takes a character of it rather than doing nothing, pasted content at its edge
is no longer adopted into the link, and word-wise deletion across its edge
takes a word instead of one letter.

## 1.7.2

No changes in this package, but the one 1.7.1 announced now actually happens:
**typing at a link's edge writes beside it.** `canInsertTextBefore` and
`canInsertTextAfter` were set to `false` here in 1.7.1, and nothing in the
core consulted them, so a character typed in front of a link still became part
of the link. `lexical_core` 1.7.2 is where that is fixed.

## 1.7.1

**A link that is emptied removes itself.** It renders nothing, so an anchor
left behind by deleting the text inside it is invisible: it is saved, sent to
every other client, exported to markdown as `[](url)`, and one accumulates per
edit that emptied a link. `LinkNode.canBeEmpty` is `false` now, which is what
the core consults when a removal leaves a parent with nothing in it, and
`registerLink` removes the ones that are emptied any other way. Both are what
upstream does.

**Typing at a link's edge writes beside it, not into it** —
`canInsertTextBefore` and `canInsertTextAfter` are `false`, as upstream. The
character after a link is not part of the link.

## 1.7.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` and
`lexical_flutter` for what changed.

## 1.6.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.6.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

## 1.5.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_image` for what changed.

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

Making, retargeting and removing links from a selection: `$toggleLink`,
`toggleLinkCommand`, `registerLink` and `$getLinkAtSelection`. The last one
answers for a **caret** as well as a range, which is the case that matters —
someone clicking inside link text expects to edit that link, not to start a
new one.

## 1.0.0

First stable release; semantic versioning applies from here.
Links and autolinks, wire-compatible with @lexical/link.

The entries below record how it got here.

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.
