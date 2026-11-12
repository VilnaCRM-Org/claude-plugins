---
name: dependency-policy
description: Use when a change adds, upgrades, removes or moves a third-party crate, edits a `Cargo.toml` dependency table or `Cargo.lock`, or when the target mapped by `make.check_security` (cargo-deny lanes advisories, licences, bans, sources) or by `make.unused_dependencies` (cargo-shear) reports a finding, including a RUSTSEC advisory. Covers the per-layer allow-lists of `architecture.toml` and the domain dependency whitelist (a needed change escalates, never edited), workspace inheritance through `[workspace.dependencies]`, diagnosis with `cargo tree -i <crate>` and the two dependency ceilings, both fixed at 0. Skip when neither target is mapped and the diff touches no manifest or lock file. Not for moving code between layers or contexts to satisfy the boundary check (use architecture-boundary-fixer), not for an OWASP audit of the service (use security-audit).
---

# Dependency Policy

## Profile keys consumed

- `architecture.layers` — the declared layer names, in declaration order; each names the layer table whose allow-lists decide which third-party crates a crate of that layer may use; `[]` skips the allow-list check
- `make.check_security` — the dependency policy check over the locked dependencies (advisories, licences, bans, sources); `null` degrades to a manual review of the manifest diff
- `make.unused_dependencies` — the check for unused or misplaced dependencies; `null` degrades to a manual review of the manifest diff
- `quality.max_dependency_policy_findings` — the ceiling, fixed at 0, for findings of the dependency policy check
- `quality.max_unused_dependencies` — the ceiling, fixed at 0, for unused or misplaced dependencies
- `capabilities.protected_config` — `true` when the repository protects its quality configuration, so a policy or allow-list change escalates with the protected-change line; `false` when it has no protected list, so such a change is still never made to obtain a pass and is escalated for a separate, human-reviewed policy change

## Context

Every third-party crate in a service derived from the Rust template passes three policies:

1. **The dependency policy, `deny.toml`**, checked by cargo-deny through the target mapped by `make.check_security`. Its four lanes: **advisories** (the RustSec database: vulnerable, unsound, yanked and unmaintained crates), **licences** (an allow-list of licence identifiers), **bans** (denied crates, wildcard version requirements, and `[bans.workspace-dependencies]`, which denies a version declared outside the workspace table and a workspace entry nobody uses) and **sources** (crates.io only; unknown registries and git sources are denied).
2. **Unused dependencies**, checked by the target mapped by `make.unused_dependencies`, which runs `cargo shear` (never call it directly): a declared dependency that no code uses, or a test-only dependency declared under `[dependencies]`.
3. **Per-layer allow-lists, `architecture.toml`**, enforced by the boundary check that [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md) owns. Each layer table lists the third-party crates its crates may use (`external`), may use in tests (`dev_external`) and must not reach even transitively (`forbidden_transitive`). The domain layer's `external` list is the domain dependency whitelist: domain crates stay free of frameworks and I/O.

`deny.toml` and `architecture.toml` are policy, not workspace: this skill changes manifests and the lock file, never those two files. Use it when a manifest or `Cargo.lock` changes, when either dependency target reports a finding, or when a new RUSTSEC advisory touches the lock file. The repository's own rules in `AGENTS.md` win where they are stricter.

## Task

Bring every dependency change into the policy by changing manifests and the lock file only: pick a crate the layer allows, declare it through workspace inheritance, keep licences and sources inside the policy, remove what nothing uses, upgrade to a patched version when an advisory has one, and escalate everything the policy forbids changing (an advisory without a fixed version, an allow-list or a policy edit). Prove it with the targets mapped by `make.check_security` and `make.unused_dependencies`.

## Success criteria

- The target mapped by `make.check_security` exits 0 with 0 findings, within `quality.max_dependency_policy_findings`; a finding is a line of its log that starts with `error[`.
- The target mapped by `make.unused_dependencies` exits 0, within `quality.max_unused_dependencies`.
- Both ceilings are 0: the profile schema accepts no other value, so one finding fails the change.
- Every added third-party crate is on the allow-list of the layer of the crate that declares it, and no crate on that layer's `forbidden_transitive` list became reachable through normal dependencies.
- Every dependency version is declared once, in `[workspace.dependencies]`; member manifests inherit it with `workspace = true`.
- `git status --porcelain -- deny.toml architecture.toml` prints nothing, and every forbidden change is reported in the escalation block instead.

## Steps

### 1. Resolve the profile and the protected list

Read the six keys above. Then:

