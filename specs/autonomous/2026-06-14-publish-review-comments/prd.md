---
stepsCompleted: [step-01-init, step-02c-executive-summary, step-03-success, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-publish-review-comments/research.md
  - specs/autonomous/2026-06-14-publish-review-comments/product-brief.md
  - specs/autonomous/2026-06-14-security-audit-skill/prd.md
  - plugins/php-backend-sdlc/scripts/get-pr-comments.sh
  - plugins/php-backend-sdlc/scripts/fr-nfr-gate.sh
  - plugins/php-backend-sdlc/scripts/ai-review-loop.sh
  - plugins/php-backend-sdlc/scripts/lib/common.sh
  - plugins/php-backend-sdlc/skills/security-audit/SKILL.md
  - plugins/php-backend-sdlc/skills/code-review/SKILL.md
  - plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md
  - plugins/php-backend-sdlc/commands/sdlc-review.md
  - plugins/php-backend-sdlc/docs/profile-schema.md
  - .github/workflows/ci.yml
workflowType: 'prd'
date: 2026-06-14
author: John (BMAD PM agent, autonomous run — interactive steps skipped, decisions recorded inline)
---

# Product Requirements Document — Publish Review Findings as PR Comments (`php-backend-sdlc`)

## 1. Executive Summary

Add an **opt-in, gated capability** to the existing `php-backend-sdlc` plugin
(v1: 8 commands, 7 agents, 22 skills + 2 meta-guides, generalized to any PHP
backend via `.claude/php-sdlc.yml`) that **publishes** the findings of its three
review lenses — `security-audit`, the BMAD FR/NFR review gate, and `code-review`
— as GitHub PR comments, and posts a single **conclusion** comment at loop
close. Today the lenses do first-class work whose output never reaches the PR
conversation: the security lens emits a SECURITY-AUDIT RUN REPORT into the
orchestrator transcript (`security-audit/SKILL.md:298-309`), the FR/NFR gate
posts a comment **only on FAIL** (success is comment-quiet — the commit status
is the durable signal, `fr-nfr-gate.sh:16-21,133-144`), and `code-review` keeps
its evidence in a private `PR_COMMENT_EVIDENCE` ledger
(`code-review/SKILL.md:86-149`). A human reviewer landing on the PR sees a
green/red status check and fix commits, but not *what each lens found, at what
severity, and which findings were auto-fixed at the root cause with a
regression test*.

The feature introduces **one shared poster** —
`plugins/php-backend-sdlc/scripts/post-review-findings.sh` — built as a sibling
of `scripts/get-pr-comments.sh`: same shebang / `set -euo pipefail` /
`lib/common.sh` sourcing, the same `--pr` flag-and-validation, the same
origin-then-`gh` repo-slug resolution, JSON-validity/shape guards before
trusting `gh` output, and the same jq-with-python3 dual backend
(`get-pr-comments.sh:1-24,29-39,57-68,109-130`). It consumes a canonical
finding-record **ledger** (JSON on stdin or `--file`) plus a lens argument
(`security | fr-nfr | code-review`), renders **one** consolidated, deduped,
severity-ordered Markdown comment per lens, and is **idempotent** via a hidden
HTML marker (`<!-- sdlc-review:<lens> -->`) — it **updates** its prior bot
comment instead of spamming, reusing the marker-block replace-in-place
discipline already shipped in `scripts/inject-governance.sh` (research §2.5,
§3.1). A `--conclusion` mode aggregates the three lens ledgers into one
`<!-- sdlc-review:conclusion -->` comment: counts found by lens and severity,
count auto-fixed root-cause-with-regression-test, iterations used, and run
duration.

The capability is **default-off and opt-in**, gated behind a new
`capabilities.publish_pr_comments` profile flag (modeled on
`capabilities.dynamic_security_testing`, `profile-schema.md:130`), posts **only
to the resolved repo's own PR** (never a third party / fork base), redacts known
secret shapes, and **degrades** (gh absent / no PR / flag off / empty ledger /
malformed gh read → skip-with-note, exit 0, never fail the loop, NFR-3) — the
deliberate inverse of `get-pr-comments.sh`'s die-on-`gh`-absent
(`get-pr-comments.sh:40`; research §4 R5, §6.6). A short, gated **Publish** step
wires into each of the three skills and into the `/sdlc-review` orchestrator,
which posts the conclusion once at loop close using the `iteration <n>/5`
counter and the timing it captures (`sdlc-review.md:170-187`). Brief goals
G1–G10 (product-brief §4) govern this PRD; every FR/NFR traces to them (§5).

## 2. Functional Requirements

### 2.1 The shared poster — `scripts/post-review-findings.sh`

**FR-1 — `post-review-findings.sh`, sibling of `get-pr-comments.sh`** (G1, G4, G8)
A new script `plugins/php-backend-sdlc/scripts/post-review-findings.sh`, built as
a sibling of `get-pr-comments.sh`: `#!/usr/bin/env bash`, `set -euo pipefail`,
`SCRIPT_DIR` resolution, and `source "$SCRIPT_DIR/lib/common.sh"` behind the
`# shellcheck source=lib/common.sh` pragma so `shellcheck -x` follows the lib
(`get-pr-comments.sh:1-24`; `ci.yml` shellcheck job). It accepts:

- a **lens argument** (positional or `--lens`): one of `security | fr-nfr |
  code-review` for the per-lens modes, or `--conclusion` for the aggregate mode
  (FR-4); an unknown lens is a clean `die` with usage text.
- `--pr <n>` — PR number with the same numeric guard `[[ "$PR" =~ ^[0-9]+$ ]]`
  and the same `gh pr view --json number --jq .number` default-resolution +
  re-validation of the `gh`-resolved value (`get-pr-comments.sh:31,37-55`).
- `--file <path>` and stdin — the canonical ledger JSON (FR-3); for
  `--conclusion`, one or more ledgers (concatenated array or repeated `--file`).
- unknown arguments → `die` with usage text (`get-pr-comments.sh:34`).

The repo slug resolves owner/name from the origin remote with `gh repo view` as
fallback (`get-pr-comments.sh:57-68`); this `OWNER/NAME` feeds both the
authorization check (FR-7) and the comment list/update path (FR-2). Every JSON
transform (ledger parse, render, dedup/sort, comment-list parse) offers **both**
a jq and a python3-stdlib backend, like every transform in `get-pr-comments.sh`
(`:113-120, 264-333`), so the script runs where only python3 exists. The script
is **shellcheck-`-x`-clean** and **bats-stub-friendly** (driven by
`STUB_GH_OUTPUT`, asserted via `STUB_GH_LOG`, FR-10).
**AC:** `shellcheck -x scripts/post-review-findings.sh` exits 0 in the
`shellcheck` CI job; a dry-run with a fixture ledger and the stub `gh` renders a
comment body; the script resolves `OWNER/NAME` from an `origin` remote in a
temp git repo and from `gh repo view` when no `origin` exists; with `jq` removed
from `PATH` the python3 backend produces byte-identical canonical render output.

**FR-2 — Idempotent hidden-marker publish (update-vs-create)** (G1)
Each per-lens comment carries a hidden marker `<!-- sdlc-review:<lens> -->`
(and the conclusion `<!-- sdlc-review:conclusion -->`). On every run the poster
**lists** the PR's issue comments, **finds** the one whose body contains the
lens marker AND is authored by the posting identity (FR-7), and **updates** it
(`gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id} -f body=...` or the
GraphQL `updateIssueComment` mutation); it **creates** a comment
(`gh pr comment "$pr" --body ...`, as in `fr-nfr-gate.sh:103`) only when no
marker'd, author-matched comment exists. Modeled on the in-repo
`inject-governance.sh` marker-block replace-in-place discipline (research §2.5),
including its corruption tolerance: **duplicate** marker'd comments collapse to
one (edit the oldest; the rest MAY be hidden via the GraphQL `minimizeComment`
mutation as the corruption-recovery branch only). `gh pr comment --edit-last`
is **never** used (it edits the last actor comment regardless of lens —
lens-unsafe). The comment-list read is guarded by the same
`raw_is_json`/shape-guard discipline before trusting `gh` output
(`get-pr-comments.sh:109-130, 152-260`); a non-JSON / error-envelope read
degrades (FR-9), falling back to create or skip.
**AC:** With the stub `gh`, a first run logs exactly one create call and no
update call (asserted via `STUB_GH_LOG`); a second run against a list response
that already contains the marker'd, author-matched comment logs exactly one
update (PATCH/`updateIssueComment`) call and **zero** create calls; a list
response containing two marker'd comments edits the oldest and never creates a
third; no run emits a `gh pr comment --edit-last` call.

**FR-3 — Canonical finding-record ledger schema** (G2)
The poster consumes ONE canonical ledger JSON, defined once and derived from
the three lens shapes (a projection of the security-audit finding-record
`security-audit/SKILL.md:272-309`, unioned with the code-review
priority/disposition categorization `code-review/SKILL.md:256-263` and the
FR/NFR `FR_NFR_NEW_FINDINGS` count `fr-nfr-gate.sh:116-121`):

```json
{
  "lens": "security | fr-nfr | code-review",
  "pr": 123,
  "findings": [
    {
      "id": "<family-or-rule>-<n>",
      "severity": "Critical | High | Medium | Low",
      "cwe": "CWE-89",
      "owasp": "A03:2021",
      "location": "<architecture.source_root>/<path>:<line>",
      "endpoint": "<METHOD> <path>",
      "summary": "<one-line, redacted>",
      "status": "open | fixed | dropped",
      "auto_fixed": true,
      "regression_test": "<test path>"
    }
  ],
  "iterations": 3,
  "started_at": "<ISO-8601 UTC>",
  "ended_at": "<ISO-8601 UTC>"
}
```

`cwe`, `owasp`, `endpoint`, `regression_test` are **optional** (FR/NFR and
code-review findings often carry none); `id`, `severity`, `location`, `summary`,
`status` are required per finding; `auto_fixed` is a bool (a finding routed
through `php-implementer` with a failing-then-passing regression test counts as
auto-fixed root-cause, `security-audit/SKILL.md:194-204`). The schema is both
jq- and python-parseable. A malformed ledger (not JSON, wrong top-level type,
missing `lens`) is a clean `die` for the per-lens modes and a per-ledger
skip-with-note for `--conclusion` (FR-9), never a traceback.
**AC:** A fixture ledger with all fields and a minimal fixture with only the
required fields both render without error; a finding omitting `cwe`/`owasp`
renders with those columns blank, never with the literal `null`; a ledger that
is not JSON, or whose top-level value is an array/scalar, or that lacks `lens`,
is rejected with a `[php-sdlc][ERROR]`-prefixed diagnostic (per-lens) or a
skip-note (conclusion), and never reaches the render step.

**FR-4 — Per-lens consolidated render: dedup + severity order** (G2)
For a per-lens run the poster renders **one** Markdown comment from the ledger:
a header naming the lens, the hidden marker (FR-2), a deduped and
severity-ordered finding table, and a per-lens summary line. Findings are
**deduped** by the tuple `(cwe, location, endpoint)` — the exact tuple the
security lens already dedupes on (`security-audit/SKILL.md:185-187`) — so two
findings hitting the same sink collapse to one row. The remaining rows are
**ordered by severity band Critical → High → Medium → Low**, with `dropped`
findings either omitted or grouped under a clearly-labelled "dropped / not
reproduced" subsection (never interleaved with open findings). The render runs
through either the jq or the python3 backend with identical output. An **empty**
ledger (zero findings) is the degrade path FR-9, not an empty comment.
**AC:** A ledger with two findings sharing `(cwe, location, endpoint)` renders
one row, not two; a ledger with mixed severities renders Critical first and Low
last; the jq and python3 backends produce byte-identical comment bodies for the
same ledger; a `dropped`-status finding never appears above an `open` finding.

**FR-5 — `--conclusion` aggregate comment (counts found / auto-fixed / duration)** (G2)
In `--conclusion` mode the poster reads the three lens ledgers and renders one
aggregate comment (marker `<!-- sdlc-review:conclusion -->`) containing:

- **counts found by lens and severity** — a matrix of (lens × Critical/High/
  Medium/Low) finding counts;
- **count auto-fixed root-cause-with-regression-test** — the number of findings
  with `auto_fixed: true` and a non-empty `regression_test`, by lens;
- **iterations used** — per lens (and/or the orchestrator's overall
  `iteration <n>/5`, `sdlc-review.md:180-187`);
- **run duration** — derived from the orchestrator-captured start/end (or the
  ledgers' `started_at`/`ended_at`), rendered human-readably (e.g. `12m 04s`).

**All counting and the duration delta use the `common.sh` wrap-safe digit-string
helpers (`strip_zeros`/`num_gt`, `:39-58`), never bash `(( ))`** — the same
discipline `fr-nfr-gate.sh:125-137` and `ai-review-loop.sh:44-54` enforce, so a
crafted huge count or timestamp cannot wrap a total to a wrong value (R8). The
conclusion comment is idempotent by the same marker mechanism (FR-2). A lens
with no ledger contributes a zero row, not a missing one.
**AC:** Given three fixture ledgers, the conclusion comment's per-lens severity
counts equal the source findings; the auto-fixed count equals the number of
`auto_fixed:true`-with-`regression_test` findings; a ledger with a 20-digit
finding count does not wrap the rendered total (wrap-safe digit-string math);
the duration renders from `started_at`/`ended_at`; a second `--conclusion` run
updates the existing conclusion comment rather than creating a second.

### 2.2 The three skills' Publish step + orchestrator wiring

**FR-6 — Gated Publish step in each of the three review skills** (G1, G3, G9)
Each of the three review skills gains a **short, gated Publish step** (a few
lines pointing at the poster + the gate flag; enumerations stay in the script so
each SKILL.md stays ≤ ~500 lines, NFR-7). Each step (a) checks
`capabilities.publish_pr_comments` and skips-with-note when false/absent,
(b) emits its lens ledger (FR-3) and invokes the `make.post_review_findings`
target — or the substituted `scripts/post-review-findings.sh` when that key is
`null` (FR-8) — with the lens arg, ledger, and `--pr`, and (c) states the
degrade contract (FR-9). The slot per skill:

- `security-audit/SKILL.md` — Publish slots **after §5.4 aggregate / at loop
  close**, emitting the `security` lens ledger from the finding records
  (`security-audit/SKILL.md:182-204, 298-309`).
- `bmad-fr-nfr-review-gate/SKILL.md` — Publish slots **where the gate already
  posts** (`fr-nfr-gate.sh:96-144`; `bmad-fr-nfr-review-gate/SKILL.md:55-60,
  244-245`), emitting the `fr-nfr` lens ledger from the gate findings.
- `code-review/SKILL.md` — Publish slots **after its evidence ledger** (after
  Step 5 / Step 6), emitting the `code-review` lens ledger from the
  priority/disposition categorization (`code-review/SKILL.md:256-263`).

Each skill lists `capabilities.publish_pr_comments` and
`make.post_review_findings` under its `## Profile keys consumed` header
(FR-8/profile-keys-check, `ci.yml` profile-keys-check job).
**AC:** Each of the three SKILL.md files contains a Publish step that (1) gates
on `capabilities.publish_pr_comments`, (2) resolves the poster via
`make.post_review_findings` (null → plugin script), (3) passes the correct lens
arg, and (4) states the degrade-with-note contract; each file lists both new
keys under `## Profile keys consumed`; each file remains ≤ ~500 lines; the
`frontmatter-check` and `markdown-lint` CI jobs stay green on all three.

**FR-7 — Authorized / in-scope boundary + secret redaction** (G5, G6)
The poster writes **only** to the origin/`gh`-resolved `OWNER/NAME`'s own PR.
Before any write it verifies the target PR's base repository equals the resolved
`OWNER/NAME`; a PR whose base repo differs (third-party / fork-base / an
arbitrary owner/repo supplied via `--pr` against a mismatched remote) is
**refused with a note** (skip-with-note, exit 0 — FR-9), never written. The
update-find author-filters to the **posting identity** (the token user, e.g. via
`gh api user`, or a configured bot login) so it never edits a human comment that
merely quotes the marker (R7). Before render, the poster **redacts** a documented
set of known secret shapes from every finding `summary`/`location`/reproduction
field — AWS access keys, JWTs, `password=`/`secret=`/`token=` assignments,
`://user:pass@` URL credentials, and high-entropy token-like strings — as a
defensive second layer over the ledger's already-redacted text (the
security-auditor no-exfiltration boundary, `security-audit/SKILL.md:48-49`).
This reuses the plugin's in-scope and no-exfiltration discipline applied to the
**PR target** rather than the probe target.
**AC:** A `--pr` whose resolved base repo differs from the origin/`gh`-resolved
`OWNER/NAME` produces a skip-with-note and **zero** `gh` write calls
(`STUB_GH_LOG`); the update path never selects a comment whose author differs
from the posting identity; a fixture ledger whose `summary` contains an AWS key,
a JWT, a `password=...`, and a `://user:pass@host` URL renders with each secret
masked and the cleartext absent from the comment body (bats redaction test).

**FR-8 — New profile keys in `docs/profile-schema.md`** (G3, G9)
Two minimal keys are added following existing conventions:

- `capabilities.publish_pr_comments` — a **bool, default `false`** /
  opt-in capability flag gating the Publish step and the poster's write path,
  mirroring `capabilities.dynamic_security_testing` /
  `capabilities.structurizr` (`profile-schema.md:127, 130`). When false/absent
  the Publish step and the poster skip-with-note (FR-6, FR-9).
- `make.post_review_findings` — a **nullable** row in the required `make` map;
  `null` (the shipped default) ⇒ the plugin substitutes
  `scripts/post-review-findings.sh`, exactly mirroring the
  `make.ai_review_loop` / `make.pr_comments` / `make.fr_nfr_gate`
  null-substitution precedent (`profile-schema.md:76-78`).

Because the `make` map is **required-and-complete** (`profile-schema.md:60-64`),
the new key must be **emitted by `scripts/generate-profile.sh` and accepted by
`scripts/validate-profile.sh`** (an incomplete map is a validation error), and
added to the annotated `# profile-example` block (`profile-schema.md:138-189`).
Both keys are documented in `docs/profile-schema.md` (table row + the
`# profile-example` block) so the `profile-keys-check` CI job — which greps each
skill's `## Profile keys consumed` header against this page — passes (any key a
skill cites that is absent from the schema page fails CI).
**AC:** `docs/profile-schema.md` lists `capabilities.publish_pr_comments` (bool,
default false) in the `capabilities` table and `make.post_review_findings`
(nullable, plugin-substitutes-when-null) in the `make` table, and the
`# profile-example` block carries both; `generate-profile.sh` emits
`make.post_review_findings` and `validate-profile.sh` accepts a profile
containing it and rejects a `make` map missing it; `profile-keys-check` is green
with the three edited skills citing both keys.

