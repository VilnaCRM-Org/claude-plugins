---
stepsCompleted: [step-01-init, step-02-vision, step-03-users, step-04-metrics, step-05-scope, step-06-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-publish-review-comments/research.md
  - specs/autonomous/2026-06-14-security-audit-skill/product-brief.md
  - plugins/php-backend-sdlc/scripts/get-pr-comments.sh
  - plugins/php-backend-sdlc/scripts/fr-nfr-gate.sh
  - plugins/php-backend-sdlc/scripts/ai-review-loop.sh
  - plugins/php-backend-sdlc/skills/security-audit/SKILL.md
  - plugins/php-backend-sdlc/skills/code-review/SKILL.md
  - plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md
  - plugins/php-backend-sdlc/commands/sdlc-review.md
  - plugins/php-backend-sdlc/commands/sdlc-finish-pr.md
  - plugins/php-backend-sdlc/docs/profile-schema.md
date: 2026-06-14
author: Mary (BMAD analyst agent, autonomous run)
mode: autonomous (no human pauses; assumptions recorded inline)
---

# Product Brief: Publish Review Findings as PR Comments — `php-backend-sdlc`

## 0. Executive Summary

Add an opt-in, gated capability to the `php-backend-sdlc` plugin that
**publishes** the findings of its three review lenses — `security-audit`, the
BMAD FR/NFR review gate, and `code-review` — as GitHub PR comments, and posts a
single **conclusion** comment at loop close. Today the plugin's review work is
high-signal but largely invisible on the PR itself: the security lens emits a
SECURITY-AUDIT RUN REPORT into the orchestrator transcript, the FR/NFR gate
posts a comment **only on FAIL** (success is comment-quiet — the commit status
is the durable signal; `fr-nfr-gate.sh:16-21,133-144`), and the code-review
lens keeps its evidence in a private ledger file. A human reviewer landing on
the PR sees a green/red status check and a fix commit, but not *what each lens
found, at what severity, and which findings were auto-fixed at the root cause*.

The feature introduces one shared poster — `scripts/post-review-findings.sh` —
built as a sibling of `scripts/get-pr-comments.sh`: same shebang/`set -euo
pipefail`/`lib/common.sh` sourcing, the same `--pr` flag-and-validation, the
same origin-then-`gh` repo-slug resolution, and the same jq-with-python3 dual
backend (`get-pr-comments.sh:1-24,29-39,57-68,113-120`). It consumes a
canonical finding-record **ledger** (JSON on stdin or file) plus a lens
argument (`security | fr-nfr | code-review`), renders **one** consolidated,
deduped, severity-ordered Markdown comment per lens, and is **idempotent** via a
hidden HTML marker (`<!-- sdlc-review:<lens> -->`) — it **updates** its prior
bot comment instead of spamming, reusing the marker-block replace-in-place
discipline already shipped in `scripts/inject-governance.sh` (research §2.5,
§3.1). A `--conclusion` mode aggregates the three lens ledgers into one comment:
counts found by lens and severity, count auto-fixed root-cause-with-regression-
test, iterations used, and run duration.

The capability is **default-off and opt-in**, gated behind a new
`capabilities.publish_pr_comments` profile flag (modeled on
`capabilities.dynamic_security_testing`, `profile-schema.md:130`), posts **only
to the resolved repo's own PR** (never a third party/fork base), redacts known
secret shapes, and **degrades** (gh absent / no PR / flag off / empty ledger /
malformed gh read → skip-with-note, exit 0, never fail the loop, NFR-3) — the
deliberate inverse of `get-pr-comments.sh`'s die-on-gh-absent (research §4 R5,
§6.6). A short, gated **Publish** step wires into each of the three skills and
into the `/sdlc-review` orchestrator, which posts the conclusion once at loop
close using the `iteration <n>/5` counter and timing it already captures
(`sdlc-review.md:170-187`). Success is measured by zero comment spam (one
comment per lens, asserted via the bats `STUB_GH_LOG`), correct dedup/severity
ordering, redaction of secret shapes, correct on/off gating and every degrade
path, accurate conclusion math (wrap-safe digit-string arithmetic), and a clean
pass of all CI gates plus all three test tiers.