- When `capabilities.protected_config` is `true`, read the protected list once with `cargo xtask config-guard --list` (FR-1 raw call 2; when neither the host toolchain nor the container route is available, read `protected-config.toml` with python3 `tomllib` instead) and note whether `deny.toml`, `architecture.toml` and `Cargo.toml` tables are on it. A listed item is never edited; a needed change ends in step 7 with the protected-change line.
- When `capabilities.protected_config` is `false`, the repository has no protected list. The two policy files are still out of scope for a feature change: a needed change ends in step 7 as a separate, human-reviewed policy change, never as part of this change.
- When `architecture.layers` lists layers, step 3 applies. When it is `[]`, record `SKIPPED: architecture.layers is empty` for step 3 (the repository declares no layer model); the cargo-deny lanes and the unused-dependency check still apply.

### 2. Diagnose with `cargo tree -i <crate>`

The two raw calls this skill may make (FR-1 raw call 1) show why a crate is in the graph and where it is declared:

```bash
cargo tree -i <crate>
cargo metadata --format-version 1 --no-deps
```

`cargo tree -i <crate>` inverts the tree: it prints every path from a workspace crate down to `<crate>`, so the lines nearest the workspace crates name the direct dependency to change. `cargo metadata --format-version 1 --no-deps` lists the workspace members with their manifest paths and declared dependencies. When the calling stage runs in container mode, both go through the container route, with the user and group ids resolved once to literals from `id -u` and `id -g`:

```bash
docker compose exec -T --user <uid>:<gid> app cargo tree -i <crate>
```

No other raw `cargo` call is part of this skill.

### 3. Check the layer allow-list before adding a crate

1. Find the layer: the layer table whose `crates` pattern matches the crate that will declare the dependency; its `name` is one of `architecture.layers`.
2. A normal dependency must be on that table's `external` list, a dev-dependency on its `dev_external` list; `"*"` allows any crate.
3. After the change, run `cargo tree -i <forbidden>` for each crate of the table's `forbidden_transitive` list: no path may run through normal dependencies.
4. For a domain crate, the domain dependency whitelist is the complete set of third-party crates it may use. A sourced example (the template's domain table; read the service's own file at runtime):

   ```toml # profile-example
   # architecture.toml of the Rust template, domain layer table
   [[layer]]
   name = "domain"
   crates = ["*-domain"]
   directory = "domain"
   depends_on = ["domain"]
   external = ["async-trait", "thiserror", "uuid"]
   dev_external = ["proptest", "rstest", "tokio"]
   forbidden_transitive = ["axum", "hyper", "reqwest", "sqlx", "tokio"]
   ```

5. When the crate is not on the list, redesign first so the dependency lives in a layer that allows it (a port in the domain, its adapter in infrastructure; see [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md)). When the story needs the crate in that layer anyway, go to step 7; never edit the allow-list.

### 4. Declare the crate through workspace inheritance

- Declare the version once, in `[workspace.dependencies]` of the root `Cargo.toml`, with a concrete version requirement (never `*`: wildcards are banned) and with `default-features = false` plus explicit features when the defaults pull a banned or unneeded crate.
- In the member manifest, inherit it: `<crate>.workspace = true`, or `<crate> = { workspace = true, features = [...] }` to add features for that member. A version written in a member manifest is a workspace-dependencies duplicate.
- Add the workspace entry with its first user and remove it with its last; an entry nobody uses is denied.
- Members also inherit the package fields (`version.workspace = true`, `edition.workspace = true`, `rust-version.workspace = true`, `license.workspace = true`) and the lint policy (`[lints]` with `workspace = true`); never add a per-crate lint table.
- Before adding a crate, check that its licence is on the `[licenses]` allow-list of `deny.toml` and that it comes from crates.io; a path dependency is allowed only for a workspace crate.
- Every gate runs with `--locked`, so `Cargo.lock` must match the manifests. Refresh it with the lock-file target that `docs/make-targets.md` lists (no profile key maps it: read its name there at runtime and run it in the background like every other target), then read the `Cargo.lock` diff; every version it moved is checked again in step 5. When the repository lists no such target, go to step 7. Never run `cargo update` or `cargo add` directly: neither is on the FR-1 exception list.

### 5. Run the two dependency checks

Run each mapped target as [verification-workflow](../verification-workflow/SKILL.md) prescribes (in the background, logged and polled to the end): first `make.check_security`, then `make.unused_dependencies`. Measure the policy check by its `error[` lines and the unused-dependency check by its exit code, and compare each with its ceiling (0).

- A null key is recorded `not run (capability absent)` (degrade D1). For a null `make.check_security`, review the manifest diff against steps 3 and 4 (allow-list, inheritance, wildcards, sources, licences) and report the advisory lane as not checked; for a null `make.unused_dependencies`, confirm with a search of the member's sources that each added dependency is used. Either way the result is `SUCCESS-WITH-REPORT`, never a claimed pass.
- A run that cannot start (no toolchain, no reachable container engine, the advisory database not reachable) is recorded `not run (no toolchain)`, `not run (no Docker)` or `failed` with the log tail, and handed back to the calling stage, which escalates; it is never retried in a loop.

