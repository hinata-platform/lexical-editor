# Changelog

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
