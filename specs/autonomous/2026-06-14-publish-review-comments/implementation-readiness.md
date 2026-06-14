---
stepsCompleted: [step-01-init, step-02-context, step-03-dor-checklist, step-04-sequencing, step-05-stacked-branch-retarget, step-06-risks, step-07-go-no-go, step-08-complete]
inputDocuments:
  - specs/autonomous/2026-06-14-publish-review-comments/research.md
  - specs/autonomous/2026-06-14-publish-review-comments/product-brief.md
  - specs/autonomous/2026-06-14-publish-review-comments/prd.md
  - specs/autonomous/2026-06-14-publish-review-comments/architecture.md
  - specs/autonomous/2026-06-14-publish-review-comments/epics.md
  - plugins/php-backend-sdlc/scripts/get-pr-comments.sh
  - plugins/php-backend-sdlc/scripts/lib/common.sh
  - plugins/php-backend-sdlc/scripts/validate-profile.sh
  - plugins/php-backend-sdlc/scripts/generate-profile.sh
  - plugins/php-backend-sdlc/docs/profile-schema.md
  - plugins/php-backend-sdlc/commands/sdlc-review.md
  - plugins/php-backend-sdlc/tests/component-counts.bats
  - .github/workflows/ci.yml
workflowType: 'implementation-readiness'
date: 2026-06-14
author: Winston (BMAD Architect agent, autonomous run)
---

# Implementation Readiness — Publish Review Findings as PR Comments (`php-backend-sdlc`)

This gate confirms the planning chain (`research.md` → `product-brief.md` →
`prd.md` → `architecture.md` → `epics.md`) is internally consistent, buildable,
and verifiable, and that the branch is correctly based for merge. It is the last
artifact before implementation (Ralph / `/sdlc-implement`). The verdict is at
§6. Every checklist item below was verified against the live tree and the prior
artifacts, with line-anchored evidence.

---

## 0. State verified at gate time (live tree, not assumed)

| Fact | Verification | Result |
|---|---|---|
| Branch | `git branch --show-current` | `feature/publish-review-comments` |
| Base relationship | `git merge-base --is-ancestor main HEAD` | **`main` IS an ancestor of HEAD** — the branch is rooted directly on `main`, NOT on a live feature branch |
| Branches containing the fork point | `git branch --contains $(git merge-base HEAD main)` | `main`, `feature/security-audit-skill`, `feature/publish-review-comments` |
| security-audit predecessor | `git log origin/main` | `feature/security-audit-skill` work is reachable from `main`; its PR has merged |
| Open PRs | `gh pr list --state open` | `[]` — no open PR exists for this branch yet |
| `common.sh` helpers | grep | `log_info`/`log_warn`/`die` (`:21-25`), `strip_zeros` (`:39`), `num_gt` (`:46`), `num_lt` (`:58`), `yaml_parses` (`:95`), `profile_path` (`:279`), `profile_get` (`:284`) all present; **`num_add` does NOT yet exist** (B6 adds it) |
| `get-pr-comments.sh` die-on-gh-absent | grep | `command -v gh … || die "gh CLI not found on PATH"` (`:40`) — the contract the poster deliberately inverts |
| `validate-profile.sh` `MAKE_KEYS` | grep `:146-147` | `(ci start tests e2e psalm deptrac phpinsights infection ai_review_loop pr_comments fr_nfr_gate load_tests)` — **lacks both `security` AND `post_review_findings`** |
| `generate-profile.sh` anchors | grep | make heredoc ends at `load_tests:` (`:344`); `capabilities:` block at `:362-363` emits `structurizr` only |
| `profile-schema.md` rows | grep | `make.pr_comments`/`fr_nfr_gate`/`ai_review_loop` (`:76-78`), `make.security` (`:80`), `capabilities.structurizr` (`:127`), `capabilities.dynamic_security_testing` (`:130`) present; the two new keys absent (Epic A adds them) |
| Component counts | `tests/component-counts.bats:51-80` | asserts **8 commands / 7 agents / 22 skills + 2 meta-guides** — must stay unchanged (NFR-8) |
| `/sdlc-review` tools | `sdlc-review.md:4` | `allowed-tools: ["Bash", "Read", "Glob", "Grep", "Task"]` — `Bash` present, the conclusion slot needs no new tool |

