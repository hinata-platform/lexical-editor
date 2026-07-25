# Changelog

## 0.1.0-dev.1

First development release.

### Added

- `$generateHtmlFromNodes`: semantic HTML for headings, quotes, lists
  including check lists, code with its language, links, and the text formats.
- `$generateNodesFromHtml`: the tags a paste actually arrives as, with
  unrecognized elements contributing their text rather than nothing.
- `HtmlImportLimits`, bounding depth, node count and text length, because
  pasted markup is untrusted input.
- Escaping applied to every value that reaches the output, attributes
  included.
