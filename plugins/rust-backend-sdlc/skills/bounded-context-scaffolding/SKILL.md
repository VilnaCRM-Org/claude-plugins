---
name: bounded-context-scaffolding
description: Use when adding a new bounded context `<group>/<context>` to a Rust template-derived service, either through /rs-sdlc-new-context or as the in-loop story 1 "Scaffold `<group>/<context>`" that the plan stage writes when the context is absent from `[workspace].members`. Covers the name rules with the reserved context names and xtask's existence rule over the live tree, the checklist C1–C12 with the evidence target of each item, the architecture model (one component per crate, one relationship per dependency edge), workspace dependencies added at first use, the composition-root wiring including the `Adapters { .. }` literals and the contract-pinning tests, the context gate set run one stage per call, and the branch rule. Skip when the context already exists in the live tree, because the change is then a feature inside it. Not for adding an operation to an existing context (use api-resource-development), not for creating a new service (use service-scaffolding), not for moving code between layers or contexts (use architecture-boundary-fixer).
---

# Bounded Context Scaffolding

## Profile keys consumed

- `make.new_context` — the scaffolding target of C1, called with `group=<group> context=<context>`; null stops the skill before anything is written
- `architecture.crates_root` — the directory that holds every context; the template scaffolder writes only below its fixed root `crates`, so null or any other value stops the skill
- `architecture.bounded_contexts` — the contexts recorded when the profile was generated; informational only, never used to decide whether a name exists
- `make.validate_architecture_model` — the architecture-model check, evidence of C2; null keeps the model edit and records the check `not run (capability absent)`
- `make.ci_preflight` — stage 1 of the context gate set, the preflight stage (configuration and repository checks), called with `base_ref=<base> CONFIG_CHANGE_APPROVED=`
- `make.ci_static_analysis` — stage 2, the static-analysis stage
- `make.ci_tests` — stage 3, the test stage, which needs the compose database
- `make.ci_contracts` — stage 4, the contract stage, called with `base_ref=<base>`
- `make.ci_mutation` — stage 5, mutation testing of the changed code, called with `base_ref=<base>`
- `make.ci_delivery` — stage 6, the delivery stage (the production image and the checks that run against it)
- `make.validate_configuration` — the closing protected-configuration check, called with `base_ref=<base> CONFIG_CHANGE_APPROVED=`

## Context

A bounded context of a template-derived service is three crates, `<context>-domain`, `<context>-application` and `<context>-infrastructure`, in `crates/<group>/<context>/{domain,application,infrastructure}`. The template's scaffolder (`make new-context`, backed by the workspace's `xtask` crate) writes only six files (a manifest and a `src/lib.rs` per crate), registers the three member paths in sorted order, refreshes `Cargo.lock` and prints the next steps. The new crates have no dependency, so they pass the architecture, crate-isolation and unused-dependency checks as they are. Everything else is wiring, and every piece has a gate that fails until it is right:

- The architecture-model check fails until `workspace.dsl` has one component per crate and one relationship per dependency edge (every workspace-internal `[dependencies]` edge between modelled crates).
- The dependency policy denies a `[workspace.dependencies]` entry that nothing uses (cargo-deny `unused = "deny"` with `include-path-dependencies = true`), so an entry is added at first use, never ahead of it.
- Three tests in the composition root build the `Adapters` struct with a literal, and two tests pin the OpenAPI document and the GraphQL schema; a new adapter or root breaks them until they are updated in the same change.
- The contract-snapshot gate needs both snapshots regenerated and committed, and the mutation gate reads only committed changes, so the gate set runs after the commit.

The template's own guide for this (`docs/new-service.md`, section "Add a bounded context") and `AGENTS.md` win where they are stricter. The skill has two variants that share the name rules, C1–C11 and the gate set: the standalone run through /rs-sdlc-new-context, and the in-loop story 1 of the feature loop (step 7).

