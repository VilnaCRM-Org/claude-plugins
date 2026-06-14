---
stepsCompleted: [step-01-init, step-02-context, step-03-epic-breakdown, step-04-story-decomposition, step-05-ordering, step-06-acceptance-criteria, step-07-test-mapping, step-08-traceability, step-09-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-publish-review-comments/prd.md
  - specs/autonomous/2026-06-14-publish-review-comments/architecture.md
  - specs/autonomous/2026-06-14-publish-review-comments/research.md
  - specs/autonomous/2026-06-14-publish-review-comments/product-brief.md
  - plugins/php-backend-sdlc/scripts/get-pr-comments.sh
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
  - .github/workflows/ci.yml
workflowType: 'epics'
date: 2026-06-14
author: Bob (BMAD SM/PM agent, autonomous run)
---

# Epics & Stories — Publish Review Findings as PR Comments (`php-backend-sdlc`)

This is the implementation backlog for `prd.md` (FR-1..11 / NFR-1..8) and
`architecture.md` (§0 OQ resolutions, §1–§13). Stories are small,
independently-implementable, and **ordered so the shared poster lands before
the skill wiring** that depends on it. Every story names its exact files, its
binding acceptance criteria (a subset of the PRD/architecture ACs that story is
responsible for), and the test that proves it. Each story traces to one or more
FR/NFR.

## Sequencing rationale (read before picking a story)

The dependency spine is: **profile keys → poster foundation → poster
behaviors → skill/orchestrator wiring → cross-tier tests**. Concretely:

1. **Epic A (profile keys)** lands first because `profile-keys-check`
   (`ci.yml:211`) fails the instant any skill cites a key absent from
   `docs/profile-schema.md` — so the schema/generator/validator rows MUST exist
   before Epic C touches a SKILL.md (architecture §11.4 order-of-operations).
2. **Epic B (the poster)** lands next: the skills and the orchestrator invoke
   `scripts/post-review-findings.sh`, so it must exist and behave first. Within
   Epic B, the CLI skeleton + gate (B1) precedes the ledger parse (B2), which
   precedes render (B3), which precedes the gh write algorithm (B4); auth +
   redaction (B5), conclusion (B6), and the wrap-safe helper (the B6
   dependency) are layered on the validated skeleton.
3. **Epic C (skill + orchestrator wiring)** depends on both A (keys exist) and
   B (poster exists). Each skill story is independent of the others.
4. **Epic D (cross-tier quality tests)** depends on C (the edited skills) and B
   (the bats suite already lands per-story inside B/C). It is the python
   prompt-quality re-judge and the LLM-judge tier.

Within an epic, lower story numbers are earlier in the spine. A story's
"Depends on" line names its hard predecessors.

---

## Epic A — Profile keys (schema + generator + validator)

**Goal:** add `capabilities.publish_pr_comments` (bool, default `false`) and
`make.post_review_findings` (nullable) across the schema doc, the generator, and
the validator, so the CI `profile-keys-check` and `generalization-audit` jobs
stay green and the keys exist BEFORE any skill cites them.
**Traces:** FR-8, NFR-6, NFR-7, NFR-1. **PRD §2.2/FR-8; architecture §11.**

### Story A1 — Document both keys in `docs/profile-schema.md`

- **id:** A1
- **title:** Add `capabilities.publish_pr_comments` + `make.post_review_findings` to the schema doc
- **depends on:** none (root of the spine)
- **files touched:**
  - `plugins/php-backend-sdlc/docs/profile-schema.md` — add a `make` table row
    `make.post_review_findings` (nullable; plugin substitutes
    `scripts/post-review-findings.sh` when null; mirrors `make.ai_review_loop` /
    `make.pr_comments` / `make.fr_nfr_gate`); add a `capabilities` table row
    `capabilities.publish_pr_comments` (no; bool; default `false`; gates the
    Publish step + the poster write path; mirrors
    `capabilities.dynamic_security_testing` / `capabilities.structurizr`); add
    both lines inside the `# profile-example` fenced block
    (`post_review_findings: null` under `make:`, `publish_pr_comments: false`
    under `capabilities:`).
- **acceptance criteria (FR-8 AC subset):**
  1. The `make` table lists `make.post_review_findings` as nullable with the
     plugin-substitutes-when-null semantics.
  2. The `capabilities` table lists `capabilities.publish_pr_comments` as a
     bool defaulting to `false`.
  3. The `# profile-example` block carries both new lines (concrete values are
     allowed only inside this fence per `generalization-audit`,
     `ci.yml:271-280`).
  4. Both new dotted paths are backticked so `profile-keys-check` (`ci.yml:211`)
     can grep them.
- **test:** CI `markdown-lint` (`ci.yml:79`) and `generalization-audit`
  (`ci.yml:249`) green on the edited doc; a manual grep
  `grep -E 'capabilities\.publish_pr_comments|make\.post_review_findings' docs/profile-schema.md`
  returns both backticked paths (table + example fence). No skill cites the keys
  yet, so `profile-keys-check` is unaffected by this story alone.

### Story A2 — Emit both keys from `scripts/generate-profile.sh`

- **id:** A2
- **title:** Emit `make.post_review_findings: null` + `capabilities.publish_pr_comments: false` from the generator
- **depends on:** A1 (schema is the source of truth the generator must match)
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/generate-profile.sh` — add
    `post_review_findings: null` to the make-emission heredoc (after
    `load_tests:`, `generate-profile.sh:344`); add `publish_pr_comments: false`
    to the `capabilities:` emission block (`generate-profile.sh:362-365`). Do
    NOT add `make.security` (a pre-existing, out-of-scope generator gap per
    architecture §11.2) — add only the new key to keep the make-map-complete
    invariant satisfied.
- **acceptance criteria (FR-8 AC subset):**
  1. A generated profile contains `make.post_review_findings: null` under
     `make:`.
  2. A generated profile contains `capabilities.publish_pr_comments: false`
     under `capabilities:`.
  3. The generator change adds ONLY `post_review_findings` to the make block (no
     `make.security`), keeping the diff minimal.
- **test:** a new/extended case in
  `plugins/php-backend-sdlc/tests/generate-profile.bats` (or the existing
  generator bats suite) asserting the two emitted lines appear in a freshly
  generated profile; CI `shellcheck` (`ci.yml:95`) green on the edited script.

### Story A3 — Require `make.post_review_findings` in `scripts/validate-profile.sh`

- **id:** A3
- **title:** Add `post_review_findings` to the validator `MAKE_KEYS` completeness check
- **depends on:** A1 (schema), A2 (generated profiles must already carry the key, or A3 would reject them)
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/validate-profile.sh` — add
    `post_review_findings` to the `MAKE_KEYS` array
    (`validate-profile.sh:146-147`) so a `make` map missing it is a validation
    error (the map is required-and-complete, FR-8). No new check for the bool
    capability (capabilities are optional/default-off — the validator does not
    require `capabilities.dynamic_security_testing` either).
- **acceptance criteria (FR-8 AC subset):**
  1. `validate-profile.sh` accepts a profile that contains
     `make.post_review_findings` (any of null / a path).
  2. `validate-profile.sh` rejects a profile whose `make` map omits
     `make.post_review_findings` with a "make map incomplete" violation naming
     the key.
  3. No validation is added for `capabilities.publish_pr_comments` (optional).
- **test:** cases in
  `plugins/php-backend-sdlc/tests/validate-profile.bats` (existing validator
  suite): one passing fixture profile with the key, one failing fixture without
  it asserting the "make map incomplete: 'make.post_review_findings'"
  diagnostic; CI `shellcheck` green.

---

## Epic B — The shared poster `scripts/post-review-findings.sh`

**Goal:** build the new poster as a sibling of `get-pr-comments.sh` with the
full CLI, gating, ledger parse, render, idempotent gh write, authorization,
redaction, degrade matrix, and `--conclusion` aggregation — each behavior added
in a dependency-ordered story with its own bats coverage in
`tests/post-review-findings.bats`.
**Traces:** FR-1..5, FR-7, FR-9, NFR-1..6. **PRD §2.1/§2.3; architecture §2–§7, §12.1.**

> All B stories grow ONE bats suite `tests/post-review-findings.bats` and the
> fixture set under `tests/fixtures/ledgers/` + `tests/fixtures/profiles/`. The
> suite reuses the env-driven `gh` stub (`tests/fixtures/bin/gh`:
> `STUB_GH_OUTPUT`/`STUB_GH_EXIT`/`STUB_GH_LOG`) and the subcommand-routing `gh`
> wrapper technique (`get-pr-comments.bats:1-10,121-137`). Each B story below
> names the specific cases it adds.

### Story B1 — Poster skeleton: header, CLI grammar, repo/PR resolution, capability gate

- **id:** B1
- **title:** `post-review-findings.sh` skeleton — strict mode, lib sourcing, arg parsing, gate-first, degrade-on-missing-externals
- **depends on:** A1–A3 (the gate reads `capabilities.publish_pr_comments`; the key must be schema-valid). Practically buildable in parallel with A but MERGED after A.
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` (new) —
    `#!/usr/bin/env bash`, `set -euo pipefail`, `SCRIPT_DIR` + the
    `# shellcheck source=lib/common.sh` pragma + `source lib/common.sh`
    (architecture §2.1); the **degrade-first contract header block** documenting
    the deliberate inverse of `get-pr-comments.sh:40` (NFR-3 AC); the argument
    grammar (architecture §2.2): positional/`--lens`, `--conclusion`, `--pr`
    (numeric guard + `gh pr view` default-resolution + re-validate),
    repeatable `--file`/stdin, `--bot-login`, `--started-at`/`--ended-at`/
    `--duration-seconds`/`--iterations`, `--dry-run`, `--json`, `-h|--help`,
    unknown → `die`; the **capability gate as the FIRST action** (architecture
    §5.1) reading `profile_get … capabilities.publish_pr_comments false`,
    skip-note + `exit 0` when not `true`, BEFORE any `gh` call; the repo-slug +
    PR resolution block (architecture §2.3) with every `die`-on-missing-external
    turned into `log_info … — skipping publish; exit 0`; `command -v gh` checked
    AFTER the gate (D1 precedes D2).
  - `plugins/php-backend-sdlc/tests/post-review-findings.bats` (new) — setup()
    mirroring `get-pr-comments.bats:12-25` (temp git repo + `origin` remote,
    `PATH="$STUBS:$PATH"`, flag-on fixture profile).
  - `plugins/php-backend-sdlc/tests/fixtures/profiles/publish-on.yml`,
    `…/publish-off.yml` (new fixtures).
- **acceptance criteria (FR-1, NFR-6, FR-9 D1/D2/D3 subset):**
  1. `shellcheck -x scripts/post-review-findings.sh` exits 0.
  2. The header block documents the die-vs-degrade contrast with
     `get-pr-comments.sh` (NFR-3 AC).
  3. With the flag false/absent the script makes **zero** `gh` calls and exits 0
     with a skip-note (the gate precedes `gh`).
  4. An unknown argument and an unknown lens both `die` with usage text.
  5. `gh` absent (D2), no PR resolvable (D3) → skip-note + exit 0, never a die.
- **test (cases added to `tests/post-review-findings.bats`):** `shellcheck -x`
  release gate (CI `shellcheck` job); gating-OFF → skip-note + exit 0 + zero gh
  (assert empty `STUB_GH_LOG`); gating-ON proceeds; unknown flag / unknown lens
  → exit 1 usage; D2 (`PATH` without gh) → skip-note exit 0; D3 (no `--pr`,
  routing stub returns empty `gh pr view`) → skip-note exit 0.

### Story B2 — Ledger parse + validation (dual jq/python3 backend) + empty-ledger degrade

- **id:** B2
- **title:** Canonical ledger parse/validate with jq+python3 parity; per-lens die vs conclusion skip; empty-ledger D4
- **depends on:** B1
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` — add the ledger
    reader (`--file` repeatable + stdin / `-`), the `raw_is_json` + shape-guard
    discipline ported from `get-pr-comments.sh:113-130,152-260` (top-level
    object, `lens` present + string, `findings` array; absent ⇒ `[]`); both
    backends behind `command -v jq` (architecture §2.4/§3.3). Per-lens malformed
    ledger → hard `die` with `[php-sdlc][ERROR]`; `--conclusion` malformed/absent
    ledger → per-ledger skip-note + zero row (deferred wiring lands in B6, but
    the parse contract is here). Empty ledger (zero findings) → D4 skip-note +
    exit 0 (no empty comment).
  - `plugins/php-backend-sdlc/tests/fixtures/ledgers/full.json`,
    `minimal-required.json`, `empty.json`, `not-json.txt`,
    `wrong-toplevel.json` (array/scalar), `missing-lens.json` (new fixtures).
- **acceptance criteria (FR-3, FR-9 D4 subset):**
  1. A full fixture ledger and a minimal (required-fields-only) fixture both
     parse without error.
  2. A non-JSON file, an array/scalar top-level, and a `lens`-less object are
     each rejected (per-lens mode) with a `[php-sdlc][ERROR]` diagnostic and
     exit 1 — never a jq parse error or python traceback.
  3. An empty ledger (zero findings) is the D4 degrade: skip-note + exit 0 +
     zero `gh` write calls — NOT an error and NOT an empty comment.
  4. The jq and python3 parse paths agree (no divergence with jq removed).
- **test:** bats cases — minimal-required renders (paired with B3's render but
  the parse half asserted here); malformed per-lens ledger → `die` exit 1
  `[php-sdlc][ERROR]` no traceback (jq and python paths); empty ledger → D4
  skip-note exit 0 zero writes.

### Story B3 — Per-lens render: dedup, severity order, `n/a` placeholders, dropped subsection

- **id:** B3
- **title:** Per-lens consolidated Markdown render with `(cwe,location,endpoint)` dedup + severity ordering, jq/python byte-identical
- **depends on:** B2
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` — add the render
    (architecture §9): hidden marker `<!-- sdlc-review:<lens> -->` as first line,
    header naming the lens + PR, the severity-ordered table (Critical→High→
    Medium→Low, rank 0..3, unknown=99; stable secondary sort `id` then
    `location` so both backends agree byte-for-byte), dedup by the tuple
    `(cwe, location, endpoint)` with absent fields tupled as `""`, absent
    optional fields rendered as `n/a` (never literal `null`), a "Dropped / not
    reproduced" subsection for `status == dropped` (never above an open
    finding), and the per-lens summary line (N findings by band; A auto-fixed).
    `--dry-run`/`--json` short-circuit to stdout with zero `gh` calls (still
    honoring the gate from B1).
  - `plugins/php-backend-sdlc/tests/fixtures/ledgers/dedup-pair.json`,
    `mixed-severity.json`, `dropped-and-open.json` (new fixtures).
