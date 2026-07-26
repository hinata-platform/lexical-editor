# Changelog

## 1.1.0

First release. The packages version in lockstep, so this one joins the set at
its current version rather than at 1.0.0.

The `.lexical` document envelope: `editorState`, `lastSaved`, `source` and
`version`, matching `@lexical/file` field for field, with parsing separated
from installing so a corrupt file cannot take the open document with it.