## 1. Problem Statement

The `php-backend-sdlc` plugin runs three review lenses inside its SDLC loop, and
each produces structured findings — but the findings rarely surface **on the
PR**, where the human reviewer and PR author actually look:

- **`security-audit`** drives an adversarial red-team loop to zero new verified
  findings, emitting a per-finding record (CWE / OWASP / severity / location /
  reproduction / remediation / regression_test) and a SECURITY-AUDIT RUN REPORT
  (`security-audit/SKILL.md:272-309`). That report lives in the orchestrator
  transcript; nothing publishes it to the PR. A reviewer cannot see *which OWASP
  families were probed, what was found at what severity, and what was fixed*.
- **The BMAD FR/NFR review gate** posts a PR comment carrying findings **only
  when the new-findings count is above zero** — success is intentionally
  comment-quiet and relies on the `BMAD FR/NFR Review Gate` commit status
  (`fr-nfr-gate.sh:16-21,87-94,133-144`). There is no consolidated, durable,
  human-readable summary of what the gate verified when it passes.
- **`code-review`** keeps an auditable per-comment evidence ledger in a private
  `PR_COMMENT_EVIDENCE` file (`code-review/SKILL.md:86-149`). That ledger proves
  every reviewer comment was addressed, but it is not rendered onto the PR as a
  reviewer-facing summary of priorities and dispositions.

Concrete gaps this feature fills:

- **Findings are invisible on the PR.** The durable PR-visible artifacts are a
  status check and the fix commits. There is no single comment per lens telling
  a reviewer *what was found, ordered by severity, deduped across families*.
- **No close-out summary.** At loop close, nothing tells the PR audience how
  many issues each lens found, how many were auto-fixed at the root cause with a
  regression test, how many iterations the loop took, and how long it ran — the
  exact aggregation the SECURITY-AUDIT RUN REPORT, the FR/NFR
  `FR_NFR_NEW_FINDINGS` count, and the loop's own iteration counter already
  contain (`security-audit/SKILL.md:298-309`; `fr-nfr-gate.sh:116-121`;
  `sdlc-review.md:180-187`).
- **The only existing poster is FAIL-only and bespoke.** `fr-nfr-gate.sh`'s
  `gh pr comment` create primitive (`:96-105`) posts on FAIL, has no idempotent
  update, no marker, no dedup/severity rendering, and no per-lens generality —
  re-running it would create duplicate comments. There is no shared, idempotent,
  redaction-aware poster the three lenses can reuse.
- **Publishing is all-or-nothing risk today.** Any naive "comment the findings"
  addition risks comment spam, secret leakage, posting to the wrong/third-party
  PR, and failing the loop when `gh` is unavailable — none of which the current
  code is structured to prevent for a *write* path (the read path
  `get-pr-comments.sh` deliberately dies when `gh` is absent, `:40`).

The result: the plugin does first-class review work whose output never reaches
the PR conversation in a consolidated, durable, safe form. This feature closes
that gap with one shared, gated, idempotent poster and short Publish steps wired
into the three lenses and the orchestrator.

## 2. Target Users

- **Primary: plugin operators running `/sdlc-review` and `/sdlc-finish-pr` on
  their own authorized repo.** They drive the review/finish stages and want the
  lenses' findings published onto the PR — one consolidated, severity-ordered
  comment per lens plus a conclusion at loop close — without manually copying
  transcript output, and without risking spam, leaked secrets, or a failed loop
  when `gh` is unavailable. They opt in by setting one profile flag.
