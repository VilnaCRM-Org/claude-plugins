# Operational automation inventory

The reporter summarizes supplied claims. It does not verify referenced
operations, deployed revisions, authorship, or approval of a supplied baseline.
Every report sets `externally_verified: false`.

```bash
python3 plugins/devops-sdlc/scripts/automation_coverage.py CURRENT.json --baseline BASELINE.json
```

Omit `--baseline` for an exploratory report. Without a baseline,
`reported_automation_target_met` is always null. A baseline mismatch returns
`status: "BLOCKED"` and exit code 2. Valid reports return exit code 0, including
below-target reports. They never certify the broader 90% automation goal.

Python 3.10+ and POSIX are required. The reporter reads only the explicitly
supplied inventory and optional baseline. Descriptor-anchored traversal and
`O_NOFOLLOW` reject symlink components; the final input opens with
`O_NONBLOCK` and must be a regular file. FIFOs, devices, sockets and directories
cannot block the reader. Each input is limited to 8 MiB and remains unchanged.
No references, commands, network services, cloud credentials or external
processes are accessed.

## Schema version 1

The root contains exactly `schema_version`, `inventory_version`, and `rows`.
The schema version is integer 1; booleans/floats are rejected.
`inventory_version` is a nonempty bounded maintainer label. `rows` contains at
most 10,000 objects and may be empty.

| Required row field | Contract |
| --- | --- |
| `id` | Unique canonical lowercase ASCII row ID. |
| `repository` | Canonical lowercase GitHub `owner/repo`; URLs and case variants are rejected. |
| `target` | Canonical target ID, not an unrestricted path. |
| `environment` | Canonical explicit environment ID. |
| `operation` | Canonical accepted end-to-end operation ID. |
| `applicable` | Boolean deciding membership in the denominator. |
| `outcome` | `complete`, `failed`, `blocked`, `skipped`, `incomplete`, or `excluded`. |
| `evidence` | Exactly `kind` and `reference`. |
| `exclusion_reason` | Nonempty reason for an excluded row; null otherwise. |

IDs use `[a-z0-9][a-z0-9._-]{0,127}`. Case variants, invisible characters,
non-ASCII letters, spaces and slash-containing target IDs are rejected rather
than silently rewritten. Repository owners use up to 39 lowercase ASCII
alphanumeric/hyphen characters with alphanumeric ends; repository names use
up to 100 lowercase ASCII alphanumeric/dot/underscore/hyphen characters and
start alphanumeric. These are local syntax checks, not GitHub existence or
redirect verification.

Both IDs and `(repository, target, environment, operation)` tuples must be
unique. Renaming a row cannot duplicate an operation. Use one accepted
end-to-end operation per row; retries and individual commands do not become
additional completed operations.

`evidence.kind` is `actual`, `fixture`, `mock`, `simulated`,
`documentation`, or `none`. Every kind except `none` requires a nonempty
`reference`; `none` requires null. A `complete` outcome requires evidence.
References are inert strings. An arbitrary reference labeled `actual` remains
an unverified author claim.

| Optional metadata | Contract |
| --- | --- |
| `execution_mode` | `autonomous`, `assisted`, or `manual`; omission means unreported. |
| `workflow_supported` | Boolean claiming a supported workflow performed the work. |
| `source_revision` | Full lowercase 40- or 64-character hexadecimal Git revision. |
| `owner` | Canonical accountable owner or team ID. |
| `engine`, `risk`, `family` | Canonical grouping labels using the ID vocabulary. |
| `command`, `preconditions` | Up to 256 nonempty string tokens; inert descriptive data. |

Optional fields may be omitted, but cannot be null. Missing provenance keeps a
row out of the automation numerator. A supplied revision with invalid syntax is
rejected. Assisted completion involved human intervention; manual completion
was performed by a human. Owners must consistently distinguish intentional
policy approval checkpoints from hands-on assisted execution.

General text must be nonempty, trimmed, at most 4,096 characters, and free of
C0 controls and lone Unicode surrogates. Labels have the stricter ASCII rules.
Unknown keys, duplicate JSON keys, malformed types, non-finite numbers and
inconsistent applicability/outcome combinations fail closed.
Supply only non-secret metadata: reports reproduce supplied rows without
redacting their contents.

