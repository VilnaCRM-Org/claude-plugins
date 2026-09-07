---
name: review-thread-resolution-workflow
description: >-
  Use when a pull request carries many open review threads from several reviewers (CodeRabbit,
  cubic, qlty, humans) and they need to be answered and resolved — including deciding when to
  resolve, what to reply on a thread that will not be changed, and why the mapped pull-request
  comment target may return fewer threads than the pull request actually has.
---

# Review thread resolution workflow

## Profile keys consumed

- `make.pr_comments`
- `ci.required_checks`
- `framework.package_manager`

Thread enumeration goes through the target mapped by `make.pr_comments`; skip that step with a
recorded note when the key maps to `null` and enumerate with the GitHub CLI instead. Generic
tooling (`gh`, `git`) may be invoked directly.

## Overview

A resolved thread is a claim: the concern is addressed and the fix is verified. That claim only
holds if the thread was read, given an explicit outcome, and resolved after CI went terminal and
green on the pushed head. Resolving on read turns the resolved state into noise.

## When to use

- A pull request has more than a handful of open threads, especially across several review bots.
- One reviewer's threads were handled and the others were never enumerated.
- Threads were resolved and then reopened because CI failed on the pushed fix.
- A reviewer finding will deliberately not be actioned and needs a defensible answer.
- Not for: a single trivial thread on a file you just fixed — answer and resolve it in place.

## Applicability by repository shape

- **React SPA shape** (feature modules under the source root, a bootable app, an aggregate CI
  target): yes — a `make.pr_comments` target wrapping a review-thread script, accepting an optional
  pull-request number and a text/json/markdown format; see the pagination gotcha below.
- **Next.js app shape** (routed pages, no aggregate duplication gate): yes — same mapped target,
  same formats, its own copy of the script; its GraphQL query already pages review threads
  correctly.
- **Component-library shape** (Storybook-first, no bootable app, published package): partial — no
  mapped `make.pr_comments` target; enumerate threads with the GitHub CLI instead.

```bash # profile-example
# With a profile whose make.pr_comments maps to the `pr-comments` target:
make pr-comments PR=123 FORMAT=json
```

## Procedure

1. **Enumerate every thread first, from every reviewer.** Never work from one bot's comment list.
   The common failure is handling four threads from one reviewer while a dozen more sit open under
   two others.
2. **Give each thread exactly one recorded outcome** before touching the keyboard on the next: fixed
   in code, replied with reasoning and deliberately unchanged, or deferred to a filed ticket. A
   thread with no recorded outcome is not ready to resolve.
3. **Fix causes, not symptoms.** A reviewer finding is satisfied by changing the code or by a
   reasoned reply — never by relaxing the gate that would have caught it and never by an inline lint
   or type-check suppression directive.
4. **Push everything, then reply on the threads.** Replies land before resolution so the reasoning
   is visible on threads that will not change.
5. **Wait for CI to go terminal and green on the pushed head** — the full set named by
   `ci.required_checks`. Not "mostly green", not "the relevant jobs" — a review fix routinely trips
   an unrelated gate.
6. **Resolve the whole set in one pass.** Simultaneous resolution across reviewers means every
   resolved thread carries the same verified CI run behind it.

## Gotchas

- **Thread listing can silently under-report.** GitHub's GraphQL connection caps `first` at 100.
  The React SPA shape's review-thread script requests `reviewThreads(first: 250)`, which the API
  rejects; the fix is to page the query at 100 with an `after` cursor, as the Next.js shape's copy
  of the script already does. Do not conclude "no unresolved threads" from a failed or truncated
  listing.
- A reviewer bot that rewrites the pull-request body on push silently drops issue-closing keywords
  added by hand. Keep those keywords in the commit messages, and set the body after the final push.
- Findings that assume a toolchain the repository does not use (npm/yarn commands when the profile's
  `framework.package_manager` is something else) are answered on the thread with the reason, not
  silently ignored.

## When resolving early is fine

- A one-line typo fix on a non-executed file, already pushed.
- A dependency-bump review where the pipeline's own pass is the whole signal.
- A deferred improvement — resolve once the follow-up ticket exists and CI is green, with the ticket
  linked in the reply.

## Common mistakes

- Resolving threads while checks are still queued — wait for the run on the pushed head to reach a
  terminal state first.
- Resolving a thread that was never read because a bot summary implied it was minor — enumerate the
  threads from the listing, not from the summary.
- Answering "will not change" threads by resolving them silently — post the reasoning on the thread
  before resolving it.
- Treating an empty listing as proof of zero open threads — check the query's exit status and its
  page count before believing it.
