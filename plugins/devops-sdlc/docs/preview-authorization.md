# Credentialed Pulumi preview authorization

Local checks and command intentions need no host grant. Credentialed Pulumi
preview requires `--execute --trust-repo --read-only-credentials` and
`--preview-authorization <absolute-protected-grant-path>`. Flags acknowledge
conditions; they cannot restrict IAM or sandbox repository Python.

## Trusted issuer and execution host

A trusted host administrator or CI credential broker must authorize the initiating
actor, verify the exact trusted non-fork source and operation, approve the backend
destination, and establish a genuinely restricted read-only role. The issuer
must verify effective IAM permissions, including relevant session and resource
policies. STS identifies a session; it does not enumerate its permissions.

The broker supplies temporary session credentials only to an isolated preview
worker. Its protected toolchain, dependencies, source, environment and network
policy must prevent unreviewed code or other processes from gaining those
credentials. Existing [host execution policy](execution-policy.md) applies.
The plugin does not provision this broker, discover IAM permissions from boolean
assertions, or turn an editable checkout into a sandbox.

The worker must be a non-root, non-setuid POSIX user. The authorization is a
root-owned regular file outside the checkout, under the fixed issuer namespace
`/etc/devops-sdlc/preview/` or `/run/devops-sdlc/preview/`, with one hard link. Its entire
directory chain must be root-owned and not writable by group or others. Symlinks
and `..` or double-root aliases are rejected during descriptor-relative traversal.
The helper reads at most
16 KiB and rejects duplicate, missing or extra JSON keys.

The checkout and tracked files must also be protected from worker writes. Require
a clean Git checkout with no untracked or ignored inputs; keep dependencies,
caches and outputs in separately controlled host locations. The current origin
must identify the exact authorized GitHub repository. Require an ordinary
protected `.git` metadata tree: linked worktrees, object alternates, config
includes and `config.worktree` are rejected. Git metadata commands use the
protected system Git with a minimal environment and checkout-specific
`safe.directory` configuration; no global trust setting is changed. This gate deliberately
blocks credentialed execution in ordinary editable developer checkouts.

## Grant contents and binding

The exact field inventory is `GRANT_KEYS` in `scripts/devops.py`. Supply every
field with its required JSON type; extra fields are rejected. The issuer records:

| Fields | Required meaning |
| --- | --- |
| `schema_version`, `kind` | Integer `1`, string `credentialed-pulumi-preview`. |
| `issuer`, `actor`, `actor_uid` | Nonempty issuer and initiating actor identities, plus the exact worker's integer UID. |
| `repo_path`, `repository`, `git_sha` | Exact checkout path, profile `owner/name`, and current Git revision. |
| `operation_sha256` | Stable hash emitted by the helper's reviewed intention for this source, profile, target, environment and argv. |
| `backend`, `account_id` | Exact approved destination URI and selected AWS account; another bucket, path or host requires new authorization. |
| `principal_arn`, `principal_id`, `access_key_id` | Exact temporary assumed-role ARN, STS UserId and temporary access-key identifier. Never include a secret key or session token. |
| `issued_at`, `expires_at`, `credentials_expire_at` | Integer Unix seconds. Grant validity is at most 900 seconds; credential expiry is at most 3600 seconds after issue. The requested timeout must fit entirely before both expiries. |
| `source_trusted`, `fork`, `read_only_role_verified` | Issuer-verified `true`, `false`, `true`; worker or repository assertions cannot supply this authority. |
| `execution_isolation` | `protected-toolchain-and-read-only-checkout`, backed by actual host controls. |
| `aws_executable`, `executable`, `path`, `home` | Approved absolute protected tool paths, a list of 1–16 protected PATH directories without `:` separators, and protected HOME. The selected executable must match the planned tool. |

Generate the intention without execution first. `operation_sha256` hashes its
canonical JSON fields before either hash is added, excluding only `created_at`.
The separate `intention_sha256` includes time and the operation hash. The broker
must inspect the actual operation and source; copying a worker-supplied hash
without independent verification does not authorize it.

The worker needs explicit `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and
`AWS_SESSION_TOKEN` from the broker. Profiles, web identity and metadata fallback
cannot replace this bound session. The helper compares the complete STS account,
assumed-role ARN and UserId, rechecks source and then authorization expiry, and only
then starts the approved command with the selected backend and stack.
The process deadline also accounts for startup time. Inherited `TMPDIR` and
credential-profile configuration do not reach the preview environment.

Missing, changed, expired or mismatched authorization blocks preview before
Pulumi starts. Preserve the rejection and sanitized authorization hash; never
rewrite a grant, relax its permissions, substitute a backend, or invoke raw
Pulumi to bypass the guard. The result remains COMPLETED/UNVERIFIED until actual
preview output has independent semantic validation. No local test or grant
validation establishes cloud deployment, rollback or recovery success.
