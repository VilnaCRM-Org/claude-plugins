# `/sdlc-setup` Walkthrough

`/sdlc-setup` (stage 0) prepares a PHP backend repository for the SDLC loop.
Run it once per repository from the repo root; re-running is safe. Only the
managed artifacts — the project profile, the governance blocks, and the
permissions allowlist — are ever touched, and an existing profile is kept
unless you pass `--refresh`.

```bash
cd your-php-backend-repo
/sdlc-setup            # first-time setup
/sdlc-setup --refresh  # re-detect and regenerate the profile
```

## The six setup steps

The command runs the following in order, aborting on the first hard failure.

1. **Preflight** — runs `scripts/setup-preflight.sh --report`. Checks the git
   work tree, the `claude` and `gh` CLIs (with version floors), `gh`
   authentication, the bmalph version/doctor state, and the YAML toolchain
   (`yq` or `python3` + PyYAML). On any FAIL the command aborts before
   touching the repository (see [failing preflight](#what-a-failing-preflight-looks-like)).
2. **BMAD bootstrap (fresh repo only)** — if `_bmad/` is absent, runs
   `bmalph init` non-interactively. If `_bmad/` already exists, the step is
   skipped and reported as such. A failed bootstrap aborts the run.
3. **Generate the project profile** — runs `scripts/generate-profile.sh`,
   detecting repository facts into `.claude/php-sdlc.yml`. Without `--refresh`
   an existing profile is preserved and only a detection drift diff is shown;
   with `--refresh` the profile is regenerated from detection.
4. **Validate the profile** — runs `scripts/validate-profile.sh`. On a
   `VIOLATION:` it aborts and tells you to fix the profile by hand or re-run
   `/sdlc-setup --refresh` after correcting the repository signals.
5. **Inject governance blocks** — runs `scripts/inject-governance.sh`, which
   maintains the managed `<!-- php-backend-sdlc:begin/end -->` block in
   `CLAUDE.md` and `AGENTS.md`. Content outside the markers is never modified.
6. **Permissions allowlist** — merges the four allowlist entries into
   `.claude/settings.json` so plugin-spawned `claude -p … acceptEdits`
   sessions run the container-only workflow without interactive prompts.
   Existing settings are preserved (merge, never clobber).

A final **diff summary** step then lists exactly what changed this run
(`git status --short`, the profile detection diff, the `inject-governance.sh`
change log plus `git diff -- CLAUDE.md AGENTS.md`). On an unchanged re-run it
reports a no-op.

## What each step produces

| Step | Artifact produced |
| --- | --- |
| 1 Preflight | A PASS/FAIL table; no files written |
| 2 BMAD bootstrap | `_bmad/` workspace (fresh repos only) |
| 3 Generate profile | `.claude/php-sdlc.yml` (the [project profile](profile-schema.md)) |
| 4 Validate profile | No files; pass/abort verdict only |
| 5 Inject governance | Managed block in `CLAUDE.md` and `AGENTS.md` |
| 6 Permissions | Allowlist entries merged into `.claude/settings.json` |

The allowlist written in step 6 is:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(docker compose exec php:*)",
      "Bash(git:*)",
      "Bash(gh:*)"
    ]
  }
}
```

`bypassPermissions` is a Ralph-driver opt-in only — `/sdlc-setup` never writes
it and nothing in this plugin defaults to it. See
[Permissions](permissions.md) for the full policy.

## `--refresh` semantics

- **Without `--refresh`** (default): an existing `.claude/php-sdlc.yml` is
  never overwritten. Step 3 re-runs detection and shows a drift diff between
  what is on disk and what detection would now produce, so you can decide
  whether to adopt the changes — nothing is changed silently.
- **With `--refresh`**: step 3 regenerates the profile from detection,
  replacing the previous file. Use this after you have changed repository
  signals (added a make target, enabled GraphQL, raised a quality floor) and
  want the profile to reflect them.

`--refresh` affects only the profile. Governance blocks and the permissions
allowlist are reconciled the same way on every run (managed block maintained,
allowlist entries merged).

## What a failing preflight looks like

Preflight prints one row per check. A failure looks like:

```text
PASS: git-repo — inside a git work tree
FAIL: gh-auth — gh is not authenticated
remediation: run: gh auth login
```

When any row is FAIL the command **aborts immediately** — it does not run
bootstrap, profile generation, governance, or permissions. Apply the named
remediation (for example install or upgrade `claude`/`gh`/`bmalph` to the
required floor, run `gh auth login`, or install `yq` / PyYAML) and re-run
`/sdlc-setup`.

A profile that fails validation (step 4) aborts the same way, printing every
`VIOLATION:` line; fix the profile or re-run with `--refresh` after correcting
the underlying repository signals. The generate→validate retry loop is bounded
at five iterations; on guard breach or any abort the command emits the
canonical SDLC escalation block with the blocking finding and recommended
action.

## Exit condition

Setup is complete when `setup-preflight.sh` exits 0, `validate-profile.sh`
exits 0, the governance block exists in `CLAUDE.md` and `AGENTS.md`, and
`.claude/settings.json` carries the four allowlist entries. After that the
repository is ready for `/sdlc` and the per-stage commands.