- **Secondary: human PR reviewers and PR authors.** They land on the PR and want
  a durable, readable summary of what each lens found (security, FR/NFR, code-
  review), at what severity, deduped, and a close-out with counts found / auto-
  fixed / iterations / duration — instead of inferring it from a status check
  and a string of fix commits.
- **Tertiary: autonomous orchestration itself** (`/sdlc`, `/sdlc-review`,
  `/sdlc-finish-pr`, bmalph/Ralph runs) — the orchestrator consumes the poster
  as a side-output step and posts the conclusion once at loop close with the
  timing and iteration count it captured.

## 3. Value Proposition

One shared, gated poster turns the plugin's three review lenses into PR-visible
output. `scripts/post-review-findings.sh` consumes a canonical finding ledger
plus a lens arg and renders **one** consolidated, deduped, severity-ordered
Markdown comment per lens — idempotent via a hidden `<!-- sdlc-review:<lens> -->`
marker, so it **updates** its own prior comment instead of spamming. A
`--conclusion` mode aggregates across lenses into a single close-out comment
(counts found by lens+severity, count auto-fixed root-cause-with-regression-
test, iterations, run duration). It is **default-off / opt-in** behind one
profile flag, posts **only to the resolved repo's own PR**, **redacts** secret
shapes, and **degrades** (gh absent / no PR / flag off / empty ledger → skip-
with-note, exit 0) so it never fails the loop. It is a sibling of the existing
`get-pr-comments.sh` (same flags, repo resolution, dual-backend rendering,
bats-stub-friendly shape) and reuses the in-repo `inject-governance.sh`
idempotency model — minimal conceptual novelty, maximum reuse, zero source-
project literals.

## 4. Goals and Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Idempotent, spam-free publishing | One comment per lens + one conclusion comment; a second run UPDATES, never duplicates (asserted via the bats `STUB_GH_LOG`: exactly one create, then an edit) | 0 duplicate bot comments per lens across re-runs |
| G2 | Faithful, deduped, ordered rendering | Findings deduped by `(cwe, location, endpoint)` (`security-audit/SKILL.md:185-187`) and ordered Critical→Low; conclusion counts match the source ledgers | 100% — render parity with the ledger in tests |
| G3 | Default-off, opt-in gating | Posts only when `capabilities.publish_pr_comments` is true; default false; flag-off → skip-with-note exit 0 (bats on/off) | 0 posts when the flag is false/absent |
| G4 | Degrade-safe (NFR-3) | gh absent / no PR / flag off / empty ledger / malformed gh read → `log_info` skip-note + exit 0; `gh` write failure → `log_warn`, never fail the loop | 0 loop failures attributable to the poster |
| G5 | Authorization boundary | Posts only to the origin/`gh`-resolved `OWNER/NAME`'s own PR; refuses third-party/fork-base targets with a note (`get-pr-comments.sh:57-68` resolution; research §4 R3) | 0 posts to an out-of-scope PR |
| G6 | Secret redaction | Known secret shapes (AWS keys, JWTs, `password=`, `://user:pass@`, high-entropy tokens) masked before render; honors the security-auditor no-exfiltration boundary (`security-audit/SKILL.md:48-49`) | 0 secrets rendered into a comment (bats redaction test) |
| G7 | Wrap-safe conclusion math | All counts use `common.sh` `strip_zeros`/`num_gt` digit-string arithmetic, never bash `(( ))` (`fr-nfr-gate.sh:125-137`; `ai-review-loop.sh:44-54`) | 0 arithmetic overflow / silent miscount |
| G8 | Generalization (NFR-2/NFR-4) | Poster + tests + skill edits resolve every path/PR/repo from profile or fixtures; concrete values only inside `# profile-example` fences; CI `generalization-audit` denylist green (`ci.yml` denylist) | 100% — CI generalization-audit green |
| G9 | Clean plugin integration | New `capabilities.publish_pr_comments` + nullable `make.post_review_findings` documented in `profile-schema.md`, emitted/accepted by `generate-profile.sh`/`validate-profile.sh`, added to the `# profile-example`; `profile-keys-check` passes; each edited SKILL.md ≤ ~500 lines (NFR-9) | Plugin CI green on every PR |
| G10 | Full three-tier test coverage | bats (render, idempotent update-vs-create, dedup, severity order, redaction, gating on/off, every degrade path, conclusion math) + python prompt-quality (re-judge the three edited skills) + LLM-judge | All three tiers present and green |

