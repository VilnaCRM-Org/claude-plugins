# Permissions

[Home](Home.md) › Operate › Permissions

How plugin-spawned `claude` sessions get the access they need to run
unattended — and where the hard line sits. The plugin's premise is that
the SDLC loop runs non-interactively: a `claude -p` session cannot stop
to ask a human for permission, so the access it needs has to be granted
up front, by the narrowest allowlist that works. This page is the
operator-facing summary; the authoritative source is
[docs/permissions.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/permissions.md).

## Default: `--permission-mode acceptEdits`

Every `claude -p` invocation the plugin makes — the AI review loop and
the FR/NFR gate among them — runs with `--permission-mode acceptEdits`.
That mode splits the two kinds of access cleanly:

| Action | Behavior under `acceptEdits` |
| --- | --- |
| File edits | Accepted automatically, no prompt. |
| Bash commands | Still gated — must be covered by the allowlist below, or they are denied. |

`acceptEdits` is the plugin-wide default and the **only** mode its
scripts use. It is deliberately not `bypassPermissions`: edits flow
freely so the loop can make progress, but shell access stays on the
allowlist so the blast radius of an autonomous session is bounded to a
known set of command prefixes.

## The `settings.json` allowlist

[`/sdlc-setup`](Commands.md) writes — merging, never clobbering — this
allowlist into the target repository's `.claude/settings.json` so the
container-only workflow runs unprompted:

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

Four entries, each mapped to exactly how the plugin works:

| Allow entry | Why it's needed |
| --- | --- |
| `Bash(make:*)` | All build/test/quality runs go through `make` targets resolved from the [project profile](Project-Profile.md) `make` map. |
| `Bash(docker compose exec php:*)` | The container-only rule — code runs inside the PHP service, never on the host. |
| `Bash(git:*)` | The SDLC stages branch, commit, and push. |
| `Bash(gh:*)` | Issue, PR, review, and check operations against GitHub. |

The merge-don't-clobber behavior means any allow entries you already
maintain in `.claude/settings.json` survive `/sdlc-setup`; the plugin
only adds what it needs. See
[Getting Started](Getting-Started.md) for the full setup flow.

## `bypassPermissions`: Ralph-only opt-in

`bypassPermissions` is **never** a default anywhere in this plugin, and
`/sdlc-setup` never writes it. It exists solely as a documented opt-in
for the Ralph driver (`bmalph run`), where the autonomous loop runs
unattended by design and the operator has accepted that trade-off.

If you enable it for that driver, that is your explicit decision for
that driver alone — nothing in the plugin will enable it for you, and no
SDLC command relies on it. The default loop runs entirely on
`acceptEdits` plus the four-entry allowlist.

## Capability opt-ins

Two behaviors that reach beyond editing files and running the allowlisted
commands are gated behind explicit profile capabilities, both defaulting
to `false`. They are not permission-mode settings; they are profile flags
that the relevant skill checks before acting. When the flag is off (or
absent), the step degrades to skip-with-note rather than failing — see
[Degrade and Resilience](Degrade-and-Resilience.md).

| Capability | Default | What enabling it permits |
| --- | --- | --- |
| `capabilities.dynamic_security_testing` | `false` | Live-service security probing in the [security-audit](Security-Audit.md) skill (black-box HTTP/GraphQL attacks against the running service). Pairs with `make.start`. When `false` or `make.start: null`, dynamic probing skips-with-note; the static, SAST, dependency, secret, and config lanes still run. |
| `capabilities.publish_pr_comments` | `false` | The Publish step's write path — posting review findings as PR comments. See [Publishing PR Comments](Publishing-PR-Comments.md). When `false` or absent, the Publish step and the poster skip-with-note. |

Both flags mirror each other in shape: opt-in, default off, skip-with-note
when disabled. Enabling them is a deliberate choice to let an autonomous
session take an action with external side effects — attacking a running
service or writing to a pull request. Set them in the project profile;
the schema is documented in
[docs/profile-schema.md](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/profile-schema.md).

## When a permission is denied mid-loop

A non-interactive `claude` session that hits a permission denial cannot
prompt anyone, so the denial surfaces instead of silently stalling. Per
the [degrade matrix](https://github.com/VilnaCRM-Org/claude-plugins/blob/main/plugins/php-backend-sdlc/docs/degrade-matrix.md),
the error output is included verbatim in the escalation report and points
back to the permissions doc.

To recover:

1. Add the denied command pattern to `permissions.allow` in
   `.claude/settings.json`, **or** run the affected stage interactively
   once.
2. Resume the loop.

This is the expected failure mode when the allowlist is too narrow for a
repository's `make` map or tooling — widen it to the specific prefix that
was denied, not to a broad wildcard.

## See also

- [Getting Started](Getting-Started.md) — running `/sdlc-setup`, which writes the allowlist.
- [Project Profile](Project-Profile.md) — where the `make` map and capability flags live.
- [Security Audit](Security-Audit.md) — gated by `capabilities.dynamic_security_testing`.
- [Publishing PR Comments](Publishing-PR-Comments.md) — gated by `capabilities.publish_pr_comments`.
- [Degrade and Resilience](Degrade-and-Resilience.md) — how denials and disabled capabilities degrade.
