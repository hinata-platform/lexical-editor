# Releasing

Nineteen packages, one version, one tag.

They are one library split so that an application pays only for what it uses —
not a set of independent projects — so they version in lockstep. `v1.1.0`
releases the set. A tag releases exactly the packages that carry its version,
so a fix confined to one package can also ship on its own; see
[Releasing one package on its own](#releasing-one-package-on-its-own).

## The steady state

```sh
git tag v1.0.1
git push origin v1.0.1
```

`.github/workflows/publish.yml` then:

1. works out which packages the tag releases — those whose pubspec carries its
   version, which for a lockstep release is all of them,
2. checks `.github/publish-order.txt` still covers every publishable package,
3. runs `pub publish --dry-run` over every package it is about to release,
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
24 hours** (`package-created`, scope `user`, in pub-dev's production config).
Nineteen packages do not fit in one day. The script knows the limits: it paces
itself through the burst window, publishes as many as the daily budget allows,
and prints when the window reopens. Run it again then — the order is
topological, so stopping partway leaves pub.dev consistent, and the packages
already up are skipped.

That is what happened on the first run: it created the first twelve in
publish order and stopped at the cap, leaving the tail for the next day.

The limit applies to *creating* a package. Every later release publishes new
versions of packages that already exist, which is a different and much roomier
limit — `package-published` is 12 a day **per package** and 200 a day per user,
so a whole set of nineteen costs one of each package's twelve. This is a
one-time cost of the first release, not a property of releasing. A run that
mixes the two — new versions of the packages that are up, first uploads of the
ones that are not — only spends creation budget on the new ones.

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

## Releasing one package on its own

Lockstep is a decision, not a law, and a change confined to one package is a
poor reason to spend nineteen of pub.dev's two hundred daily uploads. Bump only
that package and tag its version:

```sh
# packages/lexical_history/pubspec.yaml: version: 1.7.5
git tag v1.7.5
git push origin v1.7.5
```

The workflow reads each pubspec and releases the packages whose version equals
the tag; the rest are reported in the run summary as untouched and skipped.
Nothing on pub.dev has to change: the `v{{version}}` tag pattern is checked per
package against *that package's* version, so `v1.7.5` matches for the package
being uploaded and never comes up for the others.

The set is then on mixed versions, which is fine as long as it still resolves —
`check_publish_order.dart` verifies that every constraint one package places on
another is satisfied by what is in the repository. Widen the constraint or hold
the version back if it is not.

The one thing this cannot tell you is that you *forgot* a bump: a set meant to
ship whole with one package left behind looks exactly like a deliberate partial
release. The run summary lists both sides for that reason — read it.

## What CI already guarantees

- `dart tool/check_publish_order.dart` — every publishable package is in the
  release order, exactly once, after everything it depends on, and every
  version in the repository satisfies the constraints the others place on it.
  A package added to the repository but not to that file would otherwise be
  released never, and nobody would notice.
- `pub publish --dry-run` per package, on every pull request.
- The example apps build and their tests pass, so a published example is not a
  broken first impression.
