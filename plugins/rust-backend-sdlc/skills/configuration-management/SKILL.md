---
name: configuration-management
description: Use when a Rust service gains, renames or removes a setting, an environment variable, a `?=` make variable or a compose variable, or changes its HTTP port, so the value enters only through the clap CLI and config modules of the composition root (`architecture.composition_root`), `.env` and `.env.test` hold local placeholders and never a secret, `docs/environment.md` gets exactly one row per variable (docs-check rule 5) and the drift check mapped by `make.docs_check` stays green. Skip, reported as SKIPPED, when `architecture.composition_root` is null. Not for documenting a change that adds no variable (use documentation-sync) and not for writing a new documentation page (use documentation-creation).
---

# Configuration Management

## Profile keys consumed

- `architecture.composition_root` — the crate whose CLI and configuration modules are the only place configuration is read; null skips the skill
- `service.port` — the HTTP port plugin components use, detected from the first `APP_PORT=` line of the development env file; never written as a literal port
- `make.docs_check` — the drift check that proves rule 5 (the environment-variable reference) and rule 2 (the help of the service binary) after the change; null means its proof is `not run (capability absent)`

## Context

A template-derived service reads its configuration in exactly one place, the composition root named by `architecture.composition_root`. In the template layout these are the two modules `crates/service/src/{cli,config}.rs`:

- **`src/cli.rs` (clap).** Every setting is a field of a clap `Args` struct, typed `Option<String>` and declared with `env = "<NAME>"` and `hide_env_values = true`. Clap therefore never rejects a value, and `--help` names each variable (`[env: <NAME>]`) without printing its value. The field's doc comment becomes the help text: it states the meaning, the range and the default.
- **`src/config.rs`.** `Config::from_args` parses and validates every field, applies the defaults and collects every problem as a `ConfigProblem` that names the variable and gives a reason that never contains the value, so a malformed secret is never echoed. Rules that relate two variables run last.
- **Typed hand-off.** The bootstrap module of the composition root passes typed settings (a settings struct, a `Duration`, a validated URL) to the constructors of the adapters. The domain, application and infrastructure crates never read the process environment.
- **`std::env::var` is banned.** `clippy.toml` lists `std::env::var`, `std::env::var_os`, `std::env::vars` and `std::env::vars_os` under `disallowed-methods` with the reason "read configuration once in the composition root". `clippy.toml` is protected configuration.

The environment files and the documentation rule:

- **`.env` and `.env.test`** are tracked, sync-ignored files of local placeholders: nothing in them is a secret. `.env` holds the development defaults; `.env.test` holds only the values that differ for tests and is read after `.env`. The service loads `.env` at start-up, Docker Compose interpolates it, and the test targets export both through `scripts/with-env.sh` (the prefix `env -u DATABASE_URL scripts/with-env.sh .env .env.test --`). In all three, a value already set in the process environment wins. `scripts/with-env.sh` refuses the value forms the three readers read differently (an unquoted value with whitespace, a quote or a backslash, a `$` that does not start `${NAME}`, an unknown escape, a quote that does not close on its line, a comment right after the `=`); such a value is written in quotes.
- **docs-check rule 5.** `docs/environment.md` must list exactly the union of the variables in the help of the service's `serve`, `migrate` and `healthcheck` commands, the variables the compose files interpolate (and those their top-level `secrets:` read with `environment:`), the names assigned or referenced in `.env` and `.env.test`, the variables the `Makefile` and `make/*.mk` declare with `?=`, and the keys of `[env]` in `.cargo/config.toml`. A row is a table line whose first cell is the backticked name, in a table whose header starts with `| Name |`. A variable without a row fails ("has no row"), and so does a row that nothing reads ("has a row but nothing reads it"). The authoritative wording is the header of `scripts/check-docs.sh`.
- **The port.** The service listens on `APP_PORT`; plugin components read the same value as `service.port`, which the profile generator takes from the first `APP_PORT=` line of `.env` and re-detects on every /rs-sdlc-setup refresh.
- **Secrets.** Secrets are never committed: a real credential never enters a tracked file. The production image contains no env file: every required variable is supplied at run time by the deployment, and a credential comes from its secret store. Creating a repository secret, a deployment secret or a variable is a human action.

## Task

Add, rename or remove one setting end to end: the clap field, its validation and default, the typed hand-off to its consumer, the placeholders in `.env`/`.env.test`, its row in `docs/environment.md`, and the unit tests of the configuration module; then prove the result with the target mapped by `make.docs_check`.

## Success criteria

- The change adds no call to `std::env::var`, `std::env::var_os`, `std::env::vars` or `std::env::vars_os`, and no code outside the composition root reads the environment.
- The setting is a field of `src/cli.rs` under `architecture.composition_root` with `env = "<NAME>"` and `hide_env_values = true`, and `src/config.rs` validates it with problems that name the variable and never the value.
- `.env` holds a non-secret local placeholder when local development needs a value, and `.env.test` holds the variable only when the test value differs.
- `docs/environment.md` has exactly one row for every added variable (including each new `?=` variable and each new compose interpolation) and no row for a removed one.
- Secrets never committed: no tracked file holds a real credential, and a required variable without a default is handed to a human as a `NEXT:` line for the deployment.
- No literal port appears in code, documentation or tests; documentation cites `APP_PORT` and plugin components read `service.port`.
- The evidence line of the drift check is `passed`, or states `not run (<reason>)`.

