---
name: architecture-boundary-fixer
description: Use when the layer and bounded-context boundary check (`make.architecture`), the crate-isolation check (`make.check_crate_isolation`) or the unused-dependency check (`make.unused_dependencies`) reports a finding, or when Rust code must move between layers or bounded contexts. Fixes the code by moving it, never by editing the allow-lists of `architecture.toml`; an allow-list change escalates. Skip when all three targets are null in the profile. Not for keeping `workspace.dsl` in step with the crates (use architecture-model-sync), not for adding, upgrading or auditing a third-party crate (use dependency-policy), not for the layer rules of new code (use clean-architecture-llm).
---

# Architecture Boundary Fixer

## Profile keys consumed

- `architecture.layers` — the declared layer names, in declaration order; the vocabulary every finding is classified against
- `architecture.crates_root` — the directory that holds the workspace crates, where moved and renamed crates land
- `make.architecture` — the layer and bounded-context boundary check
- `make.check_crate_isolation` — the check that every crate builds alone, with each of its features
- `make.unused_dependencies` — the check for unused or misplaced dependencies
- `quality.max_architecture_violations` — the violation ceiling, fixed at 0, for the boundary and crate-isolation checks
- `capabilities.protected_config` — whether the repository protects its configuration files, which decides the wording of an allow-list escalation

## Repository precedence