- **acceptance criteria (FR-4, FR-3 AC subset):**
  1. Two findings sharing `(cwe, location, endpoint)` render ONE row.
  2. A mixed-severity ledger renders Critical first and Low last.
  3. The jq and python3 backends produce byte-identical comment bodies for the
     same ledger (jq removed from `PATH` via the sandbox-bin technique,
     `get-pr-comments.bats:81-98`).
  4. A `dropped` finding never appears above an `open` finding; absent
     `cwe`/`owasp` render as `n/a`, never `null`.
- **test:** bats cases — render full ledger (`--dry-run`): marker + ordered
  table + summary, zero gh; minimal render: `n/a` not `null`; jq-vs-python3
  byte-identical (`--json`/`--dry-run` with jq removed); dedup-pair → one row;
  mixed-severity order; dropped-never-above-open.

### Story B4 — Idempotent marker create-vs-update gh algorithm + duplicate-marker recovery + degrade D5/D7

- **id:** B4
- **title:** REST list→marker+author match→PATCH-else-POST; never `--edit-last`; duplicate collapse via `minimizeComment`; D5/D7 degrade
- **depends on:** B3 (render produces the body the write path posts)
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` — add the
    create-vs-update algorithm (architecture §4.2): resolve `POSTING_LOGIN`
    once (`gh api user --jq .login`, `--bot-login` override; empty → marker-only
    match with a warn); list `gh api --paginate repos/{o}/{r}/issues/{pr}/comments`
    guarded by the `raw_is_json` + shape guard (D5: non-JSON / error envelope →
    `log_warn` fall back to CREATE); find matches by marker(lens) ∈ body AND
    `lower(login)==lower(POSTING_LOGIN)`; CREATE
    `gh api -X POST …/issues/{pr}/comments -f body=@-` when no match, UPDATE
    `gh api -X PATCH …/issues/comments/{id} -f body=@-` (oldest by id) on exactly
    one, CORRUPTION-RECOVERY (edit oldest + `minimizeComment` the rest via
    GraphQL) on duplicates; body via `-f body=@-` (stdin, off argv); NEVER
    `gh pr comment --edit-last` (lens-unsafe); write failure (D7) → `log_warn`,
    exit 0, no retry/backoff. Bounded to O(lenses) gh calls (NFR-2).
- **acceptance criteria (FR-2, NFR-2, FR-9 D5/D7 subset):**
  1. First run logs exactly one `api -X POST …/comments` and zero PATCH
     (`STUB_GH_LOG`).
  2. Second run, against a list response already containing the marker'd +
     author-matched comment, logs exactly one `api -X PATCH …/comments/<id>` and
     zero POST.
  3. A list with two marker'd, author-matched comments PATCHes the oldest, emits
     ≥1 `minimizeComment`, never creates a third.
  4. No run emits `gh pr comment --edit-last`.
  5. D5 (non-JSON list read) → warn + fall back to CREATE + exit 0; D7
     (`STUB_GH_EXIT` non-zero on the write) → warn + exit 0.
  6. gh call count per lens does not grow with finding count.
- **test:** bats cases (subcommand-routing `gh` wrapper for the list→edit
  two-response path) — idempotent CREATE; idempotent UPDATE; duplicate-marker
  collapse (one PATCH + ≥1 `minimizeComment`, never a third); never
  `--edit-last`; D5 malformed list → create fallback; D7 write failure → warn
  exit 0; call-count-bounded assertion.

### Story B5 — Authorization (base-repo verify) + secret redaction + degrade D6

- **id:** B5
- **title:** In-scope-only base-repo authorization (refuse third-party/fork-base) + documented secret-shape redaction before render
- **depends on:** B3 (redaction runs before render), B4 (auth gates the write path)
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` — add the
    authorization check (architecture §5.2): read
    `gh api repos/{o}/{r}/pulls/{pr} --jq .base.repo.full_name`; when it differs
    from the resolved `OWNER/NAME` (case-insensitive via a tiny `lower` helper),
    `log_warn` refuse-note + exit 0 with ZERO write calls (D6, R3); when
    unreadable, refuse-with-note. Add the redaction pass (architecture §5.3,
    §5 table) applied to every finding's `summary`/`location`/`endpoint`/
    reproduction text BEFORE render: the six documented shapes (AWS access-key
    id, JWT, `password=`/`secret=`/`token=`/`apikey=` assignments,
    `scheme://user:pass@host` URL creds, `gh[pousr]_` tokens, bounded
    high-entropy run applied LAST), identical ordered list in jq `gsub` and
    python `re.sub` so a redacted body is byte-identical across backends. The
    author filter from B4 uses `POSTING_LOGIN` so a human comment that merely
    quotes the marker is never edited (R7).
  - `plugins/php-backend-sdlc/tests/fixtures/ledgers/secret-laden.json` (new
    fixture: a `summary` carrying an AWS key, a JWT, a `password=...`, and a
    `scheme://user:pass@host` URL).
