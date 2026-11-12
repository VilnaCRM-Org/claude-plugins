---
name: architecture-model-sync
description: Use when a workspace crate or bounded context is added, renamed or removed, or a crate-to-crate dependency or an external system appears or disappears, so `workspace.dsl` keeps exactly one component per crate and one relationship per dependency edge, proven by the model check mapped by `make.validate_architecture_model`. Skip when `capabilities.structurizr` is false (the repository keeps no Structurizr model; never create one). Not for fixing a boundary, crate-isolation or unused-dependency finding (use architecture-boundary-fixer), not for scaffolding a whole new context (use bounded-context-scaffolding).
---

# Architecture Model Sync

## Profile keys consumed

- `capabilities.structurizr` — whether the repository maintains a Structurizr model checked against its crates; false skips the skill
- `make.validate_architecture_model` — the model check that compares components and relationships with the workspace crates and their dependencies
- `architecture.crates_root` — the directory that holds the crate manifests the model mirrors
- `architecture.bounded_contexts` — the bounded-context names, each a group and a context, that the model groups its components by (informational; the live tree wins)

## Repository precedence

Read `.claude/skills/architecture-model-sync/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line.

When the repository has no such skill file, the rules below stand alone. When the repository skill and this skill disagree, follow the repository skill and record the difference in the evidence.

## Capability gate

Check `capabilities.structurizr` before anything else.

- **False:** the repository keeps no Structurizr model. Print `SKIPPED: capabilities.structurizr is false`, then the verdict line `architecture-model-sync: SUCCESS-WITH-REPORT`, and stop. Never create `workspace.dsl` from scratch under this skill.
- **True and `make.validate_architecture_model` mapped:** the designed path; continue with the Steps.
- **True and `make.validate_architecture_model` null** (a hand-edited profile): edit the model by the Steps, record the check as `not run (capability absent)` and end `SUCCESS-WITH-REPORT`; never claim the model was proven.

## Context

Use this skill in the same change as any of these:

- A workspace crate is added, renamed, moved or removed (a new layer crate, a new context's crates, a crate split or merged by a boundary fix).
- A crate gains or loses a `[dependencies]` entry on another workspace crate.
- An external system (database, message broker, cache, third-party API) starts or stops being reached by an adapter.
- The model check fails on the branch.

Inputs: the change's crate manifests, `workspace.dsl`, the output of the model check, and the crate list. The crate list is the live workspace: `cargo metadata --format-version 1 --no-deps` prints every workspace package with its manifest path and its dependencies (a dependency with a `path` is workspace-internal; `kind` null is a normal dependency, `dev` and `build` are not relationships of the running service).

Crate manifests live below `architecture.crates_root`. When that key is null, read the member paths from `[workspace].members` of the root `Cargo.toml`.

Bounded contexts come from `architecture.bounded_contexts` as `<group>/<context>`. The list is informational: when it differs from the live tree (a context added on this branch, a stale profile), the live tree wins and the difference goes into the evidence. When the list is empty, derive the contexts from the member paths (`<group>/<context>/<layer>`) alone.

## Task

Keep `workspace.dsl` equal to the workspace, with one component per crate and one relationship per dependency edge:

- exactly one component per modelled workspace crate, named exactly like the crate, so the check can match it; a removed crate loses its component and every relationship that names it;
- exactly one relationship per dependency edge between two modelled crates, written from the dependent crate to its dependency (`<dependent> -> <dependency> "<what it uses>"`), and none between two crates without such an edge;
- every external system reached by an adapter, with one relationship from the infrastructure component that reaches it;
- the system context, container and component views kept, with each new element in the view where it belongs.

The model check decides which crates are modelled: tooling, test-support and end-to-end crates are usually left out, and the check prints the exact difference (see Steps).

## Success criteria

- The target mapped by `make.validate_architecture_model` exits 0 and reports no missing view, no missing or extra component and no missing relationship.
- Every crate-to-crate relationship in the component view corresponds to a normal `[dependencies]` edge, including target-specific tables and `package =` renames; no relationship stands for a dev- or build-dependency.
- `workspace.dsl` changes in the same commit as the crate or dependency change it describes.
- Existing identifiers in `workspace.dsl` are reused; no established element is renamed to match this skill's examples.
- The evidence table and the verdict line below are printed, or the `SKIPPED:` line of the Capability gate.

## Steps

1. **Pass the Capability gate.** Stop there on its skip path.
2. **List the crates and edges.** From `cargo metadata --format-version 1 --no-deps`, write down each workspace crate and each normal dependency on another workspace crate. Group the crates by `<group>/<context>` and layer.
3. **List the model.** Read `workspace.dsl`: every `component "<crate name>"` inside the service container, the group that holds it, and every `<a> -> <b>` relationship between two components.
4. **Edit the components.** Add a component for each new crate inside the group of its context and layer, following the grouping and the tags the file already uses (one group per `<group>/<context>`, one nested group per layer). Give it a one-line description of what the crate holds. Remove the component of each removed crate. For a renamed crate, change the component's name string and keep its identifier when the identifier still reads correctly.
5. **Edit the relationships.** Add one relationship per new edge, labelled with what the dependent crate actually uses (a port it implements, a type it reads, events it publishes). Remove every relationship whose edge no longer exists. Add or remove the relationship from an infrastructure component to an external system when an adapter starts or stops reaching it, with the protocol as technology.
6. **Prove it.** Run the target mapped by `make.validate_architecture_model` as [verification-workflow](../verification-workflow/SKILL.md) prescribes (backgrounded, with its log under `target/rust-sdlc/logs/`, polled to the end). Read its findings:

   | Finding line | Fix |
   | --- | --- |
   | `missing view: …` | Restore the system context, container or component view named in the line |
   | `missing component: <crate> …` | Add the component (step 4) |
   | `extra component: <name> …` | Remove the component, or rename it to the crate it stands for |
   | `missing relationship: <a> -> <b> …` | Add the relationship from `<a>` to `<b>` (step 5) |
   | a parse or export failure | Fix the DSL syntax at the line the check names: balanced braces, components defined before the relationships that use them, no duplicate identifiers |

7. **Loop, bounded.** Re-run after each round of fixes and state the counter as `iteration <n>/5`. At most 5 rounds (`MAX_ITERATIONS=5`); a round that leaves the same findings must not repeat the same edit. The check needs a container engine: when it stops because the engine is unreachable or a tool cannot run, that is a mapped capability that cannot run, so escalate at once instead of looping.
8. **Escalate when the loop ends unmet.**

   ```text
   === SDLC ESCALATION ===
   stage: <the calling stage id>
   iteration: <n>/5
   exit_condition: <the calling stage's exit string, verbatim>
   status: NOT MET
   blocking_finding: make <make.validate_architecture_model> exit <code>: <first finding line>
   iteration_log: <one line per round: "<n>: model check -> <finding count>">
   recommended_action: fix workspace.dsl for the findings above, or start the container engine and re-run the model check
   === END ===
   ```

9. **Report.** Print the evidence table and the verdict line.

   ```text
   | item | result |
   | --- | --- |
   | crates modelled / workspace crates | <m> / <n> |
   | edges with a relationship / dependency edges | <m> / <n> |
   | contexts (live tree vs architecture.bounded_contexts) | equal, or the difference |
   | make.validate_architecture_model | PASS, FAIL or not run (capability absent) |
   architecture-model-sync: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
   ```

   `SUCCESS`: the model check passes. `SUCCESS-WITH-REPORT`: the skip path, or the model edited with the check unmapped. `ESCALATED`: the escalation block above was printed.

A sourced example of one context's components and edges, in the shape a template-derived `workspace.dsl` uses:

```text # profile-example
group "<Group>/<Context>" {
    group "<Group>/<Context>/Domain" {
        contextDomain = component "<context>-domain" "<Entity> aggregate, value objects, events, repository port." "Rust crate" {
            tags "Domain"
        }
    }
    group "<Group>/<Context>/Infrastructure" {
        contextInfrastructure = component "<context>-infrastructure" "PostgreSQL adapter of the <Entity> repository port." "Rust crate" {
            tags "Infrastructure"
        }
    }
}
contextInfrastructure -> contextDomain "Implements the <Entity> repository port"
contextInfrastructure -> database "Reads and writes <entity> rows" "SQL over TCP"
```

## Constraints

- Never create `workspace.dsl` when `capabilities.structurizr` is false; the skip path is the only outcome.
- Never edit the model check's script or `architecture.toml`; a new context needs no line in `architecture.toml`, and a boundary finding belongs to [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md).
- Never add a relationship the manifests do not state, and never leave one whose edge was removed; a label describes the real dependency, not a wish.
- Never rename established identifiers to match an example; reuse what the file defines.
- Never report the model as proven while the check is unmapped or did not run.
- Write example contexts as `<group>/<context>` and types as `<Entity>`; read the real names from the repository.

## Verification

```bash
make <make.validate_architecture_model>
```

The target exits 0 with no `missing` or `extra` line, the crate and edge counts of the evidence table match, and the output ends with the verdict line of step 9, or with `SKIPPED: capabilities.structurizr is false` and `architecture-model-sync: SUCCESS-WITH-REPORT`.
