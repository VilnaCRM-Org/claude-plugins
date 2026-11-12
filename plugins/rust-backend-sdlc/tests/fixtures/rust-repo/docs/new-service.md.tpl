# Creating a service from the template

This guide turns a copy of the template into your own service. The template is built so that very little has to change: the repository name appears in one place of the workspace manifest, and everything else is derived.

## 1. Create the repository

Use the GitHub "Use this template" button, or clone the template and push it to a new repository. Name the checkout directory after the service. Make derives the project name from the directory name and uses it for the Compose project and the image names (`<project>-app:dev`, `<project>-app:prod`), so no other file names the project.

## 2. Set the package identity

Edit `[workspace.package]` in the root `Cargo.toml` and change these values:

| Key | What it feeds |
| --- | --- |
| `description` | the service name; the OpenAPI title is `<description> API` |
| `repository` | the repository URL; the OpenAPI contact URL |
| `version` | the version of your first release: set it to `0.1.0` or to the first version you want |

After the edit, regenerate the contract snapshots (`make generate-openapi-spec`) so the committed OpenAPI snapshot carries the new title, and commit the result.

## 3. Update the service-owned files

These files name the template and belong to the service from the start; the template sync never touches them:

- `bmalph/config.json`: set `name` and `description`.
- The badges in `README.md`: point each badge at your repository, and rewrite the introduction to describe your service.
- The planning bundle under `specs/`: replace it with your own planning documents, or remove it.
- `CHANGELOG.md`: reset it to the cocogitto skeleton and remove the release sections of the template, so that your changelog starts with your first release.

## 4. Keep or remove the example context

The template ships one example bounded context under `crates/billing/invoice/` with its migration and snapshots. Keep it while you learn the layout, then remove the crates, the three paths in `[workspace].members`, the `[workspace.dependencies]` entries, the example migration and the components in `workspace.dsl`. Run `make ci` afterwards: every gate must pass without the example.

## 5. Add a bounded context

```bash
make new-context group=<group> context=<context>
```

The command creates `crates/<group>/<context>/{domain,application,infrastructure}`, registers the three crates in the workspace and prints the next steps. Both names must be lower-case words separated by hyphens; the names `shared`, `service`, `xtask`, `test-support` and `e2e-tests` are reserved.

## 6. Where a service adds its own Make targets

Never edit the template's Makefile for service targets, because the sync would overwrite the edit. Define them in the file make/service.mk, which the `Makefile` loads with `-include`, and document them in docs/make-targets-service.md. Likewise, list the jobs of the pull-request workflows that your service adds in docs/repository-settings-service.md, in the table format of docs/repository-settings.md and with a column that says whether each job is a required check.

## 7. Secrets, variables and labels to create

| Name | Kind | Used by | When absent |
| --- | --- | --- | --- |
| `ACME_APP_ID`, `ACME_APP_PRIVATE_KEY` | secrets | the release workflow and the App flavour of the template sync | the job succeeds with a notice; nothing is released or synchronised |
| `PERSONAL_ACCESS_TOKEN` | secret | the token flavour of the template sync | the job succeeds with a notice |
| `CODECOV_TOKEN` | secret | the tests workflow | the upload is skipped with a notice; the coverage gate is unaffected |
| `CODE_SCANNING_ENABLED` | repository variable | code-scanning publication | unset: published in a public repository, skipped in a private one |
| `approved-config-change`, `approved-breaking-change` | labels | the change-control workflow | the gate fails on a protected or a breaking change |
| `template_sync` | label | the sync workflows | created by the sync action |
| `bug`, `enhancement` | labels | the issue templates | GitHub defaults |

`docs/repository-settings.md` lists the required status checks and the other repository settings.

## 8. Choose one sync flavour

The template ships two workflows that merge template changes into your repository through a pull request labelled `template_sync`:

| Flavour | Credentials | Schedule | Guide |
| --- | --- | --- | --- |
| App | `ACME_APP_ID` and `ACME_APP_PRIVATE_KEY` | Mondays | `TEMPLATE_SYNC_APP.md` in the `.github` directory |
| Token | `PERSONAL_ACCESS_TOKEN` | the first of each month | `TEMPLATE_SYNC_PAT.md` in the `.github` directory |

Keep one and delete the other workflow (`template-sync-app.yml` or `template-sync-pat.yml` in `.github/workflows`) and its guide, and add the deleted paths to `.templatesyncignore`: the sync would otherwise restore them. This document and both guides name the two flavours by bare file name, and the guide that stays is synchronised from the template, so nothing needs editing for the documentation check to pass after the deletion.

## 9. Check the result

```bash
make doctor
make bootstrap
make ci
```

`make ci` runs every gate; the ordered list is in the verification section of [`AGENTS.md`](../AGENTS.md#verification). A service that passes it is as strict as the template.
