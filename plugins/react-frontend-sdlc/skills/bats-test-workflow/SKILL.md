---
name: bats-test-workflow
description: Use when writing, running, or debugging Bats tests for infrastructure code — Makefile targets, shell scripts under the scripts and CI-scripts directories, jq filters, git hooks, and CI helpers. Triggers include a failing Bats suite target, a regression test that still passes on the buggy code, a stubbed `gh` or `docker` swallowing an error, and changing a Makefile target's shell recipe.
---

# Bats Test Workflow

## Profile keys consumed

- `framework.package_manager`
- `architecture.source_root`
- `make.format`
- `make.lint`

## Overview

Bats is the test layer for shell and Makefile code. Its hardest problem is not writing a test, it is
proving the test is not decoration: a stub can swallow the very malformation the test was written to
catch, so the suite stays green on the vulnerable code.

## When to use

- Changing a Makefile target or its recipe, a script under the scripts or CI-scripts directory, a
  jq filter, or a git hook.
- Adding a regression test for a shell-side bug, especially an injection or quoting bug.
- The repository's Bats suite target fails, or a changed recipe has no case that drives it.
- Not for: application code under the tree named by `architecture.source_root` — that is Jest,
  Playwright, or the visual suite.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — specs in the Bats spec directory, the Bats suite target runs Bats in the dev
  compose service; shared stubs live in the suite's shared helper (`tests/bats/test_helper.bash`).
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — same paths and helper;
  the Bats suite target is host-only in either execution mode and needs a host install through the
  package manager named by `framework.package_manager` rather than a container.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — same
  paths and Bats suite target (in the package-manager compose service), but the helper is usually
  thinner, so read it first and add the stub you need there when it is absent.

Which helpers exist is a per-repository fact in every shape: open the helper and read it rather
than porting a name from another suite.

## Procedure

1. Run the suite, or one file, before changing anything:

   ```bash # profile-example
   make test-bats
   bun x bats tests/bats/makefile_targets.bats
   ```

   Resolve the single-file runner through the package runner for
   `framework.package_manager`, not a hardcoded one.

2. Write the case around observable behaviour. Bats gives `run` plus `$status` and `$output`;
   everything above that is repository-local. Before writing a line, read the suite's shared helper
   — conventionally `tests/bats/test_helper.bash`, the file the existing specs `load` — and list
   what it actually provides: which stub factories (a PATH-shadowing stub directory, per-command
   stubs for `docker`, `make`, `gh`, …), which assertion helpers, and the variable name it records
   invocations under. Call those names; never assume the names used in another repository's specs.
   Reuse beats a fresh ad-hoc stub, so the recorded command log stays comparable across files. If
   the helper has no stub for the command you need, add one there rather than inline, and if there
   is no helper at all, create it and load it from the spec.
3. **Prove the test goes red.** Restore the buggy version of the file under test, run the suite,
   confirm the new case fails, then restore the fix and confirm it passes:

   ```bash # profile-example
   git stash push scripts/ci/<script>.sh && make test-bats   # expect the new case to FAIL
   git stash pop && make test-bats                           # expect green
   ```

   If it stayed green, the assertion is checking presence, not difference — rewrite it.

4. Cover positive, negative, and boundary cases, as the repository's regression-testing policy
   requires. A target that is added or renamed also needs its coverage-manifest row, which is a
   separate contract.
5. Finish with the repository's own gates: the formatter mapped by `make.format`, then the lint
   aggregate mapped by `make.lint`; skip either with a recorded note when it maps to `null`.

## Assert the difference, not the presence

A stub that returns 0 for everything makes a presence check pass on both the vulnerable and the
fixed code. Assert which branch ran instead.

The helper names below are placeholders for whatever the suite's own helper defines — substitute
the real ones you read in step 2.

```bash
@test "comments on the existing alert instead of opening a duplicate" {
  setup_stub_dir                      # puts the stub PATH first and clears the command log
  export EXISTING_ALERTS_FIXTURE="$BATS_TEST_TMPDIR/open-alert.json"
  run create_alert 'release-"broken'  # a quote that malforms an interpolated jq filter
  [ "$status" -eq 0 ]
  assert_log_contains 'issue comment'
  ! grep -q 'issue create' "$COMMAND_LOG"
}
```

The negative assertion is what carries the test: without it, the case passes when the malformed
filter returns empty and the script falls through to creating a duplicate.

## Shell injection cases

- A variable spliced into a jq filter (`select(.title=="$VAR")`) is a program, not data. Pass it as
  data with `jq --arg name "$VAR"` or `--slurpfile`, then test with payloads containing `"`, `)`,
  `|`, and a newline.
- Stub the downstream command and inspect what it received verbatim, with `grep -F` so the payload
  is not re-interpreted as a pattern.
- A silent empty result is the tell: assert non-empty output, not just exit status.

## Common mistakes

- Writing the test after the fix and never checking it fails without it — decoration, not coverage.
- Asserting only `$status` — a stub returning 0 makes every branch look correct.
- Asserting a substring both branches emit (an alert prefix that appears in create and in comment) —
  assert the branch-specific token, plus a negative assertion on the other branch.
- Covering only the happy path — the policy asks for negative and boundary cases too.
- Reaching for a fresh inline stub when the shared helper already has one — load the helper and call its stub.
- Calling a helper name remembered from another repository's suite — read `tests/bats/test_helper.bash` and use the names it actually defines.
