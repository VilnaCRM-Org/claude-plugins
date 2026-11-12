# Claude Code Guide

## Start Here

Read these files, in this order, before you change anything:

1. [`AGENTS.md`](AGENTS.md): the working rules, the verification list and the close-out.
2. [`.claude/skills/README.md`](.claude/skills/README.md): the skill inventory and how to pick a skill.

## Project Snapshot

- A Rust 1.99.1 workspace with one crate per bounded-context layer.
- REST and GraphQL interfaces served with axum.
- PostgreSQL access through sqlx.
- Contract snapshots under `.github/`.
- Load tests under `tests/Load/`.
- The architecture model in `workspace.dsl`.

## Command Reference

Run `make ci-list` to print the gate targets in order. The ordered list of verification targets is in the [Verification section of `AGENTS.md`](AGENTS.md#verification); it is kept there and not repeated here.

## BMAD-METHOD Integration

Run `make bmalph-setup` once to install the BMAD and bmalph assets locally; they stay out of version control. Work through analysis, planning and solutioning with the BMAD agents, then transition the planning bundle to the Ralph loop and start Ralph.

| Phase | Focus |
| --- | --- |
| 1. Analysis | Understand the problem |
| 2. Planning | Define the solution |
| 3. Solutioning | Design the architecture |
| 4. Implementation | Build it |