- **acceptance criteria (FR-7, NFR-5, FR-9 D6 subset):**
  1. A `--pr` whose resolved base repo differs from the origin/`gh`-resolved
     `OWNER/NAME` → refuse-note + exit 0 + ZERO `gh` write calls (the
     `STUB_GH_LOG` shows the list/base read but no POST/PATCH).
  2. The update path never selects a comment whose author differs from
     `POSTING_LOGIN`.
  3. A secret-laden ledger renders with the AWS key, JWT, `password=...`, and
     `://user:pass@` each masked and the cleartext absent from the body.
  4. Redaction is byte-identical across the jq and python3 backends.
- **test:** bats cases — D6 base-repo mismatch (routing stub returns a different
  base slug) → refuse-note exit 0 zero writes; redaction of each shape →
  cleartext absent; author-filter (a marker'd comment by a non-posting login is
  not selected for UPDATE → a CREATE happens instead).

### Story B6 — `--conclusion` aggregation + wrap-safe `num_add` helper + duration/iterations sources

- **id:** B6
- **title:** Aggregate the three lens ledgers into one idempotent conclusion comment with wrap-safe counts, duration, iterations; zero-row for missing lens
- **depends on:** B2 (parse), B3 (render conventions), B4 (idempotent write), B5 (redaction reused)
- **files touched:**
  - `plugins/php-backend-sdlc/scripts/lib/common.sh` — add the wrap-safe
    `num_add A B` digit-string addition helper next to `strip_zeros`/`num_gt`/
    `num_lt` (`common.sh:37-58`), shared so the poster and any future caller use
    one implementation (architecture §7.3). NEVER bash `(( ))`.
  - `plugins/php-backend-sdlc/scripts/post-review-findings.sh` — add the
    `--conclusion` mode (architecture §7): read the three lens ledgers (one
    `--file` per lens, or an array file, or stdin array), render the
    `<!-- sdlc-review:conclusion -->` comment — findings-by-lens×severity matrix,
    auto-fixed-with-regression-test counts by lens, iterations (per-lens +
    overall from `--iterations`), and duration (priority:
    `--duration-seconds` → `--started-at`/`--ended-at` delta → ledger
    min/max → `n/a`), human-readable (`<h>h <m>m <s>s`). ALL counts/totals
    accumulated via the wrap-safe `strip_zeros`/`num_add` helpers (the
    jq/python backends only extract+group raw values; totals summed in shell);
    `dropped`-status findings excluded from counts; a lens with no/malformed
    ledger contributes a ZERO row (not a missing one). Idempotent by the §4
    marker mechanism (reuses B4).
  - `plugins/php-backend-sdlc/tests/fixtures/ledgers/conclusion-security.json`,
    `conclusion-frnfr.json`, `conclusion-codereview.json`,
    `bignum-count.json` (a 20-digit finding count) (new fixtures).
