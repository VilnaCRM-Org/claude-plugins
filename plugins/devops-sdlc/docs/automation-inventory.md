# Frozen operational automation inventory

Run the standalone reporter from the repository root:

```bash
python3 plugins/devops-sdlc/scripts/automation_coverage.py INVENTORY.json
```

Python 3.10 or newer is the only runtime dependency. The reporter reads the
explicit UTF-8 JSON input once, writes a deterministic JSON report to stdout and
leaves the input unchanged. Exit code `0` means valid input, including reports
below target; `2` means invalid arguments or invalid/unreadable input. Errors go
to stderr without echoing input contents or filenames. No cloud, engine, model,
network, environment credentials or external commands are accessed.

## Version 1 contract

The root object has exactly three required fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer `1` | Schema version; booleans and `1.0` are rejected. |
| `inventory_version` | string | Maintainer-assigned identifier for a reviewed frozen baseline. |
| `rows` | array of objects | At most 10,000 operational records; may be empty. |

Each row requires the following fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Unique row ID within this snapshot. |
| `repository` | string | Repository identifier, treated as data. |
| `target` | string | Project or stack identifier, treated as data. |
| `environment` | string | Explicit environment identifier. |
| `operation` | string | Accepted end-to-end unit of work, such as `preview` or `deploy`. |
| `applicable` | boolean | Whether this row belongs in the accepted denominator. |
| `outcome` | enum string | `complete`, `failed`, `blocked`, `skipped`, `incomplete`, or `excluded`. |
| `evidence` | object | Exactly `kind` and `reference`, as defined below. |
| `exclusion_reason` | string or null | Nonempty reason for an excluded row; otherwise null. |

Both IDs and `(repository, target, environment, operation)` tuples must be
unique. Different IDs cannot double-count the same operational unit. Use one
accepted end-to-end operation per row, rather than one row per command or retry.
Identifiers are case-sensitive and are not canonicalized against remote systems.

`evidence.kind` is exactly one of `actual`, `fixture`, `mock`, `simulated`,
`documentation`, or `none`. `reference` must be a nonempty string for every kind
except `none`, which requires null. `complete` requires evidence, even for
synthetic/documentation records. Only `complete` plus `actual` can enter the
actual numerator. `actual` means the author claims accepted real work completed
end-to-end by the plugin, not merely a successful proposal, command preparation,
human-only completion, or model self-assessment. The reporter cannot attest that
claim. Record unavailable credentials/approval as applicable `blocked` with
`none` evidence when no run evidence exists. Keep required skipped checks and
unsupported work applicable; lack of automation is not an exclusion reason.

An inapplicable row must use `outcome: "excluded"` with a nonempty
`exclusion_reason`. An applicable row must use another outcome with
`exclusion_reason: null`. Exclusions require human review: the reporter checks
that a reason exists, not whether the reason is justified.

Optional row metadata:

| Field | Type | Meaning |
| --- | --- | --- |
| `engine` | string | Engine label, for example `terraform`, `terraspace`, or `pulumi`. |
| `risk` | string | Reviewed risk tier using the team's taxonomy. |
| `family` | string | Operation family used for grouping. |
| `source_revision` | string | Revision binding for supplied evidence. |
| `owner` | string | Accountable team or role. |
| `preconditions` | array of strings | Up to 256 reviewed prerequisites. |
| `command` | array of strings | Up to 256 command tokens; inert descriptive data. |
| `workflow_supported` | boolean | Author's independent claim that a workflow exists. |

Omit unavailable optional fields; null is not valid for them. Empty `command`
and `preconditions` arrays are valid. All strings must be trimmed, nonempty,
at most 4,096 characters, and contain neither C0 control characters nor lone
Unicode surrogates. Input is limited to 8 MiB. Unknown fields, duplicate JSON
object keys, unsupported outcomes/evidence kinds, non-finite numbers, malformed
types and incomplete objects are rejected. No numeric metadata is accepted.

References, repository/target names and command tokens are always data. A
reference resembling a path, URL or shell command is never opened, fetched or
executed. Supply only non-secret identifiers and sanitized metadata: successful
reports reproduce supplied rows, and the reporter does not redact their contents.

## Counting and interpretation

`summary.applicable_denominator` counts all applicable rows.
`summary.actual_completed_numerator` counts applicable rows whose outcome is
`complete` and evidence kind is `actual`.

```text
actual_completion_percentage = actual_completed_numerator / applicable_denominator * 100
```

