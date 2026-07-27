# Changelog

## 1.7.1

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_link` for what changed.

## 1.7.0

**An image can be resized with a finger.** It never could: a resize handle
sits inside whatever scrolls the document, and against an ordinary pan the
scrollable wins — a vertical drag declares itself after `kTouchSlop`, a pan
only after `kPanSlop`, which is twice as far, so the scroll view reached its
threshold first every time and the drag never started. With a mouse it always
worked, because a scroll view does not accept mouse drags at all, which is
exactly why this went unnoticed. A pointer that goes down on a handle now
claims the gesture at once: there is nothing to arbitrate.

**And it can be hit.** The dot is centred on the edge it moves, so half of it
— three quarters, at a corner — hung outside the stack, and a stack does not
hit-test outside its own box. What was left of a 10-pixel dot was smaller than
the error in where a finger thinks it is. The area that takes the drag is now
`LexicalImageStyle.handleTouchSize` (32 by default), held inside the picture
and shrunk on a small one so eight targets do not swallow each other, while
the dot stays exactly where it was drawn — and is no longer clipped in half by
the stack it hangs over.

**A tap on a handle no longer edits the document.** Claiming the pointer on
the way down means a tap arrives as a drag of zero pixels, and writing back
the size it already has is still an edit: a dirty document, an undo step and a
save, for touching a picture.

## 1.6.1

**An image no longer leaks a decoded picture on every rebuild.** The size a
picture reports about itself was read from a listener added inside `build`, so
every build added another one and nothing ever removed them. A listener owns
the handle it is given; none of those handles were released, and a completer
with listeners is pinned in the application's image cache — so every picture
ever shown stayed in memory for the life of the process, and an editor, where
a rebuild is a keystroke, added a listener per keystroke. The stream is
resolved in `didChangeDependencies` and `didUpdateWidget` now, the way
Flutter's own `Image` does it, and released in `dispose`.

That is also what makes the read safe. `ImageStream.addListener` calls its
listener **synchronously** when the picture is already decoded — which it is
every time after the first — so from inside a build it ran a `setState` the
framework does not allow there. The completer catches that and reports it as
an image *error*, and the picture draws its "could not be loaded" stand-in
having loaded perfectly.

**A picture that fails is no longer broken until the application restarts.**
Flutter's image cache never forgets a failure: the completer that reported one
stays in the cache, and every later request for that address — another
document, another screen, an hour later — is answered with the remembered
error instead of a request. One dropped connection meant nothing with that
address ever rendered again. A failed picture is evicted now, so the next time
it is built it is fetched.

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
