export const meta = {
  name: 'fe-sdlc-pr-until-green',
  description:
    'Finish a pull request with its AI reviewers: request CodeRabbit and cubic with the exact mentions, wait for their reviews, fix CI failures and review threads, push, and repeat until every reachable reviewer approves the head and CI is green',
  whenToUse:
    'After a feature is implemented and pushed to a PR branch. Give it the PR number or URL; it loops request → wait → fix → push with bounded counters and ends SUCCESS, SUCCESS-WITH-REPORT, or ESCALATED.',
  phases: [
    { title: 'Snapshot', detail: 'pr-state.sh — one verdict per read' },
    { title: 'Request reviews', detail: 'request-ai-reviews.sh — cadence-aware mentions' },
    { title: 'Wait', detail: 'poll checks and in-flight reviews' },
    { title: 'Fix', detail: 'ci-fixer, then pr-comment-resolver' },
    { title: 'Publish', detail: 'commit and push the working tree' },
  ],
}

// ---------------------------------------------------------------------------
// Arguments: a PR number, a PR URL, "<n> --reviewers cubic", or an object
// { pr, reviewers, requiredChecks, maxFixRounds, maxWaitRounds, waitSeconds }.
// ---------------------------------------------------------------------------
const OPTS = {
  pr: null,
  reviewers: 'coderabbit,cubic',
  requiredChecks: '',
  maxFixRounds: 5,
  maxWaitRounds: 6,
  maxRequestRounds: 3,
  waitSeconds: 540,
}
function readArgs(raw) {
  if (raw == null) return
  if (typeof raw === 'number') { OPTS.pr = String(raw); return }
  if (typeof raw === 'object') {
    for (const k of Object.keys(OPTS)) if (raw[k] != null) OPTS[k] = raw[k]
    if (OPTS.pr != null) OPTS.pr = String(OPTS.pr).match(/(\d+)\s*$/)?.[1] ?? String(OPTS.pr)
    return
  }
  const tokens = String(raw).trim().split(/\s+/).filter(Boolean)
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i]
    if (t === '--reviewers') OPTS.reviewers = tokens[++i] ?? OPTS.reviewers
    else if (t === '--required-checks') OPTS.requiredChecks = tokens[++i] ?? ''
    else if (t === '--pr') OPTS.pr = tokens[++i] ?? null
    else if (/^(https?:\/\/\S+\/pull\/)?#?\d+$/.test(t)) OPTS.pr = t.match(/(\d+)$/)[1]
  }
}
readArgs(args)

// ---------------------------------------------------------------------------
// Prompt building blocks. Every agent resolves the plugin root itself: the
// workflow script has no filesystem access and the env var is only set when
// Claude Code invoked the plugin.
// ---------------------------------------------------------------------------
const PLUGIN_ROOT = [
  'First resolve the react-frontend-sdlc plugin root into a shell variable P and echo it:',
  '  P="$CLAUDE_PLUGIN_ROOT"',
  '  [ -n "$P" ] || P="$(ls -d ~/.claude/plugins/cache/*/react-frontend-sdlc/*/ 2>/dev/null | sort -V | tail -1)"',
  '  [ -n "$P" ] || P="$(find "$HOME" -maxdepth 8 -path "*/plugins/react-frontend-sdlc/.claude-plugin/plugin.json" 2>/dev/null | head -1 | xargs -r dirname | xargs -r dirname)"',
  'If P is empty, stop and return status BLOCKED with reason "plugin root not found".',
  'Run every plugin script as "$P/scripts/<name>.sh" (they are executable and self-contained).',
].join('\n')

const prFlag = () => (OPTS.pr ? `--pr ${OPTS.pr}` : '')
const reviewersFlag = () => `--reviewers ${OPTS.reviewers}`
const requiredFlag = () => (OPTS.requiredChecks ? `--required-checks "${OPTS.requiredChecks}"` : '')