An empty denominator produces JSON null and `target_met: false`. Otherwise,
`target_met` compares the exact integer ratio against 90%, without rounding the
displayed percentage first. It is a calculation over supplied claims, not a
verified operational achievement. Synthetic successes, fixtures, documentation,
blocked, failed, skipped and incomplete rows remain in the denominator.

Each summary includes outcome counts, evidence kind counts, completions by
evidence kind, explicit exclusion count and workflow support counts. Evidence
and workflow counters concern applicable rows only. Unreported workflow support
is counted separately; a documentation record does not implicitly assert the
optional `workflow_supported` field. `human_time_reduction_percentage` is always
null because this schema does not measure baseline minutes or interventions.

`breakdowns` applies the same summaries independently by engine, risk,
environment and family. Groups sort by their exact labels; an additional group
with `value: null` retains rows missing optional metadata. Group totals reconcile
to the overall summary, including exclusions. `rows`, `actual_completed_ids`,
`outstanding_ids` and `excluded_rows` sort by ID. Outstanding rows include
synthetic/documented completions. Supplied evidence and exclusion reasons stay
visible in the report.

`inventory_sha256` hashes the validated inventory serialized with sorted object
keys and rows sorted by ID, compact separators and ASCII escaping. Reordering
rows or keys does not change the digest; changing metadata or version does.
Freeze the baseline and review additions/removals outside the reporter. The
digest identifies a snapshot; it does not prove immutability, approval,
authorship, evidence freshness or completeness. The reporter neither maintains
baseline history nor independently verifies source revisions or references.

The emitted limitations explicitly state that supplied evidence is unverified,
human-time reduction is unmeasured, deployment success beyond supplied evidence
is unproven, and the inventory does not represent every kind of DevOps work.
Measure comparable hands-on baselines and interventions separately before
claiming time savings. Code coverage and workflow support are different measures
from operational automation coverage.

## Offline example

This example deliberately uses a fixture success, not a claimed real operation.
From the repository root, create a temporary example and run the real CLI:

```bash
inventory_example=$(mktemp)
cat > "$inventory_example" <<'JSON'
{
  "schema_version": 1,
  "inventory_version": "example-fixture-only-v1",
  "rows": [
    {
      "id": "service-test-preview",
      "repository": "example/service",
      "target": "application",
      "environment": "test",
      "operation": "preview",
      "applicable": true,
      "outcome": "complete",
      "evidence": {"kind": "fixture", "reference": "fixture:preview-001"},
      "exclusion_reason": null,
      "engine": "pulumi",
      "risk": "low",
      "family": "preview",
      "workflow_supported": true
    }
  ]
}
JSON
python3 plugins/devops-sdlc/scripts/automation_coverage.py "$inventory_example"
rm "$inventory_example"
```

Expected summary: denominator `1`, actual numerator `0`, percentage `0.0`,
fixture completions `1`, workflow support `1`, target met `false`. Replacing
`rows` with `[]` yields denominator/numerator `0`, percentage null and target met
false. Neither example needs credentials or evidence files.

## Focused validation

Run from the repository root. The unittest suite covers mixed evidence,
exclusions, missing credentials, threshold boundaries, empty inventories,
deterministic snapshots, strict validation and the CLI entry point. It blocks
file/network/command/environment access during the inert-reference test and
checks the input's bytes and modification time after CLI execution. These are
reporter tests, not evidence of live infrastructure or model execution.

```bash
python3 -m unittest discover -s plugins/devops-sdlc/tests -p test_automation_coverage.py -v
uvx ruff==0.15.6 format --check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx ruff==0.15.6 check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx ty==0.0.21 check plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx bandit==1.8.6 plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
uvx xenon==0.9.3 --max-absolute B --max-modules B --max-average A plugins/devops-sdlc/scripts/automation_coverage.py plugins/devops-sdlc/tests/test_automation_coverage.py
coverage_data=$(mktemp)
COVERAGE_FILE="$coverage_data" uvx coverage==7.6.7 run --rcfile=/dev/null --branch --source=automation_coverage -m unittest discover -s plugins/devops-sdlc/tests -p test_automation_coverage.py
COVERAGE_FILE="$coverage_data" uvx coverage==7.6.7 report --rcfile=/dev/null --fail-under=100 -m
rm "$coverage_data"
```

Quality tools must be installed or cached before offline validation. Ruff and ty
use the repository's `pyproject.toml`. The focused coverage invocation isolates
the reporter from the existing toolkit source selection and entry-point
exclusion: it measures the real `__main__` branch as well. No reporter lines or
branches are suppressed or excluded, and the gate requires 100% coverage.