**Material correction to the task framing (binding):** the workflow prompt
asserts "this branch is stacked on the security-audit PR; retarget to main per
the stacked-PR gotcha." **That premise is stale.** The branch forks directly
from `main`, the security-audit PR has already merged, and no open PR exists. So
the gotcha's failure mode (content orphaning on a dead base branch) **cannot
occur here** — there is nothing to retarget away from. The actionable residue of
the gotcha is preserved as a pre-merge verification step (§3 sequencing item S0
and §5), not as a rebase/retarget action. See §5 for the full reasoning.

---

## 1. Definition-of-Ready checklist (all must be ✅ to proceed)

### 1.1 Artifact completeness & consistency

- [x] **Research complete** — `research.md` surveys the sibling
  (`get-pr-comments.sh`), the idempotency prior art (marker + find-and-edit vs
  `minimizeComment` vs delete-recreate), 11 risks (R1–R11), and 11 crisp PRD
  findings. ✅
- [x] **Brief goals enumerated** — G1–G10 (idempotent/spam-free, faithful
  render+conclusion, default-off gating, degrade-safe, authorization, redaction,
  wrap-safe math, generalization, clean integration, three-tier tests). ✅
- [x] **PRD requirements numbered + AC'd** — FR-1..11 and NFR-1..8, each with a
  binding, testable **AC:** block; the seven-row degrade matrix is pinned in
  FR-9; out-of-scope is explicit (§6); assumptions A1–A7 carried (§7); eight Open
  Questions raised (§8). ✅
- [x] **Architecture resolves every OQ** — §0 binds OQ-1..7 (conclusion owner =
  `/sdlc-review`; per-lens ledger path + stdin; `gh api user` identity + `--bot-login`
  override; REST for list/create/update, GraphQL only for `minimizeComment`;
  six-shape redaction set; `make.post_review_findings: null` default;
  duration-source priority order). No OQ left open. ✅
- [x] **Architecture pins the buildable surface** — CLI grammar (§2.2), canonical
  ledger schema (§3.1), marker create-vs-update with exact `gh` commands (§4.2),
  gate/auth/redaction (§5), degrade matrix D1–D7 (§6), conclusion math + `num_add`
  (§7), the three exact SKILL.md slots (§8), per-lens render rules (§9),
  orchestrator wiring (§10), schema/generator/validator edits (§11), test plan
  per tier (§12), full traceability (§13). ✅
- [x] **Epics decompose to small, ordered, independently-implementable stories** —
  A1–A3, B1–B7, C1–C4, D1–D2 (16 stories), each with id / title / depends-on /
  files-touched / AC subset / named test; the sequencing spine is explicit
  (`profile keys → poster → wiring → cross-tier tests`). ✅
- [x] **No contradiction across artifacts** — the ledger schema is identical in
  research §2.4/§6.3, PRD FR-3, and architecture §3.1; the degrade rows match
  across PRD FR-9, architecture §6, and the brief; the dedup tuple
  `(cwe, location, endpoint)` is consistent everywhere. ✅

### 1.2 Traceability

- [x] **Forward** — every architecture §maps to ≥1 FR/NFR (architecture §13). ✅
- [x] **Reverse** — every FR-1..11 / NFR-1..8 / OQ-1..7 maps to ≥1 architecture
  section (architecture §13 reverse check) AND ≥1 story (epics
  story-to-requirement table). No orphan requirement, no uncovered goal. ✅
- [x] **Goal → requirement** — PRD §5 maps G1–G10 to FR/NFR; reverse check shows
  every FR/NFR in ≥1 goal row. ✅