## Steps

1. **Resolve the profile.** Read `architecture.composition_root`, `service.port` and `make.docs_check` from `.claude/rust-sdlc.yml`; the calling command has validated the file. Branch on `architecture.composition_root`:
   - **Null:** the repository has no composition root this skill can edit. Print `SKIPPED: architecture.composition_root is null`, then `NEXT: decide where this service reads its configuration before adding a setting`, then the verdict line `configuration-management: SUCCESS-WITH-REPORT`, and stop.
   - **Non-null:** call its value `<root>`. When `<root>/src/cli.rs` or `<root>/src/config.rs` does not exist, the repository has left the template layout: print `SKIPPED: <root>/src/cli.rs or <root>/src/config.rs not found`, the same `NEXT:` line and verdict, and stop. Otherwise continue.
2. **Name the variable.** Upper snake case, prefixed by its adapter or area (`<ADAPTER>_TIMEOUT`, `<ADAPTER>_BASE_URL`), durations in the `humantime` form the existing rows use (`500ms`, `2s`, `1m`). Check that the name is free:

   ```bash
   git grep -n '<NAME>' -- .env .env.test docs/environment.md Makefile make '<root>/src'
   ```

3. **Declare it in `src/cli.rs`.** Add the field to the `Args` struct of every command that needs it, as `Option<String>` with `env` and `hide_env_values = true`, and a doc comment with meaning, range and default. Follow the existing fields of that struct exactly.
4. **Validate it in `src/config.rs`.** Parse it in `Config::from_args` with the module's existing helpers (a duration, a bounded integer, a required value, a URL), so a missing or invalid value adds a problem that names the variable and never quotes the value. Apply the default there, not in clap. A rule that relates the new variable to another one goes with the existing cross-field rules.
5. **Hand it over typed.** Pass the parsed value from the bootstrap module of `<root>` into the constructor or settings struct of its consumer. A library crate that needs it takes it as a parameter; it never reads the environment.
6. **Write the placeholders.** Add `<NAME>=<placeholder>` to `.env` when local development needs a value other than the default, and to `.env.test` only when the test value differs. Build composed values from existing names with `${NAME}`, quote values with whitespace or special characters, and keep the LOCAL-ONLY header comment of each file. A credential gets an obvious local placeholder for the compose stack, never a real token, key, password or a URL that embeds one. When the variable is required and has no default, print `NEXT: set <NAME> in the deployment environment (from its secret store when it is a credential)`.
7. **Declare make and compose variables in service-owned files.** A make variable of the service is declared with `?=` in `make/service.mk`, never in the template `Makefile`. A compose file is synchronised from the template: a variable added to one means adding that file's path to `.templatesyncignore` in the same change, as the template's extension-seam rule asks. Each such variable needs its own row (step 8).
8. **Write the `docs/environment.md` row.** Put it in the table whose header starts with `| Name |` and whose subject fits (service settings, compose and local stack, test seeds, make variables), keeping that table's columns. The first cell is the backticked name. A rename renames the row; a removal deletes the row and, through [documentation-sync](../documentation-sync/SKILL.md), every page that cites the variable. Check each variable:

   ```bash
   grep -c '^| `<NAME>` |' docs/environment.md
   ```

   The count is 1 for every added or renamed variable and 0 for every removed one.
9. **Keep the port indirect.** Branch on whether the change touches `APP_PORT`:
   - **It does not:** documentation names the port only as `APP_PORT`, plugin components read `service.port`, and integration tests bind port 0 (any free port); no literal port is written anywhere.
   - **It does:** a port change is its own change. Edit only the `APP_PORT` line of `.env` (the compose files publish `${APP_PORT:-…}`), never `.claude/rust-sdlc.yml` on the feature branch, and print `NEXT: refresh the profile with /rs-sdlc-setup on the default branch after this change is merged`, because `service.port` keeps the old value until that refresh.
10. **Test it.** Extend the unit tests in the sibling `tests.rs` of the configuration module (`<root>/src/config/tests.rs`): the default applies when the variable is unset, an invalid value yields a problem that names the variable, and the problem's reason does not contain the value. The tests run with the verification stage (see [verification-workflow](../verification-workflow/SKILL.md)).
11. **Prove it.** Branch on `make.docs_check`:
    - **Mapped:** run `make <make.docs_check>` the way verification-workflow runs every target outside its foreground allowlist: backgrounded, with its log under `target/rust-sdlc/logs/`, polled until it exits. The target compiles the service and reads its help, so it never runs in the foreground. Exit 0 is `passed`. A non-zero exit prints lines `(<rule>) <file>:<line>: <message>`; a rule 5 line names the variable to add or remove, a rule 2 line names a `service` citation the new help no longer supports. A log that contains `This target needs a reachable container engine (docker).` is `not run (no Docker)`, a missing toolchain is `not run (no toolchain)`; neither is ever `failed` or retried, and either one ends the skill `ESCALATED` at once (a mapped capability that cannot run, degrade rows D2 and D3) with the probe or the log line as `blocking_finding`.
    - **Null:** record `not run (capability absent)`. The `grep -c` checks of step 8 are the only evidence and the outcome is `SUCCESS-WITH-REPORT`.
