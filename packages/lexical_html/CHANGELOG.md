# Changelog

## 1.11.0

Requires `lexical_core` 1.11.0 and `lexical_layout` 1.11.0.

**A mail keeps its shape.** When the editor registers the layout nodes, a
table row of two or more cells becomes a `layout-container` whose columns come
from the cells' widths, a run of MJML `mj-column-per-NN` columns becomes one
too, and a styled table, cell or `div` becomes a block style on the block it
holds, or on a one-column layout around several. `bgcolor`, `align`, `width`,
`cellpadding`, `<center>` and `<font>` are read like their CSS. Inline CSS on
text becomes the text's `style`, inherited the way CSS inherits; only the
properties a renderer draws are kept. Hidden elements, collapsed preheaders,
mobile-only variants and tracking pixels are dropped. Data tables stay text.
Without the layout nodes registered the import is what it was.

**Images.** `HtmlImport.createImage` turns an `<img>` into a node with its
width and height; without it an image contributes its `alt` text.

**Export** writes layouts as the playground's
`data-lexical-layout-container` markup, which the importer reads back, and a
block's style — rewritten from the parsed style, never copied — on its tag.

## 1.7.4

**A block wrapper contributes its text once.** A `<div>` holding only inline
content becomes a paragraph — and that paragraph was built from the converted
children *and* filled again by converting the element a second time, so every
such `div` was pasted into the document twice. Its alignment survives as
before.

## 1.7.3

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.2

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.7.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_link` for what changed.

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

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. The bundled example is now in English.

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