### 1.3 Buildability against the live tree (verified, §0)

- [x] **Sibling pattern exists** — `get-pr-comments.sh` is the verbatim template
  for shebang/strict-mode/lib-sourcing, `--pr` flag+validation, origin-then-`gh`
  slug resolution, `raw_is_json`/shape guards, dual jq/python3 backend. ✅
- [x] **`common.sh` provides the gate + log + most arithmetic primitives** —
  `profile_get`/`profile_path`/`yaml_parses`, `log_info`/`log_warn`/`die`,
  `strip_zeros`/`num_gt`/`num_lt` all present. ✅
- [ ] **`num_add` must be ADDED** — `common.sh` has no digit-string ADDITION
  helper; B6 adds it next to `strip_zeros`/`num_gt`/`num_lt` (architecture §7.3).
  This is a known, scoped gap, not a blocker. ⚠ (scheduled in B6)
- [x] **Profile-key conventions exist to mirror** — `capabilities.dynamic_security_testing`
  (default-off bool) and `make.pr_comments`/`make.fr_nfr_gate` (nullable,
  plugin-substitutes) are the exact precedents for the two new keys. ✅
- [x] **bats stub + technique exist** — `tests/fixtures/bin/gh`
  (`STUB_GH_OUTPUT`/`STUB_GH_EXIT`/`STUB_GH_LOG`) and the subcommand-routing
  wrapper documented in `get-pr-comments.bats:1-10,121-137` cover the
  two-response list→edit path the idempotency tests need. ✅
- [x] **python prompt-quality + LLM-judge harnesses exist** —
  `tools/plugin-quality/{judge,lint}` and the
  `tools/security-audit-validation/judge/` precedent for D1/D2. ✅

### 1.4 CI-gate readiness (every job the change must keep green)

- [x] **`manifest-validate`** — no manifest change for a script + skill edits;
  plugin version bump handled at release per the manifest job's semver rule. ✅
- [x] **`markdown-lint`** — three edited SKILL.md + the command + the schema doc
  must lint clean; the slots are short Markdown. ✅
- [x] **`shellcheck -x`** — `post-review-findings.sh` carries the
  `# shellcheck source=lib/common.sh` pragma so `-x` follows the lib (B1 AC). ✅
- [x] **`bats`** — the new `tests/post-review-findings.bats` lands in the
  existing `bats` job; `common.bats` gains a `num_add` case (B6). ✅
- [x] **`frontmatter-check`** — skill `name`/`description` frontmatter untouched;
  meta-guides untouched. ✅
- [x] **`profile-keys-check` (FR-17)** — **ORDER OF OPERATIONS is the live
  hazard**: the schema rows (A1) MUST land in the same change-set as, and be
  merged no later than, the first skill that cites the keys (C1–C3). The epics
  sequencing enforces this (Epic A before Epic C); the DoR flags it explicitly so
  Ralph never commits a cited-but-undeclared key. ✅ (sequencing-enforced)
- [x] **`generalization-audit` (NFR-1/NFR-2)** — denylist
  (`user[-_ ]service`, `mongo…repository`, `apprunner`, `src/user`, `src/oauth`,
  `vilnacrm`); concrete values only inside `# profile-example` fences. The poster,
  its tests, the skill slots, the command edit, and the schema table rows must
  resolve every path/PR/repo from the profile/`gh`/`git`/fixtures. ✅
- [x] **`component-counts.bats` (NFR-8)** — no new command/agent/skill; counts
  stay 8/7/22; the suite is untouched and continues to pass. ✅

### 1.5 Scope discipline

- [x] **No new command surface** (no `/sdlc-publish`); no new agent/skill. ✅
- [x] **One non-degrade case only** — a malformed per-lens ledger FILE is a hard
  `die` (caller passed broken input); everything else degrades to skip/warn +
  exit 0. This distinction is pinned and tested. ✅
