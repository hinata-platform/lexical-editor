# Changelog

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