const STATE_SCHEMA = {
  type: 'object',
  required: ['verdict', 'next', 'pr', 'head', 'ci', 'unresolved', 'reviewers', 'notes'],
  properties: {
    pr: { type: 'integer' },
    url: { type: 'string' },
    head: { type: 'string' },
    verdict: { type: 'string', enum: ['READY', 'FIX', 'REQUEST', 'WAIT', 'BLOCKED'] },
    next: { type: 'string' },
    ci: {
      type: 'object',
      required: ['status', 'failing', 'pending'],
      properties: {
        status: { type: 'string', enum: ['green', 'red', 'pending', 'none'] },
        failing: { type: 'array', items: { type: 'string' } },
        pending: { type: 'array', items: { type: 'string' } },
      },
    },
    unresolved: { type: 'object', required: ['total'], properties: { total: { type: 'integer' } } },
    reviewers: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'status'],
        properties: {
          name: { type: 'string' },
          status: { type: 'string' },
          reason: { type: ['string', 'null'] },
          ack: { type: ['boolean', 'null'] },
        },
      },
    },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

function snapshotPrompt(waitSeconds, waitVerdicts) {
  const wait = waitSeconds > 0
    ? `--wait-seconds ${waitSeconds} --interval-seconds 60 --wait-verdicts ${waitVerdicts}`
    : ''
  return [
    PLUGIN_ROOT,
    '',
    'Read the pull request finishing state with the bundled sensor and return its JSON verbatim as the structured output:',
    '',
    `  "$P/scripts/pr-state.sh" ${prFlag()} ${reviewersFlag()} ${requiredFlag()} ${wait} --json`,
    '',
    wait
      ? `The script polls for up to ${waitSeconds} seconds; run it with a ${Math.min(waitSeconds + 60, 600)}-second tool timeout and do not poll yourself.`
      : 'Run it exactly once.',
    'Do not edit anything, post anything, or interpret the verdict — the workflow decides. If the script exits non-zero, return',
    '{"verdict":"BLOCKED","next":"<the script\'s error line>","pr":0,"head":"","ci":{"status":"none","failing":[],"pending":[]},"unresolved":{"total":0},"reviewers":[],"notes":[]}.',
  ].join('\n')
}

const REQUEST_SCHEMA = {
  type: 'object',
  required: ['requested', 'waiting', 'skipped'],
  properties: {
    requested: { type: 'array', items: { type: 'string' } },
    waiting: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, minutes: { type: 'integer' } } } },
    skipped: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, reason: { type: 'string' } } } },
    error: { type: ['string', 'null'] },
  },
}

function requestPrompt(state) {
  const cmd = String(state.next || '').replace(/^request-ai-reviews\.sh\s*/, '')
  return [
    PLUGIN_ROOT,
    '',
    'Post the review mentions the sensor asked for. Run exactly this command and nothing else that writes to GitHub:',
    '',
    `  "$P/scripts/request-ai-reviews.sh" ${cmd}`,
    '',
    'Parse its lines into the structured output: REQUESTED: <name> → requested[]; WAIT: <name> <m>m → waiting[{name, minutes}];',
    'SKIPPED: <name> — <reason> → skipped[{name, reason}]. On a non-zero exit put the error line in `error` and leave the arrays empty.',
    'Never post a mention by hand and never post twice.',
  ].join('\n')
}

const CI_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { type: 'string', enum: ['ALL-GREEN', 'FIXES-READY', 'SKIPPED-NO-CI', 'BLOCKED'] },
    summary: { type: 'string' },
    blocking_finding: { type: ['string', 'null'] },
  },
}

const RESOLVER_SCHEMA = {
  type: 'object',
  required: ['remaining_unresolved', 'push_required'],
  properties: {
    remaining_unresolved: { type: 'integer' },
    push_required: { type: 'boolean' },
    blocked_threads: { type: 'integer' },
    summary: { type: 'string' },
  },
}

const PUBLISH_SCHEMA = {
  type: 'object',
  required: ['pushed'],
  properties: {
    pushed: { type: 'boolean' },
    head: { type: 'string' },
    message: { type: 'string' },
    reason: { type: ['string', 'null'] },
  },
}

function ciFixPrompt(state, iteration) {
  return [
    `ci_fix iteration ${iteration}/${OPTS.maxFixRounds} on PR #${state.pr} (${state.url || ''}).`,
    `Failing checks reported by the sensor: ${(state.ci?.failing || []).join(', ') || '(re-read with gh pr checks)'}.`,
    'Follow your agent contract: poll `gh pr checks`, read the failure logs, fix the ROOT CAUSE in the working tree,',
    'verify locally through the profile make map, run no git, never suppress a finding or soften a check.',
    'Return the contract status (ALL-GREEN | FIXES-READY | SKIPPED-NO-CI | BLOCKED) with a one-paragraph summary as the structured output.',
  ].join('\n')
}

