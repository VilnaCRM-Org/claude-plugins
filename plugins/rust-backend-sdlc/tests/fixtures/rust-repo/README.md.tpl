[![SWUbanner](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner2-direct.svg)](https://supportukrainenow.org/)

# Rust Template

[![Quality](https://github.com/acme/rust-template/actions/workflows/quality.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/quality.yml)
[![Tests](https://github.com/acme/rust-template/actions/workflows/tests.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/tests.yml)
[![Contracts](https://github.com/acme/rust-template/actions/workflows/contracts.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/contracts.yml)
[![Security](https://github.com/acme/rust-template/actions/workflows/security.yml/badge.svg)](https://github.com/acme/rust-template/actions/workflows/security.yml)
[![codecov](https://codecov.io/gh/acme/rust-template/graph/badge.svg)](https://codecov.io/gh/acme/rust-template)
[![Latest release](https://img.shields.io/github/v/release/acme/rust-template)](https://github.com/acme/rust-template/releases/latest)
[![License](https://img.shields.io/github/license/acme/rust-template)](https://github.com/acme/rust-template/blob/main/LICENSE)

The Acme baseline for backend services written in Rust: a Cargo workspace with one crate per bounded-context layer, a REST and GraphQL API on axum, PostgreSQL through sqlx, contract snapshots, architecture guards, quality gates behind one command surface, and guidance for AI coding assistants. A downstream service inherits the platform concerns instead of rebuilding them.

## Baseline

- Rust 1.99.1, pinned in `rust-toolchain.toml`, in a workspace with domain, application and infrastructure crates per bounded context
- REST and GraphQL endpoints with generated OpenAPI and GraphQL contract snapshots under `.github/`
- PostgreSQL with migrations and compile-time checked queries
- An architecture gate (`make architecture`) that keeps domain crates free of frameworks
- Unit, integration, end-to-end, mutation and load tests
- A Make command surface that runs natively or in containers

## Quick start

Check the host, then set up the repository:

```bash
make doctor
make bootstrap
```

## AI workflow

The repository carries guidance for AI coding assistants in `AGENTS.md`, `CLAUDE.md` and `.claude/skills/`. The single list of verification targets is in the "Verification" section of [`AGENTS.md`](AGENTS.md). Other files link to it and do not repeat it.

## Creating a service and receiving updates

Create a repository from this template and follow [`docs/new-service.md`](docs/new-service.md): set the package identity in the workspace manifest, adjust `bmalph/config.json` and the badges above, and choose one template-sync flavour. The two guides in the `.github` directory, `TEMPLATE_SYNC_APP.md` and `TEMPLATE_SYNC_PAT.md`, explain how updates of the template reach a service; each names the other by its bare file name, so deleting one flavour leaves no broken citation.

## Documentation

- [`docs/new-service.md`](docs/new-service.md): creating a service from the template
- [`docs/extension-seams.md`](docs/extension-seams.md): the places where a service plugs in what the template leaves out
- [`docs/repository-settings.md`](docs/repository-settings.md): the required status checks and repository settings
- [`docs/make-targets.md`](docs/make-targets.md): the gate table
- [`CHANGELOG.md`](CHANGELOG.md): the release history
