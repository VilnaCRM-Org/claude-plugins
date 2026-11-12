# Repository settings of the service

This document lists the jobs of the pull-request workflows that the service adds to the workflows of the template. It uses the table format of docs/repository-settings.md, and a template sync never touches it.

## Required status checks

Mark the jobs in the column "Required" as required status checks of the branch protection of `main`, next to the checks of the template's document.

### `invoices.yml` (Invoices)

| Job | Check name | Gate | Required |
| --- | --- | --- | --- |
| `invoice-e2e` | Invoice end-to-end tests | G13 | yes |
