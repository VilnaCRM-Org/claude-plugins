---
name: complexity-management
description: Use when the complexity gate reports a function over a clippy.toml limit (cognitive complexity, function lines, arguments, nesting) or a function approaches one - refactor to the limits quoted from clippy.toml at runtime, never raise them. Skip the measurement when the profile maps no complexity target, recorded as not run (capability absent). Not for other static-analysis findings (use rust-error-handling or async-runtime-safety) and not for the catalogue of all quality bars (use quality-standards).
---

# Complexity Management

## Profile keys consumed

- `make.complexity` — the gate target that lints production code for the four complexity lints; `null` means the bar cannot be measured.
- `quality.max_complexity_violations` — the ceiling on complexity diagnostics; its only legal value is 0.

## Repository precedence

Read `.claude/skills/complexity-management/SKILL.md` and `AGENTS.md` first; they win. This skill adds only profile resolution, the evidence format, the bounded loop, the escalation block and the verdict line. The repository skill holds the refactoring rules; this skill adds the limit quote, the measurement through `make.complexity`, the five-iteration budget and the verdict line that the review row Q3 records.

## Context

- `clippy.toml` is the single source of the four limits: `cognitive-complexity-threshold`, `too-many-lines-threshold`, `too-many-arguments-threshold` and `excessive-nesting-threshold`. They are not profile keys; the profile's handle on them is `quality.max_complexity_violations`, held at 0. The values the template ships are quoted in [quality-standards](../quality-standards/SKILL.md); this skill reads the live file instead of copying a number.
- `clippy.toml` is a protected file: it changes only through a labelled pull request with the approval label named in `protected-config.toml`, and never as part of a refactor.
- The template's complexity target (`COMPLEXITY_CMD` in `make/gates.mk`) lints production code only (library and binary targets), with the four complexity lints denied and every other warning allowed, so its output holds nothing but complexity diagnostics. The full static-analysis lint relaxes two of the lints for test code (`LINT_ALL_CMD`); production code is never relaxed.

## Task

Bring the number of complexity diagnostics down to `quality.max_complexity_violations` (0) by behaviour-preserving refactors of the functions the gate names, within at most five refactor-and-measure iterations, and report the result as one verdict line that quotes the four limits.

## Success criteria

- The target mapped by `make.complexity` exits 0 and its log holds 0 complexity diagnostics, or the bar is recorded `not run (capability absent)` when that key is `null`.
- The four limits were quoted from the live `clippy.toml` in the evidence, and `clippy.toml` and `make/gates.mk` are unchanged.
- No attribute was added to silence a complexity lint, and no production code moved into test-only code.
- The unit tests of every touched crate pass before and after the refactor.

## Steps

### 1. Quote the limits

Read the four settings from the live file and quote them in the evidence:

```bash
grep -E '^[[:space:]]*(cognitive-complexity|too-many-lines|too-many-arguments|excessive-nesting)-threshold[[:space:]]*=' clippy.toml
```

Record them as `limits (clippy.toml): cognitive <c>, lines <l>, arguments <a>, nesting <n>`. A setting that is missing, or a missing `clippy.toml`, is quoted `absent (clippy default)` with a degrade note; never add or change the setting.

### 2. Measure the violations

Branch on `make.complexity`:

- non-null: run `make` with the target mapped by `make.complexity` through the execution route of [verification-workflow](../verification-workflow/SKILL.md) (in the background, logged under `target/rust-sdlc/logs/`). Count one violation per `^error:[[:space:]]` diagnostic that names one of `clippy::cognitive_complexity`, `clippy::too_many_lines`, `clippy::excessive_nesting` or `clippy::too_many_arguments`, and take its location from the `-->` line that follows it. An exit other than 0 with no parseable diagnostic counts `≥ 1 (exit <n>)`.
- `null`: the bar cannot be measured. Record `not run (capability absent)` (degrade D1, outcome `SUCCESS-WITH-REPORT`), refactor only the functions a reader can see exceed a quoted limit, print the `NOT RUN` verdict line of step 5, and never report the bar as PASS. Never substitute a raw lint command for the missing target.

What a diagnostic looks like in the log:

```text # profile-example
error: the function has a cognitive complexity of (<measured>/<limit>)
  --> crates/<group>/<context>-application/src/<entity>_handler.rs:41:14
   |
   = help: you could split it up into multiple smaller functions
   = help: for further information visit https://rust-lang.github.io/rust-clippy/master/index.html#cognitive_complexity
```

### 3. Choose the refactoring

| Lint | Limit setting | Refactoring |
| --- | --- | --- |
| `clippy::cognitive_complexity` | `cognitive-complexity-threshold` | replace nested `if`/`else if` chains with guard clauses and early returns or with one `match` on a single value; move each branch body into a named function; replace a boolean flag parameter with an enum |
| `clippy::too_many_lines` | `too-many-lines-threshold` | extract one named function per step of the body (parse, validate, load, decide, persist, respond) and keep the original function as the readable sequence of those calls |
| `clippy::excessive_nesting` | `excessive-nesting-threshold` | return early; use `?` instead of a `match` on `Result` or `Option`; use `let … else`; replace nested loops with iterator adaptors (`filter`, `map`, `try_for_each`) |
| `clippy::too_many_arguments` | `too-many-arguments-threshold` | group the arguments that travel together into a struct or a domain value object and pass the struct; keep ports such as `Clock` as separate arguments |

