# Permissions

How plugin-spawned `claude` sessions get the access they need without
interactive prompts — and where the hard line sits (ADR-6).

## Default: `--permission-mode acceptEdits`

Every `claude -p` invocation the plugin makes (the AI review loop, the
FR/NFR gate) runs with `--permission-mode acceptEdits`: file edits are
accepted automatically, while Bash commands still need to be covered by
the allowlist below. This is the plugin-wide default and the only mode
its scripts use.

## The settings.json allowlist

`/sdlc-setup` writes (merge, never clobber) this allowlist into the
target repository's `.claude/settings.json` so the container-only
workflow runs unprompted:

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

Four entries, matching how the plugin works: everything build/test runs
through `make` targets from the [profile](profile-schema.md) `make` map
or `docker compose exec php` (container-only rule), and the SDLC stages
drive `git` and `gh`.

## `bypassPermissions`: Ralph-only opt-in

`bypassPermissions` is NEVER a default anywhere in this plugin and
`/sdlc-setup` never writes it. It exists solely as a documented opt-in
for the Ralph driver (`bmalph run`), where the autonomous loop runs
unattended by design. If you enable it there, that is your explicit
decision for that driver — nothing in the plugin will enable it for
you.

## Permission denials mid-loop

A non-interactive `claude` session that hits a permission denial cannot
prompt anyone. Per the [degrade matrix](degrade-matrix.md), the error
output is surfaced verbatim in the escalation report and points back to
this document. Fix: add the denied command pattern to
`permissions.allow` (or run the affected stage interactively once) and
resume.
