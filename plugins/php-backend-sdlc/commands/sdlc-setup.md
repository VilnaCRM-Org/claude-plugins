---
description: "Prepare a PHP backend repository for the SDLC loop: preflight, project profile, governance blocks, permissions"
argument-hint: "[--refresh]"
---

# /sdlc-setup — environment and profile setup (FR-2)

Prepare the current repository for the php-backend-sdlc loop. Re-running
is safe: outside the managed artifacts (profile, governance blocks,
permissions allowlist) nothing is touched, and an existing profile is
never overwritten unless the user passed `--refresh` (NFR-3).

## Inputs

- Target repository: the current working directory (must be a git work
  tree — preflight enforces this).
- Optional argument `--refresh`: regenerate `.claude/php-sdlc.yml` from
  detection even when it already exists. Without it, an existing profile
  is kept and only a drift diff is shown.
- No profile is required on entry — this command creates it (the
  "first action is `validate-profile.sh`" rule from the stage contract
  applies to every other command, not to `/sdlc-setup` itself).

## Procedure

1. **Preflight** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/setup-preflight.sh" --report
   ```

   If it exits non-zero, ABORT immediately: print the FAIL rows and
   their named remediations verbatim and stop. Do not attempt later
   steps with a broken toolchain (FR-2 abort-on-FAIL).

2. **BMAD bootstrap (fresh repo only)** — if `_bmad/` does not exist in
   the target repository, run `bmalph init` non-interactively. Surface
   any failure output verbatim and abort — never mask or retry a failed
   bootstrap (A2). If `_bmad/` already exists, skip this step and say so.

3. **Generate the project profile** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/generate-profile.sh"
   ```

   Append `--refresh` if and only if the user passed it. Default mode
   keeps an existing profile and prints the detection diff; report that
   diff to the user instead of silently changing anything (NFR-3).

4. **Validate the profile** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/validate-profile.sh"
   ```

   On exit 1, ABORT and show every `VIOLATION:` line. Tell the user to
   either fix the profile by hand or re-run `/sdlc-setup --refresh`
   after correcting the repository signals the detector reads.

5. **Inject governance blocks** — run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/inject-governance.sh"
   ```

   This maintains the managed `<!-- php-backend-sdlc:begin/end -->`
   block in `CLAUDE.md` and `AGENTS.md`; user content outside the
   markers is never modified.

6. **Permissions allowlist (ADR-6)** — ensure `.claude/settings.json`
   in the target repository carries the allowlist that lets
   plugin-spawned `claude -p … --permission-mode acceptEdits` sessions
   run the container-only workflow without interactive prompts:

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

   Merge, do not clobber: if the file exists, add only the missing
   entries to `permissions.allow` and leave every other setting intact.
   Document in your summary that `bypassPermissions` is a Ralph-driver
   opt-in only — `/sdlc-setup` never writes it and nothing in this
   plugin defaults to it.

7. **Diff summary** — finish by listing exactly what changed this run
   (`git status --short` plus the profile diff from step 3 and the
   governance diff from step 5). On an unchanged re-run, state that the
   run was a no-op.

## Loop & exit condition

Single-pass command with one bounded fix-retry loop around steps 3–4:
when validation fails because of a detection gap the user has since
fixed, regenerate and re-validate. Exit condition (measurable):
`setup-preflight.sh` exits 0 AND `validate-profile.sh` exits 0 AND the
governance block exists in `CLAUDE.md`/`AGENTS.md` AND
`.claude/settings.json` contains the four allowlist entries.

## Iteration guard

`MAX_ITERATIONS=5` for the generate→validate retry loop. Keep an
explicit counter and restate it on every attempt
(`setup iteration <n>/5`). Preflight and bootstrap failures are not
retried at all — they abort on first failure.

## Failure escalation

On guard breach or any abort above, emit the canonical report and stop:

```text
=== SDLC ESCALATION ===
stage: setup             iteration: <n>/5
exit_condition: preflight PASS + profile valid + governance + allowlist
status: NOT MET
blocking_finding: <one line — e.g. first preflight FAIL row or first VIOLATION line>
iteration_log: <one line per attempt>
recommended_action: <the named remediation from the failing script>
=== END ===
```