### 2.3 Orchestrator wiring

**FR-9 — Degrade matrix (never fail the loop, NFR-3)** (G4)
The poster's **default failure mode is skip-with-note + `exit 0`**, the
deliberate inverse of `get-pr-comments.sh`'s die-on-`gh`-absent (which feeds the
FR-8 read loop's exit condition, `get-pr-comments.sh:40`). This contrast is
documented in the script header so a reviewer does not "fix" the poster to die
(research §6.6). The full matrix:

| Condition | Behavior | Exit |
| --- | --- | --- |
| `capabilities.publish_pr_comments` false/absent | `log_info` skip-note (gating, R6) | 0 |
| `gh` not on `PATH` | `log_info` skip-note (NOT a die, R5) | 0 |
| No PR resolvable (`gh pr view` empty, no `--pr`) | `log_info` skip-note | 0 |
| Empty ledger (zero findings) | `log_info` skip-note (no empty comment) | 0 |
| Malformed `gh` comment-list read (non-JSON / error envelope) | `log_warn`, fall back to create or skip (R11) | 0 |
| Target PR base repo ≠ resolved `OWNER/NAME` | `log_warn` refuse-with-note (FR-7, R3) | 0 |
| `gh` write failure (PATCH/create 4xx/5xx, rate/abuse limit) | `log_warn`, never fail the loop (R4; mirrors `fr-nfr-gate.sh:96-105`) | 0 |