- **acceptance criteria (FR-5, NFR-4 AC subset):**
  1. Given three fixture ledgers, the conclusion's per-lens severity counts
     equal the source findings; the auto-fixed count equals the number of
     `auto_fixed:true`-with-`regression_test` findings, by lens.
  2. A ledger with a 20-digit finding count does NOT wrap the rendered total
     (wrap-safe digit-string math); a code-grep shows no `(( ))` over finding
     counts or timestamps.
  3. The duration renders from `--started-at`/`--ended-at`, falls back to ledger
     min/max, and renders `n/a` when neither is available.
  4. A lens with a missing/malformed ledger renders a zero row, not a missing
     one.
  5. A second `--conclusion` run UPDATEs the existing conclusion comment (PATCH,
     not a second POST).
- **test:** bats cases — conclusion math (per-lens severity counts + auto-fixed
  equal source); wrap-safe 20-digit total; conclusion idempotent (second run →
  PATCH); zero-row for missing lens; duration `--started-at`/`--ended-at` →
  human-readable delta + ledger fallback + `n/a` path. Plus a `num_add` unit
  case in `plugins/php-backend-sdlc/tests/common.bats` (existing common.sh
  suite) covering carry, leading-zero strip, and a long-digit-string sum.

### Story B7 — Install-cache integrity + final degrade-matrix sweep

