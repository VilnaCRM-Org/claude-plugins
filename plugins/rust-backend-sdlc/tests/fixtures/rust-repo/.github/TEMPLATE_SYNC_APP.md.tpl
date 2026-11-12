# Template sync with a GitHub App

This guide sets up the workflow `.github/workflows/template-sync-app.yml`, the flavour of template sync that authenticates with the GitHub App of the release automation. A repository keeps one flavour only; the other is described in `TEMPLATE_SYNC_PAT.md`, the guide of the same name in this directory.

A repository created from the template receives later changes of the template as a pull request that a bot opens. The workflow compares the template with the repository and opens or updates one pull request titled `chore(template): merge template changes` with the label `template_sync`. A maintainer reviews it like any other pull request. In the template repository itself both sync workflows compare `$GITHUB_REPOSITORY` with their source in the first step, write a notice and do nothing.

## Credentials

The workflow needs the two secrets of the release automation, `ACME_APP_ID` and `ACME_APP_PRIVATE_KEY`, and the GitHub App behind them. Without the secrets the job succeeds with a notice and nothing is synchronised.

The workflow creates a short-lived token of the App for each run with the permissions Contents, Pull requests and Workflows, each read and write.

## Schedule

The workflow runs every Monday at 09:00 UTC (`0 9 * * MON`) and on demand through "Run workflow" (`workflow_dispatch`). An open sync pull request is updated in place, so a week without a merge does not pile up pull requests.

## `.templatesyncignore`

The file `.templatesyncignore` at the root of the repository lists the paths that the sync never touches, one per line, in the `.gitignore` format, without comments. Add a path to keep it out of the sync; remove a path to receive the template's version of it. Everything else is synchronised: the shared crates, the `xtask` crate, the workflows, the `Makefile` and `make/`, the guidance and the skills.

## The label for protected configuration

When the sync changes a protected item (the lint policy, a gate threshold, a protected value in `make/gates.mk`, the load-test budgets, the toolchain files, among others), the check `validate-configuration` fails until a maintainer adds the label `approved-config-change` to the pull request. Read the diff of the protected items before you add the label: it approves exactly what the diff shows.

## Keep only one flavour

Both flavours do the same thing and would open competing pull requests. Keep one:

1. Delete the workflow file of the other flavour, `template-sync-pat.yml` in `.github/workflows`, and its guide, `TEMPLATE_SYNC_PAT.md` in `.github`. Both are named here without their directory on purpose: the documentation check (`make docs-check`) reports a citation of a path that does not exist, and this guide is synchronised from the template, so an edit that removes the citation would come back with the next sync.
2. Delete the secrets that only the removed flavour used.
3. Open the deletion as a normal pull request. The sync would restore a deleted file, so add the deleted paths to `.templatesyncignore`.
4. Search your own documents (`README.md`, for example) for citations of the deleted files and name them without their directory, as this guide does.

## Apply an ignored change by hand

A change that the template makes to an ignored file does not arrive. Add the template as a remote once, fetch it and read the difference for the ignored paths:

```sh
git fetch template main
git diff HEAD template/main -- Cargo.toml tests/Load/config.json.dist
```

Copy the template's change into your file, keep your own additions, open a normal pull request and run `make ci` before merging.