No retry/backoff machinery — a write failure warns and the loop proceeds. Skip-
and warn-notes use the `common.sh` `log_info`/`log_warn` `[php-sdlc][LEVEL]`
prefix (`common.sh:21-23`).
**AC:** Each of the seven rows is exercised in bats (flag off, `gh` removed from
`PATH`, no PR + no `--pr`, empty-findings ledger, non-JSON list response,
mismatched base repo, `STUB_GH_EXIT` non-zero on the write call): each produces
the documented note, `exit 0`, and **zero** loop-failing exits; the script
header documents the die-vs-degrade contrast with `get-pr-comments.sh`.

**FR-10 — Orchestrator posts the conclusion once at loop close** (G2, G9)
The `/sdlc-review` orchestrator (and the relevant `/sdlc-finish-pr` hand-off)
gains the conclusion wiring: it **captures start at loop entry and end at loop
close**, and at loop close — gated on `capabilities.publish_pr_comments` —
invokes the poster's `--conclusion` mode **once** with the three lens ledgers,
the captured duration, and the `iteration <n>/5` count it already tracks
(`sdlc-review.md:170-187`). The conclusion is posted exactly once per loop (not
per iteration); ownership is `/sdlc-review` at its loop close (a single post per
loop; a `/sdlc-finish-pr` hand-off does not double-post). The wiring is a short
slot in the command body that respects the command's `allowed-tools`
(`sdlc-review.md:4`) and the degrade matrix (FR-9).
**AC:** `commands/sdlc-review.md` documents capturing the loop start/end and a
single `--conclusion` post at loop close, gated on
`capabilities.publish_pr_comments`, passing the captured duration and iteration
count; the conclusion-post slot states the degrade-with-note contract; no
second conclusion post is described for the `/sdlc-finish-pr` hand-off.

