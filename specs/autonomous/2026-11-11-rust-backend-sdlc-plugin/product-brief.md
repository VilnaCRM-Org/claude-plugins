---
stepsCompleted: [step-01-init, step-02-vision, step-03-users, step-04-metrics, step-05-scope, step-06-complete]
inputDocuments:
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/task-framing.md
  - specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/research.md
  - specs/autonomous/2026-06-09-php-backend-sdlc-plugin/product-brief.md (depth bar, same artifact kind)
  - /home/user/rust-service-template/docs/new-service.md (re-read in this stage)
date: 2026-11-11
author: Mary (BMAD analyst agent, autonomous run for the main agent acting as user surrogate)
mode: autonomous (no human pauses; A/P/C menus skipped; assumptions recorded inline)
workflowType: product-brief
revision: 2 (reviser pass 2026-11-11; 29 review findings applied, see Revision Log)
---

# Product Brief: `rust-backend-sdlc` Claude Code Plugin

Path conventions: `tpl/` = the Rust service template checkout (`/home/user/rust-service-template`, HEAD `3e0bd3e`);
`php/` = `plugins/php-backend-sdlc/`; `react/` = `plugins/react-frontend-sdlc/`; `repo/` = the marketplace root.
"KF n", "H n" and "X n" cite Key Finding n, Integration Hazard n and Reference Defect n of `research.md`.

> Assumption: the BMAD create-brief workflow writes to `{planning_artifacts}/product-brief-<project>-<date>.md` and
> appends its own section names (`Core Vision`, `MVP Scope`). The task framing fixes the bundle path, and the planning
> chain requires the H2 set used below, so the file is `specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/product-brief.md`
> and the step content is mapped as follows: step 2 (vision) → Executive Summary, Problem Statement, Proposed
> Solution; step 3 (users) → Target Users; step 4 (metrics) → Goals, Success Metrics; step 5 (scope) → Scope, Out
> of Scope; constraints, risks and assumptions carry the elicitation the menus would have produced. Input-document
> discovery (step 1) found the two bundle inputs; `_bmad-output/` and `docs/` hold nothing for this topic.
>
> Assumption: identity decisions in `task-framing.md` (name, version, prefix, command list, profile path, markers,
> label, log prefix, tag namespace) are fixed and are restated here only as constraints, never re-opened.

## Executive Summary

`rust-backend-sdlc` 0.1.0 is a Claude Code plugin for the `vilnacrm-plugins` marketplace
(`plugins/rust-backend-sdlc/`) that turns the Rust service template into a product line. One command creates a new
microservice from the template (`/rs-sdlc-new-service`), one command adds a bounded context
(`/rs-sdlc-new-context`), and one command drives a feature from a few sentences to a ready-to-merge pull request
(`/rs-sdlc`): GitHub issue → BMAD planning bundle → bmalph/Ralph implementation → multi-lens review with the BMAD
FR/NFR gate → black-box QA against the running service (REST, GraphQL, `/ping`, `/api/health`) → finished PR with
CI green and every AI review thread resolved. Every stage is bounded (5 iterations; FR/NFR gate re-runs 3),
resumable from durable artifacts, and ends in exactly one of `SUCCESS` or `ESCALATED` with the canonical
`=== SDLC ESCALATION ===` block inherited from `php-backend-sdlc`.

The template already defines what "good" means — 31 ordered gates in 7 stages (`make ci-list`), 100% line and
function coverage, zero surviving mutants on the diff, clippy `-D warnings` over `all pedantic nursery cargo` plus
60+ restriction lints, cognitive complexity 8 / 50 lines / 5 arguments / nesting 5, zero architecture violations,
current contract snapshots — but it ships no driver that gets a change there. The PHP plugin has that driver, yet
it cannot be dropped in: its setup writes the protected `.claude/settings.json` (blocked by the template's
PreToolUse hook), its commit messages fail the template's commit-msg hook, its governance block would fail
`make docs-check` in every service, its implement stage never stages the plan where bmalph can see it, and it
carries 19 catalogued defects (X1–X19). `rust-backend-sdlc` ports the 70–80% of the PHP contract that is
language-agnostic, fixes those defects, and rebuilds the remainder around 32 verified template hazards (H1–H32).

v0.1.0 ships 10 commands, 7 agents, 28 skills plus 2 meta-guides, 13 executable scripts plus `scripts/lib/common.sh`,
4 Workflow-tool scripts with a deterministic harness, 1 configuration file (`config/new-service.defaults.json`),
9 docs plus a plugin `README.md`, and 16 bats suites, wired into the marketplace manifest, the root `README.md` and
`ci.yml`. The Workflow-tool layer is the last epic and the cut line (without it: 0 workflows, 8 docs, 15 suites). Success is
measured by four goals: a template-clean new service in one guided command (G1), a bounded and resumable feature
loop with an honest report contract (G2), a gate-verified bounded context in one command (G3), and quality bars
that the plugin can only tighten, never relax (G4) — plus a release gate of 0 plugin-quality lint findings and a
green marketplace CI.

## Problem Statement

### The gap: strict gates, no driver

The template answers "what must be true before merge" with unusual precision, and gives an AI agent rules
(`AGENTS.md`, 11 repository skills, 54 BMAD wrapper commands, a pinned bmalph 2.11.0) — but nothing that runs the
software-delivery loop end to end. Every service team therefore hand-drives the same sequence: write an issue, plan,
implement against 31 gates, review, exercise the running service, push, chase CI and AI-reviewer threads. Across
several services that hand-driving becomes both slow and inconsistent, which is exactly what the template exists to
prevent.

### Concrete pain

| # | Pain | Evidence | Consequence today |
| --- | --- | --- | --- |
| P1 | Creating a service is a 10-section manual guide with traps | `tpl/docs/new-service.md` §1–§10; KF 17, H29, H30 | Deterministic edits (`[workspace.package]` `description`/`repository`/`version`, `bmalph/config.json` `name`/`description`, README badges and intro, CHANGELOG reset to the cocogitto skeleton, `specs/` reset, sync flavour + `.templatesyncignore`) are done by hand. Traps: a new `description` changes the OpenAPI title (`<description> API`), so `make generate-openapi-spec` and a commit are needed before `validate-contract-snapshots` passes; the checkout directory name becomes the Compose project and image names; a version change needs `cargo update --workspace`; removing `crates/company-subdomain/` breaks docs-check rule 3 on three synchronised lines and risks an empty GraphQL root. |
| P2 | Adding a bounded context is a 12-step, 5-gate procedure | KF 16; `tpl/xtask/src/scaffold.rs`; `tpl/docs/new-service.md` §5 | `make new-context group=<g> context=<c>` writes 6 files and 3 workspace members only. The engineer then orders `[workspace.dependencies]` entries against cargo-deny `unused = "deny"`, wires `Adapters`, `bootstrap::router`, `AppState`, `openapi::api_router` and `graphql::schema` plus three tests that construct `Adapters { .. }` and two contract-pinning tests, adds one `workspace.dsl` component per crate (`make validate-architecture-model` fails until then), a reversible migration with `.sqlx/` metadata, and regenerated snapshots. |
| P3 | Gates sit at the extreme and fail in Rust-specific ways | KF 3, KF 25; `tpl/clippy.toml`; `tpl/.cargo/mutants.toml` | Coverage counts unit + integration tests only (e2e is not instrumented); a body inside an `#[async_trait]` method is invisible to coverage and complexity; each mutant is judged by its own crate's tests; `#[allow]` fails the invariants gate; `unwrap`/`expect`/`panic`/indexing/`as` are banned in production code. A generic agent loops on these until its budget is gone. Full `make ci` takes about 25 minutes on 4 vCPU, beyond a 600 s foreground tool call. |
| P4 | The template's planning output is invisible to bmalph | KF 8, H15, H16 | The template's `bmad-autonomous-planning` skill writes `specs/<bundle-id>/` and forbids `_bmad-output/`; `bmalph implement` reads only `_bmad-output/planning-artifacts/`, `_bmad-output/planning_artifacts/` and `docs/planning`, ignores a plain `research.md`, and blocks on any match of `/NO[-\s]?GO/i` in the readiness file. Without a staging step the Ralph loop starts with nothing to do. |
| P5 | The PHP plugin is incompatible with a template-derived service | KF 4–7, KF 24, X1–X19 | Writes `.claude/settings.json` (protected; hook exit 2, and CI G25 fails if bypassed); container rule `docker compose exec php` has no Rust meaning (the template is make-only with `RUN_IN_CONTAINER=1`); commit forms `review: gate iteration <n> remediation` and `Apply review suggestion: …` fail `^(feat\|fix\|refactor\|build\|chore\|ci\|docs\|style\|perf\|test)\(#[0-9]+\): .*`; governance text would trip docs-check rules 2–4; ledgers under `.sdlc/` are scanned by Prettier, gitleaks and typos; double-quoted flow lists in the profile fail `make lint-prettier`. |
| P6 | Environment hazards break naive automation | KF 11, KF 19, KF 20, H17, H25–H27 | Host `yq` is the kislyuk Python wrapper while CI has mikefarah `yq` (13 of 47 PHP YAML tests fail on the host); `setup-test-db` drops and recreates one shared test database, so parallel agents corrupt each other; G17, G15 and G25 depend on git state (uncommitted snapshots, untracked files, a missing `origin/main`); HOST targets exit 2 without Docker. |

### Problem impact

- **Copy-drift returns.** Without an installable artifact each service team copies prompts and scripts from wherever
  they last worked. The PHP precedent is documented: copied skills in one service claimed a persistence engine the
  service did not use (php product brief §1). Rust services would repeat it with the template's subtler rules.
- **Lead time is dominated by gate-chasing, not design.** A feature that is small in domain terms still touches
  manifests, wiring, `workspace.dsl`, migrations, `.sqlx/`, two contract snapshots and tests that must reach 100%
  coverage and kill every mutant.
- **Unattended agents fail dangerously or wastefully.** The only shortcuts — `#[allow]`, coverage exclusions,
  equivalent-mutant entries, allow-list edits, lowered limits — are exactly what the template forbids or routes to
  a human-gated label (`approved-config-change`, `approved-breaking-change`). An agent without that knowledge either
  burns its budget or produces a PR that the change-control job rejects.
- **The template's promise erodes.** `tpl/docs/new-service.md` §10 ends "A service that passes it is as strict as
  the template." That holds only if every service actually reaches green through the same process.

### Why existing solutions fall short

| Option | What it gives | Where it falls short |
| --- | --- | --- |
| The template alone | Gates, `AGENTS.md`, 11 skills, 54 BMAD wrappers, `make new-context`, `make bmalph-setup` | No issue → PR loop, no review or FR/NFR gate, no black-box QA, no PR finishing; bmalph cannot see `specs/<bundle-id>/`; new-service steps manual. |
| `php-backend-sdlc` 0.1.0 | The proven SDLC contract (stage machine, guards, escalation block, degrade taxonomy, ledgers, FR/NFR gate) | PHP toolchain and container model; breaks five template gates and the commit-msg hook (P5); 19 defects (X1–X19) including no bmalph staging (X5) and `.ralphrc` at the wrong path (X6). |
| `react-frontend-sdlc` | Hardened FR/NFR gate (fail-closed, PR sources, baseline NFR catalog), PR-state sensor, Workflow-tool scripts | Frontend stack; its feature workflow nests `workflow()` two levels deep (KF 22), so it escalates on every fresh PR head. |
| Plain Claude Code in the service | The repository's own skills and `AGENTS.md` | No bounded loops, no resume, no report contract, no cross-lens review, no automated PR finishing; every run is improvised. |

## Target Users

