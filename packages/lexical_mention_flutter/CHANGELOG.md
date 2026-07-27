# Changelog

## 1.7.4

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

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

**The return key takes the highlighted suggestion even when it arrives as an
input action.** A soft keyboard and the web engine's hidden input both send
Enter as a `TextInputAction` rather than as a `KeyEvent`, so on exactly the
platforms where a typeahead matters most it reached the editor as "insert a
paragraph". The picker then closed because the text before the caret had
changed — from the outside, Enter cancelling the mention. `MentionScope` now
handles `inputActionCommand` alongside the key event.

**`MentionScope.surfaceBuilder`** wraps the suggestion list in chrome a
`Decoration` cannot draw — a blurred surface, a clipped shape, a painted rim.
The popover was the one surface an application could not make its own, because
a fill, a border and a shadow were all it was allowed to ask for.

## 1.3.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version. See `lexical_core` for what changed.

## 1.2.0

No library changes. The packages version in lockstep — they are one library
split for pay-for-what-you-use, not a set of independent projects — so this
release keeps the set on one version.

## 1.1.0

- Fixed: the picker could open empty. Its overlay was built in the frame the
  caret's block first mounts in, when the block has not registered its render
  object yet, and nothing asked again afterwards.
- `MentionScope.editableKey`, so a host can have both the picker and the
  editable's geometry — two `GlobalKey`s cannot sit on one widget.

## 1.0.0

First stable release; semantic versioning applies from here.
The mention typeahead: a caret-anchored popover with keyboard navigation, and
chip rendering for the inserted token.

The entries below record how it got here.

## 0.1.0-dev.1

First development release.

### Added

- `MentionScope`: a caret-anchored overlay popover that flips above the caret
  when there is no room below, and re-applies the ambient theme inside the
  overlay.
- Keyboard navigation at critical command priority, so arrows reach the list
  before they move the caret.
- `$textBeforeCaret`, which reads a bounded amount of text and stops at a
  token rather than walking the block.
- `$insertMention`, replacing the trigger's range in a single update.