## 5. Scope

### In scope (v1)

- **New script `plugins/php-backend-sdlc/scripts/post-review-findings.sh`** — the
  shared poster, sibling of `get-pr-comments.sh`. Consumes a canonical finding
  ledger (JSON on stdin or `--file`), a lens arg (`security | fr-nfr |
  code-review`), and optional `--pr` (default via `gh pr view --json number`).
  Renders one consolidated, deduped (by `(cwe, location, endpoint)`), severity-
  ordered (Critical→Low) Markdown comment per lens. Idempotent via a hidden
  `<!-- sdlc-review:<lens> -->` marker: list PR comments → match the marker AND
  the posting-identity author → PATCH/update the existing comment, else create
  (`gh pr comment --body`, as in `fr-nfr-gate.sh:103`). `--conclusion` mode
  aggregates the three lens ledgers into one `<!-- sdlc-review:conclusion -->`
  comment (counts found by lens+severity, count auto-fixed root-cause-with-
  regression-test, iterations used, run duration). jq-with-python3 dual backend
  for every transform (`get-pr-comments.sh:113-120`); shellcheck-`-x`-clean with
  the `# shellcheck source=lib/common.sh` pragma.
- **Canonical poster-input ledger schema**, defined once and derived from the
  three lens shapes (research §2.4, §6.3):
  `{lens, pr, findings:[{id, severity, cwe?, owasp?, location, summary, status:
  open|fixed|dropped, auto_fixed: bool, regression_test?}], iterations,
  started_at, ended_at}`. A projection of the security-audit finding-record
  (`security-audit/SKILL.md:272-309`) unioned with the code-review priority/
  disposition categorization (`code-review/SKILL.md:256-263`) and the FR/NFR
  `FR_NFR_NEW_FINDINGS` count (`fr-nfr-gate.sh:116-121`). jq- and python-
  parseable.
- **Two minimal new profile keys** in `docs/profile-schema.md`:
  `capabilities.publish_pr_comments` (bool, default **false** / opt-in;
  mirrors `capabilities.dynamic_security_testing`, `profile-schema.md:130`) and
  nullable `make.post_review_findings` (plugin substitutes
  `scripts/post-review-findings.sh` when `null`; mirrors `make.pr_comments`/
  `make.fr_nfr_gate` null-substitution, `profile-schema.md:77-78`). Both added
  to `generate-profile.sh`, `validate-profile.sh` (the `make` map is required-
  and-complete; a new key must be emitted/accepted or validation fails,
  `profile-schema.md:60-64`), and the annotated `# profile-example`.
- **A short, gated Publish step in each of the three skills** (NFR-9 — a few
  lines pointing at the poster + the gate flag; enumerations stay in the script):
  - `security-audit/SKILL.md` — Publish slots after §5.4 aggregate / at loop
    close, emitting the `security` lens ledger from the finding records.
  - `bmad-fr-nfr-review-gate/SKILL.md` — Publish slots where the gate already
    posts (`fr-nfr-gate.sh:96-144`), emitting the `fr-nfr` lens ledger.
  - `code-review/SKILL.md` — Publish slots after its evidence ledger, emitting
    the `code-review` lens ledger (priorities/dispositions).
- **Orchestrator wiring** in `/sdlc-review` (and the relevant `/sdlc-finish-pr`
  hand-off): capture start at loop entry and end at loop close; post the
  conclusion comment once at loop close via `--conclusion` with the captured
  duration and the `iteration <n>/5` count it already tracks
  (`sdlc-review.md:170-187`).
