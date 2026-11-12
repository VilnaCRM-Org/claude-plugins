---
name: code-organization
description: Use when Rust code adds, moves, renames or splits a crate, a module, a source file or a test file, or when a review or the static analysis flags the layout. Covers `<context>-<layer>` crate names under `architecture.crates_root`, what belongs in the composition root, the shared crates of `architecture.shared_crates`, `foo.rs` plus `foo/` instead of `mod.rs`, unit tests in a sibling `tests.rs`, integration tests in `<crate>/tests/integration/main.rs`, the naming of modules and types, and the law "a directory named for a type holds only that type". Skip the crate-placement step when `architecture.crates_root` is null; the shared-crate, wiring, module, test-file and naming rules still apply. Not for creating a whole bounded context (use bounded-context-scaffolding), not for designing aggregates, value objects, errors and ports (use implementing-ddd-architecture), not for deciding which layer owns a responsibility (use clean-architecture-llm).
---

# Code Organization for Rust Workspaces

## Profile keys consumed

- `architecture.crates_root` — the directory below which every bounded-context layer crate lives as `<group>/<context>/<layer>`; null means the workspace has no crates directory and the crate-placement step is skipped
- `architecture.composition_root` — the crate that wires adapters, handlers and routes, whose binary entry point only calls into its library; null means the wiring stays in the entry module of the binary crate
- `architecture.shared_crates` — the shared-kernel crates; a type moves into one only when a second bounded context needs it; empty means there is no shared kernel
- `architecture.bounded_contexts` — the existing `<group>/<context>` names (informational; the live workspace members win), which tell whether a crate belongs to an existing context or needs a new one

## Context

Use this skill whenever a change creates, moves, renames or splits a crate, a module, a source file or a test file, and when a review or the static analysis reports a layout finding (a `mod.rs`, an inline test module, a crate in the wrong directory, a catch-all module). The template's gates enforce part of the layout (the static analysis denies `mod_module_files`; the boundary check verifies that a crate lives in the directory its layer entry in `architecture.toml` names) and review enforces the rest; this skill states the whole layout so files land in the right place the first time.

Placeholders used throughout: `<crates_root>` is the value of `architecture.crates_root`, `<composition_root>` the value of `architecture.composition_root`, `<group>/<context>` the bounded context of the change, `<context>` its crate-name stem, `<layer>` one of the layer directories (`domain`, `application`, `infrastructure` in a template-derived workspace; the `directory` value of each layer entry is authoritative), `<Entity>` the aggregate type and `<entity>` its snake_case form. Read the real names from the repository; never copy names from the repository's sample context into a new one.

Inputs: the story or review scope, the profile, the root `Cargo.toml` (`[workspace].members` and `[workspace.dependencies]`), `architecture.toml` and the existing crates. The full directory trees, the naming table and the move checklist are in [DIRECTORY-STRUCTURE.md](DIRECTORY-STRUCTURE.md).

## Task

Place every new or moved crate, module, source file and test file where the workspace layout expects it and name it by the conventions below, so that the static analysis, the boundary check and review find no layout issue and a reader finds each type by its kind and its bounded context.

## Success criteria

- Every bounded-context layer crate lives at `<crates_root>/<group>/<context>/<layer>`, is named `<context>-<layer>` (library `<context>_<layer>`), is registered in `[workspace].members` and `[workspace.dependencies]`, and inherits the workspace package fields and lints.
- Wiring (configuration, command-line parsing, adapter construction, handler and subscriber registration, route assembly) exists only in the composition root, and its `main.rs` contains only the call into the library.
- Shared crates hold only types that two or more contexts use and that carry no context meaning.
- No file named `mod.rs` exists: a module `foo` with children is `foo.rs` plus the directory `foo/`.
- Every module with unit tests ends with `#[cfg(test)] mod tests;` and its tests are in the sibling `foo/tests.rs`; no inline `mod tests { ... }` block exists.
- Every test that needs a database, real time, a socket or the built binary is a module of `<crate>/tests/integration/`, declared in `<crate>/tests/integration/main.rs`.
- Every directory named for a type holds only that type, and no catch-all module (`utils`, `helpers`, `common`, `misc`) exists.
- The verdict line of step 11 is printed.

