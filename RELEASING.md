# Releasing

Sixteen packages, one version, one tag.

They are one library split so that an application pays only for what it uses —
not a set of independent projects — so they version in lockstep. `v1.0.0`
releases the set, and CI refuses a tag that disagrees with the pubspecs.

## The steady state

```sh
git tag v1.0.1
git push origin v1.0.1
```

`.github/workflows/publish.yml` then:

1. checks the tag against every pubspec version,
2. checks `.github/publish-order.txt` still covers every publishable package,
3. runs `pub publish --dry-run` over **every package**,
4. publishes them, in dependency order.

Steps 1–3 exist because publishing cannot be undone. A set that fails halfway
leaves pub.dev holding versions that reference versions that were never
uploaded, and there is no delete button — only a new version.

pub.dev authenticates the run by its **GitHub OIDC token**. There is no API
key, nothing in repository secrets, and nothing to leak or rotate.

## The one-time setup

Three things live on pub.dev and cannot be done from this repository. They are
the reason the first release is not just a tag.

### 1. Publish each package once, by hand

pub.dev's automated-publishing settings live on a package's admin page, and a
package has no admin page until it exists. So the first upload of each package
is manual, from a clean checkout, **in dependency order** — `lexical_flutter`
cannot be published before `lexical_core` is on pub.dev to resolve against:

```sh
dart pub login                            # as rebar.ahmad@gmail.com
tool/publish_first_release.sh --dry-run   # validates every one, uploads none
tool/publish_first_release.sh
```

The script asks once, then publishes without stopping between packages. It is
safe to re-run: a package already on pub.dev at this version is skipped, so a
run that dies on number nine is fixed by fixing the cause and running it again.
It validates every remaining package **before** uploading any of them, and
waits for each upload to become visible before publishing the package that
depends on it.

**The first release takes two days, and that is not a bug.** pub.dev limits
creating *new* packages, per user, to 4 in two minutes and **12 in a rolling
24 hours** (`package-created` in pub-dev's production config). Sixteen packages
do not fit in one day. The script knows the limits: it paces itself through the
burst window, publishes as many as the daily budget allows, and prints when the
window reopens. Run it again then — the order is topological, so stopping
partway leaves pub.dev consistent, and the packages already up are skipped.

The limit applies to *creating* a package. Every later release publishes new
versions of packages that already exist, which is a different, much roomier
limit — so this is a one-time cost of the first release, not a property of
releasing.

### 2. Move each package to the ahmadre.com publisher

A first upload is owned by the account that made it, not by a publisher. On
each package: **Admin → Publisher → ahmadre.com**. The account must already be
a member of <https://pub.dev/publishers/ahmadre.com>.

Doing this before step 3 matters: automated publishing is authorized against
the package's owner.

### 3. Enable automated publishing

On each package: **Admin → Automated publishing → Enable publishing from
GitHub Actions**, then

| Field | Value |
|---|---|
| Repository | `hinata-platform/lexical-editor` |
| Tag pattern | `v{{version}}` |

The tag pattern is what makes one tag release the set: pub.dev checks that the
pushed tag matches the pattern with the version of the package being uploaded,
and with lockstep versions `v1.0.0` matches for every package.

Leave "Require GitHub Actions environment" off, or set it to `pub.dev` and add
`environment: pub.dev` to the job in `publish.yml`. Enabling it on pub.dev
without adding it to the workflow rejects every publish.

## When the versions have to diverge

Lockstep is a decision, not a law. The day one package needs a patch the others
do not, switch that package's pub.dev tag pattern to
`{{package}}-v{{version}}`, tag it `lexical_table-v1.0.1`, and give the
workflow a second trigger for that pattern. The order file and the version
check are then per-package rather than global — which is more machinery, so it
is worth deferring until something actually needs it.

## What CI already guarantees

- `dart tool/check_publish_order.dart` — every publishable package is in the
  release order, exactly once, after everything it depends on, and they all
  carry the same version. A package added to the repository but not to that
  file would otherwise be released never, and nobody would notice.
- `pub publish --dry-run` per package, on every pull request.
- The example apps build and their tests pass, so a published example is not a
  broken first impression.