### 2.4 Test-tier coverage

**FR-11 — Full three-tier test coverage** (G10)
All three plugin test tiers cover the feature:

- **bats** — `tests/post-review-findings.bats`, using the env-driven `gh` stub
  (`tests/fixtures/bin/gh`: `STUB_GH_OUTPUT`/`STUB_GH_EXIT`/`STUB_GH_LOG`) and a
  subcommand-routing `gh` wrapper for the two-response list→edit path (the
  technique documented in `tests/get-pr-comments.bats:1-10`). Cases:
  render (FR-4), idempotent **update-vs-create** asserted via `STUB_GH_LOG`
  (FR-2), dedup by `(cwe, location, endpoint)` (FR-4), severity ordering (FR-4),
  **redaction** of each secret shape (FR-7), gating **on/off** (FR-6/FR-9),
  **every degrade path** in the FR-9 matrix, the authorization/base-repo refusal
  (FR-7), and **conclusion math** including the wrap-safe digit-string case
  (FR-5). The suite runs in the `bats` CI job (`ci.yml`).
- **python prompt-quality** — the three edited SKILL.md files are re-judged by
  `tools/plugin-quality/judge/` against the `rubrics.py` dimensions
  (`degrade-path-soundness`, `profile-key-branching`, `exit-condition-
  consistency`, `root-cause-culture`, `instruction-unambiguity`,
  `trigger-specificity`), and pass the deterministic lint tier
  (`tools/plugin-quality/lint/check_*.py`: frontmatter, descriptions,
  generalization, references, escalation). The Publish step must keep the
  degrade-path/profile-key/exit-condition dimensions scoring high.
