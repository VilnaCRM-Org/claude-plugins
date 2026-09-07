---
name: stryker-mutation-timeout-regression-alarm
description: >-
  Use when a Stryker mutation workflow carries no `timeout-minutes` on its shard or merge job, when
  a mutation run's cost jumps an order of magnitude with no change to the mutate scope, when mutants
  come back `Timeout` instead of `Killed` or `Survived`, or when reviewing the config per-mutant
  test filtering depends on — `enableFindRelatedTests`, `coverageAnalysis`, `timeoutMS`.
---

# Stryker mutation timeout regression alarm

## Profile keys consumed

- `capabilities.mutation_testing`
- `make.test_mutation`
- `make.merge_mutation_reports`
- `quality.mutation_msi`
- `ci.workflows`
- `ci.required_checks`

## Overview

A mutation run that loses its per-mutant test filtering still succeeds — it just costs an order of
magnitude more runner time, with no error to notice. A conservative `timeout-minutes` on the shard
job turns that silent cost into a failed job. It is a kill switch, not a target.

## When to use

- A mutation shard job in the mutation-testing workflow declared by `ci.workflows` has no
  `timeout-minutes`.
- Runtime jumped sharply while the mutate scope, the shard count and the suite stayed the same.
- Mutation config touching `enableFindRelatedTests`, `coverageAnalysis`, `concurrency`, `timeoutMS`,
  or the mutate file list is under review.
- Mutants are coming back as `Timeout` rather than `Killed` or `Survived`.
- Not for: choosing the mutation score threshold or classifying survivors, which is gate policy; nor
  a shard that outgrew its cap because the mutate scope genuinely expanded, which calls for more
  shards rather than a higher ceiling.

## Applicability gate

Skip the whole alarm with a recorded note when `capabilities.mutation_testing` is `false`, or when
the target mapped by `make.test_mutation` is `null` — there is no mutation run to bound. When
`make.merge_mutation_reports` is `null` the repository runs unsharded, so skip step 3 with a
recorded note and bound the single run instead.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — the shard job carries `timeout-minutes: 15` over an 8-way matrix and the merge gate
  `timeout-minutes: 8`; `stryker.config.mjs` sets `jest.enableFindRelatedTests: true`.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — same workflow name, a
  2-way matrix at `timeout-minutes: 40` and a merge gate at 20; `enableFindRelatedTests` is likewise
  on.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — the
  4-way sharded workflow has no `timeout-minutes` on the shard job and `enableFindRelatedTests` is
  deliberately off, so the alarm has to be added and calibrated locally.

## Procedure

1. **Measure the cold cost per shard first.** Shard packing balances file bytes, not mutant density,
   so shards differ: read the slowest observed cold run from recent job logs, not an average.
2. **Set the timeout above that worst observation with headroom**, and say so in a comment naming
   the measured range. A ceiling derived from a measurement survives review; a round multiple of a
   guessed baseline does not.
3. **Give the merge and enforce job its own timeout** — it downloads every shard report and
   re-scores against `quality.mutation_msi`, and it must not hang on a missing artifact.
4. **Keep the gate failing closed.** The merge job runs even when a shard failed and asserts the
   shard result explicitly, so the branch protection listed in `ci.required_checks` never reads a
   skipped job as a pass. Guard it with `!cancelled()` rather than `always()`, so a deliberate
   cancellation is not itself reported as a gate failure:

   ```yaml
   merge:
     needs: shard
     if: ${{ !cancelled() }}
     timeout-minutes: 8
     steps:
       - name: Fail if any mutation shard did not succeed
         if: needs.shard.result != 'success'
         run: |
           echo "::error::Mutation shards did not all succeed; failing the gate."
           exit 1
   ```

5. **When the alarm fires, investigate before adjusting it.** Check per-mutant test filtering first:
   with it off, each mutant reloads the whole suite and mutants land as `Timeout` — counted as
   detected but earned by hanging, not by an assertion. See the repository's own mutation-gate
   documentation on honest mutant classification.
6. **Re-derive the ceiling only after a deliberate scope change** (more mutated files, more shards,
   a new checker) and record the new measured range in the same comment.

## Common mistakes

- Treating the timeout as a budget to grow into — raise it only after the cause of the growth is
  understood and accepted.
- Picking the value as a multiple of the fastest shard, so the slowest shard fails on a clean run.
- Leaving the merge job with a bare `needs:` and no run-anyway condition, which converts a shard
  failure into a skipped gate that reads as green.
- Turning off per-mutant test filtering to dodge a checker error — it inflates detection with
  timeouts and makes the score meaningless.
- Setting a generous timeout on a workflow whose shards were never measured, which alarms on nothing
  and gives false assurance.