- **id:** B7
- **title:** `CLAUDE_PLUGIN_ROOT` install-cache run + a single bats sweep asserting all seven FR-9 degrade rows exit 0
- **depends on:** B1–B6
- **files touched:**
  - `plugins/php-backend-sdlc/tests/post-review-findings.bats` — add the
    install-cache case (copy the plugin tree, run via `CLAUDE_PLUGIN_ROOT`,
    `get-pr-comments.bats:139-146`) and a consolidating sweep that exercises each
    of the seven degrade rows (D1 flag-off, D2 gh-absent, D3 no-PR, D4
    empty-ledger, D5 malformed list, D6 base-repo mismatch, D7 write-failure)
    and asserts every one ends `exit 0` with the documented note and zero
    loop-failing exits. (No new script logic — this story is the NFR-3/NFR-8
    evidence consolidation.)
- **acceptance criteria (FR-9, NFR-3, NFR-8 AC subset):**
  1. The poster runs from a simulated install cache via `CLAUDE_PLUGIN_ROOT` and
     produces the expected render/skip behavior.
  2. Each of the seven FR-9 degrade rows produces the documented note and exits
     0; none returns a non-zero loop-failing exit.
- **test:** the bats `tests/post-review-findings.bats` install-cache case + the
  seven-row degrade sweep, green in the CI `bats` job (`ci.yml:112`).