Read `.claude/skills/architecture-boundary-fixer/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

When the repository has no such skill file, the fix patterns below stand alone. When the repository skill and this skill disagree, follow the repository skill and record the difference in the evidence.

## Context

Use this skill when one of these holds:

- The target mapped by `make.architecture` fails: a crate matches no layer, matches two layers, depends on a forbidden layer, on another bounded context or on a third-party crate its layer may not use, or sits in the wrong directory.
- The target mapped by `make.check_crate_isolation` fails: a crate does not compile on its own or with one of its features, because it relies on a dependency or a feature that only another crate declares.
- The target mapped by `make.unused_dependencies` fails: a manifest declares a dependency that no code uses, or a test-only dependency under `[dependencies]`.
- A story or a review finding asks for code to move between layers or between bounded contexts.

Inputs: the log of the failing target, the list of changed files, the profile and the repository's boundary model in `architecture.toml` (its layer tables give each layer's crate patterns, the layers it may depend on, the third-party crates it may use and the crates it must not reach even transitively; its contexts table names the shared contexts every context may use).

The layer names come from `architecture.layers`, never from memory. When the list is empty the repository declares no layer model: classify each finding from the diagnostic itself (crate name and manifest path) and never invent layer names or layer crates.

Crate paths are written below `architecture.crates_root`. When that key is null the repository has no single crates directory: read each crate's path from `[workspace].members` of the root `Cargo.toml` instead.

## Task

Bring every mapped check to a pass with the measured violation count at `quality.max_architecture_violations` (a fixed ceiling of 0 that is never raised), by moving code between layers or bounded contexts and adjusting the crate manifests to match: move a type or a module to the layer or context that owns it, invert a dependency through a port, rename or move a crate to the path its layer pattern expects, declare a dependency in the crate that uses it, remove a dependency that nothing uses. The allow-lists of `architecture.toml` are not part of the fix space: a finding that can only be resolved by widening them is escalated, never edited.

## Success criteria

- Each target that is mapped exits 0, and the measured value is within the bound: 0 violations for `make.architecture` and `make.check_crate_isolation`; a zero exit for `make.unused_dependencies`.
- `git status --porcelain -- architecture.toml` prints nothing: the boundary model is untouched.
- No suppression was added: no lint attribute, no ignore entry, no renamed-to-dodge crate (the Constraints list the forbidden forms).
- Each moved crate or relationship is handed to [architecture-model-sync](../architecture-model-sync/SKILL.md), so the model check stays green.
- The evidence table and the verdict line below are printed.

## Steps

1. **Resolve the profile.** Read the seven keys above. For each of the three targets that is null, record `not run (capability absent)` for its row and leave it out of the loop. When all three are null, print the evidence table and end with the verdict `SUCCESS-WITH-REPORT`; there is nothing to run and nothing to fix.
2. **Run the mapped checks once, in this order:** `make.architecture`, then `make.check_crate_isolation`, then `make.unused_dependencies`. Run each target as [verification-workflow](../verification-workflow/SKILL.md) prescribes (backgrounded, with its log under `target/rust-sdlc/logs/`, polled to the end). Record the exit code and the measured value of each.
3. **Tell a finding from a broken run.** A boundary run that exits non-zero without a single violation block and without its verdict line, or a run that stops on a missing toolchain, an unreachable container engine or an unreadable configuration, is a mapped capability that cannot run. Do not loop on it: escalate at once (step 8, run-failure case).
4. **Measure.** For the boundary check, the measured value is `<n>` of the verdict line `architecture: FAILED. <n> violation(s) …` (0 on exit 0). For crate isolation, it is the number of `error: could not compile` lines, at least 1 on a non-zero exit. For unused dependencies, it is exit-based. When the output cannot be parsed, report `≥ 1 (exit <n>)` and treat the row as failed.
5. **Split the log into findings.** Each boundary violation is one block: `error[arch::<rule>]: <message>`, then `--> <manifest path>`, then `= help: <hint>`. Each crate-isolation finding is one crate and feature that failed to compile. Each unused-dependency finding is one crate and one dependency name.
6. **Fix by pattern, innermost layer first** (domain findings before application, application before infrastructure, so a fix never has to be redone):

   | Finding | Fix by changing the code |
   | --- | --- |
   | `arch::uncovered` (no layer pattern matches the crate) | Rename the crate `<context>-<layer>`, where `<layer>` is one of `architecture.layers`, and move it to its layer directory |
   | `arch::ambiguous` (two patterns match) | Rename the crate so exactly one pattern matches |
   | `arch::layer` (a forbidden layer dependency) | Remove the dependency: define a port trait in the inner layer, implement it in the outer layer, wire the two in the composition root |
   | `arch::context` (a dependency on another bounded context) | Remove it: publish a domain event and subscribe to it in the other context, or move the shared type into a shared context named by `architecture.toml` |
   | `arch::external` (a third-party crate the layer may not use) | Move the code that needs the crate to a layer that may use it, or wrap the crate behind a port implemented in infrastructure |
   | `arch::transitive` (a forbidden crate is reachable through another dependency) | Find the path with `cargo tree -i <crate>`, then remove or replace the dependency that pulls the crate in |
   | `arch::path` (the crate sits outside its layer directory) | Move the crate to the directory the hint names, below `architecture.crates_root`, and update `[workspace].members` of the root `Cargo.toml` |
   | `arch::lints` (the crate does not inherit the workspace lints) | Add `[lints]` with `workspace = true` to the crate manifest |
   | crate does not compile alone or with one feature | Declare the missing dependency or feature in that crate's own manifest, through `[workspace.dependencies]` inheritance (`<dep> = { workspace = true, features = [...] }`), or move the code that needs it to the crate that already declares it |
   | unused or misplaced dependency | Remove the entry from the crate manifest, or move a test-only entry to `[dev-dependencies]`; after a code move, remove what the old crate no longer uses |

   Some hints of the boundary checker suggest adding a crate name to a layer's crate list or a third-party crate to a layer's allow-list. Those hints describe an allow-list change: take the code fix from the table, or go to step 8.
7. **Re-run and count.** After each group of fixes, re-run the failing targets and state the counter as `iteration <n>/5` with the new measured values. At most 5 rounds (`MAX_ITERATIONS=5`). A round that does not lower the measured value must not repeat the same fix: the next round tries another pattern from the table, or the loop escalates. After the last round with findings left, escalate (step 8, exhausted-loop case).
8. **Escalate.** Three cases stop the skill with the canonical escalation block; fill its fields as follows and print nothing after it but the evidence table and the verdict line.

   - **Run failure** (step 3): `blocking_finding: make <target> exit <code>`; `recommended_action:` the missing tool, engine or configuration to restore before a re-run.
   - **Exhausted loop** (step 7): `blocking_finding:` the manifest path and `arch::<rule>` (or crate and feature, or crate and dependency) of the first finding left; `recommended_action:` the design decision that finding needs.
   - **Allow-list question:** a finding is resolved only by changing `architecture.toml` (a new layer, a new allowed layer dependency, a new allowed third-party crate, a new shared context), or `architecture.toml` already differs from the merge base of the branch. The wording depends on `capabilities.protected_config`.

   When `capabilities.protected_config` is true (the file is on the protected list printed by `cargo xtask config-guard --list`):

   ```text
   === SDLC ESCALATION ===
   stage: <the calling stage id>
   iteration: <n>/5
   exit_condition: <the calling stage's exit string, verbatim>
   status: NOT MET
   blocking_finding: <arch::rule> in <manifest path> needs an allow-list change in architecture.toml (<layer or crate>)
   iteration_log: <one line per round: "<n>: <target> -> <measured value>">
   recommended_action: if architecture.toml already changed on the branch, revert it with git restore --source=<merge-base> -- architecture.toml unless the plan intends the change; otherwise a human decides the allow-list change, applies approved-config-change and makes it in a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1
   === END ===
   ```

   When `capabilities.protected_config` is false (no protected list; the boundary model is still not this skill's to edit):

   ```text
   === SDLC ESCALATION ===
   stage: <the calling stage id>
   iteration: <n>/5
   exit_condition: <the calling stage's exit string, verbatim>
   status: NOT MET
   blocking_finding: <arch::rule> in <manifest path> needs an allow-list change in architecture.toml (<layer or crate>)
   iteration_log: <one line per round: "<n>: <target> -> <measured value>">
   recommended_action: the architecture owner decides the allow-list change in its own pull request; resume this work after it merges
   === END ===
   ```

9. **Hand over.** When a crate was added, renamed, moved or removed, or a crate-to-crate dependency appeared or disappeared, continue with [architecture-model-sync](../architecture-model-sync/SKILL.md). When code moved between crates, the tests that [testing-workflow](../testing-workflow/SKILL.md) runs must still pass.
10. **Report.** Print the evidence table and the verdict line.

    ```text
    | target key | result | measured | bound |
    | --- | --- | --- | --- |
    | make.architecture | PASS, FAIL or not run (capability absent) | <n> | 0 (quality.max_architecture_violations) |
    | make.check_crate_isolation | PASS, FAIL or not run (capability absent) | <n> | 0 (quality.max_architecture_violations) |
    | make.unused_dependencies | PASS, FAIL or not run (capability absent) | exit <n> | exit 0 |
    architecture-boundary-fixer: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
    ```

    `SUCCESS`: every mapped target passes and none is null. `SUCCESS-WITH-REPORT`: every mapped target passes and at least one row is `not run (capability absent)`. `ESCALATED`: the escalation block above was printed.

A sourced example of the boundary check's output, from a template-derived repository:

```text # profile-example
error[arch::layer]: `<context>-application` (layer `application`, context `<context>`) must not depend on `<context>-infrastructure` (layer `infrastructure`, context `<context>`)
  --> crates/<group>/<context>/application/Cargo.toml
   = help: layer `application` may depend on: [domain, application] and, as dev-dependencies, on: [test-support]; declare a port (trait) in the inner layer and implement it in the outer one

