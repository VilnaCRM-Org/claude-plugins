# Research Brief — Publish Review Findings as PR Comments

**Date:** 2026-06-14
**Author:** BMAD Analyst
**Feature:** Opt-in, gated capability for the `php-backend-sdlc` plugin that
PUBLISHES the findings of its three review lenses (security-audit, BMAD
FR/NFR review gate, code-review) as GitHub PR comments, plus a single
CONCLUSION comment at loop close.
**Status:** research input for the PRD (do not implement from this file).

---

## 1. Scope & intent (restated, non-binding)

A shared poster `scripts/post-review-findings.sh` consumes the canonical
finding-record ledger (JSON on stdin/file) plus a lens arg
(`security|fr-nfr|code-review`) and an optional `--pr`, renders ONE
consolidated, deduped, severity-ordered Markdown comment per lens, and is
IDEMPOTENT via a hidden HTML marker — it UPDATES the prior bot comment
instead of spamming. A `--conclusion` mode aggregates across lenses (counts
found / auto-fixed root-cause-with-regression-test / iterations / duration)
into one comment. It is GATED behind a default-off profile capability, posts
only to the repo's own PR (never a third party), redacts secrets, and
DEGRADES (gh absent / no PR / flag off / empty ledger → skip-with-note, exit
0). A Publish step wires into each of the three skills and the orchestrator;
the orchestrator posts the conclusion once at loop close with the timing it
captured.

---

## 2. Survey of existing patterns to mirror (cite file:line)

### 2.1 `gh` usage, flag parsing, degrade & repo-slug resolution — the POSTER's twin

`scripts/get-pr-comments.sh` is the canonical sibling. The poster must mirror:

- **Shebang + strict mode + lib sourcing**:
  `#!/usr/bin/env bash` / `set -euo pipefail` / `source "$SCRIPT_DIR/lib/common.sh"`
  (`get-pr-comments.sh:1-24`). All scripts in `scripts/` do this; shellcheck
  CI runs `shellcheck -x` to follow the sourced lib (`ci.yml:109-110`).
- **`--pr` flag + validation**: `--pr) PR="${2:?--pr needs a value}"`
  (`get-pr-comments.sh:31`), numeric guard `[[ "$PR" =~ ^[0-9]+$ ]]`
  (`get-pr-comments.sh:37-39`), and re-validation of a `gh`-resolved PR
  (`:53-55`). The poster takes the SAME `--pr` and defaults via
  `gh pr view --json number --jq .number` (`:42-45`).
- **Repo slug from origin, gh fallback**: `git remote get-url origin` →
  `sed -E 's#\.git$##; ...'` → fallback `gh repo view --json nameWithOwner`
  (`get-pr-comments.sh:57-68`; same block in `fr-nfr-gate.sh:69-78`). The
  poster needs `OWNER/NAME` for the GraphQL minimize/update path and for the
  **in-scope authorization check** (the PR must belong to this resolved repo).
- **`gh` absence is a clean die**: `command -v gh >/dev/null 2>&1 || die ...`
  (`get-pr-comments.sh:40`). For the poster this is a DEGRADE (skip-note,
  exit 0), NOT a die — see §2.4 and the NFR-3 contrast in §4.
- **JSON-validity + shape guards before consuming gh output**: `raw_is_json`
  (`get-pr-comments.sh:113-130`), `pr_data_check` (`:152-260`), BOM strip
  (`:107`). gh can exit 0 yet emit non-JSON (proxy HTML, prompts) or a
  GraphQL error envelope; the poster's update path reads back an existing
  comment id and must guard identically.
