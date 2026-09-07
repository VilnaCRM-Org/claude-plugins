---
name: test-naming-and-fixture-clarity
description: Use when naming or reviewing a test whose title does not match what its fixture actually sets up, when a fixture keeps or removes files for a non-obvious reason, or when a maintainer is about to "simplify" a bulky-looking fixture. Applies to Bats gate tests, Jest specs, and Playwright specs.
---

# Test Naming and Fixture Clarity

## Profile keys consumed

- `make.test_unit_client`
- `make.test_unit_server`
- `make.test_integration`
- `make.test_e2e`
- `make.test_visual`
- `make.lint_metrics`

Every suite runs through the profile's `make` target map; skip a dependent
step with a recorded note when its key maps to `null`. The Bats gate suite
has no logical key — invoke it through the repository's own gate-test target.

## Overview

A test name is its contract with the next maintainer. When the name describes the setup instead of
the condition, the fixture reads as bloat, someone trims it, and the guard silently widens while the
test still passes.

## When to use

- Writing a gate test whose fixture is built by mutating a valid artifact into an invalid one.
- Reviewing a test where the title and the fixture disagree.
- A fixture that keeps hundreds of files, a size floor, or a specific directory that looks
  incidental.
- A failing test whose message does not explain which of several guards fired.
- Not for: choosing which suite to run or triaging a flaky failure.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate
  CI target): yes — a `tests/bats/` gate suite plus `tests/unit/`, `tests/integration/`,
  `tests/e2e/` and `tests/visual/`; run through the repository's Bats gate-test target and the
  targets mapped by `make.test_unit_client` / `make.test_unit_server` and `make.test_e2e`.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — a `tests/bats/` gate
  suite and the `src/test/` Jest and Playwright suites; the Bats suite runs through the
  repository's own gate-test target.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes —
  `tests/bats/`, `tests/unit/`, `tests/e2e/`, `tests/visual/`; the Bats gate-test target plus the
  single unit target mapped by `make.test_unit_client`.

```bash # profile-example
# The Bats gate suite has no logical profile key; a concrete repository spells it:
make test-bats
make test-unit-all      # make.test_unit_client + make.test_unit_server
make test-e2e           # make.test_e2e
```

## Core pattern

A build-artifact validator has several guards in order: the directory must exist, it must hold a
file-count floor, and it must ship a JavaScript payload. To reach the third guard, the fixture must
satisfy the first two — so it deliberately keeps a populated static directory and its file floor and
removes only the `.js` files.

A title of `"empty static dir"` names a setup that never happens, and the fixture then looks padded.
Naming the condition makes the same fixture read as required:

```bash
@test "fails when the static dir has no .js files (no JS payload)" {
  make_valid_artifact "$ARTIFACT"
  # Remove only the .js, keeping the populated static dir and the file-count
  # floor intact, so this exercises the no-JS guard rather than the earlier
  # "missing dir" or file-count-floor checks.
  rm "$ARTIFACT/static/chunks/main.js"

  run_validator "$ARTIFACT"
  [ "$status" -eq 1 ]
  assert_output_contains 'no .js files'
}
```

Two things make this durable. The title answers "what condition fails?", not "how is the fixture
built?". The comment states which earlier guards the retained parts exist to clear, so a later edit
that trims them is visibly wrong rather than plausibly tidy.

## Quick reference

- Assert on a message fragment unique to the guard under test. Asserting on a generic failure string
  lets an earlier guard satisfy the test.
- When a fixture keeps something, say what it clears; when it removes something, say what that
  exercises.
- The comment belongs in the test, next to the fixture step, not in a commit message or a review
  thread — a future editor reads only the file.
- Where a repository gates comment ratios through the metrics policy behind `make.lint_metrics`, an
  intent comment on a non-obvious fixture is exactly the kind of comment the policy wants.

## Common mistakes

- A title naming the fixture state ("empty directory") while the fixture is populated — retitle to
  the condition the validator rejects.
- Reusing one broad assertion across several guard tests — pin each to its own message fragment.
- Trimming a fixture because it looks oversized — check which guard the removed part was clearing
  first.
- Adding a magic constant (a file count, a byte size) with no note on where the threshold comes from
  — name the guard it is sized against.
