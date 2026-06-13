# Test Campaign Summary

Adversarial test campaign for the `php-backend-sdlc` plugin: a
subagent-driven loop that wrote a test strategy, generated
positive/negative/edge plans for nine surfaces, executed them, confirmed
every bug through independent skeptic panels, fixed at root cause with
regression tests, and re-verified each round until a full round found
**zero new bugs**. A live end-to-end feature ship proved the flow
auto-performs without babysitting.

## Surfaces

`scripts-cli`, `profile-fuzz`, `governance-inject`, `gh-integration`,
`review-loop`, `commands-semantics`, `agents-contracts`,
`install-lifecycle`, `security-adversarial`. Per-surface plans with
executed case tables live in `plans/`.

## Rounds

| Round | Confirmed bugs | Notes |
| --- | --- | --- |
| 1 | 11 | Initial sweep: threshold/iteration uint64 wraps, governance concurrency + CRLF, preflight work-tree, profile `:=` parsing, raw tracebacks. |
| 2 | 12 | Persistent + fix-introduced classes: real governance lockfile, directory/FIFO/read-only refusal, fenced-marker examples, `findings_norm` zero-test, shared `num_gt`/`strip_zeros`. |
| 3 | 6 | Command-doc contracts (setup `--refresh` convergence, finish-pr MERGED/CLOSED + BLOCKED escalation, qa degrade verdict, issue dedup) + gh node-element shape guard. |
| 4 | 0 | **Convergence.** Every prior fix re-run live and held; adversarial-new probes across the recurring and highest-risk surfaces found nothing. |

29 bugs found and fixed across rounds 1–3; round 4 clean. Test count
grew from 0 to **197 bats**, all green, alongside shellcheck,
markdownlint, and the repo CI gates.

## Method notes

- Every bug was confirmed by a three-skeptic refuter panel (majority
  vote) before a fix was written, so judged-real findings were not
  speculative.
- Each round re-ran the prior rounds' repros **live** rather than
  trusting commit messages — this caught fixes that had only partially
  landed or regressed (about half of each early round's fixes), which is
  why convergence took four rounds.
- Fixes never weakened a check to pass a test; wrap-safe integer
  comparison, symlink refusal, and lockfile concurrency were added as
  real hardening with regression coverage.

## End-to-end proof

The plugin shipped a `Percentage` value object on a disposable
`php-service-template` clone with no human intervention beyond
playbook-prescribed steps: a headless `claude -p "/sdlc-setup"`
auto-discovered and ran the setup scripts, then
SETUP → ISSUE → PLAN → IMPLEMENT → REVIEW → OPEN-PR → FINISH each reached
its exit condition or a documented degrade on the first attempt, with
skills auto-applied via triage-first planning. Real issue and PR were
opened on the sandbox; `fr-nfr-gate` and `get-pr-comments` ran clean.
Zero plugin flow bugs. Evidence: `../evidence/e2e-feature-ship.md`.