- **jq-with-python3-stdlib fallback**: every transform offers both backends
  (`get-pr-comments.sh:113-120, 152-249, 264-333`). The poster's
  ledger→Markdown render and dedup/severity-sort must do the same so it runs
  where only python3 exists (matches `lib/common.sh`'s ADR-2 convention).

### 2.2 Posting + commit-status patterns — the WIRING

`scripts/fr-nfr-gate.sh` is the existing "render findings → post to PR"
script:

- **`gh pr comment "$pr" --body "$body"`** with a graceful warn-not-die on
  failure (`fr-nfr-gate.sh:96-105`). This is the **create** primitive; the
  poster ADDS idempotent update (§3).
- **Comment-quiet on success**: the gate posts a comment "only when n > 0"
  and relies on the commit status as the durable signal (`fr-nfr-gate.sh:18-21,
  133-144`). The new poster is the opposite intent — it publishes a
  consolidated comment per lens — but the "limit PR noise" principle is the
  same, satisfied here by idempotent UPDATE (one comment, edited) rather than
  by silence.
- **Heredoc/`$result`-into-`--body` markdown body** (`fr-nfr-gate.sh:140-144`)
  shows the existing Markdown comment shape the poster generalizes.
- **`die`/`log_warn`/`log_info` from the lib** (`common.sh:21-28`) — uniform
  `[php-sdlc][LEVEL]` prefix; the skip-with-note must use `log_info`/`log_warn`.

### 2.3 The loop & gate patterns — WHERE timing/iterations/counts come from

- `scripts/ai-review-loop.sh`: bounded loop `MAX_ITERATIONS` default 5
  (`:30, 98`), wrap-safe ceiling via `num_gt` (`:51-54`), per-iteration
  verdict parse `AI_REVIEW_VERDICT: PASS|FAIL` from the mandatory last line
  (`:109-122`). The **iteration count** the conclusion reports is exactly this
  loop's counter.
- `scripts/fr-nfr-gate.sh`: mandatory last line `FR_NFR_NEW_FINDINGS: <n>`
  (`:85, 116-121`), wrap-safe zero-test of the count as a digit string
  (`:125-137`). The conclusion's per-lens counts must use the same wrap-safe
  digit-string arithmetic (`common.sh:39-58` `strip_zeros`/`num_gt`), NEVER
  bash `(( ))`, or a crafted huge count corrupts the totals.
- `security-audit/SKILL.md`: the loop in §5.x (`:212-231`) — triage → fan-out
  → find → verify → fix → regress → re-verify → loop, `MAX_ITERATIONS=5`, exit
  on first zero-new-findings iteration. The "auto-fixed root-cause via
  php-implementer with a regression test" count the conclusion reports is the
  count of findings routed through §5.5 (`:194-204`) — each is root-cause +
  failing-then-passing test.

### 2.4 The finding-record schema — the LEDGER the poster consumes

`security-audit/SKILL.md` **Format** section (`:272-309`) is the canonical
finding-record. The poster's input JSON should be a machine-readable
projection of this:

```text
FINDING <family-id>-<n>
  cwe / owasp / severity (Critical|High|Medium|Low + rationale)
  location: <architecture.source_root>/<path>:<line>   # profile-resolved, NO literals
  endpoint / reproduction / expected / observed / remediation / regression_test
```

Plus the **SECURITY-AUDIT RUN REPORT** shape (`:298-309`): per-family verdict
table, per-iteration finding counts, iterations used `k/5`, promoted findings
by severity band, dropped candidates, `make.ci` PASS/FAIL,
forbidden-suppression scan CLEAN/VIOLATION, status. The conclusion comment is
essentially this run report rendered to Markdown and AGGREGATED across the
three lenses.

- `code-review/SKILL.md` finding shape: per-comment evidence ledger
  (`COMMENT_META|url|updatedAt|sha`, `COMMENT|url|commit|sha`) (`:104-149`),
  severity/priority categorization table (`:256-263`). The code-review lens'
  "findings" are reviewer comments addressed — its contribution to the
  conclusion is counts by priority/disposition (fixed-by-commit vs
  reply/decline).
- `bmad-fr-nfr-review-gate/SKILL.md` finding shape: the 5/5 scorecard +
  `FR_NFR_NEW_FINDINGS: <n>` mechanical contract (`:180-196, 248-284`), and
  the "posts a PR comment carrying the findings only when n>0" publishing
  behavior (`:56-60`) — the Publish step slots right where the gate already
  posts (`fr-nfr-gate.sh:96-144`).

**Schema decision for the PRD:** define ONE canonical poster-input JSON
(a "finding ledger") — e.g. `{lens, pr, findings:[{id, severity, cwe?, owasp?,
location, summary, status: open|fixed|dropped, auto_fixed: bool,
regression_test?}], iterations, started_at, ended_at}` — derived from the
three lens shapes above. Each lens emits this; the poster renders it; the
orchestrator concatenates the three ledgers for `--conclusion`. Keep it
jq-and-python parseable like §2.1.

### 2.5 The hidden-marker idempotency primitive — STRONGEST in-repo prior art

`scripts/inject-governance.sh` ALREADY implements "find a marker-delimited
block and replace it in place, never duplicating" (`:8-14, 35-36`):

```text
BEGIN_MARKER='<!-- php-backend-sdlc:begin -->'
END_MARKER='<!-- php-backend-sdlc:end -->'
# "...replaced in place on every run; content outside the markers is never touched"
# corrupted/unbalanced/orphan marker states are handled deterministically (:11-14)
```

This is the exact mental model for the PR-comment idempotency: a hidden marker
`<!-- sdlc-review:<lens> -->` embedded in the comment body lets the poster
FIND its own prior comment and UPDATE it. The PRD should reuse this script's
**corruption-tolerance discipline** (duplicate markers → collapse to one;
orphan → recreate) for the multi-comment case (duplicate bot comments with the
same marker → update the first, optionally minimize the rest).

### 2.6 Profile conventions for the new capability + make key

`docs/profile-schema.md`:

- **`capabilities.*` are bool, default-off, skip-with-note when false** — e.g.
  `capabilities.structurizr` (`:127`), `capabilities.dynamic_security_testing`
  (`:130`). The new `capabilities.publish_pr_comments` follows this exactly:
  `no | bool | false`, default OFF / opt-in.
- **`make.*` null-substitution precedent**: `make.ai_review_loop`,
  `make.pr_comments`, `make.fr_nfr_gate`, `make.security` are
  "yes (nullable), plugin substitutes `scripts/<x>.sh` when null" (`:76-80`).
  A new `make.post_review_findings: null` (plugin substitutes
  `scripts/post-review-findings.sh`) mirrors this exactly. **The make map is
  required-and-complete** (`:60-64`) — adding a key means `generate-profile.sh`
  and `validate-profile.sh` must emit/accept it (incomplete map = validation
  error). The annotated example (`:157-170`) must gain the line too.
- **Quality is raise-only** (`:82-105`) — unrelated to this feature; the
  poster must NOT touch `quality.*`.
- **Skill authors MUST list every consumed key under `## Profile keys
  consumed`** and reference keys as inline-code dotted paths (`:204-210`) — the
  `profile-keys-check` CI job greps this (`ci.yml:211-247`). Any key a skill
  cites that is absent from `profile-schema.md` fails CI.

### 2.7 CI gates the new code must pass (`.github/workflows/ci.yml`)

| Job | What it checks | Implication for this feature |
|---|---|---|
| `manifest-validate` (`:18-77`) | plugin.json/marketplace.json fields, semver | bump plugin version on release; no manifest change needed for a script |
| `markdown-lint` (`:79-93`) | markdownlint-cli2 over `plugins/**/*.md` | every edited SKILL.md + any new doc must lint clean |
| `shellcheck` (`:95-110`) | `shellcheck -x` over `scripts/**/*.sh` | `post-review-findings.sh` must be shellcheck-clean, source lib via the `# shellcheck source=` pragma |
| `bats` (`:112-126`) | `npx bats` over `tests/**/*.bats` | NEW `post-review-findings.bats` (stub gh) lands here |
| `frontmatter-check` (`:128-209`) | skills `name`+`description`; meta-guides MUST NOT have frontmatter | edited SKILL.md frontmatter stays valid |
| `profile-keys-check` (`:211-247`, FR-17) | every `## Profile keys consumed` key exists in `profile-schema.md` | `capabilities.publish_pr_comments` + `make.post_review_findings` MUST be documented before any skill cites them |
| `generalization-audit` (`:249-298`, NFR-2/NFR-7) | denylist grep `user[-_ ]service\|...\|vilnacrm`, no `_bmad`/`.ralph` in plugin tree | NO source-project literals anywhere; concrete values only inside `# profile-example` fences |

The denylist (`ci.yml:286`) and the `# profile-example` fence escape
(`:271-280`) mean the poster + tests + skill edits must resolve every
path/PR/repo from the profile or fixtures — never hardcode `user-service`,
`VilnaCRM`, a real PR number, etc.

### 2.8 Test-tier shapes to mirror

- **bats with a stub `gh`**: `tests/fixtures/bin/gh` is a env-driven stub
  (`STUB_GH_OUTPUT`, `STUB_GH_EXIT`, `STUB_GH_LOG` argv-log, `--version`/`auth
  status` special-cases). `tests/get-pr-comments.bats:12-24` sets up a temp git
  repo with an `origin` remote and `PATH="$STUBS:$PATH"`. The poster's bats
  suite reuses this stub; **`STUB_GH_LOG` is the key to asserting idempotency**
  (assert exactly one `gh ... comment` create on first run, an UPDATE call on
  the second). The stub currently returns ONE canned payload for all calls; the
  update path needs TWO responses (list-comments → then edit), so the suite
  generates a subcommand-routing wrapper (the `get-pr-comments.bats` header
  documents this exact technique, `:1-10`).
- **python prompt-quality (LLM-as-judge)**: `tools/plugin-quality/judge/` —
  `rubrics.py` dimensions (`trigger-specificity`, `degrade-path-soundness`,
  `exit-condition-consistency`, `profile-key-branching`, `root-cause-culture`,
  `instruction-unambiguity`, etc.), `name_filter` token-boundary matching
  (`rubrics.py:50-57`), run per skill artifact (`run_judge.py`). The edited
  three SKILL.md files are re-judged; the Publish step must keep
  degrade-path/profile-key/exit-condition dimensions scoring high. There is
  also a deterministic lint tier (`tools/plugin-quality/lint/check_*.py`:
  frontmatter, descriptions, generalization, references, escalation).
- **LLM-judge (claude CLI)**: `tools/security-audit-validation/judge/` is the
  precedent for a domain LLM-judge harness; the test plan/strategy under
  `docs/testing/` reference LLM-judge tiers.

---

## 3. GitHub-comment idempotency approaches (prior art + recommendation)

The feature's core technical risk is "post once, then update — never spam".
Three industry approaches, ranked:

1. **Hidden HTML-comment marker + find-and-edit (RECOMMENDED).** Embed
   `<!-- sdlc-review:<lens> -->` (and `<!-- sdlc-review:conclusion -->`) in the
   body. On each run: list PR issue comments, find the one authored by the
   bot/token user whose body contains the marker, and EDIT it; create only if
   none exists. This is the dominant pattern (sticky-pull-request-comment,
   peter-evans/create-or-update-comment, marocchino/sticky-pull-request-comment
   all use it). It directly mirrors the in-repo `inject-governance.sh` marker
   block (§2.5) — minimal conceptual novelty for this codebase.
   - **List:** `gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate`
     (REST) or a GraphQL `issueComments` query (matches the GraphQL style
     `get-pr-comments.sh` already uses, `:77-99`). Filter by
     `author.login == <token user>` AND `body contains marker`. Authorship
     filter prevents editing a human comment that happens to quote the marker.
   - **Update:** `gh api -X PATCH repos/{owner}/{repo}/issues/comments/{id}
     -f body=...` (REST) or the GraphQL `updateIssueComment` mutation.
   - **Create:** `gh pr comment "$pr" --body ...` (already used,
     `fr-nfr-gate.sh:103`) or `gh api -X POST .../comments`.
   - **`gh pr comment --edit-last`** exists but edits the LAST comment by the
     actor regardless of lens — UNSAFE for per-lens markers (would clobber the
     wrong lens). Prefer explicit marker-matched id resolution.

2. **GraphQL `minimizeComment` (hide outdated) + new comment.** Used by some
   bots to collapse stale comments as `OUTDATED`/`RESOLVED` rather than edit in
   place. Heavier, leaves a trail of hidden comments, more API calls. Useful as
   a SECONDARY cleanup when duplicate-marker corruption is detected (§2.5
   parallel) — minimize the extras, edit the first. Not the primary path.

3. **Delete-and-recreate.** Simplest to reason about but loses comment URL
   stability and reaction/thread history, and races with reviewers reading the
   comment. Rejected.

**Recommendation:** approach 1 as primary (marker + author-filtered find +
edit), with approach 2's `minimizeComment` as the corruption-recovery branch
(duplicate markers → keep/edit the oldest, minimize the rest). Keep both jq
and python3 backends for the list/parse step (§2.1).

---

## 4. Risks & mitigations

| # | Risk | Mitigation (encode in PRD) |
|---|---|---|
| R1 | **Comment spam** — re-posting every iteration/run | Idempotent hidden-marker UPDATE (§3.1); one comment per lens + one conclusion; assert via `STUB_GH_LOG` in bats (one create then edits) |
| R2 | **Secret leakage** — a finding's reproduction/body echoes a token, password, connection string, env var | Redact before render: mask known secret shapes (AWS keys, JWTs, `password=`, `://user:pass@`, high-entropy strings) AND honor the security-auditor "no exfiltration" boundary (`security-audit/SKILL.md:48-49`). The ledger should carry redacted reproductions; the poster redacts again defensively (belt-and-suspenders). Add a bats redaction test. |
| R3 | **Posting to a wrong/third-party PR** — `--pr` points outside the repo, or a fork PR, or a malicious dispatch | In-scope authorization: resolve `OWNER/NAME` from origin/gh (§2.1) and verify the target PR belongs to THAT repo before any write; never accept an arbitrary owner/repo. Mirrors the security-auditor in-scope-host boundary (`security-audit/SKILL.md:38-47`, `agents/security-auditor.md:87-117`) applied to the PR target. Refuse-with-note if the PR's base repo ≠ resolved repo. |
| R4 | **Rate limits / abuse limits** | One consolidated comment per lens (not per finding) bounds calls to O(lenses); idempotent edit avoids growth; `--paginate` only when listing to find the marker; warn-not-die on `gh` failure (`fr-nfr-gate.sh:96-105`) so a 403/secondary-rate-limit degrades, never fails the loop |
| R5 | **Degrade must never fail the loop (NFR-3)** | gh absent / no PR / flag off / empty ledger → `log_info` skip-note + `exit 0`. CONTRAST: `get-pr-comments.sh:40` DIES when gh is absent because it's a read the FR-8 loop depends on; the POSTER is fire-and-forget side output, so it DEGRADES. State this difference explicitly so a reviewer doesn't "fix" the poster to die. |
| R6 | **Gating bypass** — posts when `capabilities.publish_pr_comments` is false | First action of the poster: read the flag from the profile (`common.sh` `yaml_get`/`profile_get`, default false); flag-off → skip-note exit 0. Default-off is the schema default (§2.6). bats test for on/off. |
| R7 | **Wrong-comment edit** — editing a human comment containing the marker | Author-filter the find to the token/bot user (§3.1); never edit a comment not authored by the posting identity |
| R8 | **Wrap/overflow in conclusion math** | Use `common.sh` `strip_zeros`/`num_gt` digit-string arithmetic (`:39-58`), never `(( ))` — same discipline as `fr-nfr-gate.sh:125-137` and `ai-review-loop.sh:44-54` |
| R9 | **NFR-2 source-literal leakage** in script/tests/skills | Resolve every path/PR/repo from profile or fixtures; concrete values only inside `# profile-example` fences; CI denylist enforces (`ci.yml:286`) |
| R10 | **SKILL.md bloat past ~500 lines (NFR-9)** | The Publish step in each of the three skills must be a SHORT slot (a few lines pointing at the poster + the gate flag), enumerations stay in the script/`reference/`, not inline |
| R11 | **Malformed gh read on the update path** | Reuse `raw_is_json`/shape guards (`get-pr-comments.sh:113-260`) before trusting a comment-list response; a non-JSON/error envelope → degrade-note, fall back to create or skip |

---

## 5. Prior art (external) the PRD may cite

- **peter-evans/create-or-update-comment** & **marocchino /
  sticky-pull-request-comment** — canonical hidden-marker sticky-comment
  pattern; validates approach §3.1 as standard practice.
- **GitHub REST** `GET/POST /repos/{o}/{r}/issues/{n}/comments`,
  `PATCH /repos/{o}/{r}/issues/comments/{id}`; **GraphQL** `updateIssueComment`
  / `minimizeComment` mutations — the exact gh-callable primitives.
- **In-repo** `scripts/inject-governance.sh` — the marker-block
  replace-in-place idempotency model already shipped and tested in THIS plugin
  (the single most relevant prior art).
- **In-repo** `scripts/fr-nfr-gate.sh` — the existing "render findings → post
  to PR comment + commit status" flow the Publish step generalizes.

---

## 6. Findings the PRD will use (crisp)

1. **Build the poster as a sibling of `get-pr-comments.sh`**: same shebang /
   `set -euo pipefail` / `lib/common.sh` sourcing / `--pr` flag+validation /
   origin-then-gh repo-slug resolution / jq-with-python3 dual backend. It is
   shellcheck-`-x`-clean and bats-stub-friendly (driven by `STUB_GH_OUTPUT` /
   asserted via `STUB_GH_LOG`).

2. **Idempotency = hidden HTML marker `<!-- sdlc-review:<lens> -->` + author-
   filtered find-and-edit**, modeled on the in-repo `inject-governance.sh`
   marker block. List → match marker AND posting-identity author → PATCH/update
   existing, else create. `minimizeComment` is the duplicate-marker
   corruption-recovery branch only. NEVER `--edit-last` (lens-unsafe).

3. **Canonical poster-input ledger JSON** is a projection of the
   security-audit finding-record (`security-audit/SKILL.md:272-309`) unioned
   with the code-review priority/disposition and the fr-nfr `FR_NFR_NEW_FINDINGS`
   counts. Define it once in the PRD: `{lens, pr, findings[], iterations,
   started_at, ended_at}` with per-finding `{id, severity, cwe?, owasp?,
   location, summary, status, auto_fixed, regression_test?}`. Render
   consolidated, deduped (by `(cwe, location, endpoint)` per
   `security-audit/SKILL.md:185-187`), severity-ordered (Critical→Low).

4. **`--conclusion` mode** aggregates the three lens ledgers into one
   marker'd comment: counts found by lens+severity, count auto-fixed
   root-cause-with-regression-test, iterations used, run duration. All counting
   uses `common.sh` digit-string arithmetic (wrap-safe), never `(( ))`. The
   ORCHESTRATOR (`/sdlc-review`, with the timing it captured — start at loop
   entry, end at loop close, §2.3) posts it once at loop close.

5. **Gating: new `capabilities.publish_pr_comments` (bool, default false /
   opt-in)** + new nullable `make.post_review_findings` (plugin substitutes
   `scripts/post-review-findings.sh` when null), both ADDED to
   `docs/profile-schema.md`, `generate-profile.sh`, `validate-profile.sh`, and
   the `# profile-example`. Flag-off → skip-note exit 0.

6. **Degrade (NFR-3) is the poster's default failure mode, NOT die**: gh
   absent / no PR / flag off / empty ledger / malformed gh read → `log_info`
   skip-note + `exit 0`; `gh` write failure → `log_warn`, never fail the loop.
   This is the deliberate INVERSE of `get-pr-comments.sh`'s die-on-gh-absent
   (which feeds a loop exit condition); document the contrast.

7. **Authorization boundary**: post ONLY to the resolved-repo's own PR; verify
   the target PR's base repo equals the origin/gh-resolved `OWNER/NAME` before
   any write; refuse third-party/fork-base targets with a note. Reuse the
   security-auditor in-scope-boundary discipline applied to the PR target.

8. **Redaction**: redact known secret shapes from finding bodies/reproductions
   before render (defensive second layer; the ledger should already carry
   redacted text per the no-exfiltration boundary). bats redaction test
   required.

9. **Three skill Publish steps stay SHORT (NFR-9 ~500-line cap)**: each of
   security-audit / bmad-fr-nfr-review-gate / code-review gains a brief "Publish
   (gated)" slot that (a) checks `capabilities.publish_pr_comments`, (b) calls
   the `make.post_review_findings` target or the substituted script with the
   lens arg + ledger, (c) notes the degrade. The fr-nfr Publish slots where
   `fr-nfr-gate.sh` already posts; security-audit's slots after §5.4
   aggregate / at loop close; code-review's after its evidence ledger.

10. **All three test tiers required**: (a) bats — render, idempotent
    update-vs-create (via `STUB_GH_LOG`), dedup, severity order, redaction,
    gating on/off, every degrade path, conclusion math (wrap-safe);
    (b) python prompt-quality — re-judge the three edited SKILL.md against
    `rubrics.py` dimensions (degrade-path, profile-key-branching,
    exit-condition, root-cause, instruction-unambiguity) + the deterministic
    lint tier (frontmatter/descriptions/generalization/references); (c)
    LLM-judge over the edited skills. New profile keys must pass
    `profile-keys-check` and `generalization-audit` BEFORE any skill cites them.

11. **CI must stay green on**: markdown-lint (skill + doc edits), shellcheck
    -x (the new script), bats (new suite), frontmatter-check, profile-keys-check
    (new keys documented), generalization-audit (zero source literals; concrete
    values only inside `# profile-example`).
