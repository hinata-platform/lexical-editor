# Fixture generation

`gen_fixtures.mjs` builds and canonicalizes the fixture corpus by running the
**real Lexical engine** through `@lexical/headless`. It is the only thing in
this repository allowed to define what "canonical" means: derived fields and
normalization are whatever upstream actually does, not what anyone believed
it does.

```sh
npm install

# Write the built-in corpus.
node gen_fixtures.mjs --generate ../../packages/lexical_core/test/fixtures

# Canonicalize documents exported from a real app — worth more than any
# synthetic corpus, because production data finds wire-format gaps first.
node gen_fixtures.mjs --canonicalize ./incoming --out ../../packages/lexical_core/test/fixtures

# CI: verify every fixture is still a fixed point for the installed version.
node gen_fixtures.mjs --check ../../packages/lexical_core/test/fixtures
```

The generated files are committed so the Dart suite runs without a Node
toolchain. Regenerate them after an upstream version bump and read the diff:
a change there is a change in the compatibility contract, and it should be
reflected in the package `CHANGELOG` rather than merged silently.

`--check` runs weekly in CI for exactly that reason.

## Playground nodes

`layout-container`, `layout-item` and `image` are shapes Lexical web documents
carry, but upstream ships them only inside its React playground, not as a
package. `playground_nodes.mjs` re-declares their model half (fields, clone,
JSON, shadow-root and can-be-empty policy) from the v0.48.0 sources, and the
generator registers it next to the published packages.

## Pinned version

`package.json` pins the Lexical packages to an exact version. Compatibility is
stated as a version range in the repository README; bumping the pin and
regenerating is a deliberate act, not a `npm update`.