architecture: FAILED. 1 violation(s) in 13 crate(s), 7 layer(s) checked
```

## Constraints

- Never edit `architecture.toml`, and never edit the boundary checker itself; an allow-list change is a human decision reached through the escalation block of step 8.
- Never write any file on the protected list printed by `cargo xtask config-guard --list` when `capabilities.protected_config` is true.
- Never raise `quality.max_architecture_violations` above 0 and never report a pass while the measured value is above it.
- Never silence a finding: no `#[allow(...)]` attribute, no ignore entry under `[package.metadata.cargo-shear]`, no feature flag that compiles the offending code out.
- Never rename a crate, or move it into an unrelated context, only to dodge a pattern; a crate's name and place follow the responsibility of its code.
- Never create a catch-all crate or module (`utils`, `common`, `helpers`) to hide a cross-layer or cross-context dependency.
- Never apply or remove a pull-request label; a human does that after reading the escalation.
- Domain crates stay free of frameworks and I/O: an `arch::layer` or `arch::external` finding in a domain crate is fixed by moving the code outward, never by adding a dependency inward.
- Write example contexts as `<group>/<context>` and types as `<Entity>`; read the real names from the repository.

## Verification

```bash
make <make.architecture>
make <make.check_crate_isolation>
make <make.unused_dependencies>
git status --porcelain -- architecture.toml
```

Each mapped target exits 0 with a measured value of 0, the last command prints nothing, and the output ends with the evidence table and the verdict line of step 10. A null target is reported `not run (capability absent)`, never as a pass.