## Task

Add `<group>/<context>` so that it is a first-class part of the service: valid names, scaffolded crates, the architecture model, workspace dependencies, the three layers with tests and fakes, the migration and query metadata when the context persists data, the composition-root wiring, contracts and end-to-end features, and documentation. Report every checklist item C1–C12 as `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`, and prove the result with the context gate set and the closing protected-configuration check, with 0 protected files changed.

## Success criteria

- Both names passed the three name rules of step 2 against the live tree before any write, branch change or make call.
- The work happened on the branch the branch rule of step 3 selects, never on the default branch.
- Each item C1–C11 ends `DONE: C<n> <evidence>`, where the evidence is the passing evidence target of the table in step 5, or `N/A: C<n> <reason>` (only C8 for a context without persistence, and C2 when the repository has no architecture model).
- `workspace.dsl` has exactly one component per crate of the context and one relationship per workspace-internal `[dependencies]` edge whose two crates are modelled.
- Every `[workspace.dependencies]` entry of the context has at least one user.
- C12: the six stages of the context gate set passed, one call each, then the closing check mapped by `make.validate_configuration` passed with `base_ref=<base> CONFIG_CHANGE_APPROVED=`; `ci-cli` was not run.
- No protected file changed, and the profile file is unchanged on the branch.

## Steps

### 1. Resolve the keys

Read the eleven keys from `.claude/rust-sdlc.yml` (the calling command has validated it) and branch:

- `make.new_context` null: write nothing and end with the escalation block, `blocking_finding: make.new_context is null (no context scaffolder)`. Never hand-write the three crates: the scaffolder's member registration and lock refresh are part of C1.
- `architecture.crates_root` null, or a value other than `crates`: the scaffolder cannot place the crates where the repository keeps them. Write nothing and escalate with `blocking_finding: architecture.crates_root is <value>`.
- `architecture.bounded_contexts` non-empty: use it only to read the naming style of the existing contexts. `[]`: there is nothing to read. In both cases the live tree of step 2 decides existence, because the list is stale after every new context; never edit the profile on the branch to add the new context (a changed profile escalates at review), it is refreshed by a later setup run on the default branch.
- A null stage key (`make.ci_preflight` … `make.ci_delivery`): that stage of C12 is recorded `not run (capability absent)` (D1) and the run ends at best `SUCCESS-WITH-REPORT`. A null `make.validate_configuration`: the closing check is recorded the same way, and 0 protected files changed is shown instead by comparing `git diff --name-only <base>` with the protected list of `cargo xtask config-guard --list` (or a python3 `tomllib` read of `protected-config.toml` when neither the host toolchain nor the container route is available). A null `make.validate_architecture_model` is handled in C2.

### 2. Check the names against the live tree

The scaffolder's rules, applied before anything runs (the command does it through its name validator; the in-loop story re-checks before C1 because another change may have created the context since planning):

