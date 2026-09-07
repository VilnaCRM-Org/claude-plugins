---
name: parser-library-preference
description: Use when a CI gate, validation script, or config check reads YAML, JSON, TOML, or XML with `grep`, `sed`, or hand-written regex. Triggers on fail-open gate bugs, quoted or escaped keys, spaced colons, block scalars swallowing sibling keys, and repeated "fix the regex spelling" patches to the same script.
---

# Parser Library Preference

## Profile keys consumed

- `framework.package_manager`

Install and resolve the parser dependency through the package manager named
by `framework.package_manager`; every gate command otherwise runs through the
profile's `make` target map, skipping with a recorded note when a key maps to
`null`.

## Overview

A gate that scans a structured format with regex fails open on the shapes it did not anticipate, and
each patch teaches it one more spelling instead of the grammar. Where a parser is already a
dependency and can be loaded, parse the document and walk the object.

## When to use

- Writing or repairing a gate that asserts on values inside a workflow, compose file, or manifest.
- The same script has taken more than one "handle this quoting too" fix.
- A gate reports success on input a human can see is wrong.
- Reviewing a check whose correctness rests on a regex over multi-line, nested, or quoted text.
- Not for: locating a file or a symbol, where `grep` is the right tool.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate
  CI target): yes — `yaml` is a devDependency and tooling tests parse workflows with it
  (`import { parse } from 'yaml'`).
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — `js-yaml` plus
  `@types/js-yaml` are devDependencies; the `scripts/ci/` and `scripts/contracts/` gates already
  load documents with them.
- **Component-library shape** (Storybook-first, no bootable app, published package): no — no YAML
  parser is installed, and its gates read JSON policy files.

## Core pattern

Replace the scan with a load, then read the object:

```js
import fs from 'node:fs';
import yaml from 'js-yaml';

let doc;
try {
  doc = yaml.load(fs.readFileSync(file, 'utf8')) ?? {};
} catch (error) {
  // Unparseable input is a reported failure, not a stack trace: a crash here
  // would take the gate's other assertions down and hide unrelated regressions.
  fail(`${file} is not valid YAML: ${error.message.split('\n')[0]}`);
  return null;
}

// YAML 1.1 folds a bare `on:` key to boolean true; a YAML 1.2 core parser keeps
// it a string. Read both so the gate is parser-agnostic. (A boolean key reaches
// JS as the string 'true', hence `doc.true`.)
const triggers = doc.on ?? doc.true ?? {};
```

The failure modes this removes are not exotic. An escaped quote inside a double-quoted key ends a
`"[^"]*"` walk early, so the scanner steps over the value and credits a later, unrelated entry. A
spaced colon slips past a colon-space pattern. Indentation-based scope detection lets a block scalar
swallow the sibling keys of its own step. Measured against a real parser as oracle, a pair of
version-pin gates carried six such spelling bugs at once, and a sweep of realistic inputs failed
open on 5,888 of 15,369 parseable cases — roughly a third. Reparsed through the library, the same
sweep fails open on none.

## Quick reference

- Route a parse error to the gate's own failure channel, never to an uncaught throw.
- Read the parsed value defensively (`typeof x === 'string'`, `Array.isArray(x)`) — a valid document
  can still hold a shape the gate did not expect.
- Parser startup costs tens of milliseconds; that is not a reason to keep a regex.

## The one legitimate exception

A gate that must run **before** dependency installation cannot import from the dependency tree —
importing there turns a helpful drift message into a module-not-found crash on a cold checkout. Such
a script stays dependency-free, and then the regex has to be written to the grammar: consume a
double-quoted scalar whole (so `\"` is an inner escape, not a terminator), handle single-quoted keys
where `''` is a doubled quote rather than a close, and treat every unhandled shape as a failure.
Document the constraint in the file so the next reader does not "modernise" it into a crash.

## Common mistakes

- Adding one more alternation to a regex after each bug — the next spelling is already waiting.
- Letting an unparseable file throw — the run dies before the gate's other assertions report.
- Assuming a parsed key is the string it looks like — a bare `on:` may arrive as a boolean.
- Reaching for a parser in a pre-install gate — keep it dependency-free and grammar-aware instead.
