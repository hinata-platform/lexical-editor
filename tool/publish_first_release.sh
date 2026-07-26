#!/usr/bin/env bash
#
# Uploading the set to pub.dev by hand, in dependency order.
#
#   dart pub login                        # once, as the publisher account
#   tool/publish_first_release.sh --dry-run
#   tool/publish_first_release.sh
#
# Only a release that *creates* packages needs this. pub.dev configures
# automated publishing on a package's admin page, and a package has no admin
# page until it exists — so a package has to reach pub.dev once by hand before
# a tag can release it. After that, see RELEASING.md.
#
# A run may mix the two: a new version of the packages that are already up, a
# first upload of the ones that are not. Only the second kind spends
# `package-created` budget, so the two are counted apart — calling a version
# update a creation would stop a run pub.dev would have allowed.
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

# Whether pub.dev knows the package at all, at any version. Uploading a new
# version of one it already has is `package-published`, a different operation
# from `package-created` with a far roomier limit, so the two have to be told
# apart before any budget is counted.
package_exists() {
  local package="$1"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    "https://pub.dev/api/packages/$package" || echo 000)
  [ "$code" = "200" ]
}

TODO=""      # to publish, in dependency order
SKIPPED=""   # already on pub.dev at this version
NEW=""       # of TODO, the ones pub.dev has never seen — these cost creation budget
EXISTING=""  # every package of the set pub.dev already knows, at any version
for package in $PACKAGES; do
  if package_exists "$package"; then
    EXISTING="$EXISTING $package"
    if published_already "$package"; then
      SKIPPED="$SKIPPED $package"
      printf '  %-24s already on pub.dev at %s\n' "$package" "$VERSION"
      continue
    fi
    TODO="$TODO $package"
  else
    TODO="$TODO $package"
    NEW="$NEW $package"
  fi
done
[ -n "$SKIPPED" ] && echo