## Steps

1. **Resolve the profile.** Read the four keys. When `architecture.crates_root` is null, print `SKIPPED: crate placement (architecture.crates_root is null)`, skip step 3, apply steps 4 to 10 to the crates the change touches, and note the missing crates root in the evidence. When it is set, every bounded-context crate path below starts with `<crates_root>`.
2. **Classify each new or moved item.** Decide which crate owns it before deciding where the file goes: a layer crate of a bounded context (the layer follows [clean-architecture-llm](../clean-architecture-llm/SKILL.md); aggregates, value objects, errors and ports follow [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md)), a shared crate (step 4), the composition root (step 5), or a support crate (test doubles, end-to-end suites, tooling), which lives where `[workspace].members` already places such crates outside `<crates_root>`.
3. **Place the bounded-context crate.** The crate of layer `<layer>` of `<group>/<context>` is the directory `<crates_root>/<group>/<context>/<layer>` with the package name `<context>-<layer>`, imported as `<context>_<layer>`; its manifest inherits `version`, `edition`, `rust-version`, `license`, `publish` and `repository` from the workspace and sets `[lints] workspace = true`; the root `Cargo.toml` lists it in `[workspace].members` and gives it a `path` entry in `[workspace.dependencies]`. When `architecture.bounded_contexts` lists `<group>/<context>`, confirm the three crates in the live members (the list is informational) and add the file to the existing crate. When the list is empty or lacks the context, search the live members for `<context>-<layer>`; when the context does not exist, create it through [bounded-context-scaffolding](../bounded-context-scaffolding/SKILL.md), never by hand, and resume here; when that skill escalates, this skill's verdict is `ESCALATED`. A crate added, renamed or removed also changes `workspace.dsl`, which [architecture-model-sync](../architecture-model-sync/SKILL.md) keeps in step.
4. **Use the shared crates.** When `architecture.shared_crates` is non-empty, each listed path is a shared-kernel crate laid out like a layer crate (a domain, an application and an infrastructure crate in a template-derived workspace); a context may depend on them, and they never depend on a context. Move a type into the shared crate of its layer only when a second bounded context needs it and the type carries no context meaning (an aggregate, a context's error enum or a context's repository port never moves). When `architecture.shared_crates` is empty, there is no shared kernel: keep every type in its owning context; when two contexts genuinely need the same type, creating a shared context is a change to `architecture.toml`, which is escalated through [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md), never made in passing, and this skill's verdict is then `ESCALATED`.
5. **Keep wiring in the composition root.** When `architecture.composition_root` is set, the crate at `<composition_root>` owns configuration and command-line parsing, building every adapter, registering every command, query and subscriber, assembling routes, middleware and schemas, and exporting the API contracts; its `main.rs` contains only the call into the library, and each concern is its own top-level module. A sourced example of its modules is in DIRECTORY-STRUCTURE.md, "Composition root". Bounded-context crates never construct adapters or read configuration. When `architecture.composition_root` is null, the workspace has no dedicated wiring crate: keep the wiring in the binary crate's entry module and its own modules, keep it out of the layer crates, and record the wiring location in the evidence.
6. **Place modules and files.** Module and file names are snake_case, one module per file. A module `foo` with children is the file `foo.rs` (documentation and `pub mod` declarations, plus what all its children share) and the directory `foo/` holding the children; a file named `mod.rs` is never written. `lib.rs` holds the crate documentation, the `pub mod` declarations of the top-level modules and the `pub use` re-exports of the public types. Top-level module names follow the existing crates of the same layer; a crate adds a new top-level module only when none of the existing names fits.
7. **Apply the directory law.** The law is: "a directory named for a type holds only that type". A directory named for a kind of type (`value_object/`, `command/`, `query/`, `subscriber/`, `port/`) holds only modules of that kind, one type per file, each with its tests in its own `<module>/tests.rs`; the directory `foo/` beside `foo.rs` holds only the children and the tests of `foo`. A file that does not fit goes to the module of its kind, or to a new kind directory named for a well-known pattern when no existing one fits; it never goes to a catch-all `utils`, `helpers`, `common` or `misc` module. The allowed and forbidden contents per directory are tabulated in DIRECTORY-STRUCTURE.md, "The directory law".
8. **Place unit tests.** A module with unit tests ends with `#[cfg(test)] mod tests;` and its tests are in the sibling file `foo/tests.rs` (for `src/value_object/name.rs` that is `src/value_object/name/tests.rs`); a leaf module gains a directory only for its `tests.rs`. Inline `mod tests { ... }` blocks are never written, because coverage measures them as production code. Test functions are snake_case sentences stating the behaviour, without a `test_` prefix. A domain crate defines the fakes it needs in its own `tests.rs` files; a test double that a second crate needs moves into the workspace's test-support crate.
9. **Place integration tests.** A test that needs a database, a message queue, real time, a socket or the built binary lives in `<crate>/tests/integration/`, one module per subject, each declared in `<crate>/tests/integration/main.rs` as `#[cfg(test)] mod <subject>;`, so every crate has a single integration test binary. Helpers shared by the subjects go in a `support.rs` module of the same directory. A `<crate>/tests/<name>.rs` file outside `integration/` is never added.
10. **Name types and files.** Apply the naming table of DIRECTORY-STRUCTURE.md: commands and queries are an imperative verb plus the aggregate (`Create<Entity>` in `create_<entity>.rs`, handler `Create<Entity>Handler` in the same file), events are past tense (`<Entity>Created`), value objects carry the aggregate prefix (`<Entity>Name`), ports are plain nouns (`<Entity>Repository`), adapters carry their technology prefix (`<Tech><Entity>Repository`), and no type is named `Error`. When moving or renaming, move `foo.rs` and `foo/` together and update every `mod` declaration, `use` path, `pub use` re-export and manifest entry in the same change (checklist in DIRECTORY-STRUCTURE.md, "Moving or renaming").
11. **Verify and report.** Run the commands of `## Verification`; each prints nothing or only the expected entries. Then run the static analysis and the boundary check as [verification-workflow](../verification-workflow/SKILL.md) prescribes. Print exactly one verdict line:

    ```text
    code-organization: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
    ```

    `SUCCESS`: every check passes and none of the four keys forced a fallback. `SUCCESS-WITH-REPORT`: every check passes, and crate placement was skipped (step 1) or the wiring location was recorded because `architecture.composition_root` is null (step 5). `ESCALATED`: step 3 or step 4 handed off a decision that escalated; the escalation block printed by that skill is the evidence.