- [x] **No `quality.*` change** (raise-only, unrelated). ✅
- [x] **No retry/backoff machinery**; no per-finding comments; no third-party/fork
  posting; no delete-and-recreate. ✅
- [x] **`make.security` pre-existing gap is NOT widened** — architecture §11.2 and
  epics A2/A3 explicitly add ONLY `post_review_findings` to the generator and
  validator, leaving the pre-existing `make.security` omission from `MAKE_KEYS`
  out of scope (verified: `MAKE_KEYS` today lacks both keys). ✅

**DoR verdict:** all items ✅ except one scoped, scheduled gap (`num_add`, B6) and
two sequencing-enforced ordering invariants (A-before-C for `profile-keys-check`;
schema-with-skill for FR-11). None is a blocker. **READY.**

---

## 2. Dependency graph (build order)

```text
Epic A (profile keys)            Epic B (poster)
  A1 schema doc  ──────┐           B1 skeleton+gate ─► B2 parse ─► B3 render ─► B4 gh write
  A2 generator   ──┐   │                                              │           │
  A3 validator   ──┘   │                                B5 auth+redact ┘           │
   (A1►A2►A3)         │                                B6 conclusion+num_add ◄─────┘
                      │                                B7 install-cache + degrade sweep ◄─ B1..B6
                      ▼                                      │
            Epic C (wiring)  ◄── needs A (keys) AND B (poster)
              C1 security-audit Publish ─┐
              C2 fr-nfr Publish          ├─ mutually independent (C1∥C2∥C3)
              C3 code-review Publish    ─┘
              C4 orchestrator conclusion ◄── needs B6 (--conclusion) AND C1..C3 (the ledgers)
                      │
                      ▼
            Epic D (cross-tier tests)  ◄── needs C
              D1 python prompt-quality re-judge + lint
              D2 LLM-judge over the five Publish contracts
```

The bats tier is NOT a separate epic — it grows per-story inside B and C
(B1..B7 each add cases to `tests/post-review-findings.bats`; A2/A3 extend the
generator/validator bats; B6 adds a `num_add` case to `common.bats`). Epic D is
only the python prompt-quality re-judge + the LLM-judge tier.

---

## 3. Sequencing notes (the spine, with the merge-base/retarget item first)