- **LLM-judge** — the domain LLM-judge harness (the
  `tools/security-audit-validation/judge/` precedent) judges the edited skills'
  Publish step for the gating, idempotency, authorization, redaction, and
  degrade contracts.

New profile keys (FR-8) must pass `profile-keys-check` and
`generalization-audit` **before** any skill cites them.
**AC:** `tests/post-review-findings.bats` is present and green in the `bats` CI
job and covers each cited case (render, update-vs-create via `STUB_GH_LOG`,
dedup, severity order, redaction, gating on/off, every FR-9 degrade row,
base-repo refusal, conclusion math incl. wrap-safe); the python prompt-quality
judge + lint tiers run on the three edited skills and pass; an LLM-judge tier
over the edited skills is present; `profile-keys-check` and
`generalization-audit` are green over all new/edited files.

## 3. Non-Functional Requirements

**NFR-1 — Generalization (NFR-2/NFR-4 inherited)** (G8): Zero source-project
identifiers in `post-review-findings.sh`, its bats suite, the three edited
SKILL.md files, the orchestrator edit, and the schema edits — outside
`# profile-example` fences. Every path / PR number / repo slug resolves from the
profile, from `gh`/`git` at runtime, or from test fixtures. The CI-greppable
denylist (`user[-_ ]service`, `mongo[a-z]\w*repository`, `apprunner`,
`src/user`, `src/oauth`, `vilnacrm` — `ci.yml` generalization-audit job) must
not appear; concrete upstream values may appear only inside `# profile-example`
fences.
**AC:** The `generalization-audit` CI job exits 0 over all new/edited
component-dir files; seeding a denylist token (e.g. a real org/repo slug in the
bats suite outside a `# profile-example` fence) fails the audit; 100% of the new
script/tests/skill/command/schema edits pass.

