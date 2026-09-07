---
name: shell-command-verification-robustness
description: >-
  Use when writing or reviewing a gate that greps source, docs, or workflows for command invocations
  — a Bats make-target coverage contract, a doc-references linter, a reachability check over
  `make <target>` or a package-manager script — and the matcher must not silently miss a wrapped
  invocation or fire on prose such as "make sure the build passes".
---

# Shell command matchers for verification contracts

## Profile keys consumed

- `framework.package_manager`

## Overview

A gate that finds invocations by pattern is only as strong as its matcher. Decide, before writing
the regex, which direction a miss breaks — then bias the matcher toward the loud failure and pin
both positive and negative fixtures so a later edit cannot quietly change the answer.

## When to use

- Building a manifest contract that every Makefile target must appear in some test or workflow.
- Building a documentation gate that every `make <target>` a document promises really exists.
- Reviewing a matcher that greps for a command name across shell, YAML, or Markdown.
- Not for: parsing a well-formed structured file — read the YAML or JSON rather than grep it.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — a `tests/bats/make-target-coverage.tsv` manifest plus a Bats manifest contract,
  and a TypeScript `doc-references` linter behind the repository's documentation-references gate.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — the same
  `tests/bats/make-target-coverage.tsv` manifest plus a Bats manifest contract and a
  `makefile_targets.bats` suite.
- **Component-library shape** (Storybook-first, no bootable app, published package): yes — a
  `target_coverage_contract.bats` suite holds the same manifest shape, and
  `doc_make_target_coverage.bats` is the documentation-direction matcher.

Both directions apply equally to a script invocation run through `framework.package_manager`; the
command token simply changes.

## Pick the failure direction first

| Contract direction        | A miss means                         | Bias the matcher toward |
| ------------------------- | ------------------------------------ | ----------------------- |
| Every target is exercised | Silent coverage drift, gate is green | Over-matching           |
| Every documented command  | A false red on ordinary prose        | Command position only   |

A false positive fails loudly and gets fixed on the spot; a false negative leaves a green gate that
verifies nothing. That asymmetry, not tidiness, decides the regex.

## Invocation shapes a naive matcher misses

Split each line on shell separators (`;`, `&`, `|`, `(`, and quote boundaries), then strip the
following from the head of each segment before testing the first word:

- Leading variable assignments — `FOO=bar make target`
- Wrappers — `sudo`, `env`, `time`, `nice`, `command`, `exec`, `xargs`
- Shell keywords — `then`, `do`, `else`
- Option flags where the tool's flag grammar is known — `make -C dir lint`

A segment taken from inside quotes starts fresh, so `sh -c 'make target'` counts on its inner
segment while `echo "make target"` does not count on its outer one. Enforce that by construction —
extract the quoted body as its own segment — rather than by a special case in an assertion.

## Two verified shapes

Both restrict to code context and command position, so prose never fires. The shell one (the
component-library shape's Bats doc gate) gathers fenced-block bodies and inline code spans, prefixes
each line with a synthetic semicolon separator, then greps only for a command name at line start or
immediately after `;`, `&`, `|`, or `(`. The TypeScript one (the React SPA shape's doc-references
linter) does the same and also skips leading options and assignments, so the captured token is the
target rather than the flag:

```js
const MAKE_INVOCATION = /(?:^|[\s;&|(])make\s+(?:(?:-\S+|[A-Za-z0-9_]+=\S*)\s+)*([A-Za-z0-9_.-]+)/g;
```

Discard a captured token that starts with `-`, contains `=`, or has no alphanumeric: those are
flags, assignments, and prose placeholders, and reporting them would fail a valid document.

## Fixtures

Pin every shape in a fixture the gate runs against, positives and negatives together: all listed
wrapper and assignment forms, the quoted-subcommand form, plus at least two negatives — a comment
whose text contains the command name as an English verb, and a quoted string that merely mentions
it. A matcher change that loses a shape must turn the fixture red.

## Common mistakes

- Anchoring on line start only — every wrapped and separated invocation is then invisible.
- Testing only the shapes the repository happens to use today — the fixture is the contract.
- Trusting a green gate as evidence of coverage without a negative control proving it can fail.
- Skipping unknown leading flags for tools whose flag grammar takes a separate value — the value is
  then captured as the command name.