- **All three test tiers**: bats (`tests/post-review-findings.bats`) with the
  env-driven `gh` stub (`STUB_GH_OUTPUT`/`STUB_GH_EXIT`/`STUB_GH_LOG`) and the
  subcommand-routing wrapper for the two-response list→edit path (research
  §2.8); python prompt-quality re-judge of the three edited SKILL.md against the
  `rubrics.py` dimensions plus the deterministic lint tier; LLM-judge over the
  edited skills.
- **BMAD planning artifacts** for this feature in
  `specs/autonomous/2026-06-14-publish-review-comments/`.

### Out of scope (v1)

- **No new command surface.** Publishing is a Publish step inside the three
  existing skills + the `/sdlc-review`/`/sdlc-finish-pr` orchestration — no
  `/sdlc-publish` command (the command count stays unchanged).
- **No third-party / fork-base posting.** The poster posts only to the
  origin/`gh`-resolved repo's own PR; a target PR whose base repo differs is
  refused-with-note (research §4 R3). It never accepts an arbitrary owner/repo.
- **No per-finding comments / inline review threads.** One consolidated comment
  per lens (and one conclusion), bounding `gh` calls to O(lenses) and avoiding
  rate/abuse limits (research §4 R4). Inline `file:line` review threads are not
  in v1.
- **No delete-and-recreate idempotency.** Marker + author-filtered find-and-edit
  is primary; `minimizeComment` is the duplicate-marker corruption-recovery
  branch only; `gh pr comment --edit-last` is rejected (lens-unsafe) (research
  §3, §6.2).
- **No `quality.*` changes.** Quality thresholds are raise-only and unrelated;
  the poster must not touch them (`profile-schema.md:82-105`).
- **No die-on-`gh`-absent for the poster.** Unlike the read-path
  `get-pr-comments.sh` (which dies because the FR-8 loop depends on it,
  `:40`), the poster is fire-and-forget side output and DEGRADES — this contrast
  is stated so a reviewer does not "fix" the poster to die (research §6.6).
- **No secret-shape policy invention beyond a documented redaction set.** The
  poster masks a documented set of known secret shapes; defining a new secrets-
  detection engine is out of scope (belt-and-suspenders on top of the ledger's
  already-redacted text, research §4 R2).
- **No `gh`-write retry/backoff machinery.** A `gh` write failure warns and the
  loop proceeds (mirrors `fr-nfr-gate.sh:96-105`); no retry queue.

## 6. Key Features

1. **Shared poster, sibling of `get-pr-comments.sh`.** Same shebang/`set -euo
   pipefail`/`lib/common.sh` sourcing, `--pr` flag-and-validation, origin-then-
   `gh` repo-slug resolution, JSON-validity/shape guards before trusting `gh`
   output, and jq-with-python3 dual backend — so it runs where only python3
   exists and is shellcheck-`-x`-clean and bats-stub-friendly.
2. **Idempotent hidden-marker publishing.** A `<!-- sdlc-review:<lens> -->`
   marker lets the poster find its own prior comment (author-filtered to the
   posting identity) and UPDATE it; create only if none exists — modeled on the
   in-repo `inject-governance.sh` marker block. `minimizeComment` is the
   duplicate-marker corruption-recovery branch; `--edit-last` is never used.
3. **Consolidated, deduped, severity-ordered rendering.** One comment per lens,
   deduped by `(cwe, location, endpoint)`, ordered Critical→Low, rendered from
   the canonical ledger via either jq or python3.
4. **`--conclusion` aggregation at loop close.** One comment aggregating the
   three lens ledgers: counts found by lens+severity, count auto-fixed root-
   cause-with-regression-test, iterations used, run duration — posted once by the
   orchestrator with the timing and iteration count it captured. All counting
   uses wrap-safe digit-string arithmetic, never `(( ))`.
