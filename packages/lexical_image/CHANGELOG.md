# Changelog

## 1.6.0

**An image that was never resized has drag handles now.** They need geometry,
and geometry meant a *stored* size — so the only image anyone ever wants to
resize, a freshly inserted one, was the one image that could not be. The size
the image reports about itself is a size too, and the handles hang off that
until the document has one of its own.

## 1.5.0

**A `data:` image no longer re-resolves on every build.** `MemoryImage`
compares its bytes by identity and decoding a URI hands back a fresh buffer
each time, so the provider was never `==` to the one from the previous build:
a widget that resolves per build re-resolved every frame, the image never
settled long enough to report a size, and it re-decoded its payload for as long
as it was on screen. A `data:` image is identified by its URI now.

**`LexicalImageStyle`** — the outline, the drag handles and the caption caret
were one hard-coded blue. That is a fine default and a wrong answer in any
product with an accent of its own, and selection chrome is the most visible
thing about editing an image. Pass one to `LexicalImageView` or to
`imageDecoratorBuilders`; the defaults draw exactly what they always drew.

## 1.4.0

**An image that was never resized is no longer drawn 0x0.** `ImageNode` spells
"the image's own size" as `0` and `LexicalImageView` spells it as `null`, and
`imageDecoratorBuilders` forwarded the node's zero verbatim — so the `SizedBox`
around every freshly inserted image forced it to nothing. The image was
uploaded, inserted, stored and exported correctly, and completely invisible.
The builder now maps `0` to `null`, and the view treats a non-positive
dimension as the absence of one, so a caller that forwards the node's value
directly gets the image rather than an empty box.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

- `imageMarkdownTransformer({maxWidth})`: the image rule with a width of your
  choosing. `imageTransformer` is now this function at its default, which is
  still upstream's `800`, so nothing changes for anyone not passing a number.
  It exists because the only way to write a different one was to copy the rule
  into the application — and a copied rule stops matching this one the first
  time either changes.

## 1.1.0

First release. The packages version in lockstep, so this one joins the set at
its current version rather than at 1.0.0.

Images and GIFs: a decorator node matching the Lexical playground's wire
format, and a Flutter widget with drag handles, min/max limits,
aspect-ratio preservation and optional captions.
