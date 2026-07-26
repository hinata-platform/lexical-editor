# Changelog

## 1.1.0

`registerHashtag` and `defaultHashtagPattern`: detection as a pair of
transforms, so text that becomes a tag turns into one and a tag that stops
looking like a tag turns back into text. The pattern matches letters by Unicode
class — `#Grüße` and `#مرحبا` are tags — and only at the start of a word, so
`a#b` and every URL fragment are not.

## 1.0.0

First stable release; semantic versioning applies from here.
Hashtags: a non-mergeable text node.

The entries below record how it got here.

## 0.1.0-dev.1

First development release. Node types verified as a fixed point against
fixtures generated from Lexical 0.48.0.