5. **Default-off gating + minimal profile extension.** New
   `capabilities.publish_pr_comments` (bool, default false) + nullable
   `make.post_review_findings`, both documented and validated; flag-off → skip-
   with-note exit 0.
6. **Authorization + redaction boundaries.** Posts only to the resolved repo's
   own PR (refuse third-party/fork-base with a note); redact known secret shapes
   before render (defensive second layer over an already-redacted ledger).
7. **Degrade-first failure mode (NFR-3).** gh absent / no PR / flag off / empty
   ledger / malformed gh read → skip-with-note + exit 0; `gh` write failure →
   warn, never fail the loop — the deliberate inverse of the read-path
   die-on-`gh`-absent.

## 7. Constraints and Assumptions

### Binding constraints (plugin non-negotiables, inherited)

- **Profile-driven + generalized (NFR-2/NFR-4).** Every path/PR/repo resolves
  from the profile or from test fixtures; no source-project literals
  (`user-service`, `VilnaCRM`, a real PR number) outside `# profile-example`
  fences; the CI `generalization-audit` denylist and `profile-keys-check` jobs
  must pass.
- **Degrade over hard-fail (NFR-3).** The poster's default failure mode is skip-
  with-note + exit 0; a `gh` write failure warns; it never fails the loop. This
  inverts `get-pr-comments.sh`'s die-on-`gh`-absent and the contrast is
  documented.
- **Idempotent, low-noise output.** One comment per lens + one conclusion;
  re-runs UPDATE the existing marker'd comment; no per-finding spam; calls
  bounded to O(lenses).
- **Root-cause / raise-only intact.** The poster touches no `quality.*`
  thresholds and adds no suppressions; it reports, it does not relax gates.
- **Container-only / authorized boundaries unchanged.** Posts only to the
  resolved repo's own PR; never exfiltrates; redacts secret shapes — the
  security-auditor in-scope and no-exfiltration boundaries applied to the PR
  target.
- **SKILL.md ≤ ~500 lines (NFR-9).** Each Publish step is a short slot; the
  enumerations and rendering live in the script, not inline in the skill.
- **Wrap-safe arithmetic.** Conclusion counts use `common.sh`
  `strip_zeros`/`num_gt`, never bash `(( ))`.
- **CI must stay green** on `manifest-validate`, `markdown-lint`, `shellcheck -x`,
  `bats`, `frontmatter-check`, `profile-keys-check` (FR-17), and
  `generalization-audit` (NFR-2).

### Assumptions (recorded autonomously, no human confirmation)

- A1: Publishing is a Publish step inside the three skills + the orchestrator,
  not a new command — the feature scope is "shared script + Publish steps +
  schema keys"; the PRD/architecture pin the exact slot in each skill and the
  orchestrator hand-off (which command posts the conclusion).
- A2: The canonical ledger schema is `{lens, pr, findings[], iterations,
  started_at, ended_at}` with per-finding `{id, severity, cwe?, owasp?,
  location, summary, status, auto_fixed, regression_test?}` (research §6.3) —
  exact field names and the lens→ledger emission contract per skill are
  PRD/architecture decisions.
- A3: Idempotency = hidden `<!-- sdlc-review:<lens> -->` marker + author-filtered
  find-and-edit (primary), `minimizeComment` for duplicate-marker corruption
  recovery (secondary); `--edit-last` rejected (research §3, §6.2).
- A4: New key names are `capabilities.publish_pr_comments` (bool, default false)
  and nullable `make.post_review_findings` — final names are a minimal-surface
  schema decision the PRD/architecture confirm.
- A5: The orchestrator captures duration (start at loop entry, end at loop close)
  and reuses its existing `iteration <n>/5` counter for the conclusion
  (`sdlc-review.md:170-187`); the exact capture mechanism is an architecture
  detail.
- A6: The redaction set (AWS keys, JWTs, `password=`, `://user:pass@`, high-
  entropy tokens) is a defensive second layer; the ledger is expected to already
  carry redacted text per the no-exfiltration boundary. The precise pattern set
  is an architecture decision (research §4 R2).