**NFR-2 — Idempotent, low-noise output** (G1): The poster produces **one comment
per lens + one conclusion comment**; re-runs UPDATE the existing marker'd
comment; there is no per-finding spam; `gh` calls are bounded to O(lenses) — one
list + one create-or-update per lens, plus the conclusion. No per-iteration
re-post (the orchestrator posts the conclusion once at loop close, FR-10).
**AC:** Across two consecutive runs the `STUB_GH_LOG` shows exactly one create
then one update per lens (zero duplicate bot comments); the conclusion is posted
once per loop; `gh` call count per lens does not grow with finding count.

**NFR-3 — Degrade over hard-fail** (G4): The poster's default failure mode is
skip-with-note + `exit 0`; a `gh` write failure warns; it **never fails the
loop**. This inverts `get-pr-comments.sh`'s die-on-`gh`-absent
(`get-pr-comments.sh:40`) and the contrast is documented in the script header.
Every condition in the FR-9 matrix has a defined no-fail behavior.
**AC:** Every FR-9 degrade row completes with the documented note and `exit 0`;
no degrade path returns a non-zero exit; the header documents the contrast.

**NFR-4 — Wrap-safe arithmetic** (G7): All conclusion counts (per-lens severity
counts, auto-fixed counts) and the duration delta use the `common.sh`
`strip_zeros`/`num_gt` digit-string helpers (`:39-58`), **never** bash `(( ))`
— the same rule `fr-nfr-gate.sh:125-137` and `ai-review-loop.sh:44-54` enforce,
so a crafted huge count or timestamp cannot wrap a total.
**AC:** A ledger with a 20-digit finding count renders the correct total (no
modulo-2^64 wrap); a code-grep of `post-review-findings.sh` shows no `(( ))`
arithmetic over finding counts or timestamps; the wrap-safe case is asserted in
bats.

**NFR-5 — Authorized / in-scope + redaction boundary** (G5, G6): The poster
writes only to the origin/`gh`-resolved repo's own PR (refusing third-party /
fork-base targets with a note, FR-7), author-filters the update-find to the
posting identity (never editing a human comment, R7), and redacts the documented
secret-shape set before render — honoring the security-auditor no-exfiltration
boundary (`security-audit/SKILL.md:48-49`) applied to the PR target. The
redaction set is documented (not a new secrets-detection engine).
**AC:** A mismatched-base-repo target is refused with zero writes; the update
path never selects a non-posting-identity author; every documented secret shape
is masked before render with the cleartext absent from the body (bats);
SKILL.md/poster header state the in-scope-only + no-exfiltration framing.

**NFR-6 — Default-off, opt-in gating** (G3): The capability is **default-off**.
The poster's **first action** (and each skill's Publish step) reads
`capabilities.publish_pr_comments` (default false via
`common.sh` `profile_get`/`yaml_get`, `:110-140, 284-293`); flag-off/absent →
skip-with-note + `exit 0`, **before** any ledger parse or `gh` call. The schema
default is false (FR-8). No code path posts when the flag is false/absent.
**AC:** With the flag false/absent the poster makes **zero** `gh` calls and
exits 0 with a skip-note (bats); with the flag true it proceeds; the schema
documents the default as false; the gating read precedes any `gh` invocation.

