---
stepsCompleted: [step-01-init, step-02-context, step-03-cli-contract, step-04-idempotency, step-05-gating-boundary-redaction, step-06-degrade, step-07-conclusion, step-08-skill-edits, step-09-orchestrator, step-10-profile-schema, step-11-test-plan, step-12-traceability, step-13-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-publish-review-comments/prd.md
  - specs/autonomous/2026-06-14-publish-review-comments/research.md
  - specs/autonomous/2026-06-14-publish-review-comments/product-brief.md
  - plugins/php-backend-sdlc/scripts/get-pr-comments.sh
  - plugins/php-backend-sdlc/scripts/fr-nfr-gate.sh
  - plugins/php-backend-sdlc/scripts/ai-review-loop.sh
  - plugins/php-backend-sdlc/scripts/inject-governance.sh
  - plugins/php-backend-sdlc/scripts/lib/common.sh
  - plugins/php-backend-sdlc/scripts/validate-profile.sh
  - plugins/php-backend-sdlc/scripts/generate-profile.sh
  - plugins/php-backend-sdlc/skills/security-audit/SKILL.md
  - plugins/php-backend-sdlc/skills/code-review/SKILL.md
  - plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md
  - plugins/php-backend-sdlc/commands/sdlc-review.md
  - plugins/php-backend-sdlc/docs/profile-schema.md
  - plugins/php-backend-sdlc/tests/get-pr-comments.bats
  - plugins/php-backend-sdlc/tests/fixtures/bin/gh
  - tools/plugin-quality/judge/rubrics.py
  - .github/workflows/ci.yml
workflowType: 'architecture'
date: 2026-06-14
author: Winston (BMAD Architect agent, autonomous run)
---

# Architecture — Publish Review Findings as PR Comments (`php-backend-sdlc`)

This document is the concrete, buildable design for the PRD
(`prd.md`, FR-1..11 / NFR-1..8). It pins: the `post-review-findings.sh`
CLI surface, the canonical ledger JSON, the idempotent marker + create-vs-update
algorithm with exact `gh` commands, the gating + authorization + redaction
logic, the degrade matrix, the conclusion aggregation and how
duration/auto-fix/iteration counts are sourced, the exact edits to each of the
three `SKILL.md` files and the `/sdlc-review` orchestrator, the two profile-key
edits across schema + `generate-profile.sh` + `validate-profile.sh`, and the
test plan per tier. Every design decision traces to a PRD requirement and the
research findings (`research.md` §2–§6). It resolves the eight Open Questions in
PRD §8.

---

## 0. Open-question resolutions (PRD §8 → decisions, binding)

| OQ | Decision | Rationale |
|---|---|---|
| OQ-1 conclusion ownership | `/sdlc-review` owns the single `--conclusion` post at its loop close. `/sdlc-finish-pr` never posts a conclusion (it may post per-lens via the code-review Publish step, but not the aggregate). | FR-10; one post per loop; the review orchestrator is where the `iteration <n>/5` counter and loop timing already live (`sdlc-review.md:170-187`). |
| OQ-2 ledger emission | Each skill **writes its lens ledger to a known per-lens path** under a profile-resolved scratch dir (`${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/<lens>.json`), then invokes the poster with `--file`. The orchestrator reads the same three paths for `--conclusion`. Stdin is also accepted (poster reads `-` / no `--file`) for standalone use. | §3.1; a known path lets the orchestrator aggregate without re-deriving each lens output; stdin keeps the poster composable. |
| OQ-3 posting identity | Token user via `gh api user --jq .login`, cached once per run into `POSTING_LOGIN`; a `--bot-login <login>` override exists for a configured bot identity. The author filter matches `POSTING_LOGIN` case-insensitively. | FR-7, R7; `gh api user` is the zero-config default and works for both PAT and `GITHUB_TOKEN`. |
| OQ-4 list/update primitive mix | **REST** for all three operations: list `gh api --paginate repos/{o}/{r}/issues/{pr}/comments`, update `gh api -X PATCH repos/{o}/{r}/issues/comments/{id} -f body=@-`, create `gh api -X POST repos/{o}/{r}/issues/{pr}/comments -f body=@-`. **GraphQL** `minimizeComment` is the duplicate-marker corruption-recovery branch only. | §3.1; REST is simpler to stub and parse, gives a stable comment `id` for PATCH, and keeps body payloads off argv (`-f body=@-` reads the body from stdin, avoiding ARG_MAX + shell-quoting on multi-KB Markdown). |
| OQ-5 redaction set | Six documented shapes (§5.3 table): AWS access-key id, JWT, `password=`/`secret=`/`token=`/`apikey=` assignments, `scheme://user:pass@host` URL creds, GitHub/`gh[ps]_` tokens, and a bounded high-entropy hex/base64 run (≥32 chars). Implemented as a fixed regex list in the script (jq `gsub` + python `re.sub`), not a detection engine. | FR-7, R2; documented + bounded per PRD §6 "no new secret-shape policy". |
| OQ-6 `make.post_review_findings` default | Ship `null`; plugin substitutes `scripts/post-review-findings.sh`. Added to schema table + `# profile-example` + `generate-profile.sh` emission + `validate-profile.sh` `MAKE_KEYS`. | FR-8, §2.6; mirrors `make.pr_comments`/`make.fr_nfr_gate`/`make.security`. |
| OQ-7 conclusion duration source | Orchestrator-captured wall clock is primary (passed as `--started-at`/`--ended-at` ISO-8601, or `--duration-seconds`); when absent (standalone), fall back to min(`started_at`) … max(`ended_at`) across the input ledgers; when neither is available, render `duration: n/a`. | FR-5, FR-10, A5/A7; the orchestrator has the true wall clock, the ledgers are the standalone fallback. |

---

## 1. Component overview

```text
                 ┌────────────────────────── /sdlc-review (orchestrator) ───────────────────────────┐
                 │  loop start: capture started_at (ISO-8601 UTC)                                    │
                 │  iterations 1..5 (existing gate loop)                                              │
                 │  ┌── security-audit SKILL ──┐ ┌── bmad-fr-nfr SKILL ──┐ ┌── code-review SKILL ──┐  │
                 │  │ §5.4 aggregate           │ │ where gate posts      │ │ after evidence ledger │  │
                 │  │ emit security.json       │ │ emit fr-nfr.json      │ │ emit code-review.json │  │
                 │  │ Publish step (gated) ────┼─┼── Publish step (gated)┼─┼── Publish step (gated)┼──┼─┐
                 │  └──────────────────────────┘ └───────────────────────┘ └───────────────────────┘  │ │
                 │  loop close: capture ended_at; Publish CONCLUSION (gated, once) ───────────────────┼─┤
                 └───────────────────────────────────────────────────────────────────────────────────┘ │
                                                                                                         ▼
                                              scripts/post-review-findings.sh
                          ┌──────────────────────────────────────────────────────────────────┐
   ledger JSON (file/stdin)│ 1 gate read (capabilities.publish_pr_comments) → skip-note if off │
            ───────────────▶ 2 resolve PR + OWNER/NAME (origin → gh)                           │
                          │ 3 authorize: PR base repo == OWNER/NAME, else refuse-note          │
                          │ 4 parse+validate ledger (jq | python3); empty → skip-note          │
                          │ 5 redact secret shapes                                             │
                          │ 6 dedup (cwe,location,endpoint) + severity sort                    │
                          │ 7 render Markdown body with hidden marker <!-- sdlc-review:LENS --> │
                          │ 8 list comments → marker+author match → PATCH else POST            │
                          │    (--conclusion: aggregate the 3 ledgers into one comment)        │
                          └──────────────────────────────────────────────────────────────────┘
                                              every failure → log_warn/log_info + exit 0 (NFR-3)
```

No new command / agent / skill is added (NFR-8). The deliverable is:

1. one new script `scripts/post-review-findings.sh`;
2. a short Publish step inside each of the three review `SKILL.md` files;
3. a conclusion-post slot in `commands/sdlc-review.md`;
4. two profile keys (`capabilities.publish_pr_comments`, `make.post_review_findings`)
   wired through `docs/profile-schema.md` + `generate-profile.sh` +
   `validate-profile.sh`;
5. one new bats suite + python prompt-quality re-judge + an LLM-judge tier.

Component counts stay **8 commands / 7 agents / 22 skills** (+ 2 meta-guides),
so `tests/component-counts.bats` is unchanged (NFR-8).

---

## 2. `post-review-findings.sh` — CLI contract (FR-1)

### 2.1 Header, strict mode, lib sourcing (sibling of `get-pr-comments.sh`)

```bash
#!/usr/bin/env bash
# post-review-findings.sh — publish review-lens findings as ONE consolidated,
# idempotent PR comment per lens (and an aggregate --conclusion comment).
#
# DEGRADE-FIRST CONTRACT (NFR-3 / FR-9): the DEFAULT failure mode of this
# script is skip-with-note + `exit 0`. It is the DELIBERATE INVERSE of the
# sibling get-pr-comments.sh (:40), which DIES when gh is absent because it
# is a READ that the /sdlc-finish-pr loop's exit condition depends on. This
# poster is fire-and-forget SIDE OUTPUT: gh absent / no PR / flag off / empty
# ledger / malformed gh read / mismatched base repo / gh write failure all
# DEGRADE to a logged note and exit 0 — they NEVER fail the loop. Do not
# "fix" this script to die on a missing capability (research §6.6, R5).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
```

The `# shellcheck source=lib/common.sh` pragma lets the `shellcheck` CI job
(`ci.yml:95-110`, `shellcheck -x`) follow the sourced lib. The header block
documenting the die-vs-degrade inversion is itself an AC of FR-9/NFR-3.

### 2.2 Argument grammar

```text
post-review-findings.sh <lens> [options]
post-review-findings.sh --conclusion [options]

lens (positional OR --lens <lens>): security | fr-nfr | code-review
  exactly one lens is required for per-lens mode; --conclusion selects
  aggregate mode and is mutually exclusive with a positional lens.

options:
  --pr <n>            PR number; numeric guard ^[0-9]+$. Default: resolve via
                      gh pr view --json number --jq .number, then RE-VALIDATE
                      the resolved value (mirrors get-pr-comments.sh:37-55).
  --file <path>       ledger JSON file. Repeatable. For --conclusion, supply
                      one --file per lens (or a single file holding a JSON
                      array of ledgers). When omitted, read ONE ledger from
                      stdin ('-' is also accepted explicitly).
  --bot-login <login> override the posting identity (default: gh api user).
  --started-at <iso>  loop start (ISO-8601 UTC); --conclusion duration source.
  --ended-at <iso>    loop end   (ISO-8601 UTC); --conclusion duration source.
  --duration-seconds <n>  alternative explicit duration (digit string).
  --iterations <n>    orchestrator iteration count for --conclusion (digit
                      string); overrides per-ledger iterations when present.
  --dry-run           render the comment body to stdout; make ZERO gh calls.
  --json              emit the canonical render model as JSON to stdout
                      (no gh calls); for tests + machine inspection.
  -h | --help         usage text.
  *                   unknown argument → die with usage text
                      (get-pr-comments.sh:34 discipline).
```

Parsing mirrors `get-pr-comments.sh:29-39`: a `while [[ $# -gt 0 ]]; case`
loop, `--pr) PR="${2:?--pr needs a value}"; shift 2`, unknown → `die`. An
unknown lens value is a clean `die` with usage text (FR-1 AC). `--dry-run`
and `--json` both short-circuit before any `gh` invocation so the renderer is
testable without a network or stub.

**Mode/flag note:** `--dry-run` and `--json` STILL honor the capability gate
and ledger-validity checks (so a flag-off `--dry-run` prints the skip-note and
exits 0); they only suppress the `gh` list/create/update calls. This keeps the
gate the genuine first gate (NFR-6) while leaving rendering independently
testable.

### 2.3 Repo-slug + PR resolution (reused verbatim from the siblings)

`OWNER/NAME` resolves from the `origin` remote, `gh repo view` as fallback —
the exact block in `get-pr-comments.sh:57-68` and `fr-nfr-gate.sh:69-78`:

```bash
origin="$(git remote get-url origin 2>/dev/null || true)"
repo_slug=""
[[ -n "$origin" ]] && repo_slug="$(printf '%s\n' "$origin" \
  | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
[[ -z "$repo_slug" ]] && repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
# DEGRADE, not die: unresolvable repo → skip-note + exit 0 (contrast :63-66).
[[ -n "$repo_slug" ]] || { log_info "post-review-findings: cannot resolve repository (no origin remote, gh repo view failed) — skipping publish"; exit 0; }
OWNER="${repo_slug%%/*}"; NAME="${repo_slug##*/}"
```

The single behavioral change vs the siblings: every `die` on a missing
external becomes `log_info … — skipping publish; exit 0` (FR-9). PR resolution
when `--pr` is omitted uses `gh pr view --json number --jq .number` and, on an
empty/non-numeric result, **degrades** (skip-note, exit 0) instead of dying.

### 2.4 Dual jq/python3 backend

Every JSON transform (ledger parse + validate, redact, dedup/sort, render,
comment-list parse, conclusion aggregate) offers BOTH a `jq` and a
`python3`-stdlib backend behind `command -v jq`, exactly as
`get-pr-comments.sh` does for every transform (`:113-120, 152-333`). The two
backends MUST produce byte-identical bodies for the same input (FR-1/FR-4 AC:
"with `jq` removed from `PATH` the python3 backend produces byte-identical
canonical render output"). To guarantee this:

- both backends sort with the **same total order** (severity rank then a
  stable secondary key: `id`, then `location`);
- both emit the same column set, the same `n/a` placeholder for absent optional
  fields (never the literal `null`, FR-3 AC), the same header/footer text, and
  a single trailing newline;
- numeric rendering (conclusion counts) is produced by the wrap-safe shell
  helpers (§7), NOT inside jq/python, so the backends cannot diverge on big
  integers.

---

## 3. Canonical ledger JSON (FR-3)

### 3.1 Schema (one shape, all three lenses; jq- and python-parseable)

```json
{
  "lens": "security | fr-nfr | code-review",
  "pr": 123,
  "findings": [
    {
      "id": "A03-1",
      "severity": "Critical | High | Medium | Low",
      "cwe": "CWE-89",
      "owasp": "A03:2021",
      "location": "<architecture.source_root>/<path>:<line>",
      "endpoint": "POST /api/login",
      "summary": "one-line, already redacted upstream",
      "status": "open | fixed | dropped",
      "auto_fixed": true,
      "regression_test": "tests/.../SqlInjectionTest.php"
    }
  ],
  "iterations": 3,
  "started_at": "2026-06-14T10:00:00Z",
  "ended_at": "2026-06-14T10:12:04Z"
}
```

**Required per finding:** `id`, `severity`, `location`, `summary`, `status`.
**Optional per finding:** `cwe`, `owasp`, `endpoint`, `regression_test`
(FR/NFR and code-review findings often carry none). `auto_fixed` is a bool;
absent ⇒ `false`. A finding is "auto-fixed root-cause-with-regression-test"
(the conclusion metric, FR-5) iff `auto_fixed == true` AND `regression_test`
is a non-empty string (`security-audit/SKILL.md:194-204`).

**Top-level:** `lens` is required (string in the enum). `pr` is optional in the
file (the `--pr` flag / resolution wins; the ledger `pr` is advisory and, when
present and numeric, is the default when no `--pr` is given). `iterations`,
`started_at`, `ended_at` are optional (the conclusion sources them, §7).

`severity` is normalized case-insensitively to the canonical
`Critical|High|Medium|Low`; an unknown band sorts last (rank 99) and renders
verbatim — never dropped silently.

### 3.2 Per-lens projection (how each lens fills the schema)

| Lens | `id` | `severity` | `cwe`/`owasp`/`endpoint` | `status`/`auto_fixed`/`regression_test` | source |
|---|---|---|---|---|---|
| `security` | `<family-id>-<n>` | band from the finding record | from the finding record | `fixed`+`auto_fixed:true`+test when routed through §5.5 | `security-audit/SKILL.md:272-309` finding record + §5.4 dedup tuple |
| `fr-nfr` | `<FR/NFR id>-<n>` | mapped from gate severity (default `Medium` when the gate emits only a count) | usually absent | `open` for new findings; `fixed` after remediation; `auto_fixed` when a php-implementer fix + test landed | `fr-nfr-gate.sh:116-121` count + the reviewer's per-requirement matrix |
| `code-review` | `<comment-short-id>` | from the priority column (Highest→Critical/High, Medium, Low) | usually absent; `location` = `file:line` of the thread | `fixed` (commit), `dropped` (decline/stale), `auto_fixed` when an AI-loop fix + test landed | `code-review/SKILL.md:256-263` categorization + evidence ledger |

The skills are responsible for the projection (the Publish step describes it in
≤ a few lines, §8); the poster only consumes the canonical shape.

### 3.3 Ledger validation + degrade

Before rendering, the poster validates the ledger with the same
`raw_is_json` + shape-guard discipline `get-pr-comments.sh` applies to `gh`
output (`:113-130, 152-260`), both backends identical:

1. parses as JSON (else: per-lens → `die` with `[php-sdlc][ERROR]`; conclusion
   → per-ledger skip-note, FR-3 AC);
2. top-level is an object (not array/scalar) — else same handling;
3. `lens` present and a string — else same handling;
4. `findings` is an array (absent ⇒ `[]`).

A **per-lens** malformed ledger is a hard `die` (the caller passed a broken
file — surface it, never a traceback). An **empty** ledger (zero findings
after dedup) is NOT malformed: it is the FR-9 empty-ledger degrade
(skip-note + exit 0, no empty comment). For `--conclusion`, a malformed or
missing per-lens ledger is a per-ledger skip-with-note and the lens contributes
a **zero row** (FR-5: "A lens with no ledger contributes a zero row, not a
missing one"), so the aggregate still renders.

---

## 4. Idempotent marker + create-vs-update algorithm (FR-2)

### 4.1 Marker

Each comment carries a hidden HTML marker as its FIRST body line:

```text
<!-- sdlc-review:security -->
<!-- sdlc-review:fr-nfr -->
<!-- sdlc-review:code-review -->
<!-- sdlc-review:conclusion -->
```

This mirrors `inject-governance.sh`'s `<!-- php-backend-sdlc:begin/end -->`
marker-block replace-in-place model (research §2.5). HTML comments are
invisible in GitHub's rendered Markdown, so the marker is machine-findable
without user-visible noise.

### 4.2 The algorithm (exact `gh` commands)

```text
publish(lens, body):
  # 1. resolve posting identity once (cached for the run)
  POSTING_LOGIN = ${--bot-login} OR `gh api user --jq .login 2>/dev/null`
     if empty -> log_warn "cannot resolve posting identity"; POSTING_LOGIN=""
                 (the author filter then degrades to marker-only match, R7 note)

  # 2. list the PR's issue comments (paginated), guarded
  raw = gh api --paginate "repos/$OWNER/$NAME/issues/$PR/comments" \
          --jq '.[] | {id, login: .user.login, body}'   # one JSON obj per line
        2>/dev/null
     # On a non-zero gh exit OR a non-JSON / error-envelope body
     # (raw_is_json + shape guard, get-pr-comments.sh:113-130,152-260):
     #   log_warn "comment list unreadable — creating without dedup"; goto CREATE
     # (R11: degrade, fall back to create; never fail the loop)

  # 3. find the target comment: marker in body AND author == POSTING_LOGIN
  #    (case-insensitive login compare). Collect ALL matches.
  matches = [ c in raw : marker(lens) ∈ c.body
                         AND (POSTING_LOGIN == "" OR lower(c.login)==lower(POSTING_LOGIN)) ]

  # 4. create vs update vs corruption-recovery
  if matches is empty:                                   # CREATE
     gh api -X POST "repos/$OWNER/$NAME/issues/$PR/comments" -f body=@-  <<<"$body"
       || log_warn "create failed (HTTP/rate/abuse) — skipping"; (exit 0 still)
  elif matches has exactly one (oldest by id):           # UPDATE
     id = matches[0].id
     gh api -X PATCH "repos/$OWNER/$NAME/issues/comments/$id" -f body=@- <<<"$body"
       || log_warn "update failed — skipping"
  else:                                                   # CORRUPTION RECOVERY
     # duplicate marker'd, author-matched comments → edit the OLDEST (lowest id),
     # minimize the rest via GraphQL minimizeComment (research §3 approach 2).
     id = min(matches.id)
     gh api -X PATCH "repos/$OWNER/$NAME/issues/comments/$id" -f body=@- <<<"$body"
     for extra in matches[1:]:
        node_id = extra.node_id   # from the list (REST id is numeric; fetch node_id)
        gh api graphql -f query='mutation($id:ID!){minimizeComment(input:{
           subjectId:$id, classifier:OUTDATED}){clientMutationId}}' -f id="$node_id" \
           >/dev/null 2>&1 || log_warn "could not minimize duplicate comment $id"
```

Body is piped via `-f body=@-` (reads stdin) so multi-KB Markdown never hits
argv length limits or shell-quoting hazards (OQ-4). `gh pr comment --edit-last`
is **NEVER** used: it edits the last actor comment regardless of lens and would
clobber a sibling lens's comment (research §3, FR-2). `gh pr comment "$pr"
--body` (the create primitive `fr-nfr-gate.sh:103` uses) is acceptable for
CREATE but the REST `POST` is preferred for symmetry with the list/PATCH path
and to keep the `STUB_GH_LOG` assertions uniform (all three ops are `gh api`).

The list parse needs the comment `id` (REST numeric, for PATCH) and the
`node_id` (GraphQL global id, for `minimizeComment`); both are present in the
REST list payload (`.id`, `.node_id`), so one list call suffices.

### 4.3 Bounded call count (NFR-2)

Per per-lens run: **1 list** (+pagination pages) **+ 1 create-or-update**, plus
at most `k-1` minimize calls only in the rare duplicate-corruption branch.
`--conclusion` is **1 list + 1 create-or-update**. Total `gh` calls are
O(lenses), independent of finding count (NFR-2 AC: "`gh` call count per lens
does not grow with finding count"). No retry/backoff machinery — a write
failure warns and the run proceeds (FR-9, R4).

---

## 5. Gating + authorization + redaction (FR-6, FR-7, NFR-5, NFR-6)

### 5.1 Capability gate (NFR-6, FR-6) — the FIRST action

The poster's first action, before any ledger parse or `gh` call, reads the
gate flag from the profile via `common.sh`:

```bash
profile="$(profile_path)"                      # common.sh:279
publish="false"
if [[ -f "$profile" ]] && yaml_parses "$profile"; then
  publish="$(profile_get "$profile" capabilities.publish_pr_comments false)"  # common.sh:284
fi
if [[ "$publish" != "true" ]]; then
  log_info "post-review-findings: capabilities.publish_pr_comments is not true — skipping publish (opt-in, default off)"
  exit 0
fi
```

`profile_get` defaults to `false` when the key is absent (NFR-6: default-off).
A missing/unparseable profile ⇒ flag stays `false` ⇒ skip-note (never a die —
the poster degrades, FR-9). This gate runs before the `gh` resolution in §2.3,
so a flag-off run makes **zero** `gh` calls (NFR-6 AC).

The same gate is honored by `--dry-run`/`--json` (§2.2) so those modes also
print the skip-note when off.

### 5.2 Authorization / in-scope boundary (FR-7, NFR-5, R3)

After resolving `OWNER/NAME` (§2.3) and the PR, and BEFORE any write, the
poster verifies the PR's **base repository** equals the resolved `OWNER/NAME`:

```bash
base_slug="$(gh api "repos/$OWNER/$NAME/pulls/$PR" --jq .base.repo.full_name 2>/dev/null || true)"
if [[ -z "$base_slug" ]]; then
  log_warn "post-review-findings: cannot read PR #$PR base repo — refusing to publish"; exit 0
fi
if [[ "$(lower "$base_slug")" != "$(lower "$OWNER/$NAME")" ]]; then
  log_warn "post-review-findings: PR #$PR base repo '$base_slug' != resolved repo '$OWNER/$NAME' — refusing to publish to a third-party / fork-base target (in-scope only)"
  exit 0
fi
```

This is the security-auditor in-scope-target discipline
(`security-audit/SKILL.md:38-47`) applied to the **PR target** rather than the
probe target: write only to the resolved repo's own PR, never a third party /
fork base / an arbitrary owner/repo supplied via a mismatched remote. A
mismatch is a **refuse-with-note + exit 0** with **zero** write calls (FR-7 AC,
the `STUB_GH_LOG` shows the list+base read but no POST/PATCH).

### 5.3 Secret redaction (FR-7, NFR-5, R2, OQ-5)

Before render, every finding's text fields (`summary`, `location`, `endpoint`,
and any reproduction text carried in the ledger) pass through a documented
redaction pass — a defensive second layer over the ledger's already-redacted
text (the no-exfiltration boundary, `security-audit/SKILL.md:48-49`). The set
is a fixed list, NOT a detection engine:

| # | Shape | Pattern (intent) | Replacement |
|---|---|---|---|
| 1 | AWS access-key id | `\b(AKIA\|ASIA)[0-9A-Z]{16}\b` | `AKIA…REDACTED` |
| 2 | JWT | `\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b` | `eyJ…REDACTED` |
| 3 | assignment creds | `(?i)\b(password\|secret\|token\|apikey\|api_key)\s*[=:]\s*\S+` | `<key>=REDACTED` |
| 4 | URL creds | `([a-z][a-z0-9+.-]*://)[^/@\s:]+:[^/@\s]+@` | `\1REDACTED@` |
| 5 | GitHub tokens | `\bgh[pousr]_[A-Za-z0-9]{20,}\b` | `gh*_REDACTED` |
| 6 | high-entropy run | a hex/base64 token-like run `\b[A-Za-z0-9+/]{32,}={0,2}\b` (applied LAST, after 1–5) | `REDACTED` |

Both backends apply the identical ordered list (jq `gsub` with the same
ERE-compatible patterns; python `re.sub`), so a redacted body is byte-identical
across backends. The set is documented in the script header and in
`docs/` so reviewers know what is and is not masked (PRD §6: no new
secret-shape policy beyond this set). FR-7 AC: a ledger whose `summary`
contains an AWS key, a JWT, a `password=…`, and a `scheme://user:pass@host`
renders with each masked and the cleartext absent from the body.

`lower()` is a tiny `tr '[:upper:]' '[:lower:]'` helper used by the author and
base-repo compares; it adds no external dependency.

---

## 6. Degrade matrix (FR-9, NFR-3) — exact behaviors

Every row exits 0 and emits a `common.sh` `[php-sdlc][LEVEL]` note
(`common.sh:21-23`); none fails the loop. This table is the binding contract
(reproduced from PRD FR-9 with the concrete log level + branch point):

| # | Condition | Detection point | Behavior | Exit |
|---|---|---|---|---|
| D1 | `capabilities.publish_pr_comments` false/absent | §5.1 gate (first action) | `log_info` skip-note; zero `gh` calls | 0 |
| D2 | `gh` not on `PATH` | `command -v gh` after the gate | `log_info` skip-note (NOT a die — inverse of `get-pr-comments.sh:40`) | 0 |
| D3 | No PR resolvable (`gh pr view` empty/non-numeric, no `--pr`) | §2.3 PR resolution | `log_info` skip-note | 0 |
| D4 | Empty ledger (zero findings after dedup) | §3.3 after parse/dedup | `log_info` skip-note; no empty comment | 0 |
| D5 | Malformed `gh` comment-list read (non-JSON / error envelope) | §4.2 step 2 guard (R11) | `log_warn`; fall back to CREATE (or skip if create also unreadable) | 0 |
| D6 | Target PR base repo ≠ resolved `OWNER/NAME` | §5.2 authorization (R3) | `log_warn` refuse-note; zero write calls | 0 |
| D7 | `gh` write failure (POST/PATCH 4xx/5xx, rate/abuse limit) | §4.2 create/update `\|\|` branch (R4) | `log_warn`; never fail the loop | 0 |

A **malformed per-lens ledger FILE** (bad JSON / wrong top-level type / missing
`lens`) is the one NON-degrade case in per-lens mode: it is a hard `die`
(exit 1) because the caller passed a broken input, not a missing capability
(FR-3). In `--conclusion` mode the same malformed/absent ledger is a per-ledger
skip-note and a zero row (§3.3, FR-5). `command -v gh` is checked AFTER the gate
so a flag-off run never even looks for `gh` (D1 precedes D2).

No retry/backoff anywhere (PRD §6). The header (§2.1) documents the
die-vs-degrade contrast with `get-pr-comments.sh` (NFR-3 AC).

---

## 7. `--conclusion` aggregation (FR-5, NFR-4)

### 7.1 Inputs

`--conclusion` reads the three lens ledgers (one `--file` per lens, or a single
file holding a JSON array, or stdin holding an array). It renders one comment
under `<!-- sdlc-review:conclusion -->`, idempotent by the same §4 mechanism.

### 7.2 Rendered content

```text
<!-- sdlc-review:conclusion -->
## SDLC Review — Conclusion

### Findings by lens × severity
| lens | Critical | High | Medium | Low | total |
|---|---|---|---|---|---|
| security    | c | h | m | l | t |
| fr-nfr      | … |
| code-review | … |
| **all**     | Σ |

### Auto-fixed root-cause (with regression test), by lens
| lens | auto-fixed / total findings |
|---|---|
| security    | a / t |
| fr-nfr      | … |
| code-review | … |

### Iterations
| lens | iterations |   (per-lens ledger.iterations; overall = --iterations)
overall (loop): <n>/5

### Duration
<human-readable, e.g. 12m 04s>
```

A lens with no (or malformed) ledger contributes a **zero row**, never a
missing one (FR-5). `dropped`-status findings are excluded from the counts
(they are not findings the lens stands behind), consistent with the per-lens
render's "dropped / not reproduced" handling (§9 render rules).

### 7.3 Counting — wrap-safe digit-string arithmetic (NFR-4, R8)

Every count (per-lens severity counts, the per-lens and overall totals, the
auto-fixed counts) is accumulated with the `common.sh` `strip_zeros` and a new
shared `num_add` helper (digit-string addition), NEVER bash `(( ))` — the same
discipline `fr-nfr-gate.sh:125-137` and `ai-review-loop.sh:44-54` enforce.
The jq/python backends only EXTRACT and group raw values; the totals are summed
in the shell via the wrap-safe helpers so a crafted 20-digit finding count
cannot wrap a total modulo 2^64 (NFR-4 AC).

Add to `lib/common.sh` (next to `strip_zeros`/`num_gt`/`num_lt`,
`common.sh:37-58`) one helper, shared so the poster and any future caller use
one implementation:

```bash
# num_add A B — sum of two non-negative decimal integer strings, no (( )).
# Column addition with carry over the digit strings; result has no leading
# zeros. Wrap-safe: handles arbitrarily long inputs (NFR-4).
num_add() { … pure-string column add … ; }
```

(Implementing string addition in pure bash is the minimal correct primitive;
a `python3 -c 'print(int(a)+int(b))'` fallback is acceptable as the
arbitrary-precision path when the counts are small in practice, but the digit
counts here are bounded by finding counts so the pure-string version is
sufficient and dependency-free.) A code-grep of the script must show **no
`(( ))` arithmetic over finding counts or timestamps** (NFR-4 AC).

### 7.4 Duration source (OQ-7, FR-10)

Priority order:
1. `--duration-seconds <n>` (explicit, digit string) when present;
2. else `--started-at`/`--ended-at` ISO-8601 delta (orchestrator wall clock);
3. else min(`started_at`) … max(`ended_at`) across the input ledgers;
4. else render `duration: n/a`.

The ISO-8601 → epoch delta uses `date -u -d "$iso" +%s` (the same primitive
`code-review/SKILL.md:123` already uses) with a `python3` fallback
(`datetime.fromisoformat`) for portability; the resulting seconds delta is
formatted human-readably (`<h>h <m>m <s>s`, trimming leading zero units) — e.g.
`12m 04s`. A negative or unparseable delta renders `n/a` (never a crash).

### 7.5 Iterations source (FR-5)

Per-lens iterations come from each ledger's `iterations` field. The overall
loop iteration count is `--iterations <n>` passed by the orchestrator (its
existing `iteration <n>/5` counter, `sdlc-review.md:180-187`); when absent,
the overall row is the max of the per-lens `iterations`.

---

## 8. Exact SKILL.md edits (FR-6, NFR-7) — the three Publish steps

Each edit is a SHORT, gated slot (a few lines pointing at the poster + the gate
flag; the ledger projection is described in ≤ a few lines, enumerations stay in
the script). Each edit also adds the two new keys to the skill's
`## Profile keys consumed` header (FR-8 / `profile-keys-check`). Every skill
stays ≤ ~500 lines (NFR-7); the budget after edits is verified in review (no
`wc -l` CI gate exists). The slot template (adapted per lens):

```markdown
### Publish (gated, optional)

When `capabilities.publish_pr_comments` is `true`, emit this lens's findings as
the canonical ledger JSON (schema in `docs/profile-schema.md` / the poster
header) to `${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/<lens>.json`, then publish
ONE consolidated, idempotent PR comment via the target mapped by
`make.post_review_findings`; when that key is `null`, the plugin substitutes
`"${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh"`:

    "${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh" <lens> \
      --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/<lens>.json" --pr "$PR"

The poster is idempotent (hidden `<!-- sdlc-review:<lens> -->` marker — it
updates its prior comment, never spams), authorized (writes only to the
resolved repo's own PR), and DEGRADES (NFR-3): `capabilities.publish_pr_comments`
false/absent, `gh` absent, no PR, an empty ledger, a mismatched base repo, or a
`gh` write failure all skip-with-note and exit 0 — publishing NEVER fails this
loop. When the flag is false/absent, skip this step with a note.
```

### 8.1 `security-audit/SKILL.md` (PRD FR-6)

- **Slot:** a new `### 5.7 Publish (gated)` step after §5.4 aggregate / at loop
  close (after the §5.6 loop's `final:` line and before/within the Run report),
  emitting the `security` lens ledger from the promoted finding records
  (`security-audit/SKILL.md:182-204, 298-309`). The ledger's `auto_fixed:true`
  + `regression_test` entries are the §5.5 php-implementer-routed fixes.
- **`## Profile keys consumed`** (`:8-21`): add
  `capabilities.publish_pr_comments` and `make.post_review_findings`.
- **Constraints/ALWAYS:** one line noting the Publish step is gated + degrades
  (so the LLM-judge degrade-path dimension scores it).
- The slot reuses the existing §5.4 dedup tuple `(cwe, location, endpoint)`
  language so the skill and the poster agree on the dedup key (FR-4).

### 8.2 `bmad-fr-nfr-review-gate/SKILL.md` (PRD FR-6)

- **Slot:** a new `## Publish (gated)` section right where the gate already
  posts (the Workflow step 9 "leave the final result visible on the PR",
  `:244-245`; the gate's existing comment-on-FAIL behavior `:56-60`). Emit the
  `fr-nfr` lens ledger from the gate findings / per-requirement matrix
  (`fr-nfr-gate.sh:116-121`). Note that the gate's commit-status remains the
  durable success signal; the Publish comment is the additional consolidated
  view (does not replace the status).
- **`## Profile keys consumed`** (`:16-30`): add the two keys.
- Reuse the skill's existing `make.pr_comments`-null-substitution prose pattern
  (`:237`) for the `make.post_review_findings`-null substitution so the
  profile-key-branching judge dimension sees both branches.

### 8.3 `code-review/SKILL.md` (PRD FR-6)

- **Slot:** a new `### Step 5b: Publish findings (gated)` after the evidence
  ledger / Step 5 (after `Step 5: Verify All Addressed`, before `Step 6: Run
  Quality Checks`), emitting the `code-review` lens ledger from the Step 2
  priority/disposition categorization (`code-review/SKILL.md:256-263`) and the
  evidence-ledger dispositions (`fixed`=commit, `dropped`=decline/stale).
- **`## Profile keys consumed`** (`:8-16`): add the two keys to the existing
  `make.*` line + a `capabilities.*` line.
- The slot reuses the existing
  `"${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-comments.sh"` null-substitution prose
  (`:50, 244-249`) as the template for the poster substitution.

All three edits must keep `markdown-lint` (`ci.yml:79-93`) and
`frontmatter-check` (`:128-209`) green (frontmatter `name`/`description`
untouched), and `generalization-audit` (`:249-298`) green (no source literals —
the slots reference only profile keys, `$PR`, `${CLAUDE_PLUGIN_ROOT}`,
`${SDLC_LEDGER_DIR}`).

---

## 9. Per-lens render rules (FR-4)

The per-lens comment body:

```text
<!-- sdlc-review:<lens> -->
## SDLC Review — <Lens Name> findings (PR #<pr>)

| severity | id | cwe | owasp | location | endpoint | summary |
|---|---|---|---|---|---|---|
| Critical | … | … (n/a if absent) | … | … | … | … |
| …                                                        |

<optional> ### Dropped / not reproduced
| id | location | summary |
| …  (status == dropped, grouped here, never above an open finding) |

_summary: N findings (C critical, H high, M medium, L low); A auto-fixed root-cause with regression test._
```

Rules:
- **Dedup** by the tuple `(cwe, location, endpoint)` — the exact tuple the
  security lens already dedupes on (`security-audit/SKILL.md:185-187`); two
  findings hitting the same sink collapse to ONE row (FR-4 AC). The dedup key
  treats absent `cwe`/`endpoint` as the empty string for tupling.
- **Order** by severity band Critical → High → Medium → Low (rank 0..3;
  unknown = 99), stable secondary sort by `id` then `location` (so both
  backends agree byte-for-byte).
- **`dropped`** findings are excluded from the main table; if any exist they are
  grouped under a clearly labelled "Dropped / not reproduced" subsection,
  NEVER interleaved with open findings (FR-4 AC).
- Absent optional fields render as `n/a`, never the literal `null` (FR-3 AC).
- An **empty** ledger (zero non-dropped findings) does not render a comment —
  it is degrade D4 (skip-note), not an empty comment (FR-4/FR-9).
- The summary line's auto-fixed count uses the §3.1 metric (`auto_fixed` AND
  non-empty `regression_test`).

---

## 10. Orchestrator wiring — `/sdlc-review` (FR-10, NFR-2)

`commands/sdlc-review.md` gains:

### 10.1 Timing capture

- **Loop start:** at the stage-entry "First action" block (`sdlc-review.md:20-38`),
  capture `REVIEW_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"` (the same
  primitive `code-review/SKILL.md:96` uses).
- **Loop close:** capture `REVIEW_ENDED_AT` when the exit condition is met
  (`sdlc-review.md:170-178`).

### 10.2 Single conclusion post at loop close

A short slot in the "Loop & exit condition" section (`:170-187`), gated on
`capabilities.publish_pr_comments`, invokes the poster's `--conclusion` mode
**exactly once** at loop close (NOT per iteration, NFR-2), with the three lens
ledgers, the captured duration, and the existing `iteration <n>/5` counter:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh" --conclusion \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/security.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/fr-nfr.json" \
  --file "${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/code-review.json" \
  --pr "$PR" --started-at "$REVIEW_STARTED_AT" --ended-at "$REVIEW_ENDED_AT" \
  --iterations "$ITERATION"
```

The slot states the degrade-with-note contract (FR-9) and respects the
command's `allowed-tools` (`sdlc-review.md:4` — `Bash` is present, no new tool
needed). Ownership is `/sdlc-review` only: a `/sdlc-finish-pr` hand-off does
NOT post a conclusion (OQ-1, FR-10 AC — "no second conclusion post is described
for the `/sdlc-finish-pr` hand-off"). The per-lens Publish steps (§8) may run
inside either orchestrator, but the conclusion is posted once per review loop.

The edit must keep `markdown-lint` + `frontmatter-check` green and the J4
`exit-condition-consistency` judge dimension high (the conclusion slot must not
muddy the stated single exit condition — it is described as a post-exit side
effect, not part of the exit predicate).

---

## 11. Profile-schema + generator + validator edits (FR-8, NFR-7)

### 11.1 `docs/profile-schema.md`

- **`capabilities` table** (`:123-130`): add a row
  `| capabilities.publish_pr_comments | no | bool | false | Gates the Publish
  step + the poster's write path (default OFF / opt-in); when false/absent the
  Publish step and the poster skip-with-note (NFR-3). Mirrors
  capabilities.dynamic_security_testing / capabilities.structurizr. |`
- **`make` table** (`:66-80`): add a row
  `| make.post_review_findings | yes (nullable) | null | PR-comment publisher;
  plugin substitutes scripts/post-review-findings.sh when null. Mirrors
  make.ai_review_loop / make.pr_comments / make.fr_nfr_gate. |`
- **`# profile-example` block** (`:138-189`): add
  `post_review_findings: null` under `make:` and
  `publish_pr_comments: false` under `capabilities:`. (These concrete-looking
  lines are inside the `# profile-example` fence, exempt from the
  generalization audit, `ci.yml:271-280`.)

### 11.2 `scripts/generate-profile.sh`

- Add to the make-emission heredoc (`generate-profile.sh:340-344`, after
  `load_tests:`): `post_review_findings: null`. (No detection needed — there is
  no canonical make target to detect; it ships `null` like `ai_review_loop`.)
  Note `make.security` is already documented in the schema but is currently NOT
  emitted by the generator nor in `validate-profile.sh:146-147` `MAKE_KEYS` — do
  NOT widen that pre-existing gap here; add ONLY `post_review_findings` to keep
  the change minimal and the `make`-map-complete invariant satisfied for the new
  key. (A separate fix for `make.security` completeness is out of scope.)
- Add to the `capabilities:` emission block (`generate-profile.sh:362-365`):
  `publish_pr_comments: false`.

### 11.3 `scripts/validate-profile.sh`

- Add `post_review_findings` to the `MAKE_KEYS` array
  (`validate-profile.sh:146-147`) so a profile missing it is a validation error
  (the make map is required-and-complete, FR-8). No new check is needed for the
  bool capability (capabilities are optional, default-off — the validator does
  not require optional capability keys; `capabilities.dynamic_security_testing`
  is not validated either).

### 11.4 Why this satisfies `profile-keys-check`

The `profile-keys-check` CI job (`ci.yml:211-247`) greps each skill's
`## Profile keys consumed` keys against `docs/profile-schema.md`. Because
`capabilities.publish_pr_comments` and `make.post_review_findings` are added to
the schema's tables (backticked dotted paths), the three edited skills citing
them pass. ORDER OF OPERATIONS (FR-11): the schema rows land in the SAME change
as the skill edits, so the job never sees a cited-but-undeclared key.

---

## 12. Test plan per tier (FR-11)

### 12.1 bats — `tests/post-review-findings.bats`

Reuses the env-driven `gh` stub (`tests/fixtures/bin/gh`:
`STUB_GH_OUTPUT`/`STUB_GH_EXIT`/`STUB_GH_LOG`) and the subcommand-routing `gh`
wrapper technique for the multi-response list→edit path
(`get-pr-comments.bats:1-10, 121-137`). `setup()` mirrors
`get-pr-comments.bats:12-25`: a temp git repo with an `origin` remote,
`PATH="$STUBS:$PATH"`, and a fixture profile with
`capabilities.publish_pr_comments: true`. Fixtures: ledger JSONs under
`tests/fixtures/ledgers/` (full, minimal-required-only, empty, dedup-pair,
mixed-severity, dropped+open, secret-laden, 20-digit-count); a profile with
the flag on and one with it off under `tests/fixtures/profiles/`.

| Case | FR/NFR | Assertion |
|---|---|---|
| render full ledger (`--dry-run`) | FR-4 | body contains marker, severity-ordered table, summary line; zero gh calls |
| render minimal (required-only) | FR-3 | renders; absent cwe/owasp shown as `n/a`, never `null` |
| jq vs python3 byte-identical render | FR-1/FR-4 | `--json`/`--dry-run` output identical with jq removed from `PATH` (sandbox-bin technique, `get-pr-comments.bats:81-98`) |
| idempotent CREATE (first run) | FR-2/NFR-2 | `STUB_GH_LOG` shows exactly one `api -X POST …/comments`, zero PATCH |
| idempotent UPDATE (second run) | FR-2/NFR-2 | routing stub returns a list containing the marker+author comment → exactly one `api -X PATCH …/comments/<id>`, zero POST |
| duplicate-marker collapse | FR-2 | list with two marker'd author-matched comments → one PATCH on the oldest, ≥1 `minimizeComment`, never a third create |
| never `--edit-last` | FR-2 | `STUB_GH_LOG` contains no `pr comment --edit-last` |
| dedup by (cwe,location,endpoint) | FR-4 | dedup-pair ledger → one row |
| severity order | FR-4 | mixed ledger → Critical first, Low last; dropped never above open |
| redaction of each shape | FR-7/NFR-5 | secret-laden ledger → AWS key, JWT, `password=`, `://user:pass@` masked; cleartext absent from body |
| gating OFF | FR-6/NFR-6 | flag-off profile → skip-note, exit 0, zero gh calls |
| gating ON proceeds | FR-6 | flag-on → proceeds to render/post |
| D2 gh absent | FR-9/NFR-3 | `PATH` without gh → skip-note, exit 0 |
| D3 no PR | FR-9 | no `--pr`, `gh pr view` empty (routing stub) → skip-note, exit 0 |
| D4 empty ledger | FR-9 | empty ledger → skip-note, exit 0, zero write calls |
| D5 malformed list read | FR-9/R11 | `STUB_GH_OUTPUT` non-JSON on the list call → warn, falls back to CREATE, exit 0 |
| D6 base-repo mismatch | FR-7/R3 | base read returns a different slug → refuse-note, exit 0, zero write calls |
| D7 gh write failure | FR-9/R4 | `STUB_GH_EXIT` non-zero on the POST/PATCH → warn, exit 0 |
| malformed per-lens ledger | FR-3 | bad-JSON file → `die` exit 1, `[php-sdlc][ERROR]`, no traceback |
| conclusion math | FR-5 | three fixture ledgers → per-lens severity counts equal source; auto-fixed = `auto_fixed:true`+`regression_test` count |
| conclusion wrap-safe | FR-5/NFR-4 | 20-digit finding count → correct total, no modulo-2^64 wrap |
| conclusion idempotent | FR-5/NFR-2 | second `--conclusion` run → PATCH not POST |
| conclusion zero-row for missing lens | FR-5 | two ledgers + one missing → missing lens renders a zero row |
| conclusion duration | FR-5/OQ-7 | `--started-at`/`--ended-at` → human-readable delta; ledger fallback; n/a path |
| CLAUDE_PLUGIN_ROOT install-cache | NFR-8 | runs from a copied tree via `CLAUDE_PLUGIN_ROOT` (`get-pr-comments.bats:139-146`) |
| `shellcheck -x` clean | FR-1 | (CI job; not a bats case but a release gate) |

Runs in the `bats` CI job (`ci.yml:112-126`).

### 12.2 python prompt-quality (`tools/plugin-quality/`)

- **Judge** (`judge/run_judge.py`, `rubrics.py`): re-judge the three edited
  `SKILL.md` against the critical/non-critical dimensions — especially
  `degrade-path-soundness` (J3, critical, floor 4), `profile-key-branching`
  (J6, floor 4 — both new keys must BRANCH: flag-on publishes, flag-off
  skip-notes; `make.post_review_findings` null → script vs non-null → target),
  `exit-condition-consistency` (J4, the `/sdlc-review` edit), `root-cause-culture`
  (J9), `trigger-specificity`/`body-description-fidelity`. The Publish slots
  must keep these dimensions ≥ floor.
- **Lint** (`lint/check_*.py`: frontmatter, descriptions, generalization,
  references, escalation) over the three edited skills + the command edit — all
  pass deterministically.
- The two new profile keys pass `profile-keys-check` and `generalization-audit`
  (CI, §11.4 / §11.1) BEFORE the skills cite them (FR-11).

### 12.3 LLM-judge

A domain LLM-judge tier modeled on the `tools/security-audit-validation/judge/`
precedent (`run_seed_judge.py`) judges the edited skills' Publish step (and the
poster header) for the five contracts: **gating** (default-off, flag-first),
**idempotency** (marker + update-not-spam), **authorization** (in-scope-only,
base-repo verify), **redaction** (documented secret set), **degrade** (every
matrix row exits 0). The judge consumes the edited `SKILL.md` slots + the
script header comment block (§2.1, §5.3) as evidence.

---

## 13. Traceability (architecture → PRD)

| PRD requirement | Architecture section(s) |
|---|---|
| FR-1 poster sibling + CLI | §2 (all), §2.4 dual backend |
| FR-2 idempotent marker create-vs-update | §4 (all), §12.1 idempotency cases |
| FR-3 canonical ledger schema | §3 (all), §12.1 minimal/malformed cases |
| FR-4 per-lens dedup + severity render | §9, §3.1 dedup tuple, §12.1 dedup/order |
| FR-5 `--conclusion` counts/auto-fix/duration | §7 (all), §12.1 conclusion cases |
| FR-6 gated Publish step ×3 | §8 (all), §5.1 gate |
| FR-7 authorization + redaction | §5.2, §5.3, §12.1 base-repo/redaction |
| FR-8 new profile keys | §11 (all) |
| FR-9 degrade matrix | §6 (all), §2.1 header, §12.1 D1–D7 |
| FR-10 orchestrator conclusion once | §10 (all), OQ-1, OQ-7 |
| FR-11 three-tier tests | §12 (all) |
| NFR-1 generalization | §2/§8/§11 profile-resolved; §12.2 generalization-audit |
| NFR-2 idempotent low-noise | §4.3, §7, §10.2; §12.1 STUB_GH_LOG |
| NFR-3 degrade over hard-fail | §6, §2.1, §2.3 |
| NFR-4 wrap-safe arithmetic | §7.3 `num_add`; §12.1 20-digit case |
| NFR-5 in-scope + redaction | §5.2, §5.3 |
| NFR-6 default-off gating | §5.1, §11.3; §12.1 gating off |
| NFR-7 SKILL ≤500 + CI green | §8, §11.4, §10 (markdown-lint/frontmatter/profile-keys) |
| NFR-8 installability / counts | §1 (no new component); §12.1 install-cache |
| OQ-1..7 | §0 resolutions |

Reverse check: every FR (1–11) and NFR (1–8) and every OQ (1–7) maps to at
least one architecture section. No orphan requirement.

---

## 14. Risks carried into implementation (from research §4, re-pinned)

- **R1 spam:** §4 marker + UPDATE; assert via `STUB_GH_LOG` (§12.1).
- **R2 secret leakage:** §5.3 documented redaction set; bats redaction test.
- **R3 wrong-PR write:** §5.2 base-repo authorization; refuse-with-note.
- **R4 rate/abuse limits:** §4.3 O(lenses) calls; §6 D7 warn-not-die.
- **R5 degrade ≠ fail:** §6 matrix; §2.1 header documents the inversion.
- **R6 gating bypass:** §5.1 flag-first; §12.1 gating-off zero-gh-calls.
- **R7 wrong-comment edit:** §4.2 author filter (POSTING_LOGIN).
- **R8 wrap/overflow:** §7.3 digit-string `num_add`; no `(( ))`.
- **R9 source-literal leakage:** §2/§8/§11 profile/fixture-resolved only.
- **R10 SKILL bloat:** §8 short slots; enumerations in the script.
- **R11 malformed gh read:** §4.2 step-2 guard; §6 D5 fall-back-to-create.

This design is buildable as specified: one new script with the exact CLI,
marker algorithm, gating/authorization/redaction, degrade matrix, and
conclusion math above; three short SKILL.md Publish slots; one orchestrator
slot; two profile keys across schema/generator/validator; and the three test
tiers. Every external dependency degrades to a logged note and `exit 0`; every
path/PR/repo resolves from the profile, `gh`/`git`, or fixtures.