- **S0 — Base/merge hygiene (do this BEFORE opening the PR, replaces the stale
  "retarget" action).** This branch is rooted on `main` and the security-audit PR
  has already merged, so there is **no live base branch to retarget from** and no
  orphaning risk. The residual discipline from the stacked-PR gotcha is a
  pre-merge check, not a rebase: (a) confirm the PR's base is `main` at open time
  (`gh pr create --base main`); (b) before merge, re-run
  `git merge-base --is-ancestor main HEAD` and rebase onto the latest `main` if
  it has advanced, so the feature lands on current `main` (the merged
  security-audit + python-quality work is already present). If a future
  same-stack PR is opened on top of this branch, THEN the gotcha applies to it —
  verify it retargets to `main` (or this branch's merge commit) before merging.
  **No retarget action is required for this PR.** (See §5 for the full analysis.)

- **S1 — Epic A lands first (profile keys).** `profile-keys-check` fails the
  instant a skill cites a key absent from `docs/profile-schema.md`. A1 (schema)
  is the root of the spine; A2 (generator) then A3 (validator) follow so a
  freshly-generated profile already carries `make.post_review_findings` before the
  validator starts requiring it (else A3 would reject A2's own output). A is
  buildable in parallel with B but MUST be merged before C.

- **S2 — Epic B lands next (the poster), in strict internal order.**
  B1 (skeleton + gate-first + degrade-on-missing-externals) → B2 (ledger
  parse/validate + empty-degrade) → B3 (render: dedup, severity order, `n/a`,
  dropped subsection) → B4 (idempotent marker create-vs-update + duplicate
  recovery + D5/D7) → B5 (base-repo authorization + redaction + D6) → B6
  (`--conclusion` + `num_add` + duration/iterations) → B7 (install-cache +
  seven-row degrade sweep). Each story extends one bats suite. B6 is the only
  story that touches `common.sh` (the shared `num_add`); review it for the
  no-`(( ))` invariant (NFR-4) and a `common.bats` unit case.

- **S3 — Epic C wires the skills + orchestrator (needs A AND B).** C1/C2/C3 are
  mutually independent short Publish slots; each cites both new keys under
  `## Profile keys consumed` and stays ≤ ~500 lines. C4 (orchestrator timing +
  single conclusion post at loop close) depends on B6 and on C1–C3 having defined
  the three lens ledger paths. C4 must keep the single stated exit condition
  unmuddied (the conclusion is a post-EXIT side effect, J4 dimension).

- **S4 — Epic D adds the remaining two test tiers (needs C).** D1 re-judges the
  three edited skills + the command against the critical rubric dimensions
  (`degrade-path-soundness` floor 4, `profile-key-branching` floor 4 — both keys
  must BRANCH, `exit-condition-consistency` for the command) and confirms the
  deterministic lint tier green. D2 adds the LLM-judge tier over the five Publish
  contracts (gating / idempotency / authorization / redaction / degrade).

- **S5 — Release.** All seven CI jobs green; bats evidence run documenting render
  → idempotent update-vs-create → dedup → severity order → redaction → gating
  on/off → every degrade row → base-repo refusal → conclusion math; component
  counts unchanged; then open the PR on base `main` and drive CI + AI reviewers
  to green (matching the security-audit predecessor's `/sdlc-finish-pr` flow).

**Critical-path ordering invariants (Ralph must not violate):**
1. **A1 before any of C1–C3** — or `profile-keys-check` red.
2. **A2 before A3** — or the validator rejects generated profiles.
3. **B1–B5 before C1–C3** — the skills invoke the poster behaviors.
4. **B6 before C4** — `--conclusion` must exist for the orchestrator slot.
5. **Schema rows (A1) merge no later than the skill citing them (FR-11).**

---

## 4. Risks & mitigations (carried from research R1–R11, re-pinned with the gate's own additions)

| # | Risk | Mitigation | Owner story / evidence |
|---|---|---|---|
| R1 | Comment spam (re-post each run) | Hidden marker + author-filtered find-and-edit; one comment per lens + one conclusion; assert exactly-one-create-then-update via `STUB_GH_LOG` | B4; bats idempotent CREATE/UPDATE |
| R2 | Secret leakage in a finding body | Six-shape documented redaction set (AWS key, JWT, assignment creds, URL creds, `gh*_` tokens, bounded high-entropy run), applied LAST→first ordered, byte-identical across jq/python | B5; bats redaction-of-each-shape |
| R3 | Posting to a wrong/third-party PR | Base-repo authorization: verify `pulls/{pr}.base.repo.full_name == OWNER/NAME` (case-insensitive) before any write; mismatch → refuse-note, zero writes | B5; bats D6 base-mismatch |
| R4 | Rate/abuse limits | O(lenses) calls (1 list + 1 create-or-update per lens); no retry/backoff; `gh` write failure warns-not-dies | B4; bats D7 + call-count-bounded |
| R5 | Degrade ≠ fail | Default failure mode = skip/warn + exit 0; the script header documents the deliberate inverse of `get-pr-comments.sh:40` so a reviewer never "fixes" it to die | B1 header; bats seven-row sweep B7 |
| R6 | Gating bypass | Capability gate is the FIRST action (before any ledger parse or `gh` call); default-false via `profile_get`; `--dry-run`/`--json` also honor it | B1; bats gating-OFF zero-gh |
| R7 | Editing a human comment that quotes the marker | Author-filter the find to `POSTING_LOGIN` (`gh api user` or `--bot-login`); empty login degrades to marker-only with a warn | B4/B5; bats author-filter case |
| R8 | Wrap/overflow in conclusion math | All counts via `strip_zeros`/`num_add` digit-string arithmetic; NEVER `(( ))`; code-grep gate | B6; bats 20-digit wrap-safe |
| R9 | Source-literal leakage | Profile/`gh`/`git`/fixture resolution only; concrete values only inside `# profile-example` fences | all stories; CI `generalization-audit` |
| R10 | SKILL.md bloat past ~500 lines | Publish slots are short (point at the poster + the gate flag); enumerations stay in the script | C1–C3; review `wc -l` |
| R11 | Malformed `gh` comment-list read | `raw_is_json` + shape guard before trusting the list; non-JSON/error-envelope → warn, fall back to CREATE | B4; bats D5 malformed-list |
| **R12 (gate-added)** | **`profile-keys-check` ordering** — a skill citing a key before the schema row exists | Sequencing invariant 1+5 (A1 before/with C1–C3); DoR §1.4 flags it; the schema row and the citing skill ship together | epics Epic A→C order |
| **R13 (gate-added)** | **`num_add` correctness** (carry, leading-zero strip, long strings) — a new shared primitive in `common.sh` used by all conclusion totals | Pure-string column-add with carry; a dedicated `common.bats` unit case (carry, leading-zero strip, long-digit sum) plus the 20-digit conclusion case; no `(( ))` | B6; `common.bats` + bats wrap-safe |
| **R14 (gate-added)** | **jq/python byte-divergence** — the two backends drift on sort order, `n/a` placeholder, or whitespace, breaking the byte-identical AC | Single total order (severity rank → `id` → `location`), shared `n/a` placeholder, totals summed in shell (not in jq/python) so big-int rendering can't diverge; bats asserts byte-identity with jq removed from `PATH` | B3/B5/B6; bats jq-vs-python case |
| **R15 (gate-added)** | **Stale "stacked-on-security-audit" premise** in the task framing → a needless/wrong retarget | §0 + §5: the branch is already on `main`, security-audit merged, no open PR; no retarget required; the residual check is "confirm base=main + rebase on latest main pre-merge" | S0; §5 |

---

## 5. Stacked-PR gotcha — analysis & disposition (binding)

The user's global memory records a stacked-PR gotcha: *"verify a stacked PR
retargets to main before merging, or its content orphans on the dead base
branch."* The workflow prompt instructed retargeting "to main per the stacked-PR
gotcha." At gate time the live state is:

- `git merge-base --is-ancestor main HEAD` → **true** (main is an ancestor of
  HEAD): the branch is built on `main`, not on `feature/security-audit-skill`.
- The fork point is contained in `main` (and historically in
  `feature/security-audit-skill`), confirming the security-audit work has already
  merged into `main`.
- `gh pr list --state open` → `[]`: this branch has no open PR yet.

**Disposition:** there is **no live base branch to retarget away from and no
orphaning risk** — the gotcha's failure mode (a child PR whose base is a
to-be-deleted feature branch) does not exist here. Retargeting is therefore a
**no-op that must NOT be performed** (forcing a base change where none is needed
risks a spurious rebase). The gotcha is preserved as the §3 S0 pre-merge
discipline:

1. Open the PR with `--base main` (default branch).
2. Before merge, rebase onto the latest `main` if it has advanced.
3. IF a follow-on PR is later stacked on THIS branch, apply the gotcha to that
   child PR — retarget it to `main` (or this branch's merge commit) before
   merging it, so its content does not orphan.

This is recorded so the implementer does not act on the stale premise.

---

## 6. Go / No-Go verdict

### Go criteria (all met)

1. ✅ The full planning chain exists, is internally consistent, and resolves every
   Open Question (architecture §0).
2. ✅ Bidirectional traceability is complete — no orphan FR/NFR, no uncovered goal
   (architecture §13, epics traceability table).
3. ✅ The design is buildable against the live tree: the sibling script, the
   `common.sh` primitives, the profile-key precedents, the bats stub/technique,
   and both judge harnesses all exist and were verified.
4. ✅ Every CI gate the change touches has a concrete, scheduled compliance path
   (DoR §1.4), including the two ordering invariants (`profile-keys-check`,
   FR-11) the sequencing enforces.
5. ✅ All 15 risks (R1–R11 from research + R12–R15 gate-added) have an owning
   story and a test/evidence path.
6. ✅ The base/merge state is correct (rooted on `main`, security-audit merged);
   the stale "retarget" instruction is dispositioned as a no-op + a pre-merge
   check (§5), removing the only ambiguity in the task framing.
7. ✅ Scope discipline holds — no new component (counts stay 8/7/22), one
   non-degrade case only, no `quality.*`/retry/third-party-post changes.

### Conditions to track during build (not blockers)

- C-1: Add `num_add` to `common.sh` in B6 with a `common.bats` unit case (R13).
- C-2: Enforce A-before-C and schema-with-skill ordering (R12); never commit a
  cited-but-undeclared profile key.
- C-3: Assert jq/python byte-identity with jq removed from `PATH` in every render
  case (R14).
- C-4: Keep each edited SKILL.md ≤ ~500 lines (no CI gate — verify in review,
  R10).
- C-5: Open the PR on base `main`; rebase on latest `main` pre-merge (S0); do NOT
  retarget (§5).

### Verdict

**GO.** The plan is ready for implementation. Begin with Epic A (profile keys),
then Epic B (the poster, B1→B7 in order), then Epic C (skill + orchestrator
wiring), then Epic D (python prompt-quality re-judge + LLM-judge), tracking
conditions C-1..C-5. No blocker remains; the single stale assumption in the task
framing (stacked-branch retarget) is corrected and dispositioned.

---

## 7. Executive summary (10 lines)

1. Add one opt-in, default-OFF capability: publish each review lens's findings
   (security, fr-nfr, code-review) as ONE idempotent PR comment + a conclusion.
2. Deliverable = one new `scripts/post-review-findings.sh` (sibling of
   `get-pr-comments.sh`), short gated Publish slots in 3 skills, one orchestrator
   conclusion slot, and 2 profile keys — no new command/agent/skill (counts 8/7/22).
3. Idempotency = hidden `<!-- sdlc-review:<lens> -->` marker + author-filtered
   find-and-edit (REST list → PATCH-else-POST; `minimizeComment` only for
   duplicate-marker recovery); never `--edit-last`.
4. Gated on `capabilities.publish_pr_comments` (default false, gate is the FIRST
   action) + nullable `make.post_review_findings` (plugin substitutes the script).
5. Authorized: writes only to the resolved repo's own PR (base-repo verify);
   secrets redacted via a documented six-shape set, byte-identical across jq/python.
6. Degrade-first (NFR-3): flag off / gh absent / no PR / empty ledger / malformed
   gh read / base mismatch / write failure → skip-or-warn + exit 0, never fail the
   loop — the deliberate inverse of `get-pr-comments.sh:40`, documented in-header.
7. `--conclusion` aggregates the 3 ledgers: counts by lens×severity, auto-fixed
   root-cause-with-regression-test, iterations, duration — all via wrap-safe
   `strip_zeros`/new `num_add` digit-string math, never `(( ))`.
8. Build order: Epic A (keys) → Epic B (poster B1–B7) → Epic C (3 skill slots +
   orchestrator) → Epic D (python re-judge + LLM-judge); bats grows per-story.
9. Branch is rooted on `main`, security-audit already merged, no open PR — the
   "stacked retarget" premise is stale; no retarget needed, just open on base
   `main` and rebase pre-merge.
10. Verdict: **GO** — traceability complete, all 15 risks owned/tested, every CI
    gate has a compliance path; track 5 build-time conditions (num_add, key-order,
    jq/python parity, ≤500-line skills, base-main).