**NFR-7 — SKILL.md line bound + clean integration** (G9): Each edited SKILL.md
stays under ~500 lines, with the Publish step a short slot pointing at the poster
+ the gate flag (enumerations live in the script, not inline). The new
capability + nullable make key are documented in `docs/profile-schema.md`,
emitted/accepted by `generate-profile.sh`/`validate-profile.sh`, and added to the
`# profile-example`. CI stays green on `manifest-validate`, `markdown-lint`,
`shellcheck -x`, `bats`, `frontmatter-check`, `profile-keys-check` (FR-17), and
`generalization-audit` (NFR-2).
**AC:** `wc -l` of each edited SKILL.md is ≤ ~500 (authoring budget verified in
review — no `wc -l` CI gate exists); `markdownlint` + `frontmatter-check` pass on
the three skills and the command; `profile-keys-check` passes with both new keys
documented; all seven CI jobs above are green on the feature PR.

**NFR-8 — Installability / load integrity** (G9): No new command, agent, or
skill is added — the feature is a new script + a Publish step inside three
existing skills + orchestrator wiring + two profile keys. Component counts stay
**8 commands / 7 agents / 22 skills** (+ 2 meta-guides); `tests/
component-counts.bats` is unchanged and continues to pass.
**AC:** `tests/component-counts.bats` asserts 8/7/22 unchanged and passes; no
new `commands/`, `agents/`, or `skills/` directory is introduced; the command
surface count stays 8 (no `/sdlc-publish`).

## 4. Acceptance Criteria and Release Gate

Acceptance criteria are embedded per requirement above; each **AC:** block is
the binding, testable criterion for its FR/NFR. The release gate for this feature
requires all of:

1. All FR ACs demonstrated (FR-1..11), with a bats evidence run documenting
   render → idempotent update-vs-create → dedup → severity order → redaction →
   gating on/off → every degrade path → base-repo refusal → conclusion math
   (FR-2/FR-4/FR-5/FR-7/FR-9/G1/G2).
2. CI-automated NFR ACs green: NFR-1 (generalization audit over the new files),
   NFR-7 (markdownlint, frontmatter-check, profile-keys-check, shellcheck -x,
   bats), NFR-8 (component-counts 8/7/22 unchanged) — all in the existing plugin
   CI.
3. Run-documented NFR/FR ACs evidenced: NFR-2 (one create then update per lens
   via `STUB_GH_LOG`), NFR-3 (every degrade row exits 0 with a note), NFR-4
   (wrap-safe conclusion math), NFR-5 (base-repo refusal + author-filter +
   redaction), NFR-6 (flag-off → zero `gh` calls), FR-11 (all three test tiers
   present and green).
4. Traceability matrix (§5) verified complete in the implementation-readiness
   check — no orphan requirement, no uncovered goal.

## 5. Traceability Matrix

| Brief goal | Requirements |
|---|---|
| G1 Idempotent, spam-free publishing | FR-1, FR-2, FR-6, NFR-2 |
| G2 Faithful, deduped, ordered render + conclusion | FR-3, FR-4, FR-5, FR-10, FR-11 |
| G3 Default-off, opt-in gating | FR-6, FR-8, NFR-6 |
| G4 Degrade-safe (NFR-3) | FR-1, FR-9, NFR-3 |
| G5 Authorization boundary | FR-7, NFR-5 |
| G6 Secret redaction | FR-7, NFR-5 |
| G7 Wrap-safe conclusion math | FR-5, NFR-4 |
| G8 Generalization | FR-1, NFR-1 |
| G9 Clean plugin integration | FR-6, FR-8, FR-10, NFR-7, NFR-8 |
| G10 Full three-tier test coverage | FR-11 |

Reverse check: every FR/NFR appears in at least one goal row (FR-1..11,
NFR-1..8 all mapped).

## 6. Out of Scope (v1)

- **No new command surface.** Publishing is a Publish step inside the three
  existing skills + the `/sdlc-review` / `/sdlc-finish-pr` orchestration — no
  `/sdlc-publish` (command count stays 8, NFR-8).
- **No new agent or skill.** Counts stay 7 agents / 22 skills (NFR-8).
- **No third-party / fork-base posting.** The poster writes only to the
  origin/`gh`-resolved repo's own PR; a mismatched base repo is refused-with-note
  (FR-7) — it never accepts an arbitrary owner/repo.
- **No per-finding comments / inline review threads.** One consolidated comment
  per lens (and one conclusion), bounding `gh` calls to O(lenses) (NFR-2,
  research §4 R4). Inline `file:line` review threads are not in v1.
- **No delete-and-recreate idempotency.** Marker + author-filtered find-and-edit
  is primary (FR-2); `minimizeComment` is the duplicate-marker corruption-
  recovery branch only; `gh pr comment --edit-last` is rejected (lens-unsafe,
  research §3, §6.2).
- **No `quality.*` changes.** Quality thresholds are raise-only and unrelated;
  the poster touches none (`profile-schema.md:82-105`).