---

## Epic C — Skill Publish steps + orchestrator conclusion wiring

**Goal:** wire a short, gated Publish step into each of the three review skills
and a single conclusion post into the `/sdlc-review` orchestrator, each citing
the two new profile keys, staying ≤ ~500 lines, and keeping `markdown-lint` /
`frontmatter-check` / `profile-keys-check` / `generalization-audit` green.
**Traces:** FR-6, FR-10, NFR-1, NFR-7, NFR-8. **PRD §2.2/§2.3; architecture §8, §10.**

> Every C story depends on **Epic A** (keys exist in the schema, else
> `profile-keys-check` fails) and **Epic B** (the poster exists). The three
> skill stories (C1–C3) are mutually independent. C4 (orchestrator) depends on
> B6 (`--conclusion`).

### Story C1 — `security-audit/SKILL.md` Publish step (security lens)

- **id:** C1
- **title:** Add a gated `### 5.7 Publish` step to security-audit + cite both keys
- **depends on:** A1 (+A2/A3), B1–B5
- **files touched:**
  - `plugins/php-backend-sdlc/skills/security-audit/SKILL.md` — add a
    `### 5.7 Publish (gated)` step after §5.4 aggregate / at loop close
    (architecture §8.1) emitting the `security` lens ledger from the promoted
    finding records to `${SDLC_LEDGER_DIR:-.sdlc/review-ledgers}/security.json`,
    then invoking the poster resolved via `make.post_review_findings` (null →
    `${CLAUDE_PLUGIN_ROOT}/scripts/post-review-findings.sh security --file … --pr "$PR"`);
    reuse the §5.4 `(cwe, location, endpoint)` dedup-tuple language; state the
    gate + degrade contract in one line. Add
    `capabilities.publish_pr_comments` and `make.post_review_findings` to the
    `## Profile keys consumed` header (`security-audit/SKILL.md:8-21`).
- **acceptance criteria (FR-6 AC subset):**
  1. The Publish step gates on `capabilities.publish_pr_comments` and
     skip-with-notes when false/absent.
  2. It resolves the poster via `make.post_review_findings` (null → plugin
     script) and passes the `security` lens arg + the ledger + `--pr`.
  3. It states the degrade-with-note contract (NFR-3).
  4. Both new keys appear under `## Profile keys consumed`.
  5. The file stays ≤ ~500 lines.
- **test:** CI `markdown-lint`, `frontmatter-check`, `generalization-audit`, and
  `profile-keys-check` green on the edited skill (`profile-keys-check` now
  passes because A1 landed the schema rows); `wc -l` ≤ ~500 verified in review.
  (Python prompt-quality re-judge of this file is Epic D.)

### Story C2 — `bmad-fr-nfr-review-gate/SKILL.md` Publish step (fr-nfr lens)

- **id:** C2
- **title:** Add a gated `## Publish` section to the FR/NFR gate skill + cite both keys
- **depends on:** A1 (+A2/A3), B1–B5
- **files touched:**
  - `plugins/php-backend-sdlc/skills/bmad-fr-nfr-review-gate/SKILL.md` — add a
    `## Publish (gated)` section where the gate already posts (Workflow step 9 /
    the existing comment-on-FAIL behavior, architecture §8.2) emitting the
    `fr-nfr` lens ledger from the gate findings / per-requirement matrix to
    `${SDLC_LEDGER_DIR:-…}/fr-nfr.json`, then invoking the poster (null-substitution
    prose mirroring the existing `make.pr_comments` pattern); note the gate's
    commit-status stays the durable success signal and the Publish comment is an
    additional consolidated view. Add both keys to `## Profile keys consumed`
    (`bmad-fr-nfr-review-gate/SKILL.md:16-30`).
- **acceptance criteria (FR-6 AC subset):** same four-part contract as C1, with
  the `fr-nfr` lens arg; both new keys listed; the make-null-substitution branch
  is shown (so the profile-key-branching judge dimension sees both branches);
  file ≤ ~500 lines; the prose states the comment supplements (does not replace)
  the commit status.