### 6. Fix findings by lane

| Lane | Finding | Fix |
| --- | --- | --- |
| advisories | RUSTSEC advisory whose text names patched versions | `cargo tree -i <crate>`; for a direct dependency raise its requirement in `[workspace.dependencies]`, for a transitive one refresh the lock file (step 4) to a patched version; run step 5 again |
| advisories | RUSTSEC advisory without a fixed version, or an unsound or unmaintained crate with no maintained replacement the layer allows | step 7; never add an `ignore` entry |
| advisories | yanked version | refresh the lock file to a version that is not yanked |
| licences | a crate's licence is not on the allow-list | replace the crate with one whose licence is allowed; never extend the allow-list (step 7) |
| bans | a denied crate is reachable, often through default features | `cargo tree -i <banned>`; turn off the default features or select the feature that avoids it, in `[workspace.dependencies]` |
| bans | wildcard version requirement | write a concrete version requirement |
| bans | workspace-dependencies duplicate or unused entry | move the version into `[workspace.dependencies]`, or remove the unused entry |
| sources | git source or unknown registry | use the crates.io release; never allow the source (step 7) |
| unused (cargo-shear) | a declared dependency no code uses | remove it from the member manifest, and from `[workspace.dependencies]` when it was the last user |
| unused (cargo-shear) | a dependency only tests use, declared under `[dependencies]` | move it to `[dev-dependencies]` |
| unused (cargo-shear) | a dependency used only through a macro expansion the check cannot see | step 7; never add a `[package.metadata.cargo-shear]` ignore entry |

A duplicate-version warning (`multiple-versions`) is a warning, not an `error[` finding: leave it unless the story asks for it.

### 7. Escalate what the policy forbids changing

Escalate, without editing anything, when:

- a RUSTSEC advisory has no fixed version: `blocking_finding` names the advisory id, the crate and version and the `cargo tree -i <crate>` path; `recommended_action` names the options (replace the dependency, drop the feature that pulls it in, or a maintainer-approved `ignore` entry with a reason and an end date in `deny.toml`);
- a layer allow-list, the licence allow-list, a ban or a source rule would have to change;
- the lock file cannot be refreshed through a listed target;
- the same finding remains after a fix, or the calling stage's iteration guard (5) is spent.

When `capabilities.protected_config` is `true` and the change touches a listed file, `recommended_action` carries the protected-change line for that file, for example `BLOCKED: protected configuration architecture.toml — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`. When it is `false`, `recommended_action` asks for a separate policy change reviewed by a human.

## Constraints

- Never edit `deny.toml` or `architecture.toml` to obtain a pass: no `ignore` entry, no allow-list entry, no lifted ban, no allowed git source or registry.
- Never add a `[package.metadata.cargo-shear]` ignore entry and never move a dependency to a section where it is not used.
- Never declare a version in a member manifest, never write a wildcard requirement and never add a git or path dependency outside the workspace.
- Never raise `quality.max_dependency_policy_findings` or `quality.max_unused_dependencies`: both are fixed at 0.
- Never issue a raw `cargo` call other than `cargo tree -i <crate>`, `cargo metadata --format-version 1 --no-deps` and `cargo xtask config-guard --list`; the dependency checks run only through their mapped targets, never as `cargo deny` or `cargo shear` typed by hand.
- Never add a crate to a domain crate outside the domain dependency whitelist.
- The fix loop is bounded by the calling stage's iteration guard (5); it ends in a pass or in the escalation block below, never in a further retry.

## Verification

- Targets-run rows, in the FR-1 vocabulary: `<target of make.check_security>: passed | failed | not run (<reason>)` and the same for `make.unused_dependencies`, each with its measured value against its ceiling of 0.
- One row per added, upgraded or removed crate: `| crate | member manifest | layer | allow-list | licence | source | cargo tree -i path |`, or `SKIPPED: architecture.layers is empty` in the layer column.
- `git status --porcelain -- deny.toml architecture.toml` printed empty.
- Evidence for the `EXECUTE` verdict of this skill in the triage table: the targets-run rows plus the crate rows, or the escalation block.

### Escalation

When step 7 applies, print the canonical block with the calling stage's id and exit string:

```text
=== SDLC ESCALATION ===
stage: <stage-id>
iteration: <n>/5
exit_condition: <exit string of the calling stage, verbatim>
status: NOT MET
blocking_finding: <advisory id, crate and version, or the policy rule> (<cargo tree -i path>)
iteration_log: <one line per iteration: "<n>: <what ran> -> <result>">
recommended_action: <the human decision, for example a protected change with ALLOW_PROTECTED_CONFIG_EDIT=1>
=== END ===
```
