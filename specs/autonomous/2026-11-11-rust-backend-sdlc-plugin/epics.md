---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
inputDocuments:
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/prd.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/architecture.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/epics.md (depth bar, same artifact kind)
workflowType: 'epics-stories'
project_name: 'rust-backend-sdlc'
date: 2026-11-12
author: BMAD PM/SM agents (bmad-create-epics-and-stories), autonomous run for the main agent acting as user surrogate
mode: autonomous (C menus answered by the surrogate; every decision recorded as an Assumption)
---

# Epics and Stories: `rust-backend-sdlc` Claude Code Plugin

## Overview

This document decomposes the PRD (44 FRs, 16 NFRs) and the architecture (the implementation contract, which wins over the PRD where it says so) into 8 epics, 65 stories and 13 execution waves. Every one of the 283 files of the architecture's plugin tree, plus the 3 repository wiring files, is owned by exactly one story (two single-writer files are section-owned, see A3). Plugin root = `plugins/rust-backend-sdlc/`; "§ X" means the architecture section titled X; "PRD FR-n / AC-n.m" means the PRD item.

> Assumption A1: the BMAD workflow `_bmad/bmm/workflows/3-solutioning/bmad-create-epics-and-stories/` ran non-interactively. Step 1 found `prd.md` and `architecture.md` (no UX document: the plugin has no UI) and extracted the inventory below; step 2 designed the epic list; step 3 wrote the stories; step 4 validated coverage, dependencies and file ownership (results at the end of "FR Coverage Map"). Every menu was answered "C" by the surrogate.
>
> Assumption A2 (epic order = dependency order): the PRD's delivery order (1 setup, 2 new-service, 3 loop commands and agents, 4 skills, 5 review scripts, 6 new-context, 7 docs and wiring, 8 workflows) is resequenced so that no story depends on a later epic: PRD (1) → Epics 1–2, (5) → Epic 3, (4) → Epic 4, (3) → Epic 5, (2)+(6) → Epic 6, (8) → Epic 7, (7) → Epic 8. Reasons: `lint_all.py` rules L19/L20/L21/L23/L24 report a command, agent or skill whose referenced script, skill, link or agent does not exist yet; `/rs-sdlc-new-service` hands its PR to the finish-pr procedure; the release gate pins the final counts and must come last. The PRD's "epic 8" label for the workflow layer maps to Epic 7 here; it stays the cut line (ADR-18 slip clause: remove Epic 7's files and apply the post-cut counts 0 workflows / 15 suites / 8 docs / ≥ 491 tests in Stories 8.4–8.6).
>
> Assumption A3 (single-writer files): `scripts/lib/common.sh` and `tests/common-lib.bats` are written by five stories in five different waves, each owning one named section (`core` 1.6, `command helpers` 2.4, `publishing and model sessions` 3.1, `stage state and resume` 5.1, `Ralph helpers` 5.2), each marked by a `# section: <name>` comment; a later section story appends, never rewrites an earlier section. This is the architecture's "single-writer, serialized" rule and keeps every wave's ownership disjoint. Every other file has exactly one owner, including the shared files `docs/profile-schema.md`, `tests/lib/helpers.bash`, `tests/component-counts.bats`, both `README.md` files, `.github/workflows/ci.yml` and `.claude-plugin/marketplace.json`.
>
> Assumption A4 (sizing): stories target one agent session and 2–8 source files; fixture stories (1.3, 1.4, 1.5, 3.2, 3.5, 7.2–7.5) own more files because each file is a small data file (TOML, YAML, JSON, scenario) written against an exact architecture row.
>
> Assumption A5 (contract suite last): `tests/component-counts.bats` (CC-01 to CC-36) is written once, in Story 8.6, after every component exists. Earlier stories verify with scoped lint, their own suite and the token checks of the verification kit below; every story's acceptance criteria name the CC ids its files must satisfy, so 8.6 finds them satisfied.
>
> Assumption A6: commit subjects in this repository follow § Constraints: `<type>(rust-backend-sdlc): <subject>`, one commit per story or more, never `--no-verify`, never force-push; a defect found by a later story is fixed in the owning story's files by a `fix(rust-backend-sdlc): …` commit.

### Story format (parsed by bmalph)

Epics are `## Epic N: Title` plus one paragraph; stories are `### Story N.M: Title` with, in order: the user story (As a / I want / So that), a `**Read:**` line naming the architecture sections to load (nothing else needs reading), the `**Acceptance Criteria:**` block (one criterion per line, each starting `- Given`, phrased Given/when/then), then `**Files owned:**`, `**Depends on:**`, `**FRs:**` and `**Verification:**`. No heading and no indented line appears inside a story body, so bmalph's parser (`dist/transition/story-parsing.js`) attaches every criterion to the right story and ignores the trailing metadata.

### Shared story contracts

- **SC-SCRIPT** (§ Implementation Patterns › Script conventions, § Script Contracts › Shared contract, ADR-23): shebang `#!/usr/bin/env bash`; header comment with `# <name>.sh — <one line>`, `# Usage: …`, the flag list and `# Exit: 0 …; 1 …; 2 …`; `set -euo pipefail`; `SCRIPT_DIR` resolution; `# shellcheck source-path=SCRIPTDIR` and `# shellcheck source=lib/common.sh` before `source "$SCRIPT_DIR/lib/common.sh"`; `--help` in any position prints the header via `print_usage` and exits 0; unknown flag → `die_usage` exit 2; logs `[rust-sdlc][INFO|WARN|ERROR]` to stderr, handles and data to stdout; writes only documented paths through `safe_write_target` + `atomic_write`; integers through `strip_zeros`/`num_*`; the banned constructs absent (`eval`, `while true`, `until false`, `sed -i`, `readlink -f`, `date -d`, `grep -P`, `stat -c`, `declare -n`, `mapfile -d`); executable bit set (mode 755 in git); no organization token and no template slug anywhere in the file.
- **SC-SUITE** (§ Test Architecture): `load lib/helpers` and `common_setup` in `setup`; test names `@test "<script>: <behaviour>"`; hermetic (stubs on `PATH`, writes under `$BATS_TEST_TMPDIR`, no network); one `--help` case and one unknown-flag case; every documented flag, exit code and refusal has a case; K7 cases call `k7_require <tool>`; permission cases call `skip_if_root`; yq-only cases gate on `have_yq`; a materialized repository lives at `$BATS_TEST_TMPDIR/billing-service`; suite-local helpers stay in the suite (never edit `tests/lib/helpers.bash`); no committed `*.md` fixture (bundles and Markdown are generated at runtime or shipped as `*.md.tpl`).
- **SC-SKILL** (§ Skill Library › Skill anatomy and Final list, § Markdown component conventions › Skills, PRD FR-30): frontmatter exactly `name` (= directory) and `description` (contains "Use when", ≤ 1,536 characters, no `when_to_use`); one H1; first H2 `## Profile keys consumed` listing exactly the keys of the skill's row in § Final list (28 skills), as backticked dotted keys, no file names; for the 11 counterparts (rows 1–5, 11, 14, 16, 18, 21, 22) the second H2 is `## Repository precedence` citing `.claude/skills/<name>/SKILL.md` and `AGENTS.md`; then `## Context`, `## Task`, `## Success criteria`, `## Steps`, `## Constraints`, `## Verification`; an H2 whose text contains "gate"/"gating" names its skip path (`SKIPPED: <reason>`); values only by profile key, concrete values only inside fences whose opening line carries `# profile-example`; the example context written `<group>/<context>` and `<Entity>`; template lists (gate order, protected files, required checks) read at runtime (`make.ci_list`, `cargo xtask config-guard --list`, `docs/repository-settings.md`); relative links only to the skill's own supporting files, sibling skill directories and `../SKILL-DECISION-GUIDE.md`; target-repository files backticked, never linked; no plugin agent named as a backticked agent and no `${CLAUDE_PLUGIN_ROOT}/scripts/`, `${CLAUDE_PLUGIN_ROOT}/commands/` or `subagent_type` string (forbidden edges); P1–P7 only on prohibition lines; every fence has a language; no duplicate heading text.
- **SC-AGENT** (§ Agent Contracts, § Markdown component conventions › Agents, PRD FR-22): frontmatter `name` (= file stem), `description` (contains "Use when" or "Use this agent"), `tools` (comma string) and `model` exactly as the agent's row; H1 `# <name> — <title>`; the 8 H2s in order `Profile keys consumed`, `Role`, `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline` (states `MAX_ITERATIONS=5`), `Smoke prompt` (one happy-path and one degrade-path prompt); git ownership (never `git commit`, `git push`, a label or a `.ralph/` edit; exceptions only as the row states); the protected-change line `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`, a guard-hook denial reported verbatim and never retried through Bash; make-only execution with the ADR-13 closed variable set; every agent that runs `make` carries the background sentence and the container-precondition sentence verbatim; consumed keys declared in `docs/profile-schema.md`; P1–P7 only on prohibition lines; never names `php-implementer`, `react-implementer` or `general-purpose` as a backticked agent.
- **SC-CMD** (§ Command Contracts › Shared command contract and Exit strings, § The canonical escalation block, § Git rules, § Markdown component conventions › Commands, PRD FR-1, FR-2): frontmatter `description` and `argument-hint` byte-equal to the command's contract section, `allowed-tools` only on `rs-sdlc-review` and `rs-sdlc-qa`; one H1 `# rs-sdlc-<stage> — <title>`; H2s `Inputs`, `Procedure`, `Loop & exit condition`, `Iteration guard`, `Failure escalation` in order (extras only after `Procedure`); the first fenced block runs `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"` with the halt wording "run /rs-sdlc-setup on the default branch and commit the result" (except setup and new-service); the background and container-precondition sentences verbatim (every command except `rs-sdlc-issue`); `MAX_ITERATIONS=5`; the 7-field escalation block with the command's stage id; the exit string byte-equal to § Exit strings; agents through the Task tool with `subagent_type: rust-backend-sdlc:<agent>`; commits only as `protected_changes <merge-base-sha>` → `common.sh commit_msg_file '<subject>'` → `git commit -F <path>` (prefix `RUN_IN_CONTAINER=1` only on hooked git in container mode), pushes only `git push -u origin HEAD`; make calls in suffix form with variables only from the closed set (`RUN_IN_CONTAINER COMMIT_TITLE base_ref BREAKING_CHANGE_APPROVED CONFIG_CHANGE_APPROVED group context name SCHEMATHESIS_URL`), every `make validate-configuration` with `base_ref=<…> CONFIG_CHANGE_APPROVED=`; every published body as raw file → `common.sh redact --in … --out target/rust-sdlc/tmp/<name>.md` → `--body-file`/`-F body=@`; the targets-run vocabulary; never applies or removes `approved-config-change`/`approved-breaking-change`; P1–P7 only on prohibition lines; command tokens only the 10 `/rs-sdlc…` stems, plugin commands named in prose where a docs-check-safe text is required.
- **SC-DOC** (§ Documentation Set): markdownlint-cli2 clean with the repository `.markdownlint.yaml`; relative links resolve; every fence has a language; the template slug only inside `# profile-example` fences of `docs/`; command tokens only the 10 stems; outcome words only `SUCCESS`, `SUCCESS-WITH-REPORT`, `ESCALATED`.

### Verification kit

Paste once per shell from the repository root; every story's `**Verification:**` lines call these functions with explicit arguments.

```bash
P=plugins/rust-backend-sdlc
A=specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/architecture.md
# scoped lint: no lint finding on the owned files (regex over paths below the plugin root)
v_lint()      { ! python3 tools/plugin-quality/lint/lint_all.py "$P" | grep -E "^$P/($1)"; }
# same, ignoring L21/L24 (links and skill prose resolved by a later story of the same epic)
v_lint_wave() { ! python3 tools/plugin-quality/lint/lint_all.py "$P" | grep -E "^$P/($1)" | grep -vE '\[S[0-9] L2[14]\]'; }
v_md()        { npx --yes markdownlint-cli2 "$@"; }
v_sh()        { shellcheck -x "$@"; }
v_bats()      { npx --yes bats "$P/tests/$1.bats" && SDLC_FORCE_PYTHON_YAML=1 npx --yes bats "$P/tests/$1.bats" && test "$(grep -c '^@test' "$P/tests/$1.bats")" -ge "$2"; }
v_banned()    { ! grep -nE '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|while true|until false|sed -i|readlink -f|date -d|grep -P|stat -c|declare -n|mapfile -d' "$@"; }
v_gen()       { ! grep -rniE 'vilnacrm|rust-service-template|user[-_ ]service|mongo[a-z][a-z0-9_]*repository|apprunner|src/user|src/oauth' "$@"; }
v_json()      { for f in "$@"; do python3 -m json.tool "$f" >/dev/null || { echo "BAD JSON $f"; return 1; }; done; }
v_ndjson()    { python3 -c 'import json,sys; [json.loads(l) for f in sys.argv[1:] for l in open(f) if l.strip()]' "$@"; }
v_keys()      { for f in "$@"; do awk '/^## Profile keys consumed/{x=1;next}/^## /{x=0}x' "$f" | grep -oE '`(schema_version|[a-z0-9_]+(\.[a-z0-9_<>]+)+)`' | tr -d '`' | sort -u | while read -r k; do grep -qF "\`$k\`" "$P/docs/profile-schema.md" || echo "UNDECLARED $f $k"; done; done | { ! grep .; }; }
v_schema_keys() { grep -oE '^\| `(schema_version|(project|rust|template|framework|persistence|architecture|service|make|quality|ci|review|capabilities)\.[a-z0-9_]+)` \|' "$A" | grep -oE '`[^`]+`' | sort -u | while read -r k; do grep -qF "$k" "$P/docs/profile-schema.md" || echo "MISSING $k"; done | { ! grep .; }; }
v_p17()       { python3 -c 'import re,sys
P=[r"git (commit|push)\b.*(--no-verify|\s-n\b)",r"git push\b.*(--force|--force-with-lease|\s-f\b)",r"git -c core\.hooksPath",r"git config ((--local|--global) )?core\.hooksPath",r"bmalph implement.*--force",r"#\[allow|#\[mutants::skip\]|#\[coverage\(off\)\]|exclude_re|exclude_globs|--ignore-filename-regex",r"bypassPermissions"]
bad=[f"{f}:{i}" for f in sys.argv[1:] for i,l in enumerate(open(f),1) if any(re.search(p,l) for p in P) and not re.search(r"never|Never|forbidden|decline",l)]
print("\n".join(bad)); sys.exit(1 if bad else 0)' "$@"; }
v_cmdtok()    { grep -rhoE '(^|[[:space:]`(])/(rs-)?sdlc[a-z-]*' "$@" | sed -E 's/^[[:space:]`(]//' | sort -u | grep -vxE '/rs-sdlc(-(setup|new-service|new-context|issue|plan|implement|review|qa|finish-pr))?' | { ! grep .; }; }
v_sent()      { local bg ct; bg=$(grep -oE 'Every `make` call except the foreground allowlist `make\.ci_list`[^"]*' "$A" | head -1); ct=$(grep -oE 'In container mode, before the first make target[^"]*' "$A" | head -1); for f in "$@"; do grep -qF -- "$bg" "$f" || echo "NO-BACKGROUND-SENTENCE $f"; grep -qF -- "$ct" "$f" || echo "NO-CONTAINER-SENTENCE $f"; done | { ! grep .; }; }
v_esc()       { for f in "$@"; do for k in '=== SDLC ESCALATION ===' 'stage: ' 'iteration: ' 'exit_condition: ' 'status: NOT MET' 'blocking_finding: ' 'iteration_log: ' 'recommended_action: ' '=== END ==='; do grep -qF -- "$k" "$f" || echo "MISSING '$k' $f"; done; done | { ! grep .; }; }
v_exit()      { local s; s=$(awk -F' [|] ' -v id="\`$1\`" '$1 == "| " id {print $2; exit}' "$A"); test -n "$s" && shift && for f in "$@"; do grep -qF -- "$s" "$f" || echo "EXIT-STRING MISSING $f"; done | { ! grep .; }; }
v_suffix()    { ! grep -nE 'RUN_IN_CONTAINER=1 make|COMMIT_TITLE=[^ ]* make' "$@"; }
v_clock()     { ! grep -nE 'Date\.now|Math\.random|new Date\(\)' "$@"; }
v_wf()        { local n=0 s; for s in "$P/tests/fixtures/workflows/$2"-*.json; do node "$P/tests/lib/workflow-harness.mjs" "$P/workflows/$1.js" "$s" >/dev/null || { echo "FAIL $s"; return 1; }; n=$((n+1)); done; test "$n" -eq "$3"; }
```

## Requirements Inventory

### Functional Requirements

- FR-1: Shared command contract: frontmatter, 5-H2 spine, profile validation first, `MAX_ITERATIONS=5`, 7-field escalation, handles, make-only execution with the container route, background-and-poll rule (600 s cap), raw-call exception list, Docker-less classification, targets-run vocabulary.
- FR-2: Hook-valid git: subject `<type>(#N): <subject>`, issue-number derivation order (never the PR number), branch `<type>/<N>-<slug>`, fixed subjects, pre-validation, hooks never bypassed, commands own every commit and push.
- FR-3: `/rs-sdlc` orchestrator: 8-row stage table, issue state comment, PA-7 resume computed by `resume_point`, 8-field run report.
- FR-4: `/rs-sdlc-setup`: steps 1–9, protected-settings rule, `--exec` pass-through, idempotent second run.
- FR-5: Profile `.claude/rust-sdlc.yml` schema v1: 115 keys in 13 groups, null means absent, omitted means error.
- FR-6: `generate-profile.sh`: file-only detection, fallbacks, CI-check derivation, container precedence, emission format, diff/keep/refresh/stdout modes.
- FR-7: `validate-profile.sh`: rules V1–V12, tighten-only bounds, wrap-safe numbers, one line per violation.
- FR-8: `inject-governance.sh`: one docs-check-safe managed block in `CLAUDE.md`/`AGENTS.md`, repair, placement outside the verification markers, byte-stable.
- FR-9: `merge-settings.sh`: union-only allowlist (and, as amended, plugin deny entries) in `.claude/settings.local.json`; protected shared settings refused.
- FR-10: `setup-preflight.sh`: ordered checks with floors, WARN/INFO rules, `--report` table.
- FR-11: `/rs-sdlc-new-service`: S1–S14, GitHub and local modes, identity defaults, `--exec`, `--dry-run`, hand-off to finish-pr.
- FR-12: `new-service.sh`: source and customize phases, docs-check citation repair, idempotent, never commits or pushes.
- FR-13: `config/new-service.defaults.json`: default template slug and four defaults outside the scanned directories; override order.
- FR-14: `/rs-sdlc-new-context`: live-tree name validation, `make new-context`, checklist C1–C12, context gate set, hand-off.
- FR-15: `/rs-sdlc-issue`: issue with ≥ 3 testable criteria and the managed label, or adoption of an existing issue.
- FR-16: `/rs-sdlc-plan`: non-interactive bundle under `specs/<N>-<slug>/` with the `## Constraints` channel into Ralph, readiness self-check, commit.
- FR-17: `stage-planning-artifacts.sh`: staging for bmalph with pre-checks and refusals.
- FR-18: `/rs-sdlc-implement`: hooks, staging, `bmalph run --driver claude-code`, single implementer, breaker never reset, post-loop subject and coverage checks.
- FR-19: `/rs-sdlc-review`: 28-skill triage, three lenses, quality rows Q1–Q15, FR/NFR gate loop, ledgers.
- FR-20: `/rs-sdlc-qa`: boot, migrate, liveness poll, REST/GraphQL/health probes, evidence, verdict.
- FR-21: `/rs-sdlc-finish-pr`: PR create/edit, sensor loop with counters A/B/C/W/R, degrades.
- FR-22: Shared agent contract (8 H2s, git ownership, protected-change line, make-only).
- FR-23: `rust-implementer` (sonnet) rules.
- FR-24: `code-quality-reviewer` (opus): Q1–Q15 verdicts, no suppressions.
- FR-25: `fr-nfr-reviewer` (opus): requirement matrix, gate handle, fail-closed degrades.
- FR-26: `qa-manual-tester` (sonnet, `Bash, Read`): black-box only.
- FR-27: `ci-fixer` (sonnet): check → gate id → target mapping, human-gated rule.
- FR-28: `pr-comment-resolver` (sonnet): fix or reasoned reply, six decline categories.
- FR-29: `security-auditor` (opus): lanes, families, loopback-only probes.
- FR-30: Skill library of 28 skills with the common format and counterparts.
- FR-31: Rust-only skills with their mandatory tokens.
- FR-32: Meta-guides (`AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md`) and the triage protocol.
- FR-33: `scripts/lib/common.sh` and the shared script contract.
- FR-34: `ai-review-loop.sh`.
- FR-35: `fr-nfr-gate.sh`.
- FR-36: `get-pr-comments.sh`.
- FR-37: `post-review-findings.sh`.
- FR-38: `pr-state.sh`.
- FR-39: `request-ai-reviews.sh`.
- FR-40: Plugin manifest and plugin README.
- FR-41: Documentation set (9 docs).
- FR-42: Test suites (16) and fixtures.
- FR-43: Marketplace entry, root README and CI wiring.
- FR-44: Workflow-tool scripts, harness and `workflows.bats` (the cut line).

### NonFunctional Requirements

- NFR-1: Idempotent, no-clobber writes; second runs change nothing; content outside owned regions byte-identical.
- NFR-2: Generalization: 0 denylist hits in `skills/ commands/ agents/ scripts/ workflows/` outside `# profile-example` fences; slug only in `config/` and docs fences.
- NFR-3: Degrade matrix D1–D25: one defined outcome per gap; never loops, never fakes a pass.
- NFR-4: Tighten-only quality bars (12 keys equal the template values).
- NFR-5: Safety: no hook bypass, force-push, protected edit, breaker reset, `bypassPermissions`, approval label.
- NFR-6: Boundedness: numeric cap on every loop; breach ends in the 7-field escalation.
- NFR-7: Portability: bash ≥ 4.4, git ≥ 2.30, Linux and macOS, mikefarah-yq-or-PyYAML, jq-or-python3, `tomllib`.
- NFR-8: Testability: every flag and exit code bats-covered; 16 suites, floors totalling 557 (architecture, raise-only over the PRD's 460).
- NFR-9: Observability: run report, state comment, ledgers, logs, targets-run list.
- NFR-10: Security: redaction before publishing, isolated gate session, least privilege, loopback-only QA, input validation, author filters.
- NFR-11: Installability: 10/7/28/2 components load; no `_bmad`/`.ralph` in the tree.
- NFR-12: Token cost: 28 triage verdicts from frontmatter; ≤ 6 `EXECUTE` for the docs-only class.
- NFR-13: Template compatibility of every written file (yamllint, Prettier, markdownlint, typos, docs-check rules 1–4, invariant (e)).
- NFR-14: Runtime bounds: no foreground call > 600 s; profile/governance/settings scripts ≤ 5 s on the fixture.
- NFR-15: Drift resistance: template lists read at runtime; shared names and counts pinned.
- NFR-16: Version floors enforced with named remediation.

### Additional Requirements (Architecture)

- Starter: the reference plugin `plugins/php-backend-sdlc/` is mirrored (layout, frontmatter contracts, script skeleton, helpers, governance algorithm); from `plugins/react-frontend-sdlc/` the `pr-state.sh`, `request-ai-reviews.sh`, hardened `fr-nfr-gate.sh`, mikefarah `have_yq`, `resolve_repo_slug`, `claude_run_isolated`, the workflow layer and the harness are ported. Story 1.1 sets up the plugin from this starter.
- § Constraints are binding on every story: writes only under the plugin plus the 3 wiring files; pinned counts 10 commands, 7 agents, 28 skills, 2 meta-guides, 13 scripts + library, 4 workflows, 9 docs, 16 suites; no `_bmad`/`.ralph` path component; Markdown fixtures as `*.md.tpl`, `dot-claude/` and `dot-bmalph/` fixture directories; byte-identical shared names (`BMAD FR/NFR Review Gate`, `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR`, `SDLC_NOW_EPOCH`); new variables `RUST_SDLC_*`; done = lint 0 for all plugins, shellcheck 0, markdownlint 0, all suites green twice (second run `SDLC_FORCE_PYTHON_YAML=1`), floors met, `claude plugin validate --strict` 0.
- ADR-1 to ADR-27 fix the design: runtime profile reads (1), schema v1 and tighten-only bars (2, 7), the governance block text (3), bundled scripts with `make.*` SUBST keys (4), triage + three lenses + Q1–Q15 (5), permissions with local allowlist and plugin deny entries, no bypass (6), claude driver and the isolated gate session (8), release tags `rust-backend-sdlc-vX.Y.Z` (9), bmalph 2.11.0 floor, single implementer, re-entry protocol, `@AGENT.md` patch, breaker pre-check (10, 10a, 10b, 10c), loose meta-guides (11), slug in `config/` (12), make-only suffix variables and background-by-allowlist (13), durable state on the issue (14), the 17-name library dispatcher (15), ledger schema v1 (16), WARN-only template detection (17), workflow hand-back contract (18), no lint widening (19), citation repair (20), plugin agents in Ralph (21), hermetic materialized fixtures (22), exit codes (23), refresh preserve keys (24), branch guards (25), trusted authors (26), redacted body files (27).
- Amendments to the PRD (architecture wins): suffix make spelling and `git commit -F`; "hooks active" definition; FR-9 deny entries, per-executable entries, no `curl` entry; FR-14/FR-15 argument hints; three sanctioned `.ralph/` writes; conclusion comment posted by finish-pr only; `pr-state.sh --json` adds `url`; fixture layout (`bin-kislyuk/`, `dot-*`, `make/service.mk` defines `load-tests`); `onGate` default `'nested'`; per-suite floors raised to 557 (post-cut 491).
- Degrade Matrix D1–D25, Permissions Strategy (allow rows 1–39 = 66 entries; deny G1–G9, H1–H8, B1–B2, M1–M10 = 29 entries), the Governance Block exact text, the Exit strings table and the canonical escalation block are single-sourced in the architecture and copied byte for byte.

### UX Design Requirements

None: no UX document exists and the plugin has no user interface; its "interface" contracts (handles, escalation block, run report) are covered as FR-1/FR-3 acceptance criteria.

## Epic List

| Epic | User outcome | FRs | Stories |
| --- | --- | --- | --- |
| 1 Test harness, core library and project profile | a template-derived service gets a generated, validated profile; every later story has a hermetic harness | FR-5, FR-6, FR-7, FR-33 (core), FR-40 (manifest), FR-42 (harness) | 1.1–1.9 |
| 2 One-command repository setup | `/rs-sdlc-setup` prepares a checkout idempotently | FR-4, FR-8, FR-9, FR-10, FR-33 (command helpers), FR-41 (setup walkthrough) | 2.1–2.5 |
| 3 Review, gate and pull-request scripts | standalone review loop, FR/NFR gate, comment reader, findings poster, PR sensor, review requester, bundle staging | FR-17, FR-33 (publishing), FR-34–FR-39 | 3.1–3.10 |
| 4 Rust skill library | 28 profile-driven Rust skills and the decision guide | FR-30, FR-31, FR-32 (decision guide) | 4.1–4.13 |
| 5 Agents and the feature loop | `/rs-sdlc "<task>"` drives issue → plan → implement → review → QA → finished PR, resumable | FR-1–FR-3, FR-15, FR-16, FR-18–FR-29, FR-32 (agent guide), FR-33 (state, Ralph) | 5.1–5.12 |
| 6 Service creation and bounded contexts | `/rs-sdlc-new-service` and `/rs-sdlc-new-context` | FR-11–FR-14 | 6.1–6.3 |
| 7 Workflow layer (the cut line) | the loop as Workflow-tool scripts with a deterministic harness | FR-44 | 7.1–7.6 |
| 8 Documentation, marketplace wiring and release gate | install from the marketplace, full docs, pinned contracts, green release gate | FR-40–FR-43 | 8.1–8.7 |

## Epic 1: Test harness, core library and project profile

A maintainer of a template-derived Rust service can generate and validate the project profile `.claude/rust-sdlc.yml` with the plugin's own scripts: this epic sets the plugin up from the reference plugin (exact manifest, shared bats helpers, the docs-check port, stub executables and the stub template-derived repository), writes the `core` section of `scripts/lib/common.sh`, the canonical schema document and the two profile scripts with their suites; every later epic reuses this harness and library, and nothing here depends on a later epic.

### Story 1.1: Set up the plugin from the reference plugin: manifest and shared test library

As a plugin maintainer,
I want the plugin directory with its exact manifest, the shared bats helpers and the static docs-check port,
So that every later story starts from the reference plugin's layout and one hermetic test harness.
**Read:** § Plugin Manifest and Configuration › `.claude-plugin/plugin.json` (exact); § Test Architecture › Layout and helpers; ADR-22; PRD FR-40, FR-42. **Size:** M.

**Acceptance Criteria:**

- Given the architecture's exact manifest, when `.claude-plugin/plugin.json` is parsed, then it holds exactly the 8 keys `name`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords` with the values of § `.claude-plugin/plugin.json` byte for byte (`rust-backend-sdlc`, `0.1.0`, `MIT`, keywords incl. `rust`, `sdlc`, `bmad`, `ralph`, `microservices`) and `lint_all.py` reports no M1–M3 finding for the plugin (CC-24 manifest half).
- Given `tests/lib/helpers.bash` loaded by a suite with `load lib/helpers`, when `common_setup` runs, then `PLUGIN_ROOT` is the plugin root, `tests/fixtures/bin` is first on `PATH`, every `STUB_<NAME>_LOG` points under `$BATS_TEST_TMPDIR`, `STUB_DOCKER_INFO_EXIT=1` is exported, `CLAUDE_PLUGIN_ROOT` is unset, and the file defines functions only (no bats-only call at top level).
- Given `rr_materialize DEST [ORIGIN_SLUG]`, when it runs over `tests/fixtures/rust-repo/`, then DEST is a copy with every `.tpl` suffix dropped, `gitignore` renamed `.gitignore`, `dot-claude/` renamed `.claude/`, `dot-bmalph/` renamed `bmalph/`, initialized with `git init -q -b main`, committed once as `acme <ci@example.invalid>`, with `origin` = `https://github.com/${ORIGIN_SLUG:-acme/billing-service}.git` (suites use DEST `$BATS_TEST_TMPDIR/billing-service`, the name the golden profile assumes).
- Given the remaining helpers, when each is called, then `sandbox_path TOOL…` returns a PATH holding links to only the named tools, `k7_require TOOL` skips with `<tool> not installed (runs in CI)`, `bundle_write DIR [--blocked]` writes the seven FR-16 bundle files (an `architecture.md` with `## Tech Stack` and a `## Constraints` holding parts (a) and (b), an `epics.md` with at least two `### Story N.M:` headings each with acceptance criteria and a `Depends on:` line, a readiness verdict `ready`, or a readiness text containing `NO-GO` with `--blocked`), `mutate_profile FILE KEY VALUE` and `drop_profile_key FILE KEY` edit one line of the block-style golden profile, `docs_rules FILE…` runs `python3 -I tests/lib/docs-rules.py --root <repo> FILE…`, and `skip_if_root` skips with a reason under uid 0.
- Given `tests/lib/docs-rules.py`, when it runs as `python3 -I tests/lib/docs-rules.py --root <repo> FILE…` (FILE relative to `--root`), then it reports rule 1 (a backticked `make <target>` with no `^[a-zA-Z0-9_-]+:.*##[[:space:]]` rule in the Makefile or `make/*.mk`), rule 2 (a code span that is exactly `/name` without `.claude/commands/name.md`), rule 3 (a backticked path whose first segment is a tracked top-level name, missing on disk and not git-ignored, checked up to its first placeholder), rule 4 (a numbered list or fence naming three or more gate targets, the union of the Makefile's `CI_*_TARGETS`, outside the `AGENTS.md` verification markers) and invariant (e) (the literal assembled from `rust-service-` + `template`, and the repository name of the sync workflows' `TEMPLATE_REPOSITORY:` line), one line `(<rule>) <file>:<line>: <message>` each, exit 1 on any finding and 0 otherwise.

**Files owned:**

- `plugins/rust-backend-sdlc/.claude-plugin/plugin.json`
- `plugins/rust-backend-sdlc/tests/lib/helpers.bash`
- `plugins/rust-backend-sdlc/tests/lib/docs-rules.py`

**Depends on:** none

**FRs:** FR-40, FR-42 (NFR-8, NFR-11)

**Verification:**

- `python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert sorted(d)==sorted(["name","version","description","author","homepage","repository","license","keywords"]) and d["name"]=="rust-backend-sdlc" and d["version"]=="0.1.0" and d["license"]=="MIT"' plugins/rust-backend-sdlc/.claude-plugin/plugin.json`
- `v_lint '\.claude-plugin/'`
- `shellcheck -s bash plugins/rust-backend-sdlc/tests/lib/helpers.bash`
- `bash -c 'source plugins/rust-backend-sdlc/tests/lib/helpers.bash && for f in common_setup rr_materialize sandbox_path k7_require bundle_write mutate_profile drop_profile_key docs_rules skip_if_root; do declare -F "$f" >/dev/null || { echo "missing $f"; exit 1; }; done'`
- `d=$(mktemp -d) && git -C "$d" init -q && printf 'a: ## x\n' >"$d/Makefile" && printf 'Run `make b`.\n' >"$d/README.md" && git -C "$d" add -A && python3 -I plugins/rust-backend-sdlc/tests/lib/docs-rules.py --root "$d" README.md | grep -q '^(1) README.md:1:'`

### Story 1.2: Stub executables for hermetic suites

As a plugin maintainer,
I want stub `claude`, `gh`, `bmalph`, `curl`, `cargo`, `make` and `docker` executables plus a kislyuk-style `yq`,
So that every suite runs without network or real tools and asserts exact argv and environment.
**Read:** § Test Architecture › Stub executables; ADR-8 (isolation env set); ADR-10a (bmalph re-entry refusal); ADR-22. **Size:** M.

**Acceptance Criteria:**

- Given any stub under `tests/fixtures/bin/`, when it runs with `STUB_<NAME>_LOG` set, then it appends one line `<name> <argv>` to that log and exits with `STUB_<NAME>_EXIT` (default 0), and every stub starts `#!/usr/bin/env bash` with `set -euo pipefail`, is executable and passes `shellcheck -x`.
- Given the `claude` stub, when called with `--version` it prints `STUB_CLAUDE_VERSION` (default `2.1.322`), with `--help` it lists `--restricted` only when `STUB_CLAUDE_RESTRICTED=1` (the default), and otherwise it prints `STUB_CLAUDE_OUTPUT` or the n-th file `<STUB_CLAUDE_OUTPUTS_DIR>/<n>.json` (the last one repeating) and logs each of the 14 ADR-8 variables (`GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `SSH_AUTH_SOCK`, `GIT_ASKPASS`, `SSH_ASKPASS`, `GH_CONFIG_DIR`, `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL`, `GIT_TERMINAL_PROMPT`, `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`, `GIT_CONFIG_VALUE_0`) as `NAME=<value>` or `NAME unset`.
- Given the `gh` stub, when `STUB_GH_ROUTES` names a file of `<argv glob>\t<exit>\t<stdout file>` lines, then the first matching route decides stdout and exit, an unmatched call exits 9 under `STUB_GH_STRICT=1`, `--version` prints `gh version ${STUB_GH_VERSION:-2.62.0}`, `auth status` exits `STUB_GH_AUTH_EXIT`, `repo clone <src> <dir> [-- …]` copies `STUB_GH_CLONE_SOURCE` into `<dir>` as a one-commit repository, and the stdin of a `-F body=@-` call is logged.
- Given the `bmalph` stub, when `implement` runs while `.ralph/@fix_plan.md` exists, then it prints `Warning: bmalph implement has already been run.` and exits 1; otherwise it writes `.ralph/@fix_plan.md` (one `- [ ] Story <id>: <title>` line per `### Story` heading of `_bmad-output/planning-artifacts/epics.md`), `.ralph/PROJECT_CONTEXT.md` (that bundle's `## Constraints` section truncated at 5,000 characters) and `.ralph/@AGENT.md` (a copy of `../ralph/AGENT.md.tpl` relative to the stub, created by Story 5.2); `--version` prints `STUB_BMALPH_VERSION` (default `2.11.0`), `doctor` exits `STUB_BMALPH_DOCTOR_EXIT`, `run` prints `STUB_BMALPH_OUTPUT`.
- Given the `curl`, `cargo`, `make` and `docker` stubs, when invoked, then `curl` prints `STUB_CURL_OUTPUT` or a canned `HTTP/1.1 200` response, `make --version` prints `${STUB_MAKE_VERSION_LINE:-GNU Make 4.4.1}`, `docker info` exits `${STUB_DOCKER_INFO_EXIT:-1}`, and each records every call so a suite can assert zero `cargo`/`make` invocations.
- Given `tests/fixtures/bin-kislyuk/yq`, when invoked with any expression it prints `"array"` and with `--version` it prints `yq 3.4.3`, and it is outside `tests/fixtures/bin/` so it never shadows a real mikefarah `yq` (ADR-22, amends FR-42).

**Files owned:**

- `plugins/rust-backend-sdlc/tests/fixtures/bin/bmalph`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/cargo`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/claude`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/curl`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/docker`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/gh`
- `plugins/rust-backend-sdlc/tests/fixtures/bin/make`
- `plugins/rust-backend-sdlc/tests/fixtures/bin-kislyuk/yq`

**Depends on:** none

**FRs:** FR-42 (NFR-8, NFR-10)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/tests/fixtures/bin/* plugins/rust-backend-sdlc/tests/fixtures/bin-kislyuk/yq`
- `test -z "$(find plugins/rust-backend-sdlc/tests/fixtures/bin plugins/rust-backend-sdlc/tests/fixtures/bin-kislyuk -type f ! -perm -u+x)"`
- `PATH="$PWD/plugins/rust-backend-sdlc/tests/fixtures/bin:$PATH" claude --help | grep -q -- --restricted && PATH="$PWD/plugins/rust-backend-sdlc/tests/fixtures/bin:$PATH" STUB_CLAUDE_RESTRICTED=0 claude --help | { ! grep -q -- --restricted; }`
- `test "$(plugins/rust-backend-sdlc/tests/fixtures/bin-kislyuk/yq '.a | type')" = '"array"'`
- `v_gen plugins/rust-backend-sdlc/tests/fixtures/bin plugins/rust-backend-sdlc/tests/fixtures/bin-kislyuk`

### Story 1.3: Stub repository: workspace, crates and build surface

As a plugin maintainer,
I want a stub template-derived workspace with identity `acme/rust-template` and one `billing/invoice` context,
So that profile detection, context-name validation and protected-change checks run against realistic files without `cargo` or Docker.
**Read:** § Project Structure › Plugin tree (`rust-repo/` rows); § Project Profile Schema › Keys other than `make.*` and `quality.*`, `make.*` map, Quality bars (sources); ADR-17; PRD FR-42, AC-6.7, AC-14.1. **Size:** M.

**Acceptance Criteria:**

- Given `tests/fixtures/rust-repo/Cargo.toml`, when python3 `tomllib` reads it, then it is a virtual workspace whose sorted `[workspace].members` are the three `crates/billing/invoice/{application,domain,infrastructure}`, the three `crates/internal/health-check/*`, `crates/service`, the three `crates/shared/*`, `tests/e2e`, `tests/support` and `xtask`; `[workspace.package]` holds `version`, `edition = "2024"`, `rust-version = "1.99.1"`, a single-line `description` and `repository = "https://github.com/acme/rust-template"`; `[workspace.dependencies]` holds path entries for the workspace crates plus `axum`, `utoipa`, `async-graphql` and `sqlx` with a `postgres` feature; every member `Cargo.toml` names its package `<context>-<layer>` (`invoice-domain`, `health-check-application`, `shared-infrastructure`, `service`, `test-support`, …) and `Cargo.lock` exists.
- Given the configuration files, when read, then `rust-toolchain.toml` sets channel `"1.99.1"`, `architecture.toml` declares 7 `[[layer]]` entries (`domain`, `application`, `infrastructure`, `composition-root`, `test-support`, `e2e`, `tooling`), `clippy.toml` holds the four thresholds 8 / 50 / 5 / 5, `deny.toml` holds the four cargo-deny lanes, `protected-config.toml` lists in `files` at least `.claude/settings.json`, `clippy.toml`, `architecture.toml`, `deny.toml` and `make/gates.mk` plus a `directories` array, and `workspace.dsl` and `xtask/Cargo.toml` exist, so all seven A1 markers of ADR-17 are present.
- Given `Makefile`, `make/gates.mk` and `make/service.mk`, when scanned with `^[a-zA-Z0-9_-]+:.*##[[:space:]]`, then the Makefile defines stub `##` targets for 50 of the 51 template targets of the `make.*` map (all but `load-tests`), the seven `CI_*_TARGETS` assignments with `CI_PREFLIGHT_TARGETS` starting `validate-configuration`, the HOST message `This target needs a reachable container engine (docker).` and `-include make/service.mk`; `make/service.mk` defines `load-tests: ## …`; `make/gates.mk` defines `COVERAGE_GATE_CMD` with `--fail-under-lines 100 --fail-under-functions 100`, `CI_STAGES`, `SPECTRAL_FLAGS = --fail-severity=hint`, `OASDIFF_FLAGS = --fail-on ERR` and `TRIVY_FLAGS = --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore`; none of `ai-review-loop`, `pr-comments`, `fr-nfr-gate`, `post-review-findings` is a target.
- Given the persistence, service and load files, when read, then `migrations/20261110000000_create_invoices.up.sql` and `.down.sql` exist, `.sqlx/query-fixture.json` is valid JSON, `.env` has the line `APP_PORT=8081`, `.env.test` exists, and `tests/Load/config.json.dist` holds the JSON pointer `/endpoints/health/smoke/threshold`.
- Given the whole story's files, when grepped case-insensitively, then none contains the organization token of NFR-2 or the literal assembled from `rust-service-` + `template`, none ends in `.md`, and no path component is `_bmad` or `.ralph`.

**Files owned:**

- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Cargo.lock`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/rust-toolchain.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/billing/invoice/application/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/billing/invoice/domain/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/billing/invoice/infrastructure/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/internal/health-check/application/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/internal/health-check/domain/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/internal/health-check/infrastructure/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/service/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/shared/application/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/shared/domain/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/crates/shared/infrastructure/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/tests/e2e/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/tests/support/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/xtask/Cargo.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/architecture.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/clippy.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/deny.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/protected-config.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/workspace.dsl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/migrations/20261110000000_create_invoices.up.sql`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/migrations/20261110000000_create_invoices.down.sql`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.sqlx/query-fixture.json`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.env`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.env.test`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/tests/Load/config.json.dist`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Makefile`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/make/gates.mk`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/make/service.mk`

**Depends on:** none

**FRs:** FR-42 (NFR-2, NFR-11)

**Verification:**

- `find plugins/rust-backend-sdlc/tests/fixtures/rust-repo -name '*.toml' -exec python3 -c 'import sys,tomllib; [tomllib.load(open(p,"rb")) for p in sys.argv[1:]]' {} +`
- `v_json plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.sqlx/query-fixture.json plugins/rust-backend-sdlc/tests/fixtures/rust-repo/tests/Load/config.json.dist`
- `test "$(grep -cE '^[a-zA-Z0-9_-]+:.*##[[:space:]]' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Makefile)" -ge 50 && grep -qE '^load-tests:.*##' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/make/service.mk && ! grep -qE '^load-tests:' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Makefile`
- `grep -qE '^CI_PREFLIGHT_TARGETS[[:space:]]*:?=[[:space:]]*validate-configuration' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/Makefile && grep -qx 'APP_PORT=8081' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.env`
- `v_gen plugins/rust-backend-sdlc/tests/fixtures/rust-repo`

### Story 1.4: Stub repository: GitHub workflows, contracts and repository-settings tables

As a plugin maintainer,
I want the stub repository's workflows, contract snapshots, CodeRabbit file and the template's job and gate tables,
So that CI-check derivation, human-gated mapping, reviewer detection and the ci-fixer's gate table are tested on the template's real formats.
**Read:** § Project Structure › Plugin tree (`.github/`, `docs/repository-settings.md.tpl`, `docs/make-targets.md.tpl`, `variants/`); § Project Profile Schema rows `ci.*`, `review.*`, `template.*`, `service.*_snapshot`; PRD AC-6.5, FR-27. **Size:** M.

**Acceptance Criteria:**

- Given `.github/workflows/`, when listed, then it holds exactly `change-control.yml`, `contracts.yml`, `load-tests.yml`, `quality.yml`, `release.yml`, `repository.yml`, `security.yml`, `template-sync-app.yml`, `template-sync-pat.yml` and `tests.yml`, each parseable YAML, and both sync workflows carry the line `TEMPLATE_REPOSITORY: acme/rust-template`.
- Given `docs/repository-settings.md.tpl`, when compared with the template's `docs/repository-settings.md` at `3e0bd3e`, then its seven job tables under "Required status checks" (with the "Check name", "Required" and "Gate" cells) and its "Labels to create" table are copied verbatim except that every organization or repository identity reads `acme/rust-template`, so the singular sentence "without it the job `<j>` fails" and the plural "without it the jobs `<a>` and `<b>` fail" both occur and map to `Protected configuration`, `OpenAPI breaking changes` and `GraphQL breaking changes`, while the non-required rows `mutation-shard`, `bats-group` and `codeql` stay non-required (AC-6.5).
- Given `tests/fixtures/variants/repository-settings-service.md.tpl`, when copied into a materialized repository as `docs/repository-settings-service.md`, then it adds exactly one job-table row whose "Required" cell is `yes` and whose check name contains a space.
- Given `docs/make-targets.md.tpl`, when read, then it holds the template's 4-column gate table rows G1–G31 verbatim (backticked targets, G11's cell naming `doc-tests` and `tests-with-coverage`), the table `ci-fixer` maps gate ids to targets through.
- Given `.github/openapi-spec/spec.yaml`, `.github/graphql-spec/spec` and `.coderabbit.yaml`, when read, then the OpenAPI snapshot is valid YAML with `info.title`, the GraphQL snapshot is SDL text with a `Query` type, and `.coderabbit.yaml` sets `reviews.request_changes_workflow: true` (detection yields `review.coderabbit: true`, `review.reviewers` = `coderabbit`, `review.request_changes_blocking: true`).
- Given the story's files, when grepped case-insensitively, then none contains the organization token or the literal assembled from `rust-service-` + `template`, and every Markdown file ends in `.md.tpl`.

**Files owned:**

- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/change-control.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/contracts.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/load-tests.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/quality.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/release.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/repository.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/security.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/template-sync-app.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/template-sync-pat.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/tests.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/openapi-spec/spec.yaml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/graphql-spec/spec`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.coderabbit.yaml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/repository-settings.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/make-targets.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/variants/repository-settings-service.md.tpl`

**Depends on:** none

**FRs:** FR-42 (supports FR-6 AC-6.5, FR-27, FR-38)

**Verification:**

- `python3 -c 'import sys,yaml; [yaml.safe_load(open(p)) for p in sys.argv[1:]]' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/*.yml plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/openapi-spec/spec.yaml plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.coderabbit.yaml`
- `test "$(ls plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows | wc -l)" -eq 10 && test "$(grep -l 'TEMPLATE_REPOSITORY: acme/rust-template' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/workflows/template-sync-*.yml | wc -l)" -eq 2`
- `grep -q 'without it the job `' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/repository-settings.md.tpl && grep -q 'without it the jobs `' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/repository-settings.md.tpl`
- `v_gen plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs plugins/rust-backend-sdlc/tests/fixtures/variants plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.coderabbit.yaml`

### Story 1.5: Stub repository: governance Markdown, settings and template linter configs

As a plugin maintainer,
I want the stub repository's `CLAUDE.md`, `AGENTS.md`, settings, README, changelog, sync guides, issue and PR templates and the template's linter configs,
So that governance injection, settings merging, new-service customization and the K7 linter cases run on the template's real shapes.
**Read:** § Project Structure › Plugin tree (`rust-repo/` Markdown and config rows, `variants/`); ADR-20, ADR-22; § Governance Block › Content rules; PRD FR-42, AC-8.3, AC-12.5. **Size:** M.

**Acceptance Criteria:**

- Given `CLAUDE.md.tpl` and `AGENTS.md.tpl`, when materialized, then `AGENTS.md` holds a verification list between `<!-- verification:start -->` and `<!-- verification:end -->`, both files carry pre-existing user text that injection must keep byte-identical, and neither contains a `rust-backend-sdlc` marker.
- Given `dot-claude/settings.json` and `gitignore.tpl`, when materialized, then `.claude/settings.json` has the template's shape (an `allow` list, the 11 `ask` rules of § Template contract, the prefix `deny` rules such as `Bash(git commit --no-verify:*)` and `Bash(git push --force:*)`, a `PreToolUse` guard hook matching `Edit|Write|MultiEdit|NotebookEdit`) and `.gitignore` ignores `target/`, `.claude/settings.local.json` and `_bmad-output/`.
- Given `README.md.tpl`, `CHANGELOG.md.tpl`, `dot-bmalph/config.json` and `specs/example-bundle/prd.md.tpl`, when materialized, then `README.md` has a banner, one H1, badge lines starting `[![` that name `acme/rust-template` and an intro paragraph before the first H2; `CHANGELOG.md` has one release section; `bmalph/config.json` has `name`, `description` and at least one other key in Prettier format; `specs/example-bundle/` is a shipped bundle directory.
- Given `docs/extension-seams.md.tpl`, the two `.github/TEMPLATE_SYNC_*.md.tpl` guides, `.templatesyncignore` and `tests/fixtures/variants/extension-seams-fixed.md.tpl`, when materialized, then one line of `docs/extension-seams.md` backtick-cites both `.github/TEMPLATE_SYNC_APP.md` and `.github/TEMPLATE_SYNC_PAT.md` (the ADR-20 defect) while the fixed variant cites only the bare file names.
- Given `.github/ISSUE_TEMPLATE/feature_request.md.tpl`, `.github/pull_request_template.md.tpl`, `docs/new-service.md.tpl` and `dot-claude/skills/README.md.tpl`, when materialized, then the issue template has the H2s `Problem statement`, `Proposed change`, `Affected area`, `Tasks`, `Acceptance criteria`, and the PR template has `Description`, `Related issue`, `Type of change`, `How it was tested`, `Checklist`.
- Given `.markdownlint-cli2.yaml`, `.prettierrc.yml`, `.yamllint.yml` and `_typos.toml`, when compared with the template's files at `3e0bd3e`, then they are byte copies, and given the story's files, no file ends in `.md`, none contains the organization token or the literal assembled from `rust-service-` + `template`, and `git check-ignore --no-index` prints nothing for any of them.

**Files owned:**

- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-claude/settings.json`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-claude/skills/README.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/AGENTS.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/CLAUDE.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/README.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/CHANGELOG.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/extension-seams.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/new-service.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/ISSUE_TEMPLATE/feature_request.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/TEMPLATE_SYNC_APP.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/TEMPLATE_SYNC_PAT.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.github/pull_request_template.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/specs/example-bundle/prd.md.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/gitignore.tpl`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.templatesyncignore`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-bmalph/config.json`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.markdownlint-cli2.yaml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.prettierrc.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.yamllint.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/rust-repo/_typos.toml`
- `plugins/rust-backend-sdlc/tests/fixtures/variants/extension-seams-fixed.md.tpl`

**Depends on:** none

**FRs:** FR-42 (NFR-2, NFR-13)

**Verification:**

- `v_json plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-claude/settings.json plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-bmalph/config.json`
- `for f in .markdownlint-cli2.yaml .prettierrc.yml .yamllint.yml _typos.toml; do cmp "/home/user/rust-service-template/$f" "plugins/rust-backend-sdlc/tests/fixtures/rust-repo/$f" || exit 1; done`
- `grep -q 'verification:start' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/AGENTS.md.tpl && grep -c 'TEMPLATE_SYNC_' plugins/rust-backend-sdlc/tests/fixtures/rust-repo/docs/extension-seams.md.tpl | grep -qv '^0$'`
- `test -z "$(find plugins/rust-backend-sdlc/tests/fixtures -name '*.md')" && test -z "$(find plugins/rust-backend-sdlc/tests/fixtures -type f | git check-ignore --no-index --stdin)"`
- `v_gen plugins/rust-backend-sdlc/tests/fixtures/rust-repo/dot-claude plugins/rust-backend-sdlc/tests/fixtures/rust-repo/*.tpl plugins/rust-backend-sdlc/tests/fixtures/variants`

### Story 1.6: Core shell library (`common.sh` section `core`)

As a plugin maintainer,
I want the `core` section of `scripts/lib/common.sh` with its bats cases,
So that every script shares one tested implementation of logging, argument handling, YAML/JSON/TOML access, profile reads, identity parsing, validators, safe writes and the library dispatcher.
**Read:** § Script Contracts › Shared contract and `scripts/lib/common.sh` (rows `log_*` through `atomic_write`, `claude_supports_restricted`, `human_gated_labels`, `is_commit_subject`, dispatcher paragraph); ADR-15, ADR-23; § Implementation Patterns › Script conventions; PRD FR-33, AC-2.1, AC-33.1. **Size:** L.

**Acceptance Criteria:**

- Given the library executed directly with no argument or with a first argument outside the closed set of 17 ADR-15 names, when it runs, then it prints `common.sh is a library; source it instead of executing` to stderr and exits 64; given one of the 17 names whose function is defined, it runs that function with the remaining arguments and exits with its status (the closed list is complete here; Stories 2.4, 3.1, 5.1 and 5.2 add the remaining functions).
- Given `RUST_SDLC_BASH_VERSION=4.3` (or a real bash below 4.4), when the library is sourced, then its first executable lines print `[rust-sdlc][ERROR] bash 4.3 is too old: install Bash 4.4 or newer` and exit 1 before any function is defined (NFR-16).
- Given the kislyuk stub first on `PATH`, when `have_yq` runs, then it is false (only `printf 'a: [1]\n' | yq '.a | type'` printing `!!seq` passes) and caches the verdict in `_SDLC_YQ_OK`; with `SDLC_FORCE_PYTHON_YAML=1` it is false regardless; `yaml_parses`, `yaml_get`, `yaml_get_list`, `yaml_is_list`, `yaml_has`, `yaml_type`, `yaml_to_json` print byte-identical results on the mikefarah and PyYAML backends (null or absent → empty, booleans `true`/`false`, lists one item per line, `yaml_has` true for a key set to `null`, `yaml_to_json` exit 1 with the parser's first error line), and `require_yaml_toolchain` dies `no YAML toolchain: install mikefarah yq v4, or python3 with PyYAML`.
- Given the fixture repository, when `json_get` runs with jq and under `sandbox_path` without jq, then the outputs are identical; `toml_get`, `toml_get_list`, `toml_has` read `workspace.package.description`, `workspace.members` and `toolchain.channel` (→ `1.99.1`) through python3 `tomllib` and die `python3 3.11+ with tomllib is required` without it.
- Given the validators, when called, then `is_commit_subject` accepts every FR-2 fixed subject with `N=1` and rejects `review: gate iteration 2 remediation`, `Apply review suggestion: x`, `feat: x`, `feat(#): x`, `Feat (#1): x` and `feat(#0): x` (AC-2.1, first half); `is_kebab` (max 50), `is_slug` and `is_semver` follow their regexes; `resolve_repo_slug` parses the `https://github.com/o/n[.git]`, `git@github.com:o/n[.git]` and `ssh://git@github.com/o/n[.git]` origins and otherwise falls back to `gh repo view --json nameWithOwner --jq .nameWithOwner`; `default_branch` resolves origin/HEAD → `main` → `master` → `main`; `resolve_plugin_root` prefers a `CLAUDE_PLUGIN_ROOT` directory (dies when it is set but not a directory) else the library's `../..`.
- Given the arithmetic, clock and write helpers, when called, then `strip_zeros`, `num_gt`, `num_lt`, `num_add`, `is_uint` compare 20-digit strings without wrapping; `now_epoch`, `utc_now`, `utc_stamp` honour `SDLC_NOW_EPOCH` through python3 (no `date -d`); `safe_write_target` refuses a symlink, a non-regular file, a symlinked parent and a path outside ROOT; `atomic_write` writes through a same-directory `mktemp` + `mv -f` and keeps an existing file's mode; `yaml_squote` doubles `'` and strips control characters; `profile_get` returns the default only for absent or null keys (`false` is a value) and `profile_require` dies naming the key; `log_info`/`log_warn`/`log_error` write `[rust-sdlc][LEVEL] <msg>` to stderr only; `die` exits 1, `die_usage` exits 2, `need_value` rejects an empty value or one starting `--`.
- Given the fixture's `docs/repository-settings.md`, when `human_gated_labels` runs, then it prints `approved-config-change<TAB>Protected configuration`, `approved-breaking-change<TAB>OpenAPI breaking changes` and `approved-breaking-change<TAB>GraphQL breaking changes` (singular and plural sentence forms parsed), and `claude_supports_restricted` is true exactly when `claude --help` lists `--restricted`.
- Given the file, when checked, then the section starts with `# section: core`, the file is executable, `shellcheck -x` reports nothing, the banned constructs are absent, and `tests/common-lib.bats` holds at least 22 `@test` cases named `common-lib: <function>: <behaviour>`.

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/lib/common.sh` (section `core`; creates the file)
- `plugins/rust-backend-sdlc/tests/common-lib.bats` (section `core`; creates the file)

**Depends on:** 1.1, 1.2, 1.3, 1.4

**FRs:** FR-33, FR-2 (NFR-7, NFR-10, NFR-16)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/lib/common.sh && v_banned plugins/rust-backend-sdlc/scripts/lib/common.sh && v_gen plugins/rust-backend-sdlc/scripts/lib/common.sh`
- `v_bats common-lib 22`
- `plugins/rust-backend-sdlc/scripts/lib/common.sh 2>/dev/null; test $? -eq 64`
- `plugins/rust-backend-sdlc/scripts/lib/common.sh is_commit_subject 'feat(#1): add x' && ! plugins/rust-backend-sdlc/scripts/lib/common.sh is_commit_subject 'feat: x'`

### Story 1.7: Profile validator and golden profile

As a service maintainer,
I want `validate-profile.sh` to reject every malformed or loosened profile with one line per violation,
So that no command runs on a profile that relaxes a template bar or reroutes a gate key.
**Read:** § Project Profile Schema (all subsections, esp. Conventions, Validation rules, Annotated example); § Script Contracts › `scripts/validate-profile.sh`; ADR-2, ADR-7; PRD FR-5, FR-7, AC-5.1, AC-7.1–AC-7.3. **Size:** L.

**Acceptance Criteria:**

- Given `tests/fixtures/profiles/golden.yml`, when `validate-profile.sh tests/fixtures/profiles/golden.yml` runs on both YAML backends, then the last line is `VALID: <path>` and exit is 0; the golden file holds exactly the 115 schema keys in schema order with the § Conventions emission format (the two header comment lines, block style, 2-space indentation, single-quoted strings, bare enums, targets, ints, booleans and `null`, one trailing newline) and the values detection yields for the materialized stub at `$BATS_TEST_TMPDIR/billing-service` (among them `project.name` billing-service, `project.repo` acme/billing-service, `template.repository` acme/rust-template, `template.sync_flavour` both, `architecture.bounded_contexts` billing/invoice then internal/health-check, `make.load_tests` load-tests, the four SUBST keys null, `review.reviewers` coderabbit, `capabilities.run_in_container` false, `capabilities.publish_pr_comments` true, the 12 `quality.*` keys at 100 and 0).
- Given a profile violating each rule V1–V12, when validated, then each prints its exact § Validation rules line, every violation is reported (not only the first), the output ends `INVALID: <path>: <n> violation(s)` and exit is 1; V1 prints `[rust-sdlc][ERROR] profile not found: <path> (run /rs-sdlc-setup)`; `invalid-yaml.yml` prints one `VIOLATION: <path>: not parseable YAML (<first error line>)` without a traceback (AC-7.3).
- Given each of the 12 `quality.*` keys loosened by one (floors 99, ceilings 1), a floor of 101 and a 20-digit ceiling, when validated, then each is rejected naming its key with `(<value> vs bound <bound>)` and no value wraps (AC-7.1, NFR-4).
- Given `make.check_security: null` it is valid; an omitted `make.check_security` prints `VIOLATION: make.check_security: missing`; `make.start: 'start; rm -rf /'` fails V10; `make.complexity: format`, `make.tests_with_coverage: unit-tests` and `make.fr_nfr_gate: format-check` each fail V12 (AC-7.2).
- Given one missing key per group plus three `make.*` keys, a `null` where allowed versus where not, `bad-enum.yml`, `wrong-schema-version.yml`, the unknown key `quality.coverage_line`, a quoted `'100'`, and a `ci.human_gated` entry absent from `ci.required_checks`, when validated, then each yields its V3–V9 line (AC-5.1).
- Given any input, when the script runs, then it converts the file once with `yaml_to_json` and applies every rule in python3 stdlib, so both backends print byte-identical output (three parity cases), writes nothing, finishes in ≤ 5 s on the fixture, and meets SC-SCRIPT and SC-SUITE (usage errors exit 2).

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/validate-profile.sh`
- `plugins/rust-backend-sdlc/tests/validate-profile.bats`
- `plugins/rust-backend-sdlc/tests/fixtures/profiles/golden.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/profiles/invalid-yaml.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/profiles/wrong-schema-version.yml`
- `plugins/rust-backend-sdlc/tests/fixtures/profiles/bad-enum.yml`

**Depends on:** 1.3, 1.4, 1.5, 1.6

**FRs:** FR-5, FR-7 (NFR-4, NFR-7, NFR-14)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/validate-profile.sh && v_banned plugins/rust-backend-sdlc/scripts/validate-profile.sh && v_gen plugins/rust-backend-sdlc/scripts/validate-profile.sh`
- `v_bats validate-profile 33`
- `plugins/rust-backend-sdlc/scripts/validate-profile.sh plugins/rust-backend-sdlc/tests/fixtures/profiles/golden.yml | tail -1 | grep -q '^VALID: '`
- `! command -v yamllint >/dev/null || yamllint -c plugins/rust-backend-sdlc/tests/fixtures/rust-repo/.yamllint.yml plugins/rust-backend-sdlc/tests/fixtures/profiles/golden.yml`

### Story 1.8: Profile generator

As a service maintainer,
I want `generate-profile.sh` to detect the profile from repository files alone and never overwrite my profile unless I ask,
So that setup produces a valid, template-lint-clean profile in seconds and later re-runs are safe.
**Read:** § Script Contracts › `scripts/generate-profile.sh`; § Project Profile Schema (detection-source and fallback columns, `make.*` map rule, Quality bars WARN rule); ADR-17, ADR-24; PRD FR-6, AC-6.1–AC-6.7. **Size:** L.

**Acceptance Criteria:**

- Given the materialized stub at `$BATS_TEST_TMPDIR/billing-service` without a profile, when `generate-profile.sh` runs, then `.claude/rust-sdlc.yml` is byte-identical to `tests/fixtures/profiles/golden.yml` (incl. `make.load_tests: load-tests` found in `make/service.mk`), stdout is `WROTE: .claude/rust-sdlc.yml`, exit is 0 within 5 s, and the file passes `validate-profile.sh` (AC-6.1, AC-6.2).
- Given recording `cargo`, `make` and `gh` stubs, when it runs, then they record 0 calls, `.env.local` is never read, and `docker info` plus `command -v cargo` are the only probes (AC-6.3).
- Given an existing profile without `--refresh`, when it runs, then identical detection prints `UNCHANGED: .claude/rust-sdlc.yml`; a difference prints `DIFF: .claude/rust-sdlc.yml (kept; re-run with --refresh to apply)` plus a unified diff headed `--- .claude/rust-sdlc.yml` / `+++ detected`, keeps the file and exits 0; `--refresh` rewrites atomically through `mktemp .claude/.rust-sdlc.yml.XXXXXX` + `mv`; `--stdout` prints the YAML and writes nothing; a symlinked `.claude`, a symlinked or a non-regular profile exits 1 (NFR-1).
- Given ADR-24, when each of the five preserve keys (`capabilities.run_in_container`, `capabilities.dynamic_security_testing`, `capabilities.publish_pr_comments`, `review.reviewers`, `review.ai_review_agents`) holds another valid value, then it survives `--refresh`; a hand-flipped preserve key without `--refresh` prints `UNCHANGED:`; an existing `false` plus `--run-in-container true` without `--refresh` prints `UPDATED: .claude/rust-sdlc.yml (capabilities.run_in_container=true)` and the file holds `true`; with neither flag nor profile the docker/cargo stubs drive detection in all four combinations (AC-6.6).
- Given the stub stripped of one optional source per case (`.coderabbit.yaml`, `workspace.dsl`, `tests/Load/`, `.sqlx/`, `migrations/`, each snapshot, `docs/repository-settings.md`, `rust-toolchain.toml`, `.env`, both sync workflows, one A1 marker), when it runs, then the dependent keys take their fallback and exit is 0 (AC-6.1, D20).
- Given the template's job tables, when `ci.*` is derived, then `ci.required_checks` holds the "Check name" of every `Required: yes` row in document order, `ci.human_gated` (via `human_gated_labels`) equals exactly `Protected configuration`, `OpenAPI breaking changes`, `GraphQL breaking changes`, each in `ci.required_checks`, the non-required rows are absent, the service variant adds exactly one check, names with spaces are single-quoted and yamllint-clean, and an unmapped human-gated job id prints `WARN:` on stderr (AC-6.5).
- Given the fixture members, when contexts are derived, then `architecture.bounded_contexts` is billing/invoice and internal/health-check and never a `shared/*` entry (AC-6.7); a SUBST target appended at runtime to `make/service.mk` maps its key; a looser `clippy.toml` threshold or `COVERAGE_GATE_CMD` floor prints `[rust-sdlc][WARN] <file> <setting> is looser than the template value <v>; the profile keeps <default>` and the profile keeps 100/0.
- Given CI's pinned tools, when the K7 cases run, then `yamllint -c <fixture>/.yamllint.yml` and `prettier --check` with the fixture's `.prettierrc.yml` pass on the output (skipped locally with a reason), three cases re-run with `SDLC_FORCE_PYTHON_YAML=1`, and the script meets SC-SCRIPT and SC-SUITE.

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/generate-profile.sh`
- `plugins/rust-backend-sdlc/tests/generate-profile.bats`

**Depends on:** 1.6, 1.7

**FRs:** FR-5, FR-6 (NFR-1, NFR-2, NFR-3, NFR-4, NFR-13, NFR-14)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/generate-profile.sh && v_banned plugins/rust-backend-sdlc/scripts/generate-profile.sh && v_gen plugins/rust-backend-sdlc/scripts/generate-profile.sh`
- `v_bats generate-profile 33`
- `npx --yes bats plugins/rust-backend-sdlc/tests/generate-profile.bats --filter 'golden'`

### Story 1.9: Profile schema reference document

As a service maintainer and as every skill author,
I want `docs/profile-schema.md` to document every profile key, its detection, its bounds and the validation rules,
So that the profile is understandable, and CI can check that every key a skill consumes is declared.
**Read:** § Project Profile Schema (all subsections); § Documentation Set row `docs/profile-schema.md`; ADR-19; PRD FR-5, FR-41, AC-5.2, AC-31.1. **Size:** M.

**Acceptance Criteria:**

- Given § Project Profile Schema, when `docs/profile-schema.md` is read, then it states the conventions (location and ownership, 115 keys in 13 groups in emission order, "null means absent; omitted means error", unknown keys are violations, the emission format, detection never runs `cargo`, `make`, `gh` or the network, the refresh column) and documents all 115 keys, each backticked, with type, R/O, nullable, fallback, format, detection source, refresh and consumers (AC-5.2, AC-41.1).
- Given the detection-source table, when read, then it backticks `architecture.toml`, `persistence.rs`, `clippy.toml`, `deny.toml`, `protected-config.toml`, `make/gates.mk` and `docs/repository-settings-service.md`, so L25 finds the two file names it would otherwise flag (ADR-19).
- Given the quality bars, when read, then the derivation table (default, direction, protected source, gate target, measured by, enforced in), the tighten-only rule (floors exactly 100, ceilings exactly 0) and the looser-gate `WARN` behaviour appear, plus the five ADR-24 preserve keys.
- Given validation, when read, then rules V1–V12 with their exact violation lines and the `VALID:`/`INVALID:` endings appear.
- Given the annotated example, when read, then § Annotated example appears verbatim inside one fence whose opening line is ```` ```yaml # profile-example ````, the only place in this file where the default template slug appears, and the file meets SC-DOC.

**Files owned:**

- `plugins/rust-backend-sdlc/docs/profile-schema.md`

**Depends on:** none

**FRs:** FR-5, FR-41 (NFR-2, NFR-4, NFR-15)

**Verification:**

- `v_md plugins/rust-backend-sdlc/docs/profile-schema.md`
- `v_schema_keys`
- `grep -qF '# profile-example' plugins/rust-backend-sdlc/docs/profile-schema.md && for t in architecture.toml persistence.rs clippy.toml deny.toml protected-config.toml make/gates.mk docs/repository-settings-service.md; do grep -qF "\`$t\`" plugins/rust-backend-sdlc/docs/profile-schema.md || { echo "missing $t"; exit 1; }; done`
- `v_cmdtok plugins/rust-backend-sdlc/docs/profile-schema.md`

## Epic 2: One-command repository setup

A developer can run /rs-sdlc-setup once in a clean template-derived checkout and get the preflight table, bmalph installed, a valid profile, the docs-check-safe governance block in `CLAUDE.md` and `AGENTS.md`, a local permission allowlist that keeps the template's deny and ask rules effective, active hooks and a docs-check run, with a second run that changes nothing; this epic adds the three setup scripts, the command-side git, polling, probe and name-validation helpers of `common.sh`, the setup command and its walkthrough, building only on Epic 1.

### Story 2.1: Setup preflight

As a developer preparing a service,
I want `setup-preflight.sh` to check every tool floor and repository precondition with a named remediation,
So that setup stops before writing anything when the host cannot run the loop.
**Read:** § Script Contracts › `scripts/setup-preflight.sh`; § Tech Stack (floors); ADR-17; § Degrade Matrix rows D5, D6, D15, D16, D20; PRD FR-10, AC-10.1–AC-10.3, AC-4.4. **Size:** M.

**Acceptance Criteria:**

- Given stubs at their floors in a clean materialized repository, when `setup-preflight.sh --report` runs, then it prints one `<STATUS>: <check-id>: <detail>[ — remediation: <text>]` line per check in the order `git-repo`, `gh`, `gh-auth`, `claude`, `claude-restricted`, `bmalph`, `bmalph-doctor`, `python3`, `yaml-backend`, `json-backend`, `make`, `bash`, `git`, `template-markers`, `tracked-tree`, `docker`, `cargo`, then `SUMMARY: pass=<n> warn=<n> fail=<n> info=<n>`, and exits 0.
- Given the under-version stubs `gh 1.9`, `bmalph 2.10.0`, `claude` without `--restricted`, python 3.10 (through `sandbox_path`), `make 3.81` and `git 2.29`, when it runs, then each check FAILs with its named remediation (claude: `upgrade Claude Code to 2.1.248 or newer`), the default mode stops after the first FAIL, `--report` runs every check, exit is 1, and `RUST_SDLC_BASH_VERSION=4.3` fails with "install Bash 4.4 or newer" (AC-10.1, NFR-16, D15).
- Given bmalph absent with a `bmalph-setup` Makefile target, node ≥ 20 and npm, when it runs, then `bmalph` is `WARN … will be installed by make bmalph-setup` and exit is 0; without them it FAILs; with `_bmad/` present `bmalph doctor` runs, otherwise `bmalph-doctor` is `INFO … deferred until make bmalph-setup` (AC-10.2, D6).
- Given the kislyuk `yq` stub on `PATH`, when PyYAML is absent `yaml-backend` FAILs and when present it PASSes through the python fallback; with jq absent `json-backend` PASSes through python3 (AC-10.3, D16).
- Given a dirty tracked tree, a missing A1 marker, Docker unreachable and no `cargo`, when it runs, then `tracked-tree` is `INFO` listing the files of `git status --porcelain --untracked-files=no`, `template-markers` is `WARN` naming each missing marker (never FAIL, ADR-17), `docker` is `INFO unreachable` and `cargo` is `INFO absent` (AC-4.4, D5, D20).
- Given any run, when it ends, then it has written nothing, calls only the commands of its contract, and meets SC-SCRIPT and SC-SUITE.

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/setup-preflight.sh`
- `plugins/rust-backend-sdlc/tests/setup-preflight.bats`

**Depends on:** 1.6

**FRs:** FR-10, FR-4 (NFR-3, NFR-7, NFR-16)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/setup-preflight.sh && v_banned plugins/rust-backend-sdlc/scripts/setup-preflight.sh && v_gen plugins/rust-backend-sdlc/scripts/setup-preflight.sh`
- `v_bats setup-preflight 23`

### Story 2.2: Governance block injection

As a developer preparing a service,
I want `inject-governance.sh` to keep exactly one managed governance block in `CLAUDE.md` and `AGENTS.md`,
So that the plugin's rules reach every session without breaking the template's docs-check, invariants or linters and without touching my own text.
**Read:** § Governance Block (content rules and exact text); § Script Contracts › `scripts/inject-governance.sh`; ADR-3; PRD FR-8, AC-8.1–AC-8.3. **Size:** M.

**Acceptance Criteria:**

- Given a materialized `CLAUDE.md` and `AGENTS.md` without markers, when `inject-governance.sh` runs, then each file ends with exactly one blank line followed by the exact text of § Governance Block › Exact text (markers included, one trailing newline), stdout is `UPDATED: <file>` per file, content before the block keeps its sha256, and a missing file is created holding only the block (`CREATED: <file>`).
- Given a second run, when it completes, then both files are byte-identical and stdout is `UNCHANGED: CLAUDE.md` and `UNCHANGED: AGENTS.md` (AC-8.1, NFR-1).
- Given duplicate pairs, an orphan begin, an orphan end, an inverted pair, markers inside ```` ``` ```` and `~~~` fences (ignored as markers) and CRLF line endings, when it runs, then each repairs to exactly one block (first valid pair replaced in place, otherwise appended), prints `REPAIRED: <file> (<n> stray marker line(s) removed)` where it removed lines, and keeps the original line endings of the rest of the file (AC-8.1).
- Given an `AGENTS.md` whose marker pair sits between `<!-- verification:start -->` and `<!-- verification:end -->`, when it runs, then that pair is removed and the block is appended at the end of the file, never inside the verification region.
- Given `--diff`, then a unified diff per changed file and `WOULD: update <file>` print and checksums stay unchanged; a symlinked or non-regular target exits 1; an unknown flag exits 2; each run finishes in ≤ 5 s.
- Given the injected files, when `docs_rules` and the content-rule cases run, then rules 1–4 and invariant (e) report nothing, no code span starts with `/`, the backticked tokens are exactly those of content rule 2, there is no `make <x>` span, numbered list, fence or table, and neither the literal assembled from `rust-service-` + `template` (assembled from two halves in the test) nor the fixture's `TEMPLATE_REPOSITORY` name appears in what was written; one case asserts the block equals the architecture's exact text (AC-8.2).
- Given CI's pinned tools, when the K7 cases run, then markdownlint-cli2 with the fixture's `.markdownlint-cli2.yaml` and typos with its `_typos.toml` pass on both files (skipped locally with a reason), and the script meets SC-SCRIPT and SC-SUITE (AC-8.3).

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/inject-governance.sh`
- `plugins/rust-backend-sdlc/tests/inject-governance.bats`

**Depends on:** 1.1, 1.5, 1.6

**FRs:** FR-8 (NFR-1, NFR-13, NFR-14)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/inject-governance.sh && v_banned plugins/rust-backend-sdlc/scripts/inject-governance.sh && v_gen plugins/rust-backend-sdlc/scripts/inject-governance.sh`
- `v_bats inject-governance 30`

### Story 2.3: Local permission allowlist merge

As a developer preparing a service,
I want `merge-settings.sh` to add the plugin's allow and deny entries to my git-ignored local settings without touching protected settings,
So that headless runs can execute the loop while the template's deny and ask rules, and the plugin's own backstop, stay effective.
**Read:** § Permissions Strategy (allow rows 1–39, deny G/H/B/M tables); § Script Contracts › `scripts/merge-settings.sh`; ADR-6; § Degrade Matrix row D4; PRD FR-9 (amended), AC-4.2, AC-9.1–AC-9.3. **Size:** M.

**Acceptance Criteria:**

- Given the materialized stub (where `protected-config.toml` lists `.claude/settings.json` and `.gitignore` ignores `.claude/settings.local.json`), when `merge-settings.sh` runs, then `.claude/settings.local.json` holds `permissions.allow` = the existing entries in order followed by the 66 entries of allow rows 1–39 in table order (absolute `<root>` from `resolve_plugin_root`, literal `<uid>:<gid>` from `id -u`/`id -g`, 13 per-executable entries, the library entry and their 14 quoted variants) and `permissions.deny` = the existing entries byte for byte followed by the 29 entries G1–G9, H1–H8, B1–B2, M1–M10, with `ask`, `hooks`, `env`, `defaultMode` and every other key untouched, written as `json.dumps(obj, indent=2, ensure_ascii=False)` plus a newline, and stdout `WROTE: .claude/settings.local.json (+66 allow, +29 deny)` on a fresh file.
- Given a second run, when it completes, then the file is byte-identical and stdout is `UNCHANGED: .claude/settings.local.json` (AC-9.2, NFR-1).
- Given `--file shared` while `.claude/settings.json` is listed in `files` or below a listed directory, or while `protected-config.toml` is unparseable, when it runs, then it prints `REFUSED: .claude/settings.json is protected (protected-config.toml lists it); merged JSON follows` (or the `(protected-config.toml unparseable)` form) followed by the merged JSON, exits 1, and the checksum of `.claude/settings.json` is unchanged under every flag combination (AC-4.2, AC-9.1, D4).
- Given `.claude/settings.local.json` not git-ignored, when it runs, then it prints `REFUSED: .claude/settings.local.json is not git-ignored` and exits 1, while `--print` still prints the merged JSON and writes nothing.
- Given the merged result, when inspected, then no allow entry is `Bash(bmalph:*)` or contains `curl`, `bypassPermissions` or `defaultMode`, no allow entry contains `/*)` after the plugin root, every plugin-root entry names an existing executable under `<root>/scripts/`, and `--with-qa-network` adds nothing and prints `INFO: QA probes run through common.sh http_probe; no curl entry is written` (AC-9.3 as amended).
- Given malformed existing JSON or a symlinked target, when it runs, then it exits 1 with the file unchanged; it finishes in ≤ 5 s; usage errors exit 2; the script meets SC-SCRIPT and SC-SUITE.

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/merge-settings.sh`
- `plugins/rust-backend-sdlc/tests/merge-settings.bats`

**Depends on:** 1.5, 1.6

**FRs:** FR-9, FR-4 (NFR-1, NFR-3, NFR-5, NFR-10, NFR-14)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/merge-settings.sh && v_banned plugins/rust-backend-sdlc/scripts/merge-settings.sh && v_gen plugins/rust-backend-sdlc/scripts/merge-settings.sh`
- `v_bats merge-settings 24`

### Story 2.4: Command-side helpers (`common.sh` section `command helpers`)

As a feature engineer running plugin commands,
I want tested dispatcher functions for issue derivation, commit message files, hook status, log polling, loopback HTTP probes, protected-change detection and context-name validation,
So that commands never improvise shell for these checks and every one is covered by the plugin-root allow entry.
**Read:** § Script Contracts › `scripts/lib/common.sh` rows `derive_issue_number`, `commit_msg_file`, `hooks_active`, `wait_log`, `http_probe`, `protected_changes`, `validate_context_name`; § Implementation Patterns › Git rules; ADR-13, ADR-15, ADR-25, ADR-27; PRD FR-2 (AC-2.1), FR-14 (AC-14.1), FR-33. **Size:** L.

**Acceptance Criteria:**

- Given `derive_issue_number [--handle N] [--title T] [--branch B] [--body TEXT]`, when sources disagree, then the first source in the order handle (`^[1-9][0-9]*$`), title (`^[a-z]+\(#([0-9]+)\):`), branch (`^[a-z]+/([0-9]+)-`), body (`(^|[^A-Za-z])Closes #([0-9]+)`) wins, a PR number that differs from every source is ignored, and no source returns 1 with no output (AC-2.1, second half).
- Given `commit_msg_file '<subject>'`, when the subject passes `is_commit_subject`, then it writes the subject plus a newline atomically to `target/rust-sdlc/tmp/commit-<utc_stamp>.txt` and prints that path; an invalid subject exits 1 and writes nothing.
- Given `hooks_active [DIR]`, when run, then it prints `HOOKS: active` (exit 0) only when `git config --local --get core.hooksPath` is exactly `.githooks` and `.githooks/commit-msg`, `.githooks/pre-commit`, `.githooks/pre-push` exist and are executable; otherwise `HOOKS: unset` (no local value, a global-only value included), `HOOKS: foreign <value>` or `HOOKS: missing <file>`, each exit 1, and it never writes git configuration.
- Given `wait_log LOG [MAX_SECONDS]`, when LOG is outside `target/rust-sdlc/logs/` and `target/rust-sdlc/new-service/` it exits 2; otherwise it checks the last line every 30 s for at most MAX (30–540, default 110) seconds and prints the last 40 lines (control characters stripped) and `RUST_SDLC_EXIT=<n>` (exit 0) or `WAITING: <log> (<elapsed>s)` (exit 1); cases cover a finished log, a still-running log with MAX 30 and an outside log.
- Given `http_probe METHOD PATH [--header 'K: V']... [--body TEXT | --body-file F]`, when called, then the URL is the profile's validated `service.base_url` plus PATH and the curl stub's argv is exactly `curl --noproxy '*' --proto =http --max-time 10 -sS -i -X <METHOD> [-H …] [--data-binary @-|@F] -- <url>`, output is `HTTP_STATUS: <code>`, the headers and at most 64 KiB of body; a METHOD outside `GET HEAD POST PUT PATCH DELETE OPTIONS`, a PATH not matching `^/[A-Za-z0-9._~%/?&=:,+-]*$`, more than 10 headers, a header with CR, a `--body` over 16 KiB and a `--body-file` outside `target/rust-sdlc/tmp/` exit 2; a transport failure exits 1; no argument can add a second URL or a curl option.
- Given `protected_changes <sha>`, when run, then it prints `PROTECTED: <path> (<commit>|working tree)` for every `files`/`directories` entry of `protected-config.toml` changed since `<sha>` (diff plus untracked files) and `PROFILE_CHANGED: .claude/rust-sdlc.yml` when the profile existed at `<sha>` and differs now, `INFO: no protected-config.toml` when that file is absent; exit 0 none, 1 any, 2 usage; cases: none, protected file, profile changed, profile absent at base (exempt).
- Given `validate_context_name <group> <context> [ROOT]`, when run over the fixture tree, then it reads the live tree (`[workspace].members`, each member's `package.name`, `crates/<c>` and `crates/*/<c>` directories, never the profile) and refuses with exactly one `REFUSED: <rule> <detail>` line (rules `name-format`, `reserved-context`, `context-exists`, `member-exists`) every name of the AC-14.1 list (uppercase, leading digit, trailing hyphen, double hyphen in group and in context, each reserved context `shared service xtask test-support e2e-tests`, `billing/invoice`, `sales/invoice`, `sales/internal`, `billing/health-check`, a member package `<c>-domain` at a non-standard path, a context present in the tree but absent from a stale profile) and accepts valid names including `service/ledger`.
- Given the section, when checked, then it starts with `# section: command helpers`, each of the seven functions runs through the dispatcher, `shellcheck -x` and the banned-construct check are clean, and `tests/common-lib.bats` holds at least 42 `@test` cases in total.

**Files owned:**

- `plugins/rust-backend-sdlc/scripts/lib/common.sh` (section `command helpers`; appended after `core`)
- `plugins/rust-backend-sdlc/tests/common-lib.bats` (section `command helpers`; appended)

**Depends on:** 1.2, 1.3, 1.6

**FRs:** FR-33, FR-2, FR-14, FR-20 (NFR-5, NFR-10, NFR-14)

**Verification:**

- `v_sh plugins/rust-backend-sdlc/scripts/lib/common.sh && v_banned plugins/rust-backend-sdlc/scripts/lib/common.sh && v_gen plugins/rust-backend-sdlc/scripts/lib/common.sh`
- `v_bats common-lib 42`
- `test "$(plugins/rust-backend-sdlc/scripts/lib/common.sh derive_issue_number --branch feat/12-add-x)" = 12`

### Story 2.5: `/rs-sdlc-setup` command and setup walkthrough

As a developer preparing a service,
I want one command that runs preflight, bmalph setup, profile generation and validation, governance, the allowlist, hooks and docs-check in order,
So that a fresh checkout is ready for the plugin after one command and one commit.
**Read:** § Command Contracts › Shared command contract, Exit strings (row `setup`), `/rs-sdlc-setup`; § Implementation Patterns › Git rules (hooks); § Documentation Set row `docs/setup-walkthrough.md`; ADR-3, ADR-6, ADR-21, ADR-24; § Degrade Matrix D3, D4, D5, D25; PRD FR-4, AC-4.1, AC-2.3. **Size:** M.

**Acceptance Criteria:**

- Given SC-CMD, when `commands/rs-sdlc-setup.md` is read, then its frontmatter equals § `/rs-sdlc-setup` (`argument-hint: "[--refresh] [--with-qa-network] [--print-settings] [--exec host|container]"`), it has no `allowed-tools`, no `validate-profile.sh` first-fence requirement, `MAX_ITERATIONS=5` (regeneration attempts), the escalation block with `stage: setup`, and the `setup` exit string byte-equal to § Exit strings.
- Given the Procedure, when read, then it lists FR-4 steps 1–9 in order: `"${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh" --report` (any FAIL → escalate with the table); `make bmalph-setup` only when `_bmad/` is absent, `make.bmalph_setup` is mapped and the tracked tree is clean, else `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` plus `NEXT: commit or stash, then make bmalph-setup`, then the bmalph floor re-check; `generate-profile.sh` with `--refresh` passed through and `--exec host` → `--run-in-container false`, `--exec container` → `--run-in-container true`, no flag otherwise; `validate-profile.sh` with at most 5 `--refresh` regenerations; `inject-governance.sh`; `merge-settings.sh [--with-qa-network] [--print]` under the protected-settings rule (D4); `common.sh hooks_active` (`unset` → `make install-hooks` and re-check, `foreign`/`missing` → escalate with `blocking_finding: core.hooksPath=<value>`); `make docs-check` backgrounded only under the step-8 conditions, else a D3/D25 degrade note never reported as passed; the summary with written and `UNCHANGED:` files, degrade notes, the instruction "commit `.claude/rust-sdlc.yml`, `CLAUDE.md` and `AGENTS.md` together in one commit" and a warning when the branch is not the default branch (AC-4.1, CC-17).
- Given the command text, when checked, then it carries the background and container-precondition sentences verbatim, names the read-only `git config --get core.hooksPath` form and `hooks_active`, states that it never writes `.claude/settings.json` when `protected-config.toml` lists it, uses only suffix-form make calls, and P1–P7 match only prohibition lines (AC-2.3).
- Given `docs/setup-walkthrough.md`, when read, then it walks install (`claude plugin marketplace add VilnaCRM-Org/claude-plugins`, `claude plugin install rust-backend-sdlc@vilnacrm-plugins`), the setup run with sample `DONE:`/`UNCHANGED:`/`DEGRADED:` output, the single commit, protected settings and `.claude/settings.local.json`, the dirty-tree degrade, `--exec`, re-runs after a template-sync merge (J6) and after `claude plugin update`, the user-scope install recommendation (ADR-21), and a version-floors list (bmalph ≥ 2.11.0, claude ≥ 2.1.248, gh ≥ 2.0, python3 ≥ 3.11, GNU make ≥ 4.0, bash ≥ 4.4, git ≥ 2.30, node ≥ 20, jq optional) that the plugin README copies byte for byte (CC-25), and it meets SC-DOC.

**Files owned:**

- `plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md`
- `plugins/rust-backend-sdlc/docs/setup-walkthrough.md`

**Depends on:** 1.7, 1.8, 2.1, 2.2, 2.3, 2.4

**FRs:** FR-4, FR-1, FR-2, FR-41 (NFR-1, NFR-3, NFR-5, NFR-13, NFR-16)

**Verification:**

- `v_lint 'commands/rs-sdlc-setup\.md'`
- `v_md plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md plugins/rust-backend-sdlc/docs/setup-walkthrough.md`
- `C=plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md; v_sent $C && v_esc $C && v_exit setup $C && v_p17 $C && v_suffix $C && v_cmdtok $C plugins/rust-backend-sdlc/docs/setup-walkthrough.md`
- `grep -qF 'git config --get core.hooksPath' plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md && grep -qF 'hooks_active' plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md && grep -qF 'MAX_ITERATIONS=5' plugins/rust-backend-sdlc/commands/rs-sdlc-setup.md`