function resolverPrompt(state, iteration) {
  return [
    `comment_resolution iteration ${iteration}/${OPTS.maxFixRounds} on PR #${state.pr} (${state.url || ''}).`,
    'Comment source: the PR\'s own review threads (get-pr-comments.sh --unresolved-only --json; resolve the plugin root as your contract describes).',
    `Default branch: read it with \`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name\`.`,
    `Unresolved threads at dispatch: ${state.unresolved?.total ?? 'unknown'}.`,
    'For EVERY unresolved thread: fix the code in the working tree (with local verification) or post a reasoned reply via gh, then resolve the thread. Never dismiss silently. Run no git.',
    'Return remaining_unresolved (from a fresh re-fetch), push_required, blocked_threads and a summary as the structured output.',
  ].join('\n')
}

function publishPrompt(state, iteration, changes) {
  return [
    `Publish round ${iteration}: commit and push the working-tree fixes on PR #${state.pr} (${state.url || ''}).`,
    `Changes to publish: ${changes.join(' and ')}.`,
    'Steps, in the repository root:',
    '1. `git status --porcelain` — if it prints nothing, return {"pushed": false, "reason": "clean tree"}.',
    '2. If `.claude/react-sdlc.yml` maps `make.format` to a target, run it (`make <target>`); skip with a note when the key is null or the file is absent.',
    '3. `git add -A` and commit with a Conventional Commits header under 100 characters that cites the task number the branch or PR body carries',
    '   (`Closes #N`, `(#N)`, or a leading `N-` in the branch name; fall back to the PR number):',
    '   `fix(<scope>): <what the fixes address> (#N)`. Keep the commit hook chain enabled — never pass --no-verify. If a hook fails, fix the cause and retry once.',
    '4. `git push origin HEAD` (add `--set-upstream` when the branch has no upstream). Never force-push, never push to the default branch.',
    'Return {"pushed": true, "head": "<new sha>", "message": "<header>"} or {"pushed": false, "reason": "<verbatim error>"}.',
  ].join('\n')
}

// ---------------------------------------------------------------------------
// The loop.
// ---------------------------------------------------------------------------
const counters = { fix: 0, wait: 0, request: 0 }
const journal = []
const degradeNotes = new Set()
let unreachable = new Set()
let state = null

function note(line) { journal.push(line); log(line) }

function escalation(finding, action) {
  return [
    '=== SDLC ESCALATION ===',
    `stage: pr-until-green   iteration: fix ${counters.fix}/${OPTS.maxFixRounds}, wait ${counters.wait}/${OPTS.maxWaitRounds}, request ${counters.request}/${OPTS.maxRequestRounds}`,
    'exit_condition: CI green + 0 unresolved review threads + every reachable AI reviewer approves the head',
    'status: NOT MET',
    `blocking_finding: ${finding}`,
    `iteration_log: ${journal.join(' | ')}`,
    `recommended_action: ${action}`,
    '=== END ===',
  ].join('\n')
}

function report(result, extra) {
  return {
    result,
    pr: state?.pr ?? OPTS.pr,
    url: state?.url ?? null,
    head: state?.head ?? null,
    ci: state?.ci ?? null,
    reviewers: state?.reviewers ?? [],
    counters,
    degrade_notes: [...degradeNotes],
    journal,
    ...extra,
  }
}

function dropUnreachable(names) {
  for (const n of names) unreachable.add(n)
  OPTS.reviewers = OPTS.reviewers.split(',').filter((r) => !unreachable.has(r)).join(',')
  if (!OPTS.reviewers) {
    degradeNotes.add('every AI reviewer is unreachable — reviews fall back to /fe-sdlc-review; no approval was obtained')
    OPTS.reviewers = 'qlty'
  }
}

const SENSOR_FIELDS = {
  head: (s) => typeof s.head === 'string',
  'ci.failing': (s) => Array.isArray(s.ci?.failing),
  'ci.pending': (s) => Array.isArray(s.ci?.pending),
  'unresolved.total': (s) => Number.isInteger(s.unresolved?.total),
  reviewers: (s) => Array.isArray(s.reviewers),
}
const missingSensorFields = (s) => Object.entries(SENSOR_FIELDS).filter(([, ok]) => !ok(s)).map(([name]) => name)