1. **Name rule.** The group and the context both match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`: lower-case letters and digits, words separated by single hyphens, starting with a letter. An uppercase letter, a leading digit, a trailing hyphen or a double hyphen is refused.
2. **Reserved context names.** The context is none of `shared service xtask test-support e2e-tests`. The reserved words are legal as a group: `service/<context>` is accepted.
3. **Existence rule (xtask).** A context name is unique in the workspace whatever its group, and the check reads the live tree in any group, never the profile. The name is refused when `crates/<context>` is a directory, when any `crates/*/<context>` is a directory, when a `[workspace].members` path ends in the components `<context>/domain`, `<context>/application` or `<context>/infrastructure`, or when a member's package name is `<context>-domain`, `<context>-application` or `<context>-infrastructure`.

In short, with `<c>` the context: `crates/<c>` or `crates/*/<c>` as a directory, a member path ending in `<c>/<layer>`, or a package name `<c>-<layer>` refuses the name. A read-only check of rule 3 from the repository root:

```bash
ls -d crates/<context> crates/*/<context> 2>/dev/null
python3 -c 'import sys, tomllib, pathlib
c = sys.argv[1]
layers = ("domain", "application", "infrastructure")
for m in tomllib.load(open("Cargo.toml", "rb"))["workspace"]["members"]:
    manifest = pathlib.Path(m) / "Cargo.toml"
    name = tomllib.load(open(manifest, "rb")).get("package", {}).get("name", "") if manifest.is_file() else ""
    if pathlib.PurePosixPath(m).parts[-2:] in [(c, l) for l in layers] or name in [f"{c}-{l}" for l in layers]:
        print(f"EXISTS: member {m} ({name})")' '<context>'
```

Any output, or a failed rule 1 or 2, is a refusal: print `REFUSED: <rule> <detail>`, write nothing, and end with the escalation block. A context that exists is not scaffolded again: the change is a feature inside it (use [api-resource-development](../api-resource-development/SKILL.md)).

### 3. Apply the branch rule

- On a `<type>/<N>-<slug>` branch, reuse that branch and issue `N`.
- Otherwise an issue is needed (`--issue <N>`, or one created through the issue stage), then `feat/<N>-<context>` is created from the default branch.
- Never scaffold on the default branch. The in-loop variant (step 7) always runs on the loop's branch and creates no branch.

### 4. Scaffold the crates (C1)

Run the target mapped by `make.new_context` with `group=<group> context=<context>`, in the background, as [verification-workflow](../verification-workflow/SKILL.md) prescribes for every make call. Exit 0 means created. GNU make reports any recipe failure as exit 2, so classify a failure by the scaffolder's stderr prefix:

- `new-context refused:` — nothing was written; the name rules of step 2 and the scaffolder disagree. Escalate with the output.
- `new-context could not run:` — files may already exist (for example the crates were created but the offline lock refresh failed). Escalate with the output and `git status --porcelain`.
- Neither prefix — escalate with the log tail.

Then confirm the evidence: three crates under `crates/<group>/<context>/`, three member paths inserted in sorted order, and the architecture and crate-isolation checks still passing.

### 5. Work the checklist C2–C11

Each item ends `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`. The evidence targets are the template's target names; `make help` lists the service's own names. Run each as [verification-workflow](../verification-workflow/SKILL.md) prescribes; database-backed targets (test database, migrations, query metadata, coverage, end-to-end) run one at a time, and when several items share one (C5, C6, C7 and C9 all name `make tests-with-coverage`), one passing run after the last of them is the evidence for each.

| Id | Action | Files or target | Evidence target |
| --- | --- | --- | --- |
| C1 | Scaffold | the target mapped by `make.new_context` with `group=<group> context=<context>` | three crates under `crates/<group>/<context>/`, three sorted members; `make architecture`, `make check-crate-isolation` |
| C2 | Architecture model | three components and their relationships in `workspace.dsl` | the target mapped by `make.validate_architecture_model` |
| C3 | Workspace dependencies at first use | `[workspace.dependencies]` path entries for `<context>-domain`, `<context>-application`, `<context>-infrastructure`, each added when the first crate depends on it | `make check-security`, `make unused-dependencies` |
| C4 | Domain layer | `<Entity>` aggregates, value objects, ports, the context's error enum; dependencies `async-trait`, `shared-domain`, `thiserror` | `make architecture`, `make static-analysis`, `make complexity` |
| C5 | Application layer | `command/`, `query/`, `subscriber/`, `error.rs` with the `From` conversion of the domain error into `Problem`, `http.rs`, `http/dto.rs`, `http/handler.rs` with the extractor-check test, `graphql.rs` | `make static-analysis`, `make tests-with-coverage` |
| C6 | Infrastructure layer | `persistence.rs`; `tests/integration/{main,repository,migration}.rs` | `make tests-with-coverage` |
| C7 | Test support | `tests/support`: `<context>-domain.workspace = true`, an in-memory fake per port with `new()` and `failing()`, fixtures, sibling `tests.rs` | `make unused-dependencies`, `make tests-with-coverage` |
| C8 | Migration and query metadata | `make create-migration name=<snake_case>`, `make migrate`, `make migrate-rollback` then `make migrate` once, `make sqlx-prepare`, `.sqlx/` committed with the migration; `N/A` for a context without persistence | `make validate-sqlx-metadata` |
| C9 | Composition root | the wiring points listed below, including the three `Adapters { .. }` literals and the contract-pinning tests | `make tests-with-coverage`, `make e2e-tests` |
| C10 | Contracts and end-to-end | `make generate-openapi-spec`, `make generate-graphql-spec`; `features/<context>.feature`, `tests/e2e/steps/<context_snake>.rs`, its module line in `steps.rs`, `world.rs` | `make validate-contract-snapshots`, `make validate-openapi-spec`, `make openapi-diff base_ref=<base>`, `make graphql-diff base_ref=<base>`, `make e2e-tests` |
| C11 | Documentation | `docs/requests.http`, the bounded-context table of `docs/architecture.md`, an ADR under `docs/adr/` when a decision was made, `docs/environment.md` rows for new variables | `make docs-check` |
| C12 | Verify | the context gate set of step 6, then the check mapped by `make.validate_configuration` | all stages green; 0 protected files changed |

**C2, the architecture model.** Add one component per crate (`<context>-domain`, `<context>-application`, `<context>-infrastructure`, technology "Rust crate") next to the other context components of `workspace.dsl`, and one relationship for every workspace-internal `[dependencies]` edge whose two crates are modelled components: application to domain, infrastructure to domain, each layer to the shared crates it uses, and the composition root to each crate it depends on. Dev-dependencies need no relationship; the check compares the components with the workspace crates (minus `xtask`, `test-support` and `e2e-tests`) and prints every missing component and every missing relationship. C4 to C9 add edges, so keep the model in step with each of them; C2 is done when the check passes after C9. A null `make.validate_architecture_model` with a `workspace.dsl` present: edit the model anyway and record `not run (capability absent)`; no `workspace.dsl`: `N/A: C2 the repository has no architecture model`. See [architecture-model-sync](../architecture-model-sync/SKILL.md).

**C3, workspace dependencies at first use.** Declare `<context>-domain = { path = "crates/<group>/<context>/domain" }` (and the two others) in `[workspace.dependencies]` only in the change where the first crate depends on it, and inherit it in that crate with `<context>-domain.workspace = true`. An entry nobody uses fails the dependency policy (`unused = "deny"`), and a version or path written in a member manifest is a workspace-dependencies duplicate. A new third-party crate must be on the allow-list of its layer; extending an allow-list is a protected change that escalates (see [dependency-policy](../dependency-policy/SKILL.md)). No allow-list change is needed for a context that uses only the crates its layers already allow.

**C4 to C8, the layers.** Write the domain first, framework-free and I/O-free ([implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md)), then the application layer with its handlers, extractors and error mapping ([api-resource-development](../api-resource-development/SKILL.md), [rust-error-handling](../rust-error-handling/SKILL.md)), then the infrastructure adapters with their integration tests, then the fakes in `tests/support`. C8 follows [database-migrations](../database-migrations/SKILL.md); the rollback round trip is an `ask` rule, so in a headless run it is recorded `not run (ask rule)` (D13) and the item is still `DONE` on `make validate-sqlx-metadata`.

**C9, the composition-root wiring points.** In the template layout the composition root is `crates/service`:

- `crates/service/Cargo.toml`: the dependencies on the application and infrastructure crates (and the domain crate when a port type is named there), inherited from the workspace.
- `src/bootstrap.rs`: the adapter fields of `Adapters` and their construction in `Adapters::connect`, the command and query handler registration, the subscribers in `event_bus()`, the context's state struct, and its `.data(...)` on the GraphQL schema builder.
- `src/http.rs`: the context's state field in `AppState`.
- `src/openapi.rs`: the context's router nested under `/api` in `openapi::api_router`, and its tag.
- `src/graphql/schema.rs`: the context's query and mutation roots added to the merged `Query` and `Mutation` roots of `graphql::schema`.
- The three `Adapters { .. }` literals: `src/bootstrap/tests.rs`, `src/http/router/tests.rs` and `tests/integration/panic.rs` each build `Adapters` field by field, so every new adapter field is added there (with the context's fake from `tests/support`), or the tests stop compiling.
- The contract-pinning tests: `src/openapi/tests.rs` (every documented operation) and `src/graphql/schema/tests.rs` (the expected SDL, `EXPECTED_SDL`), updated to the regenerated contracts of C10 in the same change.

**C10 and C11.** Regenerate both snapshots and commit them with the code ([api-contract-development](../api-contract-development/SKILL.md)); a new context adds operations, so the diffs against the base report additions, not breaking changes. Documentation follows [documentation-sync](../documentation-sync/SKILL.md).

### 6. Run the context gate set (C12)

After the C1–C11 commit (standalone: `feat(#N): add <group>/<context> bounded context`, made by the calling command), prove the context with the template's own stage targets. The stage composition is read at runtime from the Makefile's `CI_*_TARGETS` lines (`make ci-list` prints the flattened gate order); it is never restated from memory.

1. **Docker first.** Run `docker info`. A failure ends `ESCALATED` with the output of `make doctor` (D2); no stage runs and none is fed to remediation, because most gates need the container engine or the compose database.
2. **Base.** `<base>` is the base ref the calling command resolved: the configured base ref when `git rev-parse --verify` finds it (after at most one `git fetch origin <default branch>`), else `HEAD` with a D24 degrade note (`SUCCESS-WITH-REPORT` at best). It is always passed explicitly, so the Makefile's `origin/main` fallback never applies.
3. **The six stages, one call each, in this order, each in the background and polled to its end:** `make.ci_preflight` with `base_ref=<base> CONFIG_CHANGE_APPROVED=`, `make.ci_static_analysis`, `make.ci_tests`, `make.ci_contracts` with `base_ref=<base>`, `make.ci_mutation` with `base_ref=<base>`, `make.ci_delivery`. `ci-cli` (the Bats stage) is never run: the template's Bats suite never depends on a context. The resolved calls at the template's source commit, as a sourced example:

   ```bash # profile-example
   # stage targets of the Rust template's Makefile (CI_*_TARGETS); <base> resolved by the caller
   make ci-preflight base_ref=<base> CONFIG_CHANGE_APPROVED=
   make ci-static-analysis
   make ci-tests
   make ci-contracts base_ref=<base>
   make ci-mutation base_ref=<base>
   make ci-delivery
   make validate-configuration base_ref=<base> CONFIG_CHANGE_APPROVED=
   ```

4. **Remediation.** A failing stage gets a root-cause fix through the skill that owns the failing gate (never a lowered bar or a suppression), the calling command commits it as `fix(#N): <what>`, and the run resumes at the failed stage. At most five remediation rounds; when the stage still fails after the fifth round, the run escalates with the failing stage's log tail.
5. **Closing check.** After the last remediation commit, run the check mapped by `make.validate_configuration` with `base_ref=<base> CONFIG_CHANGE_APPROVED=` (never an inherited approval). A protected file in its output escalates (D23) with `recommended_action: revert with git restore --source=<base> -- <path> unless the plan intends it; otherwise approved-config-change`.

Record one targets-run row per stage: `<target>: passed | failed | not run (<reason>)`.

### 7. The in-loop story-1 variant

When the plan stage finds a needed `<group>/<context>` absent from the live `[workspace].members`, Epic 1 opens with story 1 "Scaffold `<group>/<context>`", whose acceptance criteria are C1–C12 with the evidence targets above. That story differs from the standalone run in these points only:

| Point | Standalone (/rs-sdlc-new-context) | In-loop story 1 |
| --- | --- | --- |
| Trigger | the command with `<group> <context>` | the plan stage's story-1 rule |
| Branch and issue | step 3 (reuse, or `feat/<N>-<context>`) | the loop's `<type>/<N>-<slug>` branch and issue; no second branch |
| Name check | the command's name validator | step 2 re-run by the story before C1 |
| Commits | `feat(#N): add <group>/<context> bounded context`, then `fix(#N): <what>` | the loop's commit convention from `## Constraints` (`<type>(#N): story 1.1 <title>`) |
| Order | runs alone | no dependency; every story that uses the context depends on it, so it runs first and has the test database to itself |
| C12 | step 6, then the hand-off to review, QA and PR finishing (or three `NEXT:` lines with `--no-handoff`) | step 6 inside the story; the review stage's verify step runs the same gate set again on the final head |
| Blocking finding | the escalation block below | the story ends with a `STATUS: BLOCKED` status block naming the finding, which the implement stage escalates |

The new-context command is never invoked from inside the loop, and the in-loop story never pushes.

## Constraints

- Never write a file, change a branch or run a make target before both names passed step 2, and never decide existence from `architecture.bounded_contexts`.
- Never scaffold on the default branch, and never create a second branch inside the feature loop.
- Never hand-write the scaffolder's crates or members, and never edit the template's scaffolder, its templates or its tests.
- Never add a `[workspace.dependencies]` entry before its first user, and never write a dependency version in a member manifest.
- Never edit a protected file (`architecture.toml`, `deny.toml`, the gate configuration or any other entry of `cargo xtask config-guard --list`) to make a gate pass; a needed change escalates with the protected-change line.
- Never suppress a finding: never add `#[allow(...)]`, `#[mutants::skip]` or `#[coverage(off)]`, never add an `exclude_re` or `exclude_globs` entry, and never pass `--ignore-filename-regex`.
- Never run `ci-cli`, never run `make ci` in one call, and never let `base_ref` fall back to the Makefile default: every base-ref reader gets `base_ref=<base>` and every protected-configuration check gets `CONFIG_CHANGE_APPROVED=` with an empty value.
- Never delete or skip an `Adapters { .. }` literal test or a contract-pinning test to get past a compile error or a changed contract; update it in the same change.
- Never edit `.claude/rust-sdlc.yml` on the branch.
- The remediation loop is bounded at five rounds and every degrade ends in a report or the escalation block; no stage is retried in an open loop.

## Verification

- The name check result: `NAMES: <group>/<context> valid (live tree)` or the `REFUSED:` line.
- `BRANCH: <branch>` and `ISSUE_NUMBER: <N>`.
- Twelve checklist lines, in order: `DONE: C<n> <evidence>` or `N/A: C<n> <reason>`.
- The targets-run rows of C12 (six stages and the closing check) in the FR-1 vocabulary, with the D24 note when `<base>` is `HEAD`.
- `git diff --name-only <base>` contains no protected path, and `git diff --quiet <base> -- .claude/rust-sdlc.yml` exits 0.

### Escalation

A refused name, a null or mismatched key of step 1, a classified scaffolder failure, Docker unreachable at C12, a protected change, or a stage that still fails after the fifth remediation round ends the standalone run with the canonical block:

```text
=== SDLC ESCALATION ===
stage: new-context
iteration: <n>/5
exit_condition: context gate set green, 0 protected files changed, committed
status: NOT MET
blocking_finding: <the REFUSED: line, the failing stage and its log tail, or file:line>
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human action, for example another context name, approved-config-change, or a fix of the doctor findings>
=== END ===
```
