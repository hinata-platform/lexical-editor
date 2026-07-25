# Example — lexical_editor_flutter

A small runnable app.

```sh
cd packages/lexical_editor_flutter/example
flutter create .        # once, to add the platform folders
flutter run
```

The platform folders are not checked in — they differ per
machine and per Flutter version, and they would be the largest thing in the
repository. `flutter create .` writes them from the pubspec that is already
here, and changes nothing else.