> Assumption: persona names are illustrative; the segments are derived from the request (create services, build
> features) and the task-framing goals G1–G4; the framing does not name personas. The autonomous agents that execute
> the plugin's procedures are added as a tertiary segment.

### Primary users

**Service creators — "Sam", tech lead starting `billing-service`.** Sam has a domain to build and a deadline, and
the organisation mandates the Rust template. Today Sam reads `docs/new-service.md`, edits `Cargo.toml`,
`bmalph/config.json`, README badges and `CHANGELOG.md` by hand, guesses which sync workflow to keep, forgets to
regenerate the OpenAPI snapshot after changing `description`, and discovers the failure in CI on the first PR.
Success for Sam: one command produces a repository whose bootstrap PR is green on the first push, with the SDLC
tooling already set up, and a printed list of the human decisions left (secrets, labels, branch protection,
keep-or-remove the example context). The "this is exactly what I needed" moment: `/rs-sdlc-new-service` prints
`DONE:` for every deterministic step, `NEXT:` for each remaining human step, and the bootstrap PR turns green.

**Feature engineers — "Alex", backend engineer on an existing template-derived service.** Alex knows Rust but not
every template rule (no `mod.rs`, `ValidatedJson` instead of bare `Json`, `Clock` and `UuidGenerator` ports instead
of `SystemTime::now`/`Uuid::new_v4`, sibling `tests.rs`, `#[expect(lint, reason = "…")]` only where permitted).
Today a three-file feature turns into a day of gate-chasing. Success for Alex: describe the task in a few
sentences, get an issue, a plan to skim, an implementation that passes the gates stage by stage, a QA report with
real HTTP evidence, and a PR that is CI-green with no open AI-review threads — or a precise escalation saying which
human decision is needed. Adding a context (`/rs-sdlc-new-context billing invoice`) is the same experience for the
12-step checklist C1–C12 (Proposed Solution, entry point 2).

### Secondary users

**Reviewers and maintainers — "Jordan", code owner of several services.** Jordan reviews PRs produced by people and
agents. Jordan needs evidence, not claims: which targets ran and which did not (with the reason), FR/NFR gate
verdicts on the exact head SHA (commit status `BMAD FR/NFR Review Gate`), one conclusion comment per review lens,
review ledgers, and the assurance that no protected file or threshold changed without `approved-config-change`.
Success: review time spent on design, never on re-running gates or spotting suppressions.

**Platform team — maintainers of the template and the marketplace.** They own the gates, the protected
configuration, the template sync, and the plugins. They need the plugin to consume the template rather than fork
it: read lists at runtime (`make ci-list`, `cargo xtask config-guard --list`), defer to the repository's skills
(repository wins), never write protected files, survive template sync (re-runnable setup restores the governance
block), and pass the marketplace's own quality bar (plugin-quality lint, generalization audit, shellcheck, bats,
markdownlint). Success: a template change does not require a plugin release unless a gate name or path changes,
and the plugin can be upgraded without touching any service repository.

### Tertiary users: autonomous agents

Ralph loops started by `bmalph run`, Workflow-tool scripts (`workflows/rs-sdlc-*.js`) and the plugin's seven
subagents consume commands, skills and agent prompts as operating procedures. They need machine-readable handles
(`ISSUE_URL:`, `ISSUE_NUMBER:`, `SPECS_DIR:`, `---RALPH_STATUS---`, `FR_NFR_REVIEWER:`, `AI_REVIEW_VERDICT:`,
`## Status:`), hard iteration limits, and explicit degrade paths that never loop.

### User journeys

| Segment | Discovery | Onboarding | Core usage | Success moment | Long term |
| --- | --- | --- | --- | --- | --- |
| Service creator | Marketplace `README.md` row; template `docs/new-service.md` | `claude plugin marketplace add` + `claude plugin install rust-backend-sdlc@vilnacrm-plugins` | `/rs-sdlc-new-service billing-service --description "Billing"` (GitHub template mode, local path or in place) | Bootstrap PR `chore(#1): initialize service from template` green; profile and governance committed | Re-runs `/rs-sdlc-setup` after each template-sync PR; hands the service to feature engineers |
| Feature engineer | Governance block in `CLAUDE.md`/`AGENTS.md` names the plugin commands in prose | `/rs-sdlc-setup` once per clone (preflight, profile, governance, local allowlist) | `/rs-sdlc "<few sentences>"`; individual stages (`/rs-sdlc-plan`, `/rs-sdlc-review`, …) when resuming or iterating | `=== SDLC RUN REPORT ===` with `result: SUCCESS` and a PR ready to merge | Uses `/rs-sdlc-new-context` for new domains; escalations become human decisions, not debugging sessions |
| Reviewer / maintainer | PR body and review comments produced by the plugin | None (reads PRs) | Reads ledgers, gate status, "targets run / not run" list | Approves on design, not on gate re-runs | Trusts that no protected change or suppression slips in |
| Platform team | Marketplace CI and release notes (`rust-backend-sdlc-vX.Y.Z`) | Wires CI jobs, reviews plugin PRs | Updates the plugin when the template renames a gate or path | Template sync and plugin upgrades never conflict | One SDLC contract across PHP, React and Rust services |

## Proposed Solution

### Product shape

A single installable plugin, `plugins/rust-backend-sdlc/`, version `0.1.0`, MIT, author VilnaCRM, mirroring the
directory layout and contracts of `php-backend-sdlc` and adopting the Workflow-tool layer of `react-frontend-sdlc`.
Per-repository variance lives in one generated, committed file, `.claude/rust-sdlc.yml` (`schema_version: 1`), that
skills, agents and scripts read at runtime. The plugin never renders skills per repository, never copies its skills
into `.claude/skills/`, and never vendors `_bmad/` or `.ralph/`.

### Three entry points

