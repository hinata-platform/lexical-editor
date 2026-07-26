# Changelog

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
