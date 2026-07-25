#!/usr/bin/env bash
#
# The first upload of every package to pub.dev, by hand and in order.
#
#   dart pub login                        # once, as the publisher account
#   tool/publish_first_release.sh --dry-run
#   tool/publish_first_release.sh
#
# Only the *first* release needs this. pub.dev configures automated publishing
# on a package's admin page, and a package has no admin page until it exists —
# so the set has to reach pub.dev once by hand before a tag can do it. After
# that, see RELEASING.md.
#
# Two properties worth knowing, because they are what makes running this twice
# safe:
#
#   * It is **resumable**. A package already on pub.dev at this version is
#     skipped, so a run that dies on number nine is fixed by re-running.
#   * It **validates everything before uploading anything**. Publishing cannot
#     be undone, and a set that fails halfway leaves versions on pub.dev
#     pointing at versions that were never uploaded.

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------

if command -v flutter >/dev/null 2>&1; then
  FLUTTER="$(command -v flutter)"
elif [ -x "$HOME/fvm/versions/stable/bin/flutter" ]; then
  # FVM pins a version per machine; use it when there is no global install.
  FLUTTER="$HOME/fvm/versions/stable/bin/flutter"
else
  echo "error: no flutter on PATH and none at ~/fvm/versions/stable" >&2
  exit 1
fi

# The dart beside flutter, so both come from one SDK — but only if it is really
# there: `flutter` on PATH is often a shim whose directory holds nothing else.
DART="$(dirname "$FLUTTER")/dart"
if [ ! -x "$DART" ]; then
  if command -v dart >/dev/null 2>&1; then
    DART="$(command -v dart)"
  else
    echo "error: found $FLUTTER but no dart beside it or on PATH" >&2
    exit 1
  fi
fi

PACKAGES=$(grep -v '^#' .github/publish-order.txt | grep -v '^$')
COUNT=$(echo "$PACKAGES" | wc -l | tr -d ' ')
VERSION=$(grep -E '^version:' packages/lexical_core/pubspec.yaml | head -1 | cut -d' ' -f2)

echo "publishing $COUNT packages at version $VERSION"
echo "using $FLUTTER"
echo

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# Not a hard failure: pub asks for credentials itself if they are missing. It
# is far friendlier to say so now than after fifteen successful uploads.
#
# The file is wherever the platform puts application config, which is a
# different place on each of them — plus the pre-2.15 location. Checking only
# the Linux path tells a logged-in macOS user they are logged out, which is
# worse than not checking at all.
credentials_found=0
for candidate in \
  "$HOME/Library/Application Support/dart/pub-credentials.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/dart/pub-credentials.json" \
  "${APPDATA:-}/dart/pub-credentials.json" \
  "${PUB_CACHE:-$HOME/.pub-cache}/credentials.json"; do
  [ -f "$candidate" ] && credentials_found=1 && break
done
if [ "$credentials_found" = "0" ]; then
  echo "warning: no pub.dev credentials found — run 'dart pub login' first."
  echo
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "warning: the working tree is dirty. pub warns about this, and what"
  echo "         you publish should be what is committed."
  echo
fi

echo "== checking the release order and versions"
"$DART" tool/check_publish_order.dart
echo

# Ask pub.dev what is already there, so this can be re-run after a failure.
# 200 means that exact version exists and re-uploading it would be rejected.
published_already() {
  local package="$1"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    "https://pub.dev/api/packages/$package/versions/$VERSION" || echo 000)
  [ "$code" = "200" ]
}

TODO=""
SKIPPED=""
for package in $PACKAGES; do
  if published_already "$package"; then
    SKIPPED="$SKIPPED $package"
    printf '  %-24s already on pub.dev at %s\n' "$package" "$VERSION"
  else
    TODO="$TODO $package"
  fi
done
[ -n "$SKIPPED" ] && echo

if [ -z "$TODO" ]; then
  echo "nothing to do — every package is on pub.dev at $VERSION."
  exit 0
fi

echo "== validating every package before uploading any"
for package in $TODO; do
  printf '  %-24s ' "$package"
  if (cd "packages/$package" && "$FLUTTER" pub publish --dry-run >/tmp/pub-dry-$package.log 2>&1); then
    echo "ok"
  else
    echo "FAILED"
    echo
    cat "/tmp/pub-dry-$package.log" >&2
    echo >&2
    echo "error: $package would be rejected; nothing has been published." >&2
    exit 1
  fi
done
echo

if [ "$DRY_RUN" = "1" ]; then
  echo "dry run: everything validates. Re-run without --dry-run to publish."
  exit 0
fi

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------

echo "About to publish, in this order:"
for package in $TODO; do echo "  $package $VERSION"; done
echo
echo "This cannot be undone. A published version stays published."
printf 'Type the version (%s) to continue: ' "$VERSION"
read -r confirmation
if [ "$confirmation" != "$VERSION" ]; then
  echo "aborted."
  exit 1
fi
echo

# pub.dev serves a new version immediately, but "immediately" is a promise
# about a distributed system: the next package resolves against the one just
# uploaded, so wait until it is actually visible rather than assume it.
wait_until_visible() {
  local package="$1"
  for _ in $(seq 1 30); do
    published_already "$package" && return 0
    sleep 2
  done
  echo "error: $package $VERSION is not visible on pub.dev after a minute." >&2
  echo "       Later packages depend on it; stopping here." >&2
  return 1
}

DONE=""
for package in $TODO; do
  echo "== $package"
  (cd "packages/$package" && "$FLUTTER" pub publish --force)
  wait_until_visible "$package"
  DONE="$DONE $package"
  echo
done

echo "published:$DONE"
echo
echo "Two things left, both on pub.dev and both once per package:"
echo "  1. Admin -> Publisher -> ahmadre.com"
echo "  2. Admin -> Automated publishing -> hinata-platform/lexical-editor,"
echo "     tag pattern  v{{version}}"
echo
echo "After that a release is:  git tag v$VERSION && git push origin v$VERSION"
echo "See RELEASING.md."
