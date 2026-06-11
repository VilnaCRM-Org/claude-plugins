# Evidence: live finish-pr run (FR-8) on PR #2

The plugin's own delivery PR
([VilnaCRM-Org/claude-plugins#2](https://github.com/VilnaCRM-Org/claude-plugins/pull/2))
served as the live FR-8 demonstration: a real PR that started with
failing checks and unresolved AI-reviewer comments and was driven to
all-green with zero unresolved threads using the plugin's own loop
shape (poll → diagnose → root-cause fix → dispatcher commit/push →
re-poll; comment threads fetched through `get-pr-comments.sh`, each
fixed or answered with a reasoned reply, never silently dismissed).

## Starting state (first check round)

| Check | State | Cause |
| --- | --- | --- |
| bats | fail | `npm install -g bats` hit `EACCES` on the hosted runner |
| qlty check | fail | 22 blocking issues (workflow token permissions, unpinned actions, shellcheck source resolution) |
| CodeRabbit | fail | "Insufficient usage credits" — no review produced |
| cubic AI reviewer | pass (with 10 review threads) | 10 verified findings posted as unresolved threads |
| 6 remaining CI jobs | pass | — |

## Iterations (counter A — failing checks)

1. **bats**: root cause was the global npm install, not the tests —
   replaced with `npx --yes bats` (commit `81cf19c`). Check green on
   the next round.
2. **qlty check**: reproduced locally with the qlty CLI; fixed
   root-cause — least-privilege `permissions: contents: read` on the
   repo workflow and both stub-repo fixture workflows (checkov
   CKV2_GHA_1), checkout actions pinned to a full commit SHA, and a
   committed `.qlty/` config with `external-sources=true` so the
   shellcheck driver follows the sourced shared lib. No rules disabled,
   no suppression pragmas (commit `c9a91d6`). Check green on the next
   round.

## Comment resolution (counter B — AI reviewer threads)

All 10 cubic threads were fetched via the shipped
`get-pr-comments.sh --pr 2 --unresolved-only --json` feed (the FR-14
source of truth), then dispositioned:

- **9 fixed** root-cause (commit `eec5a16`) — setup retry-loop
  contradiction, QA-fail resumability loop-back, silent-success on an
  all-unsupported agent matrix, scalar `bounded_contexts` type check,
  missing marker label in issue adopt mode, `--spec-path` repo-boundary
  confinement, closed-issue detection in `/sdlc-plan`, JSON-toolchain
  prerequisite and `_bmad/` workspace notes in the setup walkthrough.
  Each thread received a reply describing the fix and was resolved.
- **1 reasoned reply** (no code change) — the reviewer asked to rename
  `/bmad-help`; the command exists under that exact name in BMAD core,
  so the suggestion would have broken the docs. The justification was
  posted on the thread.

Replies posted: 10/10; threads resolved on every fixed item; zero
silent dismissals.

## Degrade paths exercised (NFR-4)

- **CodeRabbit unavailable** (usage credits exhausted, re-trigger via
  `@coderabbitai review` attempted): the loop fell back to the
  remaining functioning reviewers (cubic, qlty) plus the plugin's own
  multi-lens review loop, exactly as the degrade matrix prescribes for
  a missing reviewer app.
- **Qodo paused** (unpaid seat): reported-and-skipped.

## Final state

All CI jobs green (bats 149/149 in CI, shellcheck, markdown-lint,
manifest-validate, frontmatter-check, profile-keys-check,
generalization-audit), qlty check and qlty fmt green, cubic green,
0 unresolved actionable review threads. The only non-green status is
CodeRabbit's credits notice, which produces no review content and is
outside repository control (documented degrade path above).