async function snapshot(waitSeconds, waitVerdicts) {
  phase(waitSeconds > 0 ? 'Wait' : 'Snapshot')
  const s = await agent(snapshotPrompt(waitSeconds, waitVerdicts || 'WAIT'), {
    label: waitSeconds > 0 ? `wait ${waitSeconds}s` : 'pr-state',
    phase: waitSeconds > 0 ? 'Wait' : 'Snapshot',
    schema: STATE_SCHEMA,
    effort: 'low',
  })
  if (!s) throw new Error('snapshot agent returned nothing')
  const missing = missingSensorFields(s)
  if (missing.length && s.verdict !== 'BLOCKED') {
    return { verdict: 'BLOCKED', next: `malformed sensor payload — missing ${missing.join(',')}`, pr: s.pr || 0, head: '', ci: { status: 'none', failing: [], pending: [] }, unresolved: { total: 0 }, reviewers: [], notes: [] }
  }
  if (!OPTS.pr && s.pr) OPTS.pr = String(s.pr)
  for (const n of s.notes || []) degradeNotes.add(n)
  return s
}

let requestsForHead = 0
let lastHead = null

state = await snapshot(0)
while (true) {
  if (state.head !== lastHead) {
    lastHead = state.head
    requestsForHead = 0
    counters.wait = 0
  }
  note(`head=${(state.head || '').slice(0, 7)} verdict=${state.verdict} next=${state.next}`)

  if (state.verdict === 'READY') {
    if (!['green', 'none'].includes(state.ci.status) || state.unresolved.total > 0 || state.reviewers.some((r) => !['APPROVED', 'SKIPPED'].includes(r.status))) {
      return report('ESCALATED', { escalation: escalation('sensor reported READY with contradicting facts', 'upgrade the plugin; the sensor and the workflow disagree') })
    }
    const skipped = (state.reviewers || []).filter((r) => r.status === 'SKIPPED')
    const result = degradeNotes.size || skipped.length || unreachable.size ? 'SUCCESS-WITH-REPORT' : 'SUCCESS'
    return report(result, { exit_condition: 'met' })
  }

  if (state.verdict === 'BLOCKED') {
    return report('ESCALATED', { escalation: escalation(state.next, 'resolve the blocking PR state, then re-run the workflow') })
  }

  if (state.verdict === 'FIX') {
    if (counters.fix >= OPTS.maxFixRounds) {
      return report('ESCALATED', {
        escalation: escalation(`fix budget exhausted with: ${state.next}`, 'inspect the remaining failing checks and threads by hand, then re-run'),
      })
    }
    counters.fix += 1
    phase('Fix')
    const changes = []
    if ((state.ci?.failing || []).length) {
      const ci = await agent(ciFixPrompt(state, counters.fix), {
        label: `ci-fixer ${counters.fix}/${OPTS.maxFixRounds}`,
        phase: 'Fix',
        agentType: 'react-frontend-sdlc:ci-fixer',
        schema: CI_SCHEMA,
      })
      if (!ci || ci.status === 'BLOCKED') {
        return report('ESCALATED', {
          escalation: escalation(`ci-fixer BLOCKED — ${ci?.blocking_finding || ci?.summary || 'no result'}`, 'fix the blocking cause (gh auth, missing PR, protected workflow) and re-run'),
        })
      }
      if (ci.status === 'SKIPPED-NO-CI') degradeNotes.add('CI stage skipped: the PR reports no checks')
      if (ci.status === 'FIXES-READY') changes.push('CI fixes')
      note(`ci-fixer → ${ci.status}`)
    }
    if ((state.unresolved?.total || 0) > 0) {
      const cr = await agent(resolverPrompt(state, counters.fix), {
        label: `pr-comment-resolver ${counters.fix}/${OPTS.maxFixRounds}`,
        phase: 'Fix',
        agentType: 'react-frontend-sdlc:pr-comment-resolver',
        schema: RESOLVER_SCHEMA,
      })
      if (!cr) return report('ESCALATED', { escalation: escalation('pr-comment-resolver returned nothing', 'inspect the unresolved threads by hand') })
      if (cr.push_required) changes.push('review-thread fixes')
      note(`resolver → remaining=${cr.remaining_unresolved} push=${cr.push_required} blocked=${cr.blocked_threads ?? 0}`)
    }
    if (changes.length) {
      phase('Publish')
      const pub = await agent(publishPrompt(state, counters.fix, changes), {
        label: `publish ${counters.fix}`,
        phase: 'Publish',
        schema: PUBLISH_SCHEMA,
      })
      if (!pub?.pushed) {
        return report('ESCALATED', { escalation: escalation(`push failed — ${pub?.reason || 'no result'}`, 'commit and push the working tree by hand, then re-run') })
      }
      note(`pushed ${String(pub.head || '').slice(0, 7)} "${pub.message || ''}"`)
    } else {
      note('nothing to publish; re-reading state')
    }
    state = await snapshot(0)
    continue
  }

  if (state.verdict === 'REQUEST') {
    if (requestsForHead >= OPTS.maxRequestRounds) {
      const notApproved = (state.reviewers || []).filter((r) => r.status === 'NOT_APPROVED').map((r) => r.name)
      if (notApproved.length) {
        return report('ESCALATED', {
          escalation: escalation(`${notApproved.join(',')} reviewed head ${String(state.head).slice(0, 7)} and did not approve after ${OPTS.maxRequestRounds} re-review requests`, 'read the reviewer\'s latest review; its findings are outside the resolved threads'),
        })
      }
      const silent = (state.reviewers || []).filter((r) => ['NONE', 'STALE', 'REQUESTED'].includes(r.status)).map((r) => r.name)
      degradeNotes.add(`${silent.join(',')} did not review head ${String(state.head).slice(0, 7)} after ${OPTS.maxRequestRounds} requests — reported as missing, not passed`)
      dropUnreachable(silent)
      note(`request budget spent for this head; continuing without ${silent.join(',')}`)
      state = await snapshot(0)
      continue
    }
    requestsForHead += 1
    counters.request = Math.max(counters.request, requestsForHead)
    phase('Request reviews')
    const req = await agent(requestPrompt(state), { label: `request ${requestsForHead}`, phase: 'Request reviews', schema: REQUEST_SCHEMA, effort: 'low' })
    if (!req || req.error) {
      return report('ESCALATED', { escalation: escalation(`request-ai-reviews.sh failed — ${req?.error || 'no result'}`, 'check gh auth and the bot app installation, then re-run') })
    }
    for (const s of req.skipped || []) degradeNotes.add(`${s.name}: ${s.reason}`)
    if ((req.skipped || []).length) dropUnreachable(req.skipped.map((s) => s.name))
    note(`requested=${(req.requested || []).join(',') || '-'} waiting=${(req.waiting || []).map((w) => `${w.name}:${w.minutes}m`).join(',') || '-'} skipped=${(req.skipped || []).map((s) => s.name).join(',') || '-'}`)
    const waitMin = Math.max(0, ...(req.waiting || []).map((w) => w.minutes || 0))
    if (!(req.requested || []).length && waitMin > 0) {
      counters.wait += 1
      if (counters.wait > OPTS.maxWaitRounds) {
        return report('ESCALATED', { escalation: escalation('wait budget exhausted inside the CodeRabbit request interval', 'wait for the interval to lapse and re-run, or pass --reviewers cubic') })
      }
      state = await snapshot(Math.min(waitMin * 60, OPTS.waitSeconds), 'WAIT,REQUEST')
      continue
    }
    state = await snapshot(Math.min(120, OPTS.waitSeconds))
    continue
  }

  if (state.verdict === 'WAIT') {
    counters.wait += 1
    if (counters.wait > OPTS.maxWaitRounds) {
      const pendingReviews = (state.reviewers || []).filter((r) => r.status === 'REQUESTED').map((r) => r.name)
      const pendingChecks = state.ci?.pending || []
      if (pendingReviews.length && !pendingChecks.length) {
        degradeNotes.add(`${pendingReviews.join(',')} acknowledged but never reviewed head ${String(state.head).slice(0, 7)} within ${OPTS.maxWaitRounds} wait rounds — reported as missing, not passed`)
        dropUnreachable(pendingReviews)
        state = await snapshot(0)
        continue
      }
      return report('ESCALATED', { escalation: escalation(`wait budget exhausted: ${state.next}`, 'check the stuck CI jobs or reviewer apps, then re-run') })
    }
    state = await snapshot(OPTS.waitSeconds)
    continue
  }

  return report('ESCALATED', { escalation: escalation(`unknown verdict ${state.verdict}`, 'upgrade the plugin; the sensor and the workflow disagree') })
}
