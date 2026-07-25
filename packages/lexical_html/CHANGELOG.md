# Changelog

## 1.0.0

First stable release; semantic versioning applies from here.
HTML import and export, with a sanitizer that runs at render time rather than
mangling the model.

The entries below record how it got here.

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
