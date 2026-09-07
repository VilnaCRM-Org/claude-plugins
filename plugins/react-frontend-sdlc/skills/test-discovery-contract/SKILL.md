---
name: test-discovery-contract
description: >-
  Use when a test file exists, type-checks and lints clean but never runs — a spec under an e2e root
  named with a Jest `.test.ts` suffix, a file missing a required infix, a new extension no runner
  matches — or when writing a Bats contract that reconciles declared tests against what `jest
  --listTests` and `playwright test --list` actually discover.
---

# Test discovery contract

## Profile keys consumed

- `make.test_unit_client`
- `make.test_unit_server`
- `make.test_integration`
- `make.test_e2e`
- `make.test_visual`

The contract reconciles the test roots behind these mapped targets. A key that maps to `null` means
that suite does not exist in this repository: drop its root from the inventory with a recorded note
rather than failing the contract on a directory that was never supposed to be there.

## Overview

Runner test-match rules are suffix- and directory-exact and fail open: a misnamed spec is discovered
by nobody, runs nowhere, and still reports green through lint, type-check and coverage. A discovery
contract reconciles two sets — files that **declare** tests, and files a runner **discovers** — and
fails on the difference.

## When to use

- A newly added spec passes review yet never appears in any run's output.
- A new test root, a new runner project, or a new file extension is introduced.
- Coverage percentages move without a corresponding change in the suite.
- Not for: a test that runs and fails — this gate only proves execution, never correctness.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — `tests/bats/test_discovery_contract.bats` over `tests/unit`, `tests/integration`,
  `tests/apollo-server`, `tests/e2e` and `tests/visual`, run by the repository's Bats suite target.
- **Next.js app shape** (routed pages, no aggregate duplication gate): partial — a Bats harness and
  its suite target exist and specs live under `src/test/`, but there is no discovery contract yet;
  the pattern ports directly.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — a
  Bats suite target plus a test-structure lint police test file placement, not whether a runner
  discovers each file.

```bash # profile-example
# The Bats suite target that carries the contract in the React SPA shape:
make test-bats
```

## Procedure

1. **Declare the inventory by content, not by name.** Grep the test roots for a top-level `test(` /
   `it(` / `describe(` including chained modifiers, so `test.concurrent.each(` and
   `describe.each.only(` count:

   ```bash
   grep -rlE '^[[:space:]]*(test|it|describe)(\.[A-Za-z]+)*\(' -- $TEST_ROOTS \
     | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' | sort -u
   ```

   Filter extensions as a second step — the dev container's BusyBox grep has no `--include`.

2. **Collect the discovered set from every runner**, once per environment the config switches on
   (`jest --listTests` per `TEST_ENV`, plus `playwright test --list --reporter=json`). Strip Jest's
   absolute container paths to repo-relative.
3. **Diff and fail on orphans** (`comm -23 declared discovered`), printing each undiscovered file.
4. **Add a zero-discovery guard.** Assert every runner returns a non-empty list, so a config that
   silently narrows to nothing cannot pass as "no orphans".
5. **Probe the extension filter.** Plant a throwaway `describe()` file for each JS/TS-family
   extension under one root and assert the inventory grep matched all of them, so a narrowed filter
   is caught rather than trusted.

## Implementation rules that carry the contract

- **Capture exit status before the pipe.** `sed`, `sort` and `grep` all mask the upstream status; a
  runner that crashes after partial output would hand back a truncated list that hides orphans.
  `grep` exiting 1 means no matches (valid); above 1 means a root is missing or unreadable.
- **`--listTests` exits non-zero when nothing matches**, which is itself the narrowing signal.
- **Walk the Playwright JSON recursively** for `.file`: specs nest inside child suites under
  `test.describe`, so a flat path misses them and reports false orphans. Slice the output from the
  first line starting `{` — dotenv banners print before the JSON.
- **Self-heal the probes.** Sweep them in both `setup()` and `teardown()` so an interrupt, OOM or
  kill cannot strand files that would fail the next run, and gitignore the probe name pattern.
- **Keep shared suite helpers outside the roots.** A helper that wraps `describe`/`it` inside an
  exported function is a known false positive; move it to a helper directory rather than widening
  the inventory grep, which would reopen the hole the gate exists to close.

## Common mistakes

- Counting files instead of diffing sets — a count matches by accident, so diff declared against
  discovered and print each orphan by name.
- Listing only the default runner environment — list once per environment the runner config switches
  on, and union the results.
- Discarding runner stderr, so a module-resolution error reads as an empty discovery list — capture
  it and replay it on failure.
- Deleting a probe sweep because "the test cleans up" — the sweep exists for the run that dies.
