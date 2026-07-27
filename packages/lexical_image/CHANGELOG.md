# Changelog

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