is_new() {
  case " $NEW " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# pub.dev's rate limits on creating packages
# ---------------------------------------------------------------------------
#
# From pub-dev's production config (app/config/dartlang-pub.yaml), the
# `package-created` operation is limited per user to:
#
#     burst 4   in a 2-minute window
#     daily 12  in a rolling 24-hour window
#
# Sixteen packages therefore cannot all be created on one day. That is not a
# problem to work around; it is a schedule to respect, and the only real
# question is when the next window opens. Asking pub.dev when the existing
# packages were created answers it exactly, rather than guessing an hour and
# hoping.
DAILY_LIMIT=12
BURST_LIMIT=4

# Prints: <created in the last 24h> <seconds until the oldest one ages out>
#
# A package was created when its *earliest* version was published, not its
# latest. Reading `latest.published` would count every package that took a new
# version today as created today — so a set that publishes new versions of the
# packages already up would report its own budget as spent and refuse a run
# pub.dev has no objection to.
daily_usage() {
  local names="$1"
  {
    for package in $names; do
      curl -s --max-time 15 "https://pub.dev/api/packages/$package" || true
      echo
    done
  } | python3 -c '
import sys, json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
stamps = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
    except ValueError:
        continue
    published = [
        v["published"] for v in (data.get("versions") or []) if v.get("published")
    ]
    if not published:
        continue
    when = min(
        datetime.datetime.fromisoformat(p.replace("Z", "+00:00")) for p in published
    )
    age = (now - when).total_seconds()
    if age < 86400:
        stamps.append(age)
stamps.sort(reverse=True)
wait = int(86400 - stamps[0]) + 60 if stamps else 0
print(len(stamps), wait)
'
}

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

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------
#
# Computed before the dry run returns, because "how much of this fits today"
# is the question a dry run is asked. Nothing here writes to pub.dev.

# A network hiccup must not turn into an unbound variable and a stack trace.
USED_TODAY=0
WAIT_SECONDS=0
read -r USED_TODAY WAIT_SECONDS <<<"$(daily_usage "$EXISTING")" || true
BUDGET=$((DAILY_LIMIT - ${USED_TODAY:-0}))
[ "$BUDGET" -lt 0 ] && BUDGET=0
TODO_COUNT=$(echo $TODO | wc -w | tr -d ' ')
NEW_COUNT=$(echo $NEW | wc -w | tr -d ' ')
UPDATE_COUNT=$((TODO_COUNT - NEW_COUNT))

echo "pub.dev allows $DAILY_LIMIT new packages per day, $BURST_LIMIT per two minutes."
echo "  created in the last 24h: $USED_TODAY"
echo "  left today:              $BUDGET"
echo "  new packages to create:  $NEW_COUNT"
echo "  versions to update:      $UPDATE_COUNT"
if [ "$NEW_COUNT" -gt 0 ] && [ "$BUDGET" -eq 0 ]; then
  echo
  printf 'The daily window is full. It reopens in about %dh %dm — re-run\n' \
    "$((WAIT_SECONDS / 3600))" "$(((WAIT_SECONDS % 3600) / 60))"
  echo "then; it continues where it stopped."
  exit 0
fi
if [ "$NEW_COUNT" -gt "$BUDGET" ]; then
  echo
  echo "Only $BUDGET of the new ones fit today. The rest is one more run"
  echo "tomorrow; the order is topological, so stopping partway is safe."
fi
echo

if [ "$DRY_RUN" = "1" ]; then
  echo "Would publish, in this order:"
else
  echo "About to publish, in this order:"
fi
created=0
for package in $TODO; do
  if is_new "$package"; then
    created=$((created + 1))
    # Everything after an unaffordable creation may depend on it, so the
    # listing stops where the run will.
    [ "$created" -gt "$BUDGET" ] && break
    echo "  $package $VERSION   (new package)"
  else
    echo "  $package $VERSION"
  fi
done
echo
if [ "$DRY_RUN" = "1" ]; then
  echo "dry run: everything validates. Re-run without --dry-run to publish."
  exit 0
fi

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
CREATED=0
CREATED_NAMES=""
REMAINING=""

for package in $TODO; do
  new=0
  is_new "$package" && new=1

  if [ "$new" = "1" ]; then
    # The creation budget is spent. Everything left in the order may depend on
    # this package, and a version whose dependency was never uploaded is the
    # half-published set this script exists to avoid — so stop rather than
    # skip ahead.
    if [ "$CREATED" -ge "$BUDGET" ]; then
      REMAINING="$REMAINING $package"
      echo "-- the day's creation budget is spent; stopping before $package."
      break
    fi

    # Four per two minutes, and only creations count against it. Waiting
    # *before* the fifth is politer than being refused and retrying, and it
    # keeps the run readable.
    if [ "$CREATED" -gt 0 ] && [ $((CREATED % BURST_LIMIT)) -eq 0 ]; then
      echo "-- $BURST_LIMIT created; waiting out the two-minute burst window"
      sleep 125
      echo
    fi
  fi

  echo "== $package"
  log="/tmp/pub-publish-$package.log"
  if (cd "packages/$package" && "$FLUTTER" pub publish --force) 2>&1 | tee "$log"; then
    :
  fi

  if published_already "$package"; then
    wait_until_visible "$package"
    DONE="$DONE $package"
    if [ "$new" = "1" ]; then
      CREATED=$((CREATED + 1))
      CREATED_NAMES="$CREATED_NAMES $package"
    fi
    echo
    continue
  fi

  # Not published. A rate limit is a schedule, not a failure; anything else is
  # a failure and stopping is right, because the packages after this one
  # depend on it.
  if grep -q 'rate limit has been reached' "$log"; then
    REMAINING="$REMAINING $package"
    if grep -q 'in the last day' "$log"; then
      echo
      if [ "$new" = "1" ]; then
        echo "-- pub.dev's daily limit of $DAILY_LIMIT new packages is reached."
      else
        echo "-- pub.dev's daily publish limit for $package is reached."
      fi
      break
    fi
    echo "-- burst limit; waiting two minutes and trying $package once more"
    sleep 125
    if (cd "packages/$package" && "$FLUTTER" pub publish --force) 2>&1 | tee "$log"; then
      :
    fi
    if published_already "$package"; then
      REMAINING="${REMAINING% $package}"
      DONE="$DONE $package"
      if [ "$new" = "1" ]; then
        CREATED=$((CREATED + 1))
        CREATED_NAMES="$CREATED_NAMES $package"
      fi
      echo
      continue
    fi
    echo
    echo "-- still refused; stopping here."
    break
  fi

  echo >&2
  echo "error: $package was not published, and not because of a rate limit." >&2
  echo "       See $log. Nothing after it has been touched." >&2
  exit 1
done

# Anything not attempted in this run.
for package in $TODO; do
  case " $DONE $REMAINING " in
    *" $package "*) ;;
    *) REMAINING="$REMAINING $package" ;;
  esac
done

echo "published:${DONE:- nothing}"
if [ -n "$REMAINING" ]; then
  WAIT_SECONDS=0
  # Every package pub.dev now knows: the ones it already had, plus the ones
  # this run created. Passing a name twice would count its creation twice.
  read -r _ WAIT_SECONDS <<<"$(daily_usage "$EXISTING$CREATED_NAMES")" || true
  WAIT_SECONDS=${WAIT_SECONDS:-0}
  echo "still to go:$REMAINING"
  echo
  echo "The daily window reopens in about $((WAIT_SECONDS / 3600))h $(((WAIT_SECONDS % 3600) / 60))m."
  echo "Re-run this script then — it skips what is already up."
  echo
fi
echo
echo "Two things left, both on pub.dev and both once per package:"
echo "  1. Admin -> Publisher -> ahmadre.com"
echo "  2. Admin -> Automated publishing -> hinata-platform/lexical-editor,"
echo "     tag pattern  v{{version}}"
echo
echo "After that a release is:  git tag v$VERSION && git push origin v$VERSION"
echo "See RELEASING.md."