## Completion and automation are separate

`supplied_actual_completed_numerator` counts applicable rows with
`outcome: "complete"` and `evidence.kind: "actual"`, including manual and
assisted work. It is an operational completion claim, not an automation count.

`reported_automation_numerator` requires every predicate below:

- The row is applicable.
- Outcome is `complete` and evidence kind is `actual`.
- Execution mode is explicitly `autonomous`.
- `workflow_supported` is explicitly true.
- A valid full `source_revision` and canonical `owner` are supplied.

```text
reported_automation_percentage =
  reported_automation_numerator / applicable_denominator * 100
```

Manual, assisted, unsupported, unreported-mode, fixture, mock, simulated and
documentation completions remain in the denominator. Required skipped work,
missing credentials/approvals and incomplete automation remain applicable.
Lack of automation is not an exclusion reason.

With a matching baseline and nonempty denominator,
`reported_automation_target_met` compares the unrounded integer ratio to 90%.
Without a baseline it is null. With a matching empty baseline it is false and
percentages are null. Even a calculated true target has
`externally_verified: false`.

Summaries include outcomes, evidence kinds, completion modes, workflow support,
unreported metadata and exclusions. Breakdowns apply the same calculation by
engine, risk, environment and family; null groups retain missing labels.
Group totals reconcile. `human_time_reduction_percentage` is always null because
this schema does not measure hands-on minutes.

The report preserves `rows`, `supplied_actual_completed_ids`,
`reported_automated_ids`, `outstanding_automation_ids`, and `excluded_rows`,
sorted by ID. Manual completion can appear in both the supplied-completion
list and the outstanding-automation list.

## Baseline integrity

The baseline uses the same schema. Its canonical denominator contract contains
exactly each row's `id`, `repository`, `target`, `environment`, `operation`,
and `applicable`, sorted by ID. The reporter rejects added/removed/renamed
identities and changed applicability. Exclusion drift cannot silently reduce
the denominator.

Outcomes, evidence, execution modes and optional metadata may advance without
changing `baseline.denominator_sha256`. Reordering rows or JSON keys does not
change it. `inventory_sha256` hashes the complete current inventory, preserving
visibility of outcome and metadata changes.

An excluded row requires `outcome: "excluded"`, `applicable: false`, and a
nonempty reason. The baseline binds applicability, not explanatory wording;
changed reasons remain visible in the full inventory hash and supplied rows.
Applicable rows require a null reason.

These hashes do not establish approval, authorship, immutability, authentic
evidence or comprehensive DevOps coverage. A caller can supply a different
baseline. Retain the reviewed baseline and digest in the existing repository
and approval process. A legitimate scope change requires a newly reviewed
baseline; passing the current file as its own baseline does not prove review.

## Example interpretation

For an applicable row with actual completed evidence, autonomous mode,
workflow support, a full revision and an owner, the reported automation
numerator is 1. With a one-row denominator its percentage is 100.
Without a baseline the target remains null; with a matching baseline the
calculated target is true. External verification remains false in both cases.

Changing the mode to `manual` preserves supplied actual completion and reduces
automation to zero. Changing evidence to `fixture` makes both numerators zero.
Neither fixture tests nor model self-assessments establish actual operations.

## Focused validation

Tests cover canonical identities, baseline drift, autonomous versus manual
counting, raw claim preservation, FIFO/symlink rejection, inert references and
the real CLI entry point. No reporter branches are excluded from coverage.

```bash
python3 -m unittest discover -s plugins/devops-sdlc/tests -p test_automation_coverage.py -v
uvx ruff@0.15.6 check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx ruff@0.15.6 format --check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx ty@0.0.21 check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx bandit@1.8.6 -q plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx xenon@0.9.3 --max-absolute B --max-modules B --max-average A plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
COVERAGE_FILE=/tmp/devops-inventory-coverage uvx coverage@7.6.7 run --rcfile=/dev/null --branch --source=automation_coverage -m unittest discover -s plugins/devops-sdlc/tests -p test_automation_coverage.py
COVERAGE_FILE=/tmp/devops-inventory-coverage uvx coverage@7.6.7 report --rcfile=/dev/null --fail-under=100 -m
```
