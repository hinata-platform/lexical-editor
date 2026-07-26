# Example — lexical_editor_flutter

A small runnable app — and the published demo:
**<https://hinata.ahmadre.com/lexical-editor/>**, rebuilt from `main`
on every push by `.github/workflows/pages.yml`.

```sh
cd packages/lexical_editor_flutter/example
flutter create .        # once, to add the platform folders
flutter run
```

Only `web/` is checked in, because the demo site is built from it. The other
platform folders differ per machine and per Flutter version and would be the
largest thing in the repository, so `flutter create .` writes them from the
pubspec that is already here and changes nothing else.