Handlers follow the repository's pattern: an `#[async_trait]` trait method only delegates to an inherent `async fn`, and each step of the logic is its own function (see [async-runtime-safety](../async-runtime-safety/SKILL.md)).

Guard clauses and one named step per rule:

```rust
// Before: nested branches raise both cognitive complexity and nesting depth.
fn apply(entity: &mut Entity, cmd: &UpdateEntity) -> Result<(), EntityError> {
    if let Some(name) = &cmd.name {
        if name.is_empty() {
            return Err(EntityError::EmptyName);
        } else {
            if entity.is_archived() {
                return Err(EntityError::Archived);
            } else {
                entity.rename(name.clone());
            }
        }
    }
    Ok(())
}

// After: one guard per rule, the happy path at the left margin.
fn apply(entity: &mut Entity, cmd: &UpdateEntity) -> Result<(), EntityError> {
    let Some(name) = &cmd.name else {
        return Ok(());
    };
    ensure_renamable(entity, name)?;
    entity.rename(name.clone());
    Ok(())
}

fn ensure_renamable(entity: &Entity, name: &str) -> Result<(), EntityError> {
    if name.is_empty() {
        return Err(EntityError::EmptyName);
    }
    if entity.is_archived() {
        return Err(EntityError::Archived);
    }
    Ok(())
}
```

Arguments that travel together become one value object:

```rust
// Before: related values travel as loose arguments through every call.
fn schedule(
    id: EntityId,
    name: String,
    starts_at: Timestamp,
    ends_at: Timestamp,
    priority: Priority,
    owner: OwnerId,
    clock: &dyn Clock,
) -> Result<Entity, EntityError> {
    let window = Window::new(starts_at, ends_at, priority)?;
    Entity::schedule(id, name, window, owner, clock.now())
}

// After: the window is a domain value object built where its values originate.
fn schedule(
    id: EntityId,
    name: String,
    window: Window,
    owner: OwnerId,
    clock: &dyn Clock,
) -> Result<Entity, EntityError> {
    Entity::schedule(id, name, window, owner, clock.now())
}
```

### 4. Refactor without changing behaviour

1. Run the unit tests of the crate that holds the function before the first edit, as [testing-workflow](../testing-workflow/SKILL.md) describes; a failing test before the refactor is reported first, not refactored around.
2. Apply one refactoring from the table per function, name each extracted function after what it does (`ensure_renamable`, `load_<entity>`), and keep the extracted functions private in the same module.
3. Keep public signatures unless grouping arguments is the fix; when it is, update every caller in the same change and place the new struct in the layer that owns the concept (a domain value object when it carries domain meaning).
4. Add unit tests for every new function in the sibling `tests.rs`, so the coverage floors of [quality-standards](../quality-standards/SKILL.md) still hold.
5. Run the unit tests again; a test whose outcome changed means the refactor changed behaviour, so undo that edit and choose another refactoring.

### 5. Re-measure within the budget

1. After each round of refactors, re-run step 2 and log `complexity iteration <n>/5: <count> violation(s)`. The budget is 5 iterations; the counter never resets within a run.
2. When a round does not lower the count, use a different refactoring from the table in the next round instead of repeating the same one.
3. Count 0 with exit 0: print the `PASS` verdict line and stop.
4. Count above 0 after iteration 5/5: stop, print the `FAIL` verdict line and hand the calling stage what its escalation block needs: `blocking_finding: <file>:<line> clippy::<lint> (<measured>/<limit>)` and `recommended_action: split the function's responsibilities in a dedicated story`. Raising a limit is never the way out.

The verdict line, as the review row Q3 records it:

```text
complexity: PASS measured 0 bound 0 limits (clippy.toml): cognitive <c>, lines <l>, arguments <a>, nesting <n>
complexity: FAIL measured <count> bound 0 limits (clippy.toml): cognitive <c>, lines <l>, arguments <a>, nesting <n>
complexity: NOT RUN (capability absent) limits (clippy.toml): cognitive <c>, lines <l>, arguments <a>, nesting <n>
```

## Constraints

- Never raise, remove or add a limit in `clippy.toml`, and never edit `COMPLEXITY_CMD` or `make/gates.mk`; a limit that seems wrong is reported as a protected-configuration escalation, never changed.
- Never add an `#[expect]` for `clippy::cognitive_complexity`, `clippy::too_many_lines`, `clippy::excessive_nesting` or `clippy::too_many_arguments`, with or without a reason.
- Never add an `#[allow` attribute for any lint, at item, module or crate level.
- Never move production logic into `#[cfg(test)]` code, a test target or a macro to hide it from the production-only lint.
- Never change behaviour, delete a test or weaken an assertion so that a refactor passes.
- Never set `quality.max_complexity_violations` to any value but 0.
- Never run the lint tool directly; measure only through the target mapped by `make.complexity`.

## Verification

1. The protected sources are unchanged and the diff adds no complexity attribute (each command prints nothing):

   ```bash
   git diff HEAD --stat -- clippy.toml make/gates.mk
   git diff HEAD | grep -nE '^\+.*#\[(allow|expect)\(clippy::(cognitive_complexity|too_many_lines|excessive_nesting|too_many_arguments)'
   ```

2. The last run of the target mapped by `make.complexity` exited 0 with 0 diagnostics, and the verdict line quotes the four limits from the live `clippy.toml`.
3. The unit tests of every touched crate pass after the last refactor (see [testing-workflow](../testing-workflow/SKILL.md)).