## Constraints

- Never create a file named `mod.rs`, and never write an inline `mod tests { ... }` block.
- Never place a bounded-context crate outside `<crates_root>/<group>/<context>/<layer>`, never name it other than `<context>-<layer>`, and never register a crate by hand that bounded-context-scaffolding creates.
- Never put wiring, configuration reads or adapter construction in a bounded-context crate.
- Never move a context-specific type into a shared crate, and never create a shared context without the escalation of step 4.
- Never add a catch-all `utils`, `helpers`, `common` or `misc` module, and never mix kinds of types in a directory named for one kind.
- Never edit `architecture.toml`, `clippy.toml` or the lint table of `Cargo.toml` so that a layout passes; move the code.
- Write examples as `<group>/<context>` and `<Entity>`; read the real names from the repository.

## Verification

Run from the repository root with `<roots>` set to `<crates_root>`, plus `<composition_root>` when it lies outside `<crates_root>` (the crate directories the change touched when `architecture.crates_root` is null):

```bash
find <roots> -name mod.rs -not -path '*/target/*'
grep -rnE --include='*.rs' '^[[:space:]]*(pub )?mod tests[[:space:]]*\{' <roots>
find <roots> -path '*/tests/*.rs' -not -path '*/tests/integration/*' -not -path '*/target/*'
find <roots> \( -name utils.rs -o -name helpers.rs -o -name common.rs -o -name misc.rs \) -not -path '*/target/*'
grep -nF '<group>/<context>/' Cargo.toml
```

The first four print nothing; the last prints one `[workspace].members` entry and one `[workspace.dependencies]` path entry per layer crate of the context. The static analysis and the boundary check then pass as step 11 describes, and the output ends with the verdict line.