- **test:** CI `markdown-lint`, `frontmatter-check`, `generalization-audit`,
  `profile-keys-check` green on the edited skill; `wc -l` ≤ ~500.

### Story C3 — `code-review/SKILL.md` Publish step (code-review lens)

- **id:** C3
- **title:** Add a gated `### Step 5b: Publish findings` to code-review + cite both keys
- **depends on:** A1 (+A2/A3), B1–B5
- **files touched:**
  - `plugins/php-backend-sdlc/skills/code-review/SKILL.md` — add a
    `### Step 5b: Publish findings (gated)` after Step 5 / before Step 6
    (architecture §8.3) emitting the `code-review` lens ledger from the
    priority/disposition categorization + evidence-ledger dispositions
    (`fixed`=commit, `dropped`=decline/stale) to
    `${SDLC_LEDGER_DIR:-…}/code-review.json`, then invoking the poster
    (null-substitution prose mirroring the existing `get-pr-comments.sh`
    substitution at `:50,244-249`). Add both keys — a `capabilities.*` line and
    the two keys on the `make.*` line — to `## Profile keys consumed`
    (`code-review/SKILL.md:8-16`).
- **acceptance criteria (FR-6 AC subset):** same four-part contract as C1, with
  the `code-review` lens arg; both new keys listed; file ≤ ~500 lines.
- **test:** CI `markdown-lint`, `frontmatter-check`, `generalization-audit`,
  `profile-keys-check` green on the edited skill; `wc -l` ≤ ~500.

### Story C4 — `/sdlc-review` orchestrator: timing capture + single conclusion post

- **id:** C4
- **title:** Capture loop start/end in `/sdlc-review` and post the conclusion exactly once at loop close
- **depends on:** B6 (`--conclusion` mode), C1–C3 (the per-lens ledgers the conclusion aggregates)
- **files touched:**
  - `plugins/php-backend-sdlc/commands/sdlc-review.md` — capture
    `REVIEW_STARTED_AT` at the stage-entry "First action" block
    (`sdlc-review.md:20-38`) and `REVIEW_ENDED_AT` at loop close
    (`sdlc-review.md:170-178`) using `date -u +%Y-%m-%dT%H:%M:%SZ`; add a short
    slot in the "Loop & exit condition" section (`:170-187`), gated on
    `capabilities.publish_pr_comments`, invoking the poster's `--conclusion`
    mode EXACTLY once at loop close (NOT per iteration) with the three lens
    ledgers, `--pr`, `--started-at`/`--ended-at`, and the existing
    `--iterations "$ITERATION"` counter (architecture §10.2); state the
    degrade-with-note contract; describe the conclusion as a post-EXIT side
    effect (not part of the exit predicate); no `/sdlc-finish-pr` hand-off
    double-post (OQ-1). Respect the command's existing `allowed-tools`
    (`sdlc-review.md:4` — `Bash` already present, no new tool).
- **acceptance criteria (FR-10, NFR-2 AC subset):**
  1. The command documents capturing loop start/end.
  2. A single `--conclusion` post at loop close, gated on
     `capabilities.publish_pr_comments`, passing the captured duration and
     iteration count.
  3. The conclusion-post slot states the degrade-with-note contract and is
     described as a post-exit side effect (the single exit condition stays
     unmuddied).
  4. No second conclusion post is described for the `/sdlc-finish-pr` hand-off.
- **test:** CI `markdown-lint` + `frontmatter-check` green on the edited command;
  python prompt-quality `exit-condition-consistency` (J4) dimension stays high
  (Epic D); a grep confirms a single `--conclusion` invocation and the
  gating/degrade lines.

---

## Epic D — Cross-tier quality tests (python prompt-quality + LLM-judge)

**Goal:** prove the three edited skills + the command still pass the
deterministic lint tier and score ≥ floor on the judge dimensions, and add the
domain LLM-judge tier over the Publish contracts. (The bats tier lands
per-story inside Epics B/C; this epic is the remaining two tiers from FR-11.)
**Traces:** FR-11, NFR-7. **PRD §2.4/FR-11; architecture §12.2, §12.3.**

> Every D story depends on Epic C (the edited skills/command are the judge
> inputs).

### Story D1 — Python prompt-quality re-judge + lint over the edited skills/command

- **id:** D1
- **title:** Re-judge the three edited SKILL.md + the command; pass lint + the critical judge dimensions
- **depends on:** C1–C4
- **files touched:**
  - `tools/plugin-quality/judge/` config/manifest (the list of files judged) —
    ensure the three edited skills are (re-)judged against `rubrics.py`
    dimensions, especially `degrade-path-soundness` (J3, critical, floor 4),
    `profile-key-branching` (J6, floor 4 — both new keys must BRANCH: flag-on
    publishes, flag-off skip-notes; `make.post_review_findings` null → script vs
    non-null → target), `exit-condition-consistency` (J4, the command edit),
    `root-cause-culture` (J9), `trigger-specificity`/`body-description-fidelity`.
  - (No edits to `lint/check_*.py` expected — the deterministic lint tier
    [frontmatter, descriptions, generalization, references, escalation] runs
    over the edited files unchanged; this story confirms green.)