1. **New service — `/rs-sdlc-new-service <name> --description "<text>" [--owner <org>] [--visibility private|public]
   [--template <owner/repo> | --template-path <dir> | --in-place] [--dest <parent-dir>] [--version <x.y.z>]
   [--intro "<text>"] [--sync-flavour app|pat] [--keep-specs] [--issue <N>] [--exec host|container] [--dry-run]`.**
   - **Flags.** `--dest` is the parent directory (default `.`); the checkout is always `<parent-dir>/<name>`, so the
     directory name equals the Compose project and image name prefix (`tpl/docs/new-service.md` §1). `--version`
     defaults to `0.1.0`. `--intro` replaces the README introduction (default: one sentence built from
     `--description`). `--keep-specs` keeps the template's planning bundle. `--issue` supplies the bootstrap issue in
     local mode. `--exec` selects how the make steps run (default `container` when Docker is reachable and the host has
     no `cargo`, else `host`); setup records the same choice as `capabilities.run_in_container`. `--dry-run` prints
     `WOULD:` lines, creates nothing on GitHub and writes nothing.
   - **Modes.** GitHub mode: `--template` (or the configured default slug), or `--in-place` in a checkout whose
     `origin` is a GitHub repository, with `gh auth status` OK. Local mode: `--template-path`, or `--in-place` without
     a GitHub `origin`. The template slug default lives in `config/new-service.defaults.json` (override order:
     `--template` > `RUST_SDLC_TEMPLATE_REPO` > config), outside the four generalization-scanned directories.
   - **Source step — `scripts/new-service.sh --phase source`.** It first probes `gh api repos/<slug> --jq .is_template`.
     - `true` → template flow: `gh repo create <owner>/<name> --template <slug> --private|--public` without `--clone`,
       poll `gh api repos/<owner>/<name>/commits?per_page=1` up to 10 × 3 s, then `gh repo clone <owner>/<name>
       <parent-dir>/<name>`.
     - `false` → clone-and-push (the case of the default template today: `is_template` is `false`, checked live on
       2026-11-11; `docs/new-service.md` §1 names "clone the template and push it to a new repository" as the
       alternative): `gh repo create <owner>/<name> --private|--public` (empty, no `--clone`), a shallow
       `gh repo clone <slug> <tmp> -- --depth 1`, `git -C <tmp> archive HEAD | tar -x -C <parent-dir>/<name>`
       (tracked files only, fresh history; the template has no `export-ignore` attributes), `git init -b main`,
       `origin` set to the new repository. It prints `IMPORT_PENDING: <slug>@<sha>` and the advice line
       `NEXT: ask the template owner to enable Settings > Template repository`.
     - `--template-path <dir>`: the same `git archive HEAD` import from a local checkout; no remote, no push.
     - `--in-place`: `SKIP: source (in place)`.
     - Re-run: when `<owner>/<name>` exists and `<parent-dir>/<name>` is a clone whose `origin` matches →
       `SKIP: source (exists)`; when the repository exists but the directory is missing or has another `origin` →
       exit 1 with the reason. A second `gh repo create` never runs.
   - **Customize step — `scripts/new-service.sh --phase customize`** performs the deterministic
     `docs/new-service.md` steps: identity inside `[workspace.package]` only (`description`, `repository`); version
     (`UNCHANGED: version <v>` when the copied version equals the target, else `NEXT: scripts/set-version.sh <v>`,
     executed by the command at S9, because a repository created from the template copies the version the template
     last released, §2); `bmalph/config.json` `name`/`description`; README title, badges and intro; `CHANGELOG.md`
     reset to the cocogitto skeleton; `specs/` reset, defined as deleting every bundle directory under `specs/` that
     the source commit shipped (enumerated at runtime, never named in the script), skipped with `--keep-specs`; sync
     flavour (keep one workflow and its guide, delete the other pair, add both deleted paths to `.templatesyncignore`).
     When `--sync-flavour` is omitted, the command asks in an interactive session; headless, the script prints
     `SKIP: sync flavour (undecided)` plus `NEXT: re-run with --sync-flavour app|pat`, and G1(a) counts that run as not
     met. Each step prints `DONE:`/`SKIP:`/`UNCHANGED:`; exit 0 success, 1 refused or failed (the failing step leaves
     its file untouched), 2 usage error. `--phase all` (default for standalone use) runs both phases. The script never
     commits, never pushes and never removes the example context.
   - **Ordered sequence run by the command** (status: EXECUTED by the command, or printed as `NEXT:`):

     | Step | Action | When | Status |
     | --- | --- | --- | --- |
     | S1 | `new-service.sh --phase source` | always | EXECUTED |
     | S2 | ensure label `rust-backend-sdlc`; create bootstrap issue N with the G1(c) checks as acceptance criteria; print `ISSUE_NUMBER:` | GitHub mode | EXECUTED; local mode takes `--issue <N>` |
     | S3 | `git add -A`; commit `chore(#N): import template <slug> at <sha7>` on `main`; `git push -u origin main` (hooks are not yet active; the message is hook-valid anyway) | clone-and-push only | EXECUTED |
     | S4 | `git switch -c chore/N-initialize-service` | N known | EXECUTED |
     | S5 | `new-service.sh --phase customize …` | always | EXECUTED |
     | S6 | judgment steps: keep the example context (default; removal is a later guided story, A5); secrets, variables and labels from the new repository's `docs/new-service.md` §8; branch protection from `docs/repository-settings.md` | always | NEXT |
     | S7 | `make doctor`, report only: on a fresh host it exits 1 for pinned tools that S8 installs; its `[MISSING]`/`[OUTDATED]` lines are shown and the command continues | always | EXECUTED |
     | S8 | `make bootstrap` (prerequisite check, `make install` or `install-bats.sh`, `install-hooks`, full doctor, `make start` with `--wait-timeout 900`), run in the background and polled every 30 s up to 60 min, log `target/rust-sdlc/new-service/bootstrap.log`; there is no separate `make install-hooks` step | Docker reachable | EXECUTED; otherwise `NOT RUN (no Docker)` |
     | S9 | `scripts/set-version.sh <v>` when S5 printed it (host: directly; container: through the Makefile's `EXEC` prefix `docker compose exec -T --user <uid>:<gid> app`, `tpl/Makefile:35`) | version differs | EXECUTED when a toolchain or the `app` container exists, else NEXT |
     | S10 | `make generate-openapi-spec` (the OpenAPI title becomes `<description> API`) | always | EXECUTED when S8 succeeded or the host toolchain exists; else NEXT and the command stops before S11 |
     | S11 | commit `chore(#N): initialize service from template` (identity, version, `Cargo.lock`, snapshot, service-owned files); the hooks from S8 run `make pre-commit` | N known | EXECUTED; local mode without `--issue`: NEXT with a `<N>` placeholder, and the command stops |
     | S12 | `/rs-sdlc-setup` on the now-clean tree, so `make bmalph-setup` runs and `_bmad/` and `.ralph/` exist | after S11 | EXECUTED |
     | S13 | commit `chore(#N): add rust-backend-sdlc profile and governance` (`.claude/rust-sdlc.yml`, `CLAUDE.md`, `AGENTS.md`) | after S12 | EXECUTED |
     | S14 | `COMMIT_TITLE='chore(#N): initialize service from template' make check-commit-message`; `git push -u origin chore/N-initialize-service`; `gh pr create` with the body from `.github/pull_request_template.md` and `Closes #N`; hand-off to `/rs-sdlc-finish-pr` (counters A/B/C) | GitHub mode | EXECUTED; local mode: NEXT |

     The command ends with one `DONE:`/`NEXT:` summary. Sam's success moment is the finish-pr hand-off ending with
     every non-human-gated required check green (K13); human-gated checks (labels, secrets) stay `NEXT:` lines.
2. **New bounded context — `/rs-sdlc-new-context <group> <context> [--issue <N>] [--no-handoff]`.**
   - Validates both names against the xtask rules before anything runs (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`; reserved
     `shared service xtask test-support e2e-tests`; no existing context of that name) through a `lib/common.sh`
     function, then runs `make new-context group=<g> context=<c>` (exit 0 created, 1 refused with nothing written,
     2 could not run).
   - **Branch and issue rule (v0.1.0).** On a `<type>/<N>-<slug>` branch the command reuses that branch and issue N.
     Otherwise it needs an issue (`--issue`, or one created through the issue stage, A18) and creates
     `feat/<N>-<context>` from the default branch.
   - **Checklist C1–C12**, dispatched to `rust-implementer`; each step ends `DONE` with its evidence or
     `N/A: <reason>` (source: `tpl/docs/new-service.md` §5 plus the research recipe for a bounded context):

     | Id | Action | Files or target | Evidence |
     | --- | --- | --- | --- |
     | C1 | Scaffold | `make new-context group=<g> context=<c>` | three crates under `crates/<g>/<c>/`, three sorted members; `make architecture`, `make check-crate-isolation` |
     | C2 | Architecture model | three components and their relationships in `workspace.dsl` | `make validate-architecture-model` |
     | C3 | Workspace dependencies at first use | `[workspace.dependencies]` path entries for `<c>-domain`, `<c>-application`, `<c>-infrastructure`, added only when a crate depends on them | `make check-security` (cargo-deny `unused = "deny"`, `include-path-dependencies = true`, `tpl/deny.toml:48-52`), `make unused-dependencies` |
     | C4 | Domain layer | entities, value objects, ports, `<Ctx>Error`; dependencies `async-trait`, `shared-domain`, `thiserror` | `make architecture` (framework- and I/O-free), `make static-analysis`, `make complexity` |
     | C5 | Application layer | `command/`, `query/`, `subscriber/`, `error.rs` with `From<<Ctx>Error> for Problem`, `http.rs`, `http/dto.rs`, `http/handler.rs` with the extractor-check test, `graphql.rs` | `make static-analysis`, `make tests-with-coverage` |
     | C6 | Infrastructure layer | `persistence.rs`; `tests/integration/{main,repository,migration}.rs` | `make tests-with-coverage` |
     | C7 | Test support | `tests/support`: `<c>-domain.workspace = true`, in-memory fake (`new()`/`failing()`), fixtures, sibling `tests.rs` | `make unused-dependencies`, `make tests-with-coverage` |
     | C8 | Migration and query metadata | `make create-migration name=<snake_case>`, `make migrate`, `make migrate-rollback` then `make migrate` once (an ask rule, see Design principles), `make sqlx-prepare`, `.sqlx/` committed with the migration; `N/A` for a context without persistence | `make validate-sqlx-metadata` |
     | C9 | Composition root | `crates/service/Cargo.toml`; `Adapters`, `connect`, handlers, `event_bus()`, `<Ctx>State` and the schema `.data(...)` in `bootstrap.rs`; the `AppState` field; the `openapi::api_router` nest and tag; `graphql::schema` roots; the three `Adapters { .. }` literals and the contract-pinning tests | `make tests-with-coverage`, `make e2e-tests` |
     | C10 | Contracts and end-to-end | `make generate-openapi-spec`, `make generate-graphql-spec`; `features/<c>.feature`, `tests/e2e/steps/<c_snake>.rs`, the `steps.rs` module line, `world.rs` | `make validate-contract-snapshots`, `make validate-openapi-spec`, `make openapi-diff`, `make graphql-diff`, `make e2e-tests` |
     | C11 | Documentation | `docs/requests.http`, the bounded-context table in `docs/architecture.md`, an ADR when a decision was made, `docs/environment.md` for new variables | `make docs-check` |
     | C12 | Verify | the context gate set below, then `make validate-configuration` | all stages green; 0 protected files changed |

   - **Context gate set** = the template's own stage targets, read at runtime from the Makefile's `CI_*_TARGETS`
     lists and run one stage per call after the C1–C11 commit (G15 and G17 need committed files), in the background
     and polled when a stage exceeds 600 s: `make ci-preflight`, `make ci-static-analysis`, `make ci-tests`,
     `make ci-contracts`, `make ci-mutation`. These five stages hold 26 gates at `3e0bd3e`, including `check-security`,
     `complexity`, `format-check`, `docs-check`, `validate-openapi-spec`, `openapi-diff`, `graphql-diff`, `e2e-tests`
     and `mutation-tests-diff`. `make ci-delivery` runs when Docker is reachable; otherwise it is recorded as
     `not run (no Docker)` and left to PR CI. `ci-cli` (Bats) is not run, because the template's Bats suite never
     depends on a context. A closing `make validate-configuration` runs after the last remediation commit.
   - **End state.** Commit `feat(#N): add <group>/<context> bounded context` (plus `fix(#N): …` remediation commits),
     then hand-off to `/rs-sdlc-review` → `/rs-sdlc-qa` → `/rs-sdlc-finish-pr` with the feature loop's counters.
     `--no-handoff` stops after the commit and prints those three commands as `NEXT:` lines.
   - **Inside the feature loop.** When the plan needs a `<group>/<context>` that is absent from `[workspace].members`,
     the plan stage makes story 1 "Scaffold `<group>/<context>`". That story applies the `bounded-context-scaffolding`
     skill with C1–C12 as acceptance criteria and runs in the Ralph loop on the loop's branch and issue, under the
     loop's commit convention. `/rs-sdlc-new-context` is not invoked, so no second branch is created. The review
     stage's verify step runs the same gate set.
3. **Feature loop — `/rs-sdlc "<task in a few sentences>"`.**

   | # | Stage | Delegates to | Exit condition | Guard |
   | --- | --- | --- | --- | --- |
   | 0 | setup-check | `validate-profile.sh` + preflight freshness | valid `.claude/rust-sdlc.yml`; governance markers present in `CLAUDE.md` and `AGENTS.md`; `_bmad/` present | halt with "run /rs-sdlc-setup on the default branch and commit the result" and never re-run setup on the feature branch; the review stage's marker check uses the same wording |
   | 1 | issue | `/rs-sdlc-issue` | issue with testable acceptance criteria, label `rust-backend-sdlc`; `ISSUE_URL:` + `ISSUE_NUMBER:` | 5 |
   | — | branch | orchestrator | branch `<type>/<issue>-<slug>` created from the default branch and checked out before planning | — |
   | 2 | plan | `/rs-sdlc-plan` | `specs/<issue>-<kebab-title>/` complete in the template's bundle format; `architecture.md` carries a `## Constraints` section stating the commit convention with the literal issue number and the `story N.M` subject form; readiness verdict "ready" and no readiness-regex match; bundle committed on the feature branch as `docs(#N): add planning bundle <issue>-<kebab-title>` | 5 |
   | 3 | implement | `/rs-sdlc-implement` | hooks active (`git config --get core.hooksPath`, else `make install-hooks`; the template denies only raw `git config core.hooksPath` writes); `stage-planning-artifacts.sh` → `bmalph implement` (never `--force`; it carries `## Constraints` into `.ralph/PROJECT_CONTEXT.md`) → `bmalph run --driver claude-code --no-dashboard`; every subject in `git log --format=%s <merge-base>..HEAD` passes `COMMIT_TITLE='<subject>' make check-commit-message` (hard; a mismatch escalates); the `<type>(#N): story N.M <title>` form is reported and best-effort; final `make tests-with-coverage` green | 5 + Ralph circuit breaker (never reset) |
   | 4 | review | `/rs-sdlc-review` | zero new findings in the last gate iteration AND every quality threshold PASS; remediation commits `fix(#N): address review gate iteration <n> findings`; verdict written to the issue state comment with the head SHA | 5 |
   | 5 | qa | `/rs-sdlc-qa` | black-box PASS against `make start` on port 8081 (`/ping` → 200 `pong`, `/api/health` → 204, REST and GraphQL probes from the committed snapshots and acceptance criteria); verdict written to the issue state comment with the head SHA; FAIL routes back to stage 3 | 5 |
   | 6 | finish-pr | `/rs-sdlc-finish-pr` with `pr-state.sh` (verdicts `BLOCKED > FIX > GATE > REQUEST > WAIT > READY`) and `request-ai-reviews.sh` | CI green + FR/NFR gate green on the head SHA + 0 unresolved review threads; title pre-validated with `COMMIT_TITLE='…' make check-commit-message` | A `ci_fix` 5, B `comment_resolution` 5, C gate 3 |

   The run ends with `=== SDLC RUN REPORT ===` (`task`, `branch`, `result: SUCCESS | ESCALATED`, stage table,
   `artifacts`, `degrade_notes`, `escalation`). Resume reads durable records: the managed issue label, the feature
   branch with its `docs(#N)` bundle commit, the PR, the `BMAD FR/NFR Review Gate` status, and one state comment on
   the managed issue (marker `<!-- rust-sdlc-state -->`, edited in place, one line per completed stage: stage,
   result, `head_sha`, iteration, UTC time). A stage counts as done only when its recorded `head_sha` equals the
   current `HEAD`, so review and QA verdicts go stale with every new commit. The JSON under
   `target/rust-sdlc/state/<slug>.json` is a cache only. When `gh` cannot reach GitHub, the cache is the only record;
   review and QA re-run when it is absent, and the run reports this as a degrade note.

### Component inventory (v0.1.0)

| Component | Count | Members |
| --- | --- | --- |
| Commands (`commands/*.md`) | 10 | `rs-sdlc`, `rs-sdlc-setup`, `rs-sdlc-new-service`, `rs-sdlc-new-context`, `rs-sdlc-issue`, `rs-sdlc-plan`, `rs-sdlc-implement`, `rs-sdlc-review`, `rs-sdlc-qa`, `rs-sdlc-finish-pr` |
| Agents (`agents/*.md`) | 7 | `rust-implementer`, `code-quality-reviewer`, `fr-nfr-reviewer`, `ci-fixer`, `pr-comment-resolver`, `qa-manual-tester` (`Bash, Read` only), `security-auditor` |
| Skills (`skills/<name>/SKILL.md`) | 28 | 22 mapped from PHP, 11 of which carry a template skill's name (5 renamed to it: `api-resource-development`, `api-contract-development`, `architecture-boundary-fixer`, `architecture-model-sync`, `verification-workflow`; 6 already same-named: `bmad-autonomous-planning`, `complexity-management`, `documentation-sync`, `load-testing`, `quality-standards`, `testing-workflow`) + 6 Rust-only: `service-scaffolding`, `bounded-context-scaffolding`, `rust-error-handling`, `async-runtime-safety`, `dependency-policy`, `configuration-management` |
| Meta-guides (`skills/*.md`, no frontmatter) | 2 | `AI-AGENT-GUIDE.md`, `SKILL-DECISION-GUIDE.md` |
| Scripts (`scripts/`) | 13 + lib | `lib/common.sh`; `setup-preflight.sh`, `generate-profile.sh`, `validate-profile.sh`, `inject-governance.sh`, `merge-settings.sh`, `new-service.sh`, `stage-planning-artifacts.sh`, `ai-review-loop.sh`, `fr-nfr-gate.sh`, `get-pr-comments.sh`, `post-review-findings.sh`, `pr-state.sh`, `request-ai-reviews.sh` |
| Workflows (`workflows/*.js`) | 4 (0 after the cut) | workflow epic only: `rs-sdlc-feature`, `rs-sdlc-review-panel`, `rs-sdlc-pr-until-green`, `rs-sdlc-fr-nfr-review`; harness `tests/lib/workflow-harness.mjs` |
| Configuration | 1 | `config/new-service.defaults.json` |
| Plugin README | 1 | `README.md` at the plugin root: install with `claude plugin marketplace add` + `claude plugin install rust-backend-sdlc@vilnacrm-plugins`, the 10 commands, links to the docs (as in the three sibling plugins) |
| Docs | 9 (8 after the cut) | `profile-schema.md`, `setup-walkthrough.md`, `sdlc-loop.md`, `permissions.md`, `degrade-matrix.md`, `release-process.md`, `new-service-walkthrough.md`, `testing/test-strategy.md`; `workflows.md` (workflow epic) |
| Tests | 16 bats suites (15 after the cut) | 10 ported PHP suites (`ai-review-loop`, `common-lib`, `component-counts`, `fr-nfr-gate`, `generate-profile`, `get-pr-comments`, `inject-governance`, `post-review-findings`, `setup-preflight`, `validate-profile`) + `new-service.bats`, `merge-settings.bats`, `stage-planning-artifacts.bats`, `pr-state.bats`, `request-ai-reviews.bats`; `workflows.bats` (workflow epic); Rust stub repository fixture (`acme/billing-service`, `crates/billing/invoice/*`, copies of the template's `.yamllint.yml`, `.prettierrc.yml`, `.markdownlint-cli2.yaml`, `_typos.toml`), stubs `bin/{claude,gh,bmalph,cargo,make}` |

### Design principles

- **Repository wins.** Each of the 11 plugin skills that shares a name with a template skill has a
  `## Repository precedence` section: read `.claude/skills/<name>/SKILL.md` and `AGENTS.md` first; the plugin adds
  only the SDLC wrapper (profile resolution, evidence format, bounded loop, escalation block, verdict line).
- **Make-only execution.** Every gate runs through `make` via the profile's `make.*` map; `RUN_IN_CONTAINER=1` is
  prefixed when the profile selects container execution (also for `git commit`/`git push`, because the hooks run
  `make pre-commit` and `make unit-tests`). The only raw cargo invocations are the template-sanctioned ones:
  `cargo tree -i`, `cargo metadata`, `cargo xtask config-guard --list`, and the single-test debug command
  `scripts/with-env.sh .env .env.test -- cargo nextest run -p <crate> <name>`, run after `make setup-test-db`
  (`tpl/.claude/skills/testing-workflow/SKILL.md:32`). A version change goes only through the template's
  `scripts/set-version.sh <v>` (new-service S9), which runs `cargo update --workspace` itself. `make ci-list` and
  `make help` are allowed at runtime as no-compile, no-Docker reads; profile generation parses the Makefile text
  instead (scope item 5). Non-cargo tools are used where a stage documents them: `git` and `gh` throughout,
  `bmalph` in implement, loopback `curl` in QA, `python3` and `jq` inside scripts.
- **Tighten-only bars.** Shipped defaults equal the template's values; `validate-profile.sh` rejects any floor below
  or ceiling above them.
- **Protected-configuration-safe.** `merge-settings.sh` writes the permission allowlist to the git-ignored
  `.claude/settings.local.json` (or prints it) and refuses `.claude/settings.json` when `protected-config.toml`
  lists it; the template's deny and ask rules stay effective (deny > ask > allow). The template's `ask` targets that
  plugin procedures can reach are `make migrate-rollback` (C8, migrations), `make build`, `make stop`, `make down`,
  `make clean`, `make purge`, `make update`, `make static-analysis-fix` and `make unused-dependencies-fix`
  (`tpl/.claude/settings.json`). In an interactive session the user is prompted. In a headless run
  (`claude -p --permission-mode acceptEdits`, Ralph, Workflow) the step is recorded as `not run (ask rule)` in the
  targets-run list and the PR body, and is never reported as passed. QA never stops the shared stack.
- **docs-check-safe governance.** The managed block between `<!-- rust-backend-sdlc:begin -->` and
  `<!-- rust-backend-sdlc:end -->` names plugin commands in plain prose, backticks only paths that exist in every
  template-derived repository plus the committed profile, lists no three gate targets in a fence or numbered list,
  never spells the template's name, and sits outside the `AGENTS.md` verification markers.
- **Hook-valid git.** One commit builder emits `<type>(#<issue>): <subject>`; the issue number comes from
  `ISSUE_NUMBER:`, the PR title, the branch (`^[a-z]+/([0-9]+)-`) or `Closes #N`, never from the PR number;
  `--no-verify` and force pushes are never used (and are denied by the template anyway). Ralph's commits follow the
  same form through two mechanisms: the `## Constraints` section the plan stage writes (carried by `bmalph implement`
  into `.ralph/PROJECT_CONTEXT.md`, because bmalph's generated prompt asks only for "descriptive conventional commit
  message"), and active hooks. After the loop, every subject since the merge base is checked with
  `make check-commit-message`, because template CI checks only the PR title (`change-control.yml:49-50`).
- **Bounded, resumable, honest.** `MAX_ITERATIONS=5` per stage, gate counter 3, Ralph breaker terminal; degrade
  paths never loop and never fake a pass (`SUCCESS-WITH-REPORT` for an absent capability, `ESCALATED` for a mapped
  capability that cannot run).
- **Shared-resource discipline.** Parallel agents run only DB-free targets (`format`, `unit-tests`, `lint-code`,
  `architecture`, `complexity`); one serialized verify step runs the database-backed gates; long gates run stage by
  stage (`make ci-preflight` … `make ci-cli`), never `make ci` in one 600 s foreground call.
- **bmalph-compatible planning.** Bundles follow the template's format under `specs/<issue>-<kebab-title>/` and are
  staged into the git-ignored `_bmad-output/planning-artifacts/` (with `research.md` copied as
  `technical-research.md`) only for `bmalph implement`.

### Key differentiators

- **Built against the template's exact contract, not generic Rust advice.** Gate names, order, exit codes,
  protected paths, docs-check rules and runtime probes come from the verified template (31 gates, 50 protected files,
  36 required checks) and are re-read at runtime where they can drift.
- **Cross-stack parity.** Same stage machine, escalation block, run report, ledgers and the byte-identical commit
  status context `BMAD FR/NFR Review Gate` as the PHP and React plugins; an engineer moving between `/sdlc-*`,
  `/fe-sdlc-*` and `/rs-sdlc-*` keeps one mental model.
- **Lessons already paid for.** Fixes X1–X19 from the PHP reference and the Workflow nesting defect from React
  (hand-back contract: `rs-sdlc-pr-until-green` takes `onGate: 'nested' | 'return'`; `rs-sdlc-feature` runs the gate
  itself and re-enters with carried counters; static call-graph test keeps nesting at depth one).
- **Lifecycle coverage the siblings lack.** Service creation and bounded-context addition are first-class commands,
  not documentation.

## Goals

| # | Goal | Metric | Target | Measured by |
| --- | --- | --- | --- | --- |
| G1 | Create a new Rust microservice from the template in one guided command | (a) deterministic `docs/new-service.md` steps automated; (b) idempotence; (c) result state; (d) hands-on time | (a) 8 of 8 deterministic steps (identity, version, `bmalph/config.json`, README, CHANGELOG, `specs/`, sync flavour, `.templatesyncignore`) with 0 manual file edits, for runs that pass `--sync-flavour` (an undecided flavour counts as not met); (b) a second `new-service.sh` run with the same arguments prints only `UNCHANGED:`/`SKIP:` lines (including `SKIP: source (exists)`) and exits 0; (c) after sequence S1–S14 (or the `NEXT:` lines a run printed, executed by hand): `make validate-invariants`, `make docs-check` and `make validate-contract-snapshots` pass; markdownlint-cli2 and typos pass on `CLAUDE.md`, `AGENTS.md`, `README.md` and `CHANGELOG.md`; Prettier passes on `bmalph/config.json` and the profile; yamllint passes on the profile; where the toolchain and Docker exist, `make ci-preflight` and `make ci-static-analysis` pass; (d) ≤ 15 minutes of hands-on time (A14) | `new-service.bats` on the Rust stub repository (incl. a gh stub reporting `is_template=false`, the re-run `SKIP:` cases and the undecided-flavour case); K7 linter cases on the stub fixture (release gate); a scratch copy of the template for the make targets (host-recorded evidence); K9 and K13 (post-release) |
| G2 | Build features through the full SDLC loop, bounded and resumable, with the SUCCESS / ESCALATED report contract | (a) loop boundedness; (b) terminal outcome; (c) resume; (d) end-to-end completion | (a) every stage stops at 5 iterations (counters A/B 5, C 3); 0 unbounded loops; (b) 100% of runs end with `result: SUCCESS` or `result: ESCALATED`, and every escalation carries all 7 fields of `=== SDLC ESCALATION ===` with a concrete `blocking_finding`; (c) re-invoking `/rs-sdlc` on an issue resumes at the first incomplete stage with 0 completed stages repeated, from the durable records (issue state comment with `head_sha`, label, branch, bundle commit, PR, gate status), also after `cargo clean` or in a fresh clone; (d) ≥ 1 documented reference run (a small CRUD resource in a new bounded context on a fresh service) reaching a ready PR with 0 human interventions in the first release cycle, with setup run as `merge-settings.sh --with-qa-network` (counted as setup, A4) | Release gate: command-layer contract tests in `component-counts.bats` over `commands/rs-sdlc*.md` (`MAX_ITERATIONS=5`, counters A/B/C, the 7-field escalation block, the resume table and state-comment format in `rs-sdlc.md`); extra evidence when the workflow epic ships: harness scenarios and `workflows.bats` (incl. the depth-one call-graph test); the reference run (post-release, A15) |
| G3 | Add a bounded context with one command, verified by the gates | (a) name validation; (b) wiring completeness; (c) gate result; (d) protected files and git; (e) end state | (a) 100% of invalid names (regex, reserved, duplicate) refused before `make new-context` runs, nothing written; (b) all 12 checklist steps C1–C12 executed with their evidence, or marked `N/A` with a reason; (c) the context gate set green: `ci-preflight`, `ci-static-analysis`, `ci-tests`, `ci-contracts`, `ci-mutation` (26 gates at `3e0bd3e`), and `ci-delivery` green or recorded `not run (no Docker)`; (d) 0 protected files changed (closing `make validate-configuration` green) and commit `feat(#N): add <group>/<context> bounded context` accepted by the commit-msg hook, on the branch the branch-and-issue rule selects; (e) handed off to review → QA → finish-pr, or three `NEXT:` lines with `--no-handoff` | Name-validation tests in `common-lib.bats`; checklist, gate-set and branch-rule contract cases in `component-counts.bats`; the context gate set in the reference run |
| G4 | Every quality bar comes from the template's gates and is tighten-only | (a) relaxation rejection; (b) suppression guidance; (c) protected writes; (d) governance safety | (a) `validate-profile.sh` rejects 100% of looser values for each of the 12 threshold keys listed once in A2 (2 floors at 100; 10 ceilings at 0, incl. complexity violations, image vulnerabilities HIGH/CRITICAL and smoke-budget breaches); (b) 0 plugin components instruct `#[allow]`, an unjustified `#[expect]`, a coverage or mutant exclusion, or a lowered limit, and `pr-comment-resolver` declines each; (c) 0 plugin code paths write a file listed by `protected-config.toml`; (d) the governance block violates 0 docs-check rules (1–4) and invariant (e) | 12 bats rejection tests in `validate-profile.bats`, one per A2 key; grep tests over plugin text; `merge-settings.bats`; static governance-block tests |

> Assumption: because the template's bars already sit at their strictest value (100%, 0, 0), "tighten-only"
> degenerates to "must equal the template value" for every bar except the four `clippy.toml` complexity limits and
> the smoke-test budget, which could only be lowered. Both are read by their gates from protected files
> (`clippy.toml`; the budget JSON pointers in `tests/Load/config.json.dist`), so a stricter profile value cannot be
> enforced by `make complexity` or `make smoke-load-tests`. v0.1.0 therefore records zero-violation ceilings for
> both and quotes the limits from their files at review time (research Open Question 1). A2 is the single key list.

## Success Metrics

### User success metrics

- **Service creator:** the bootstrap PR of a new service passes every non-human-gated required check of the template
  on its first push (K13); every human decision left is listed as a `NEXT:` line, none is discovered in CI.
- **Feature engineer:** the number of manual interventions between `/rs-sdlc "<task>"` and a ready PR (target 0 for
  the reference task); when the plugin escalates, the escalation names the exact human action (a label, a protected
  change with `ALLOW_PROTECTED_CONFIG_EDIT=1`, an advisory without a fix).
- **Reviewer / maintainer:** every plugin PR body lists targets run and not run (with the reason), carries
  `Closes #N`, and shows exactly one conclusion comment per review lens (markers `<!-- rust-sdlc-review:<lens> -->`).
- **Platform team:** adopting the plugin requires 0 changes to the template and 0 protected-file edits in any
  service; re-running `/rs-sdlc-setup` after a template-sync merge restores the governance block with 0 changes to
  user-owned text.

### Business objectives

1. **Consistency across Rust services.** Every template-derived service runs the same SDLC contract against the same
   gates, so "as strict as the template" holds service by service.
2. **Shorter lead time.** Day zero to a green bootstrap PR within one working session (target: under two hours of
   wall-clock time on a provisioned host, first compile and CI included; measured by K13); feature lead time spent on
   design rather than on gate-chasing.
3. **Cross-stack fluency.** One command shape and one report contract across the PHP, React and Rust plugins.
4. **Template return on investment.** The plugin reuses the template's gates, skills and scaffolding (repository
   wins) instead of duplicating them, so template improvements reach every service without a plugin change.
5. **Low maintenance.** Single-sourced skills, runtime detection of template facts, a pinned test suite, and a
   release tag namespace (`rust-backend-sdlc-vX.Y.Z`).

### Key performance indicators

| ID | KPI | Target | Measured by | When |
| --- | --- | --- | --- | --- |
| K1 | Plugin-quality lint findings, all plugins | 0 | `python3 tools/plugin-quality/lint/lint_all.py` | Release gate |
| K2 | Marketplace CI | all jobs green, incl. `profile-keys-check` and `generalization-audit` extended to `plugins/rust-backend-sdlc` and the `rust-backend-sdlc-v*` tag filter | `.github/workflows/ci.yml` | Release gate |
| K3 | Component counts | 10 commands / 7 agents / 28 skills / 2 meta-guides / 13 scripts + lib / 4 workflows (0 after the cut) / 9 docs (8 after the cut) | `tests/component-counts.bats` | Release gate |
| K4 | bats suites | 16 suites (15 after the cut), 0 failures in the CI `bats` job; backend-parity cases that re-run YAML-reading cases with `SDLC_FORCE_PYTHON_YAML=1` inside `common-lib.bats`, `validate-profile.bats`, `generate-profile.bats` and `ai-review-loop.bats` (the reference plugins' mechanism); skips only for uid 0 or an absent optional tool, each with a reason | CI job `bats` (`npx --yes bats` over `plugins/*/tests/*.bats`) | Release gate |
| K5 | Shell and Markdown hygiene | 0 `shellcheck -x` findings; 0 markdownlint-cli2 findings under `plugins/` | CI jobs `shellcheck`, `markdown-lint` | Release gate |
| K6 | Generalization | 0 denylist hits in `skills/`, `commands/`, `agents/`, `scripts/` outside `# profile-example` fences | `tools/plugin-quality/lint/check_generalization.py`, CI `generalization-audit` | Release gate |
| K7 | Template integration | on the Rust stub-repository fixture (copies of the template's `.yamllint.yml`, `.prettierrc.yml`, `.markdownlint-cli2.yaml`, `_typos.toml`), after `new-service.sh --phase customize`, `generate-profile.sh` and `inject-governance.sh`: yamllint and `prettier --check` pass on the profile; Prettier passes on `bmalph/config.json`; markdownlint-cli2 and typos pass on `CLAUDE.md`, `AGENTS.md`, `README.md` and `CHANGELOG.md`; the governance block passes static docs-check rules 1–4 and invariant (e); a second `inject-governance.sh` run is byte-identical | bats; the CI `bats` job installs yamllint 1.38.0 and typos 1.52.0 (pip) and Prettier 3.9.10 and markdownlint-cli2 0.24.0 (npx), the template's pins, so these cases run in CI instead of skipping (scope item 12); locally each case skips with a reason when its tool is absent | Release gate |
| K8 | Workflow determinism (only when the workflow epic ships) | all harness scenarios pass; static call graph depth ≤ 1; `--as-child` mode proves no grandchild `workflow()` | `tests/workflows.bats` | Release gate of the workflow epic |
| K9 | New-service hands-on time | ≤ 15 min (A14) | walkthrough timing on the first new service | Post-release |
| K10 | Reference feature run | ≥ 1 documented run, `result: SUCCESS`, 0 human interventions; precondition: setup ran `merge-settings.sh --with-qa-network` (counted as setup, A4) | run report attached to the docs | First release cycle |
| K11 | Escalation precision | 100% of `ESCALATED` runs carry the 7-field block with a concrete blocking finding and recommended action; 0 PRs merged with a relaxed bar | run reports; change-control job history | Post-release |
| K12 | Adoption | ≥ 1 new service created with `/rs-sdlc-new-service` and ≥ 1 feature PR finished with `/rs-sdlc` | GitHub search over the organisation's repositories: `gh search prs --owner <org> "initialize service from template" in:title` and `gh search issues --owner <org> --label rust-backend-sdlc` | First release cycle |
| K13 | Green bootstrap PR | first service created with `/rs-sdlc-new-service`: every non-human-gated required check green on the bootstrap PR's first push; 0 edits beyond the printed `NEXT:` steps; wall-clock ≤ 2 h from S1 to that result | the walkthrough run, recorded in `docs/new-service-walkthrough.md` | Post-release |

## Scope

### MVP core features (v0.1.0, in scope)

1. **Plugin package** `plugins/rust-backend-sdlc/` with `.claude-plugin/plugin.json` (`name`, `version` `0.1.0`,
   `description`, `author`, `homepage`, `repository`, `license` `MIT`, `keywords`; no custom keys, so
   `claude plugin validate --strict` passes) and a plugin-root `README.md` (install line, command list, docs links),
   as in the three sibling plugins.
2. **10 commands** with `description` + `argument-hint` frontmatter and the 5-H2 spine (`Inputs`, `Procedure`,
   `Loop & exit condition`, `Iteration guard`, `Failure escalation`); every command except setup and new-service
   starts with `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"`.
3. **7 agents** with `name`, `description`, `tools`, `model` and the 8-H2 spine (`Profile keys consumed`, `Role`,
   `Inputs`, `Outputs`, `Allowed actions`, `Degrade paths`, `Iteration discipline`, `Smoke prompt`); agents never run
   git except the documented `gh run rerun --failed` (ci-fixer) and thread replies (pr-comment-resolver); commands
   own commits and pushes.
4. **28 skills + 2 meta-guides**, each skill with `## Profile keys consumed` first (keys declared in
   `docs/profile-schema.md`), `## Repository precedence` where a template skill of the same name exists, concrete
   values only in `# profile-example` fences, and the Rust-specific rules (error model through `Problem`
   `application/problem+json`; `ApiPath`/`ValidatedQuery`/`ValidatedJson`/`ApiJson` extractors; commands return no
   data; idempotent subscribers; `#[async_trait]` delegation to inherent `async fn`; sibling `tests.rs`; deterministic
   seeds `TEST_SEED`/`PROPTEST_RNG_SEED`; migration and `.sqlx/` co-change; snapshot regeneration; `workspace.dsl`
   co-change; layer allow-lists from `architecture.toml`).
5. **Project profile** `.claude/rust-sdlc.yml`, `schema_version: 1`, generated by reading `Cargo.toml`,
   `rust-toolchain.toml`, `architecture.toml`, `clippy.toml`, `make/gates.mk`, `protected-config.toml`, the Makefile
   and `make/service.mk` targets, workflows, `docs/repository-settings.md` required-check rows, `.coderabbit.yaml`
   and the sync workflows — with python3 `tomllib` and text parsing (targets with the `make help` regex
   `^[a-zA-Z0-9_-]+:.*## `, gate order from the `CI_*_TARGETS` assignments and `CI_STAGES` in `make/gates.mk`),
   never by running `cargo` or `make`; block-style YAML with
   2-space indentation and single-quoted strings where quoting is needed; every documented key emitted; "null means
   absent; omitted means error" for every `make.*` key.
6. **Setup** `/rs-sdlc-setup`: `setup-preflight.sh --report` (`gh auth status`, `claude --version`, python3 with
   `tomllib`, GNU make ≥ 4.0, dirty-tree report; bmalph ≥ 2.11.0, or, when bmalph is absent and the Makefile defines
   `bmalph-setup`, node ≥ 20 and npm reported as WARN "will be installed by make bmalph-setup", with the version
   re-checked after that step; FAIL only when bmalph is absent and neither the installer target nor node and npm are
   available) → `make bmalph-setup` only when `_bmad/` is absent and the tree has no tracked changes
   (`tpl/scripts/install-bmalph.sh:204-209` refuses otherwise, exit 1); on a dirty tree setup does not run it,
   continues the other steps, records `DEGRADED: make bmalph-setup not run (tracked changes: <files>)` and prints
   `NEXT: commit or stash, then make bmalph-setup` (stage 0 of the feature loop halts until `_bmad/` exists) →
   `generate-profile.sh` → `validate-profile.sh` (bounded `--refresh` retry, max 5) → `inject-governance.sh` →
   `merge-settings.sh [--with-qa-network]` → `make install-hooks` when `git config --get core.hooksPath` is unset →
   `make docs-check` when the toolchain or container execution is available → a summary naming the files to commit
   together.
7. **New-service and new-context commands** as described in Proposed Solution (sequence S1–S14, checklist C1–C12,
   the context gate set), with `new-service.sh` (`--phase source|customize|all`) and the `service-scaffolding` /
   `bounded-context-scaffolding` skills.
8. **Feature-loop commands** (`/rs-sdlc`, `-issue`, `-plan`, `-implement`, `-review`, `-qa`, `-finish-pr`) with the
   PHP contracts ported verbatim where language-agnostic, defects X1–X19 fixed, `ISSUE_NUMBER:` and the branch step
   (before plan) added, the `## Constraints` commit convention and the post-loop subject check, the durable issue
   state comment `<!-- rust-sdlc-state -->`, and the React interface of `fr-nfr-gate.sh` (`--spec-path --pr
   --impact-context --iteration --advisory`, fail-closed when no requirement source exists) with a Rust baseline NFR
   catalog (`NFR-BASE-TEST`, `-QUALITY`, `-ARCH`, `-CONTRACT`, `-DATA`, `-SEC`, `-OBS`).
9. **Review, gate and publishing scripts (epic 5)**: review ledgers under
   `${SDLC_LEDGER_DIR:-target/rust-sdlc/review-ledgers}` (git-ignored by the template), poster markers
   `<!-- rust-sdlc-review:<lens> -->`, conclusion posted exactly once (deferred to finish-pr when no PR exists at
   review time); `ai-review-loop.sh`, `fr-nfr-gate.sh`, `get-pr-comments.sh`, `post-review-findings.sh`;
   `pr-state.sh` (verdicts `BLOCKED > FIX > GATE > REQUEST > WAIT > READY`) and `request-ai-reviews.sh` with
   profile-defaulted reviewers, both used by `/rs-sdlc-finish-pr`, with `pr-state.bats` and `request-ai-reviews.bats`.
10. **Workflow epic (epic 8, the cut line)**: exactly the 4 `workflows/rs-sdlc-*.js` files with the hand-back fix,
    `tests/lib/workflow-harness.mjs`, `tests/workflows.bats` and `docs/workflows.md`.
11. **Docs** (9 files listed in the inventory, 8 without the workflow epic) and **tests** (16 bats suites, 15 without
    the epic, with hermetic stubs; Markdown, `_bmad` and `.ralph` fixtures generated at runtime under
    `$BATS_TEST_TMPDIR`).
12. **Marketplace wiring**: `.claude-plugin/marketplace.json` entry (`source: ./plugins/rust-backend-sdlc`), root
    `README.md` plugin row and install line, `ci.yml` tag filter `rust-backend-sdlc-v*`, explicit
    `plugins/php-backend-sdlc plugins/rust-backend-sdlc` lists in `profile-keys-check` and `generalization-audit`,
    and a tool step in the `bats` job that installs yamllint 1.38.0 and typos 1.52.0 (pip) and pre-fetches Prettier
    3.9.10 and markdownlint-cli2 0.24.0 (npx) so the K7 cases run in CI.
13. **Planning bundle** for this build under `specs/autonomous/2026-11-11-rust-backend-sdlc-plugin/`.

### MVP success criteria (definition of done for v0.1.0)

- K1–K7 met (release gate), and K8 when the workflow epic ships; G1–G4 release-gate parts proven by bats (and by the
  harness when the epic ships).
- Every command, agent and skill loads after `claude plugin install` from the local marketplace (10/7/28).
- The governance block and profile generated on a scratch copy of the template are committed together and pass the
  template's docs-check rules and linters (statically in CI; with `make docs-check` where the toolchain exists).
- No file under `plugins/rust-backend-sdlc/` contains a `_bmad` or `.ralph` path component; no Python is added to
  the plugin beyond inline `python3` fallbacks inside shell scripts.

### Delivery order and cut line

Epics are ordered so that each delivers usable value: (1) package skeleton, `lib/common.sh`, profile scripts and
setup; (2) new-service; (3) feature-loop commands and agents; (4) skills and meta-guides; (5) review, gate and
publishing scripts, including `pr-state.sh`, `request-ai-reviews.sh` and their two suites; (6) new-context; (7) docs
and marketplace wiring; (8) the workflow epic. The workflow epic is the cut line and contains exactly the 4
`workflows/rs-sdlc-*.js` files, `tests/lib/workflow-harness.mjs`, `tests/workflows.bats` and `docs/workflows.md`.
If it slips, G1–G4 still hold through the command layer, because finish-pr's sensor and review requester live in
epic 5 and G2's release-gate measure is the command-layer contract tests. Post-cut counts: 10 commands / 7 agents /
28 skills / 2 meta-guides, 13 scripts + lib, 0 workflows, 15 suites, 8 docs; `component-counts.bats` (K3) and K4 are
adjusted in the same change and K8 is dropped.

### Future vision

- Widen the shared lint (`check_references.py` `/rs-sdlc*` commands, profile prefixes, `toml|rs|dsl|sql|feature`
  extensions; `check_structure.py` gate predicate) as a separate marketplace change with unit tests.
- Guided example-context removal promoted to a scripted mode once the empty-GraphQL-root question is settled.
- Template version pinning in the profile and an automated drift report when the template renames a gate or path.
- A shared SDLC core across the PHP, React and Rust plugins (stage machine, sensor, gate) extracted once three
  plugins prove the same contract.
- Support for Rust workspaces that are not template-derived, through profile capabilities only.

## Out of Scope

- **Changing the template.** No edits to its gates, thresholds, protected configuration, Makefile, xtask or
  repository skills; no request for an `approved-config-change` as part of setup. A change the template routes to a
  human-gated label is escalated, never produced.
- **Writing `.claude/settings.json`** in a service where it is protected, and weakening any template deny or ask rule.
- **Copying plugin skills into `.claude/skills/`** or plugin scripts into `scripts/` of a service (docs-check rules 3
  and 7 and the template sync would break).
- **Automated removal of the example context** in `new-service.sh` (guided `rust-implementer` story only; A5).
- **Licence changes** (invariant (f) pins `CC0-1.0`). The version is part of identity and in scope (S5/S9).
- **Creating secrets, repository variables, approval labels or branch protection** on the user's behalf; the command
  prints them from the new repository's own `docs/new-service.md` and `docs/repository-settings.md`.
- **Running a live Ralph loop or live GitHub flow from the planning session** (task framing); the reference run is a
  post-release KPI.
- **Rewriting bmalph or Ralph**, vendoring `_bmad/` or `.ralph/`, or changing `.ralph/.ralphrc` (including its
  `bypassPermissions` default).
- **Widening `tools/plugin-quality` lint rules** in the plugin PR (A6), and adding `plugins/react-frontend-sdlc` to
  the CI key-check list (A11).
- **Worktree isolation for parallel agents** (`isolation: 'worktree'`): full recompiles and Compose name and port
  clashes outweigh the benefit.
- **Non-Claude drivers** (Codex and others), hosted services or GitHub Apps; Windows hosts.
- **Fault injection over HTTP and load testing beyond the template's smoke target** in QA.
- **First-class support for non-template Rust repositories**; they receive best-effort behaviour through absent
  capabilities (A1).

## Constraints

### Fixed identity (task framing)

| Item | Value |
| --- | --- |
| Name / directory | `rust-backend-sdlc` / `plugins/rust-backend-sdlc/` |
| Version, licence, author | `0.1.0`, MIT, VilnaCRM |
| Command prefix and commands | `rs-sdlc`; the 10 commands listed in the inventory |
| Profile | `.claude/rust-sdlc.yml`, `schema_version: 1` |
| Governance markers | `<!-- rust-backend-sdlc:begin -->` / `<!-- rust-backend-sdlc:end -->` in `CLAUDE.md` and `AGENTS.md` |
| Managed issue label, log prefix, release tag | `rust-backend-sdlc`, `[rust-sdlc]`, `rust-backend-sdlc-vX.Y.Z` |
| Shared names kept byte-identical | `SDLC_FORCE_PYTHON_YAML`, `SDLC_LEDGER_DIR`, commit status context `BMAD FR/NFR Review Gate` |

### Marketplace repository constraints

- `python3 tools/plugin-quality/lint/lint_all.py` reports 0 findings for every plugin.
- Generalization (NFR-2): no denylisted token (the template's organisation name, other service names, PHP-specific
  repository names) in `skills/`, `commands/`, `agents/`, `scripts/` outside `# profile-example` fences; `.sh` files
  have no escape, so the template slug lives in `config/new-service.defaults.json` and fixtures use
  `acme/rust-template`.
- Frontmatter: commands `description` + `argument-hint`; agents `name`, `description`, `tools`, `model`; skills
  `name` + `description`; meta-guides without frontmatter.
- Every skill lists consumed profile keys under `## Profile keys consumed`, each declared in
  `docs/profile-schema.md`; file names such as `clippy.toml` stay out of that section unless the schema declares them
  (H21).
- Shell passes `shellcheck -x`; tests are bats; Markdown passes markdownlint-cli2 with the repository config.
- No `_bmad` or `.ralph` path component anywhere in the plugin tree (L29).
- YAML backend: `lib/common.sh` accepts only mikefarah `yq` (probe `.a | type` must print `!!seq`, cached in
  `_SDLC_YQ_OK`) and otherwise falls back to python3 + PyYAML.

### Template constraints the plugin's output must satisfy

- **Make-only:** every tool through `make`; `RUN_IN_CONTAINER=1` for container execution; HOST targets exit 2
  without a reachable Docker engine.
- **Protected configuration:** 50 files, 4 directories (`tests/CLI/bats/`, `xtask/tests/`, `xtask/src/arch/`,
  `xtask/src/config_guard/`), `Cargo.toml [workspace.lints]`, budget JSON pointers; a change needs
  `approved-config-change` and a session restarted with `ALLOW_PROTECTED_CONFIG_EDIT=1`.
- **docs-check (G26):** rules 1–4 bind the governance block (no unknown `make` targets, no backticked slash command
  without `.claude/commands/<name>.md`, no backticked missing tracked path, no fence or numbered list naming three or
  more gate targets outside the `AGENTS.md` verification markers).
- **Invariants (G31):** the template's name never appears in `CLAUDE.md`/`AGENTS.md`; `#[allow]` is forbidden.
- **Linters over service files:** yamllint (`extends: default`, braces with one inner space, 2-space indentation,
  `document-start` off, `truthy`), Prettier (`singleQuote: true`, `printWidth: 100`), typos (hidden files scanned),
  markdownlint (`MD013` off, `MD024` siblings only, `MD033` allows `a`, `img`, `p`).
- **Git:** commit and PR title `type(#issue): subject`; branch `type/<issue>-<slug>`; hooks never bypassed; releases
  and `CHANGELOG.md` produced by the release job.
- **Data and contracts:** never edit an applied migration; commit `.sqlx/` with each migration; regenerate snapshots
  and update `workspace.dsl` in the same change; breaking OpenAPI or GraphQL changes need
  `approved-breaking-change`.
- **Service-owned extensions:** `make/service.mk` + `docs/make-targets-service.md` (a target also needs a Bats test
  in the protected `tests/CLI/bats/`, so it is a human-gated path); `.templatesyncignore` for each synchronised path a
  service changes.

### Runtime and tooling constraints

- Bash tool foreground limit 600 s; full `make ci` ≈ 25 min → stage targets run individually or in the background;
  `make bootstrap` ends with `make start --wait-timeout 900` → always backgrounded and polled (new-service S8).
- The template's `ask` rules (`make migrate-rollback`, `build`, `stop`, `down`, `clean`, `purge`, `update`,
  `static-analysis-fix`, `unused-dependencies-fix`) cannot be answered in headless runs → recorded as
  `not run (ask rule)`, never as passed. `git config core.hooksPath` writes are denied → hooks only via
  `make install-hooks`.
- One shared test database (`setup-test-db` drops and recreates it) → no parallel DB-backed targets.
- Git-state gates: snapshots must be committed before G17; new files must be `git add`-ed before mutation testing;
  G25 needs the base ref fetched (`base_ref=HEAD` in local mode until `origin/main` exists).
- `bmalph implement` reads only `_bmad-output/planning-artifacts/` (or its two aliases); readiness must not match
  `/NO[-\s]?GO/i`; `--force` is never used.
- Ralph runs with `CLAUDE_PERMISSION_MODE="bypassPermissions"` from `.ralph/.ralphrc` by default; the template's
  guard hooks still fire inside it. Plugin commands use `claude -p … --permission-mode acceptEdits --max-turns 30`.
- python3 ≥ 3.11 (`tomllib`); host 3.13, CI 3.12. CI runners provide mikefarah `yq` v4, node and jq.

## Risks

| # | Risk | Likelihood | Impact | Mitigation | Evidence |
| --- | --- | --- | --- | --- | --- |
| R1 | The governance block fails `make docs-check` or invariant (e) in every service | High without care | High (every service CI red) | Prose-only slash commands; backticked paths from a fixed safe list plus the committed profile; no gate lists; no template name; static bats tests per rule; `make docs-check` at setup when possible; "commit profile and block together" | H2–H4, H6, H8 |
| R2 | Setup writes protected settings and is blocked or fails CI | High (PHP behaviour) | High | `merge-settings.sh` writes `.claude/settings.local.json` or prints; refuses protected targets; bats | H1, X9 |
| R3 | Commits and PR titles rejected by the commit-msg hook and title check | High (PHP forms) | High | Single commit builder; issue-number derivation never from the PR number; `COMMIT_TITLE='…' make check-commit-message` pre-validation; bats pins every form | H10, X3 |
| R4 | Ralph starts with no artifacts or is blocked by the readiness regex | High (PHP has no staging) | High | `stage-planning-artifacts.sh` (exit 0/1/2); readiness self-check with the same regex; no `--force` | H15, H16, X5 |
| R5 | Implementers exhaust budgets on 100% coverage and zero mutants | Medium | High | Rust testing rules in `rust-implementer` and `testing-workflow` (`#[async_trait]` delegation, sibling `tests.rs`, per-crate tests for mutants, e2e not counted); fast inner loop; mutation once per iteration; equivalent mutants escalated as protected changes | KF 25, H28 |
| R6 | Long gates exceed the 600 s tool cap; Docker absent in sandboxed sessions | High | Medium | Stage-by-stage targets or background runs; degrade matrix: absent capability → `SUCCESS-WITH-REPORT`, mapped but unrunnable → `ESCALATED` with `make doctor` output; never a faked pass | H26, A10 |
| R7 | Parallel agents corrupt the shared test database or fight over the Cargo build lock | Medium | High (flaky failures read as real) | DB-free targets in parallel; one serialized verify step; build-lock waits expected | H25 |
| R8 | Template sync deletes the governance block | High (every merged sync) | Low | Idempotent setup; stage 0 and review halt on missing markers with "run /rs-sdlc-setup on the default branch and commit the result" (no automatic re-run on a feature branch); never add `CLAUDE.md`/`AGENTS.md` to `.templatesyncignore` | H7 |
| R9 | Template drift (no tags): gate names, xtask commands or paths change | Medium | Medium | Read lists at runtime (`make ci-list`, `cargo xtask config-guard --list`, `make help`); template detection heuristic; template commit recorded in the profile for diagnostics | Research OQ 9 |
| R10 | `yq` variant mismatch: tests pass in CI and fail on hosts | High on the session host | Medium | `!!seq` probe, PyYAML fallback, tests gated on `have_yq`, backend-parity tests | H17, X17 |
| R11 | Generalization lint blocks the template slug or secret names | High | Medium | Slug in `config/new-service.defaults.json`; secret and label names read from the target at runtime; generic fixtures | H18 |
| R12 | Shared-lint blind spots hide `/rs-sdlc-*` typos and mis-flag Rust file names | Medium | Low | Plugin-local token and key tests; schema detection-source table backticks `architecture.toml`; lint widening as a follow-up | H19 |
| R13 | A ported feature workflow escalates on every fresh PR head (nesting) | High if ported as-is | High | Hand-back contract (`onGate`, `carry`), `--as-child` harness mode, static call-graph test | H32, KF 22 |
| R14 | Plugin skills contradict the template's same-named skills | Medium | Medium | `## Repository precedence`; one triage verdict per pair (source `repo+plugin`); plugin skills never copied into the service | H12 |
| R15 | Example-context removal breaks docs-check or the GraphQL schema | Medium | Medium | Keep by default; guided story edits the three docs lines, updates `.templatesyncignore`, replaces (never deletes) GraphQL roots, regenerates snapshots | H29, OQ 7 |
| R16 | Scope (28 skills, 4 workflows, 16 suites) delays delivery | Medium | Medium | Epic order with the workflow epic (4 workflows, harness, `workflows.bats`, `docs/workflows.md` only) as the cut line; finish-pr's scripts in epic 5; skills ported from PHP structure; counts pinned so a cut is explicit (post-cut 0/15/8) | Delivery order |
| R17 | Ralph's `bypassPermissions` default surprises users | Medium | Medium | `docs/permissions.md` states the default truthfully; template hooks still guard protected files; plugin never edits `.ralph/.ralphrc` | X8, KF 9 |
| R18 | `gh repo create --template` races asynchronous template generation | Low | Medium | Create without `--clone`, poll commits (10 × 3 s), then clone; local and in-place modes as fallbacks | OQ 6 |
| R19 | Template repository flag off: `gh repo create --template` and "Use this template" fail before any deterministic step (true for the default template on 2026-11-11) | High today | High (G1 default path dead) | Probe `gh api repos/<slug> --jq .is_template` first; `false` → clone-and-push mode (empty repository, `git archive HEAD` import, fresh history, `chore(#N): import template …` on `main`); advice `NEXT: ask the template owner to enable Settings > Template repository`; `new-service.bats` case with a gh stub reporting `is_template=false` | live `gh api` check; `tpl/docs/new-service.md` §1 |
| R20 | Ralph commits without `(#N)` land unnoticed (bmalph's prompt asks only for conventional commits; template CI checks only the PR title) | High without care | Medium | `## Constraints` commit convention carried into `.ralph/PROJECT_CONTEXT.md`; hooks activated before `bmalph run`; post-loop `make check-commit-message` over every subject since the merge base, escalate on a mismatch | bmalph `dist/transition/context.js`; `change-control.yml:49-50` |
| R21 | Template `ask` rules stall headless runs (e.g. `make migrate-rollback` before committing a migration pair, `tpl/docs/operations.md:37`) | Medium | Low | Recorded `not run (ask rule)` in targets-run and the PR body, never reported as passed; interactive sessions prompt | `tpl/.claude/settings.json` |

## Assumptions

> Assumption: **A1 — Supported targets.** First-class support is for repositories created from the Rust service
> template, detected by `rust-toolchain.toml`, `architecture.toml`, `protected-config.toml`, `xtask/Cargo.toml`,
> `make/gates.mk`, `crates/service/Cargo.toml`, `workspace.dsl` and the Makefile's `CI_PREFLIGHT_TARGETS`
> assignment starting with `validate-configuration` (parsed from the Makefile text, the same list `make ci-list`
> prints). Other Rust workspaces get a valid profile with absent (`null`) capabilities and degrade paths, without
> guarantees; the template is the only codebase the request names.
>
> Assumption: **A2 — Thresholds (the single key list).** Shipped defaults equal the template's protected values;
> `validate-profile.sh` has one rejection test per key (12). Key names are indicative; the architecture fixes their
> spelling under `quality.*`.
>
> | Key (indicative) | Bound | Gate |
> | --- | --- | --- |
> | `quality.coverage_lines` | floor 100 | `tests-with-coverage` |
> | `quality.coverage_functions` | floor 100 | `tests-with-coverage` |
> | `quality.max_surviving_mutants` | ceiling 0 | `mutation-tests-diff` |
> | `quality.max_clippy_findings` | ceiling 0 | `static-analysis` |
> | `quality.max_complexity_violations` | ceiling 0; limits quoted from `clippy.toml` | `complexity` |
> | `quality.max_architecture_violations` | ceiling 0 | `architecture` |
> | `quality.max_unused_dependencies` | ceiling 0 | `unused-dependencies` |
> | `quality.max_dependency_policy_findings` | ceiling 0 | `check-security` |
> | `quality.max_spectral_findings` | ceiling 0 | `validate-openapi-spec` |
> | `quality.max_unapproved_breaking_changes` | ceiling 0 | `openapi-diff`, `graphql-diff` |
> | `quality.max_image_vulnerabilities_high_critical` | ceiling 0 | `image-scan` |
> | `quality.max_smoke_budget_breaches` | ceiling 0; budget (health p99 50 ms) quoted from `tests/Load/config.json.dist` | `smoke-load-tests` |
>
> Assumption: **A3 — Profile namespaces.** Toolchain facts under `rust.*`, runtime URLs and paths under `service.*`,
> gating booleans under `capabilities.*`/`framework.*`/`persistence.*` (so the shared L18 predicate sees them),
> container execution as `capabilities.run_in_container`; a plugin-local test declares the non-L25 namespaces. The
> architecture fixes the final key set (research Open Question 2).
>
> Assumption: **A4 — QA network permissions.** By default setup prints, and does not write, loopback-scoped `curl`
> allowlist entries. The opt-in `merge-settings.sh --with-qa-network` writes them to the git-ignored
> `.claude/settings.local.json` only, scoped to `http://localhost:<service.port>/` and `http://127.0.0.1:<service.port>/`
> with a fixed URL-first command form that `qa-manual-tester` always uses (research Open Question 3: prefix
> semantics). A headless run without them cannot probe, so the reference run (G2d, K10) requires setup with
> `--with-qa-network`, counted as setup and not as an intervention.
>
> Assumption: **A5 — Example context.** `new-service.sh` never removes it; removal is a guided `rust-implementer`
> story (research Open Question 4).
>
> Assumption: **A6 — Lint widening.** Changes to `tools/plugin-quality` land after the plugin, as a separate change
> with unit tests (research Open Question 5).
>
> Assumption: **A7 — Repository creation.** Probe `gh api repos/<slug> --jq .is_template`. When `true`, template
> flow: `gh repo create <owner>/<name> --template <slug>` without `--clone`, poll the commits API up to 10 × 3 s,
> then `gh repo clone` into `<parent-dir>/<name>` (research Open Question 6). Otherwise clone-and-push: an empty
> repository, a `git archive HEAD` import with fresh history, and the import commit on `main` (S1, S3).
>
> Assumption: **A8 — GraphQL roots.** A `MergedObject` `Query` without a context field is treated as invalid; roots
> are replaced, never deleted (research Open Question 7).
>
> Assumption: **A9 — Stage record.** Review and QA leave no GitHub artifact before stage 6 (reference defect X11), so
> every stage verdict is persisted durably in one state comment on the managed issue (marker
> `<!-- rust-sdlc-state -->`, edited in place; stage, result, `head_sha`, iteration, UTC time), next to the label,
> the `docs(#N)` bundle commit on the feature branch (the branch now precedes plan), the PR and the gate status. A
> verdict counts on resume only when its `head_sha` equals `HEAD`. The JSON under
> `target/rust-sdlc/state/<slug>.json` is a cache, so `cargo clean` or a fresh clone loses nothing; without GitHub
> access, review and QA re-run when the cache is absent (degrade note) (research Open Question 8).
>
> Assumption: **A10 — Docker-less QA.** When `make.start` is mapped but Docker is unreachable, stage 5 ends
> `ESCALATED` with the `make doctor` output; when `make.start` is `null`, QA is skipped as `SUCCESS-WITH-REPORT`
> (research Open Question 10).
>
> Assumption: **A11 — React key check.** Adding `plugins/react-frontend-sdlc` to the CI `profile-keys-check` list is
> out of scope and noted in the PR (research Open Question 11).
>
> Assumption: **A12 — Workflow names.** `workflow('rust-backend-sdlc:rs-sdlc-…')` resolution cannot be verified
> offline; every nested call site escalates gracefully with the manual command line (research Open Question 12).
>
> Assumption: **A13 — Workflow epic included.** The epic is in v0.1.0 because its risk is controlled (deterministic
> harness, no model in the loop, only node + jq in CI) and it is the last epic, so it doubles as the cut line.
>
> Assumption: **A14 — G1 timing.** The 15-minute hands-on target excludes the Rust toolchain download, Docker image
> pulls, the first compile and a full `make ci`; it counts the operator's time at the keyboard.
>
> Assumption: **A15 — End-to-end evidence.** The planning session cannot run a live Ralph loop or GitHub flow (task
> framing), so the release gate proves G2 with the harness, bats and contract tests; the live reference run (G2d,
> K10) is measured in the first release cycle.
>
> Assumption: **A16 — Skill count.** 28 skills exceed the "about 25" guidance by three; one-to-one PHP parity (22)
> plus six Rust-only skills is preferred over merging skills, because parity keeps the triage and decision guide
> mechanical.
>
> Assumption: **A17 — Tool floors.** bmalph ≥ 2.11.0 (the template's pin), python3 ≥ 3.11, GNU make ≥ 4.0, and the
> `claude` CLI floor required by the hardened gate's restricted mode; the preflight reports each with remediation.
> An absent bmalph is a WARN, not a FAIL, where the Makefile defines `bmalph-setup` and node ≥ 20 with npm exists,
> because that target installs the pinned bmalph under `~/.npm-global` (`tpl/scripts/install-bmalph.sh:8,168-170`).
>
> Assumption: **A18 — Issue for new contexts.** `/rs-sdlc-new-context` requires an issue number for the hook-valid
> commit; without `--issue`, and when not on a `<type>/<N>-…` branch, it creates one through the issue stage first.
>
> Assumption: **A19 — Labels and secrets.** The plugin never creates `approved-config-change`,
> `approved-breaking-change`, secrets, variables or branch protection; it prints them as `NEXT:` steps. It creates
> only its own managed issue label `rust-backend-sdlc` when missing.
>
> Assumption: **A20 — New-service ownership.** The command owns GitHub actions and commits (S2–S4, S8–S14); the
> script owns only file changes and repository creation (S1, S5) and never commits. Local mode commits only with
> `--issue <N>`, because the commit-msg hook needs `(#N)`; without it the run stops before S11 and prints S11–S14 as
> `NEXT:` lines with a `<N>` placeholder.
>
> Assumption: **A21 — New-context end state.** v0.1.0 hands a standalone run off to review → QA → finish-pr (a
> context PR must pass the same gates as a feature); inside the feature loop the scaffold is story 1 of the plan, not
> a call to the command.
>
> Assumption: **A22 — Setup on a dirty tree.** Setup continues without `make bmalph-setup` and records a
> `DEGRADED:` line plus a `NEXT:` line; it never skips silently. Halting would also block the profile and
> governance refresh in a repository that already has `_bmad/`, where bmalph-setup is not needed at all; stage 0
> still halts the feature loop until `_bmad/` exists, so the degrade cannot leak into implementation.

### Open questions handed to the PRD and architecture (non-blocking)

1. Final profile key set and required-versus-optional split (bounded by A2 and A3).
2. `--template-path` and clone-and-push both import with `git archive HEAD` (tracked, committed files, fresh
   history). Still open: whether `--template-path` should refuse a template checkout that has uncommitted changes
   (recommended: refuse with exit 1 and the reason).
3. Bats test-count floor for K4 beyond "16 suites, 0 failures" (the PHP reference has 239 tests in 10 suites).
4. Whether the review stage runs the security lens on every iteration or only when `*.rs`, `Cargo.toml`,
   `Cargo.lock`, `migrations/` or `.sqlx/` changed (the research recommends the latter).
5. Which required checks `pr-state.sh` treats as human-gated (`ci.human_gated`), parsed from
   `docs/repository-settings.md` versus declared in the profile.

## Revision Log

Reviser pass, 2026-11-11. Each finding was checked against its sources (`tpl/` at `3e0bd3e`, the live `gh api` flag,
`repo/.github/workflows/ci.yml`, `react/commands/fe-sdlc-finish-pr.md`, bmalph `dist/transition/context.js`,
`research.md`). F13–F29 partly repeat F1–F12 and were merged into the same edits.

| # | Sev. | Finding | Result | Rationale |
| --- | --- | --- | --- | --- |
| F1 | major | Default template has `is_template=false`; template flow fails | applied | Verified live (`false`). Added the probe, the clone-and-push mode (S1/S3), the advice `NEXT:`, R19, A7 and a `new-service.bats` gh-stub case. |
| F2 | major | New-service sequence contradictory (ownership, order, dirty tree, `(#N)`, PR hand-off) | applied | One S1–S14 table with EXECUTED/NEXT. `make doctor` is report-only because `doctor.sh` exits 1 on a fresh host before `make bootstrap` installs tools. Bootstrap is backgrounded. Two commits, setup on a clean tree, local mode needs `--issue`, finish-pr hand-off. G1(c) points to the sequence. |
| F3 | major | Cut line false: finish-pr needs `pr-state.sh`/`request-ai-reviews.sh` | applied | Confirmed in `react/commands/fe-sdlc-finish-pr.md:117,180` and research (15 + 1 suites). Moved to epic 5. The epic is now 4 workflows, the harness, `workflows.bats` and `docs/workflows.md`. Post-cut counts stated. G2's gate is now the command-contract tests. |
| F4 | major | G3 underspecified (gates, end state, loop link, 12 steps) | applied | Added checklist C1–C12 (id, action, target, evidence), the stage-target gate set, the end state with hand-off or `--no-handoff`, and the rule that the plan's story 1 scaffolds a missing context. |
| F5 | major | Green bootstrap PR unmeasured; `lint-repo` linters unchecked | applied | G1(c) and K7 extended with markdownlint-cli2, typos and Prettier on the written files. `ci-preflight`/`ci-static-analysis` added where Docker exists. New K13. |
| F6 | minor | "four segments the framing names" is false | applied | The framing names no personas. Reworded. |
| F7 | minor | G4(a) omits complexity | applied | A2 is now the single 12-key list. G4(a) refers to it and counts 12 rejection tests. |
| F8 | minor | Version belongs to identity | applied | `scripts/set-version.sh` exists (it runs `cargo update --workspace`). Added as step S5/S9 with `UNCHANGED:`, and removed from Out of Scope. |
| F9 | minor | Preflight blocks on bmalph that `bmalph-setup` installs | applied | Confirmed `install-bmalph.sh:8,168-170` (npm, Node 20+). Absent bmalph is now a WARN when the target and node/npm exist. A17 updated. |
| F10 | minor | Make-only list too broad and incomplete | applied | Reworded to "raw cargo invocations". Added the `with-env.sh … cargo nextest run` debug command (testing-workflow SKILL.md:32). Listed the non-cargo tools. |
| F11 | minor | Synopsis lacks flags; flavour default; `specs/` reset undefined | applied | Full flag set given. An omitted flavour gives `SKIP:` + `NEXT:` and is excluded from G1(a). `specs/` reset defined (delete the shipped bundle dirs unless `--keep-specs`). |
| F12 | minor | K4 "both backends" unmeasurable | applied | In-suite `SDLC_FORCE_PYTHON_YAML=1` parity cases, as in the php/react suites (verified). One CI invocation. |
| F13 | major | New-service order (dup of F2) plus dirty-tree setup behaviour | applied | Merged into S1–S14. Setup on a dirty tree continues, records `DEGRADED:` + `NEXT:` and never skips silently (A22). Stage 0 halts until `_bmad/` exists. |
| F14 | major | `pr-state.sh` in the cut epic (dup of F3) | applied | Merged with F3. The stage-6 row now names both scripts. |
| F15 | major | Context gate set misses `check-security`, `mutation-tests-diff`, etc. | applied | Chose the template's stage targets (`ci-preflight` … `ci-mutation`, 26 gates, a superset of the proposed 15) read from `CI_*_TARGETS`, plus `ci-delivery` with Docker and a closing `validate-configuration`. The count is fixed (no N−1), because `validate-sqlx-metadata` passes without a migration. |
| F16 | major | New-context vs feature-loop branch and end state | applied | Branch rule: reuse a `<type>/<N>-…` branch, else `feat/<N>-<context>`. In-loop scaffolding is plan story 1 with no command call. Standalone runs hand off (A21). |
| F17 | major | Ralph commits lack `(#N)`; stage-3 exit not enforceable | applied | bmalph's prompt is confirmed ("descriptive conventional commit message"), and `## Constraints` is confirmed to be carried into PROJECT_CONTEXT. Added the plan constraint, hooks via `git config --get core.hooksPath` / `make install-hooks` (raw writes are denied), and the post-loop `check-commit-message` over every subject. The story form is best-effort. R20 added. |
| F18 | major | A9 false: review/QA leave no GitHub artifact | applied | Option (a): an issue state comment `<!-- rust-sdlc-state -->` with `head_sha` validity. The branch moved before plan, and the bundle is committed as `docs(#N)` on it. A degrade path is defined without GitHub. |
| F19 | major | A4 curl prompts contradict "0 interventions" | applied | Both options: opt-in `merge-settings.sh --with-qa-network` (loopback only, `settings.local.json`) and a stated precondition for G2(d)/K10. |
| F20 | major | K7 always skipped in CI | applied | Confirmed the `bats` job installs no linters. K7 now runs on the stub fixture with template config copies. Scope 12 adds pinned yamllint, typos, Prettier and markdownlint-cli2 to the `bats` job. |
| F21 | minor | No plugin-root README | applied | All three siblings ship one (verified). Added to the inventory and scope item 1. |
| F22 | minor | Preflight bmalph order (dup of F9) | applied | Merged with F9, including the version re-check after `make bmalph-setup`. |
| F23 | minor | Threshold keys incomplete (complexity, image scan, smoke p99) | applied | All 12 keys are listed once in A2. Smoke p99 is included as a zero-breach ceiling with the budget quoted, by the same logic as complexity. |
| F24 | minor | Raw-command list vs `cargo update`; generation vs `make ci-list` | applied | Version changes go only through `set-version.sh`. Generation parses Makefile text (`make help` regex, `CI_*_TARGETS`). `make ci-list`/`make help` are allowed at runtime. A1 updated. |
| F25 | minor | `ask` rules (`migrate-rollback`) stall headless runs | applied | Listed all 9 reachable ask targets from `tpl/.claude/settings.json`. Headless runs record `not run (ask rule)`, never passed. R21 added. |
| F26 | minor | K4 mechanism (dup of F12) | applied | Merged with F12 (in-suite parity, no second CI run). |
| F27 | minor | Idempotence of the source step; flavour default | applied | Added the `SKIP: source (exists)` / exit-1 rule. Merged the flavour default with F11. |
| F28 | minor | Stage-0 row contradicts itself | applied | Halt with "run /rs-sdlc-setup on the default branch and commit the result". The review stage and R8 use the same wording. |
| F29 | minor | K12 source does not exist | applied | Replaced with `gh search prs` / `gh search issues` queries over the organisation. |

No finding was rejected.