- A7: List/find uses `gh api .../issues/{pr}/comments --paginate` (REST) or the
  GraphQL `issueComments` query already in the codebase style; update uses PATCH
  `issues/comments/{id}` or `updateIssueComment`; create uses `gh pr comment
  --body` — the exact primitive mix is an architecture decision (research §3).

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **Comment spam** — re-posting every iteration/run | Idempotent hidden-marker UPDATE (one comment per lens + one conclusion); assert via the bats `STUB_GH_LOG` (one create then edits) — research §4 R1 |
| **Secret leakage** — a finding body echoes a token/password/connection string | Redact known secret shapes before render (defensive second layer over an already-redacted ledger); honor the no-exfiltration boundary; bats redaction test — research §4 R2 |
| **Posting to a wrong/third-party PR** — `--pr` outside the repo, or a fork base | Resolve `OWNER/NAME` from origin/`gh` and verify the target PR's base repo equals it before any write; refuse-with-note otherwise — research §4 R3 |
| **Rate / abuse limits** | One consolidated comment per lens (calls O(lenses)); idempotent edit avoids growth; warn-not-die on `gh` failure — research §4 R4 |
| **Degrade must never fail the loop (NFR-3)** | gh absent / no PR / flag off / empty ledger / malformed gh read → skip-note + exit 0; document the contrast with `get-pr-comments.sh`'s die-on-`gh`-absent — research §4 R5, §6.6 |
| **Gating bypass** — posts when the flag is false | First action: read `capabilities.publish_pr_comments` (default false); flag-off → skip-note exit 0; bats on/off test — research §4 R6 |
| **Wrong-comment edit** — editing a human comment quoting the marker | Author-filter the find to the posting identity; never edit a comment not authored by it — research §4 R7 |
| **Wrap/overflow in conclusion math** | Use `common.sh` `strip_zeros`/`num_gt` digit-string arithmetic, never `(( ))` — research §4 R8 |
| **NFR-2 source-literal leakage** in script/tests/skills | Resolve every path/PR/repo from profile or fixtures; concrete values only inside `# profile-example` fences; CI denylist enforces — research §4 R9 |
| **SKILL.md bloat past ~500 lines (NFR-9)** | Each Publish step is a short slot pointing at the poster + the gate flag; enumerations stay in the script/`reference/` — research §4 R10 |
| **Malformed `gh` read on the update path** | Reuse `raw_is_json`/shape guards before trusting a comment-list response; non-JSON/error envelope → degrade-note, fall back to create or skip — research §4 R11 |

## 9. Open Questions (non-blocking for PRD)

1. **Conclusion ownership** — does `/sdlc-review` post the conclusion at its loop
   close, or `/sdlc-finish-pr`, or both stages (one per loop)? (Leaning
   `/sdlc-review` at loop close per the research; architecture pins which
   orchestrator owns the timing and the single post.)
2. **Ledger emission contract per lens** — does each skill write the ledger JSON
   to a known path, pipe it on stdin, or have the orchestrator assemble it from
   the lens's report? (Schema is fixed in A2; the emission mechanism is
   architecture.)
3. **Posting identity for the author filter** — token user via `gh api user`,
   or a configured bot login? (Affects the author-filter find; architecture.)
4. **List/update primitive mix** — REST `--paginate` + PATCH vs GraphQL
   `issueComments` + `updateIssueComment` + `minimizeComment` (matching the
   existing GraphQL style); both backends keep jq+python parse parity.
5. **Redaction pattern set** — the exact secret-shape regexes and the high-
   entropy heuristic threshold (architecture decision, research §4 R2).
6. **`make.post_review_findings` default** — ship `null` (plugin substitutes the
   script) consistent with `make.pr_comments`/`make.fr_nfr_gate`; confirm in the
   `# profile-example`.