- **acceptance criteria (FR-11 AC subset):**
  1. The deterministic lint tier passes on the three edited skills + the
     command.
  2. The judge scores the Publish-step dimensions
     (degrade-path-soundness, profile-key-branching, exit-condition-consistency)
     ≥ their floors.
- **test:** `tools/plugin-quality` lint run green; `tools/plugin-quality` judge
  run reporting the cited dimensions ≥ floor on the three edited skills and the
  command; `profile-keys-check` + `generalization-audit` green (re-confirmed).

### Story D2 — LLM-judge tier over the Publish-step contracts

- **id:** D2
- **title:** Add an LLM-judge tier asserting gating / idempotency / authorization / redaction / degrade in the edited skills + poster header
- **depends on:** C1–C4, B1–B6 (the poster header is judge evidence)
- **files touched:**
  - a new domain LLM-judge harness modeled on the
    `tools/security-audit-validation/judge/` precedent (`run_seed_judge.py`) —
    judges the edited skills' Publish step (and the poster header block §2.1/
    §5.3) for the five contracts: **gating** (default-off, flag-first),
    **idempotency** (marker + update-not-spam), **authorization**
    (in-scope-only, base-repo verify), **redaction** (documented secret set),
    **degrade** (every matrix row exits 0). Place under
    `tools/publish-review-validation/judge/` (or extend the existing harness;
    the path is an implementation choice consistent with the precedent).
- **acceptance criteria (FR-11 AC subset):**
  1. An LLM-judge tier exists and consumes the edited `SKILL.md` Publish slots +
     the poster header as evidence.
  2. It judges the five contracts (gating, idempotency, authorization,
     redaction, degrade) and passes on the shipped slots/header.
- **test:** the LLM-judge harness runs (claude CLI, as the security-audit
  precedent does) and reports a pass on the five contracts for the three edited
  skills + the poster header.

---

## Story-to-requirement traceability

| Story | Title (short) | FR/NFR covered |
|---|---|---|
| A1 | schema doc keys | FR-8, NFR-1, NFR-7 |
| A2 | generator emits keys | FR-8, NFR-7 |
| A3 | validator requires make key | FR-8, NFR-7 |
| B1 | poster skeleton + gate-first | FR-1, NFR-6, FR-9 (D1/D2/D3), NFR-3, NFR-1 |
| B2 | ledger parse/validate + empty degrade | FR-3, FR-9 (D4), NFR-1 |
| B3 | per-lens render (dedup/order) | FR-4, FR-3, NFR-1 |
| B4 | idempotent marker create/update | FR-2, NFR-2, FR-9 (D5/D7), NFR-3 |
| B5 | authorization + redaction | FR-7, NFR-5, FR-9 (D6) |
| B6 | conclusion + wrap-safe num_add | FR-5, NFR-4, NFR-2 |
| B7 | install-cache + degrade sweep | FR-9, NFR-3, NFR-8 |
| C1 | security-audit Publish step | FR-6, NFR-7, NFR-1 |
| C2 | fr-nfr-gate Publish step | FR-6, NFR-7, NFR-1 |
| C3 | code-review Publish step | FR-6, NFR-7, NFR-1 |
| C4 | orchestrator conclusion wiring | FR-10, NFR-2, NFR-7, NFR-1 |
| D1 | python prompt-quality re-judge | FR-11, NFR-7 |
| D2 | LLM-judge Publish contracts | FR-11 |

Reverse check: every FR (1–11) and NFR (1–8) is covered by at least one story.
FR-1→B1; FR-2→B4; FR-3→B2/B3; FR-4→B3; FR-5→B6; FR-6→C1/C2/C3; FR-7→B5;
FR-8→A1/A2/A3; FR-9→B1/B2/B4/B5/B7; FR-10→C4; FR-11→B/C bats + D1/D2.
NFR-1→A1/B*/C*; NFR-2→B4/B6/C4; NFR-3→B1/B4/B7; NFR-4→B6; NFR-5→B5;
NFR-6→B1; NFR-7→A*/C*/D1; NFR-8→B7 (+ unchanged `component-counts.bats`).

## Definition of done (per story)

A story is done when: its named files are changed exactly as scoped; its
acceptance criteria are demonstrably met; its named test is present and green
(or, for doc/skill stories, the named CI jobs are green); and it introduces no
source-project literal outside a `# profile-example` fence (NFR-1 /
`generalization-audit`). No story adds a command, agent, or skill — component
counts stay 8/7/22 (NFR-8), so `tests/component-counts.bats` is untouched and
continues to pass.