- **No die-on-`gh`-absent for the poster.** Unlike the read-path
  `get-pr-comments.sh` (`:40`), the poster is fire-and-forget side output and
  DEGRADES (FR-9, NFR-3) — the contrast is documented in the script header.
- **No new secret-shape policy beyond the documented redaction set.** The poster
  masks a documented set of known secret shapes; a new secrets-detection engine
  is out of scope (belt-and-suspenders over the ledger's already-redacted text,
  research §4 R2).
- **No `gh`-write retry/backoff machinery.** A `gh` write failure warns and the
  loop proceeds (mirrors `fr-nfr-gate.sh:96-105`); no retry queue (FR-9).

## 7. Assumptions (carried from brief §7, binding for architecture)

- A1: Publishing is a Publish step inside the three skills + the orchestrator,
  not a new command — scope is "shared script + Publish steps + schema keys"; the
  architecture pins the exact slot in each skill and which orchestrator posts the
  conclusion (FR-6, FR-10).
- A2: The canonical ledger schema is `{lens, pr, findings[], iterations,
  started_at, ended_at}` with per-finding `{id, severity, cwe?, owasp?, location,
  endpoint?, summary, status, auto_fixed, regression_test?}` (FR-3); the
  lens→ledger emission mechanism per skill (known path vs stdin vs
  orchestrator-assembled) is an architecture decision.
- A3: Idempotency = hidden `<!-- sdlc-review:<lens> -->` marker + author-filtered
  find-and-edit (primary), `minimizeComment` for duplicate-marker corruption
  recovery (secondary); `--edit-last` rejected (FR-2, research §3, §6.2).
- A4: New key names are `capabilities.publish_pr_comments` (bool, default false)
  and nullable `make.post_review_findings` — final names are a minimal-surface
  schema decision the architecture confirms (FR-8).
- A5: The orchestrator captures duration (start at loop entry, end at loop close)
  and reuses its existing `iteration <n>/5` counter for the conclusion
  (`sdlc-review.md:170-187`); the exact capture mechanism is an architecture
  detail (FR-10).
- A6: The redaction set (AWS keys, JWTs, `password=`/`secret=`/`token=`,
  `://user:pass@`, high-entropy tokens) is a defensive second layer over an
  already-redacted ledger; the precise regex/entropy threshold is an architecture
  decision (FR-7, research §4 R2).
- A7: List/find uses `gh api .../issues/{pr}/comments --paginate` (REST) or the
  GraphQL `issueComments` query (matching the existing GraphQL style); update
  uses PATCH `issues/comments/{id}` or `updateIssueComment`; create uses
  `gh pr comment --body`; the exact primitive mix and posting-identity source
  (`gh api user` vs configured bot login) are architecture decisions (FR-2,
  FR-7, research §3).
- Binding constraints restated: runtime profile reads; profile-resolved
  paths/PR/repo (NFR-1); degrade over hard-fail with `exit 0` (NFR-3);
  idempotent O(lenses) output (NFR-2); wrap-safe digit-string arithmetic
  (NFR-4); authorized in-scope-only + no-exfiltration + redaction (NFR-5);
  default-off opt-in gate (NFR-6); SKILL.md ≤ ~500 lines + green CI (NFR-7);
  unchanged component counts (NFR-8).

## 8. Open Questions for Architecture

1. **Conclusion ownership (OQ-1):** `/sdlc-review` at its loop close (leaning,
   per FR-10 and the brief) vs `/sdlc-finish-pr` vs both (one per loop). Architecture
   pins which orchestrator owns the timing and the single post, and how the
   `/sdlc-finish-pr` hand-off avoids a double-post.
2. **Ledger emission contract per lens (OQ-2):** each skill writes the ledger
   JSON to a known path, pipes it on stdin, or the orchestrator assembles it from
   the lens report. Schema is fixed (A2); the mechanism is architecture.
3. **Posting identity for the author filter (OQ-3):** token user via
   `gh api user`, or a configured bot login — affects the author-filtered find
   (FR-7, R7).
4. **List/update primitive mix (OQ-4):** REST `--paginate` + PATCH vs GraphQL
   `issueComments` + `updateIssueComment` + `minimizeComment` (matching the
   existing GraphQL style, `get-pr-comments.sh:77-99`); both backends keep
   jq+python parse parity.
5. **Redaction pattern set (OQ-5):** the exact secret-shape regexes and the
   high-entropy heuristic threshold (FR-7, research §4 R2).
6. **`make.post_review_findings` default (OQ-6):** ship `null` (plugin
   substitutes the script) consistent with `make.pr_comments` /
   `make.fr_nfr_gate`; confirm in the `# profile-example`.
7. **Conclusion duration source (OQ-7):** orchestrator-captured wall clock
   (FR-10) vs the ledgers' `started_at`/`ended_at` (FR-3/FR-5) when the
   orchestrator timing is unavailable (e.g. standalone poster invocation).
</content>
</invoke>