12. **Loop, bounded.** After each round of fixes, run the drift check again and state the counter as `iteration <n>/5`. At most 5 rounds (`MAX_ITERATIONS=5`); a round that leaves the same finding must not repeat the same edit. A finding about a variable or file this change did not touch is recorded and handed to the calling stage, not fixed here; when only such findings are left, the loop ends with the evidence line `failed (<n> findings outside this change)` and the verdict `SUCCESS-WITH-REPORT`. A finding that only a protected file could clear (for example a key of `[env]` in `.cargo/config.toml`, or `scripts/with-env.sh` itself) stops the work with `BLOCKED: protected configuration <path> — needs approved-config-change and a session restarted with ALLOW_PROTECTED_CONFIG_EDIT=1`.
13. **Escalate when the loop ends unmet.**

    ```text
    === SDLC ESCALATION ===
    stage: <the calling stage id>
    iteration: <n>/5
    exit_condition: <the calling stage's exit string, verbatim>
    status: NOT MET
    blocking_finding: (5) docs/environment.md: <message> (make <make.docs_check> exit 1)
    iteration_log: <one line per round: "<n>: drift check -> <finding count>">
    recommended_action: add or remove the docs/environment.md row named above, or apply the protected change with approved-config-change and ALLOW_PROTECTED_CONFIG_EDIT=1
    === END ===
    ```

14. **Report.** Print the evidence and the verdict line:

    ```text
    | variable | cli.rs | config.rs | .env | .env.test | docs/environment.md row |
    | --- | --- | --- | --- | --- | --- |
    | <NAME> | added | validated, default <default> | placeholder or none | override or none | 1 |
    <target mapped by make.docs_check>: passed (<log path>) | failed (<n> findings) | not run (<reason>)
    configuration-management: SUCCESS | SUCCESS-WITH-REPORT | ESCALATED
    ```

    `SUCCESS`: the drift check passed. `SUCCESS-WITH-REPORT`: a `SKIPPED:` path, a `NEXT:` line for a human, an unmapped drift check, or only findings outside this change left (step 12). `ESCALATED`: the mapped drift check could not run (step 11), or the block of step 13 or a `BLOCKED:` line was printed.

A sourced example in the shape of the template's modules, for a timeout of one outbound adapter:

```rust # profile-example
// crates/service/src/cli.rs, a field of ServeArgs
/// Timeout of one call to the <adapter> API (default 2s).
#[arg(long = "<adapter>-timeout", env = "<ADAPTER>_TIMEOUT", hide_env_values = true)]
pub <adapter>_timeout: Option<String>,

// crates/service/src/config.rs, in the function that builds the adapter's settings
let timeout = collector.collect(
    "<ADAPTER>_TIMEOUT",
    duration(args.<adapter>_timeout.as_deref(), Duration::from_secs(2)),
);
```

```text # profile-example
docs/environment.md, table "Service settings":
| `<ADAPTER>_TIMEOUT` | duration | `2s` | no | `service serve` (the <adapter> client) | none |
```

## Constraints

- Never call `std::env::var`, `std::env::var_os`, `std::env::vars` or `std::env::vars_os`, and never add an `expect` attribute for `clippy::disallowed_methods` to make such a call compile; configuration enters only through `src/cli.rs` and `src/config.rs` under `architecture.composition_root`.
- Never commit a secret: `.env` and `.env.test` hold local placeholders only, real values come from the deployment at run time, and creating a secret or a variable in GitHub or in a deployment is a human `NEXT:` step.
- Never print, log or report the value of a variable; problems and evidence name the variable only.
- Never edit `scripts/with-env.sh`, `clippy.toml`, `.cargo/config.toml` or any other path that `cargo xtask config-guard --list` prints; a needed change escalates with the `BLOCKED:` line of step 12.
- Never write a literal port in code, documentation or tests; the port is `APP_PORT` in `.env` and `service.port` in the profile.
- Never declare a service variable in the template `Makefile`, and never source an env file in a shell (`set -a; . ./.env` overrides the caller's values); the test targets use `scripts/with-env.sh`.
- Never leave a variable without its `docs/environment.md` row, or a row without a reader.

## Verification

```bash
make <make.docs_check>
```

The run exits 0, `git grep -n 'std::env::var' -- '<root>/src'` shows no new call, each `grep -c` of step 8 prints the expected count, and the output ends with the evidence and the verdict line of step 14. A null `make.docs_check` shows as `not run (capability absent)` with the verdict `configuration-management: SUCCESS-WITH-REPORT`.

The triage row the calling stage records for this skill:

```text
| configuration-management | plugin | EXECUTE | <the evidence line of the drift check> |
```
