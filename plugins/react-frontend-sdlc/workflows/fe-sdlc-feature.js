export const meta = {
  name: 'fe-sdlc-feature',
  description:
    'The full frontend SDLC for one planned feature: validate the profile, resolve the issue and specs bundle, implement the stories with parallel react-implementer agents, run the review panel, QA the running app, open or update the PR, then drive it to green with the AI reviewers — bounded at every stage, resumable from the artifacts that already exist',
  whenToUse:
    'When a task already has a GitHub issue and a specs/<slug>/ planning chain (or you accept the plugin generating them) and you want the whole loop run unattended, ending in a PR that CI and the AI reviewers have approved.',
  phases: [
    { title: 'Setup check', detail: 'validate-profile.sh + setup-preflight.sh' },
    { title: 'Resolve plan', detail: 'issue, specs/<slug>/, stories' },
    { title: 'Implement', detail: 'react-implementer per independent story' },
    { title: 'Review', detail: 'fe-sdlc-review-panel' },
    { title: 'QA', detail: 'qa-visual-tester against the running stack' },
    { title: 'Finish PR', detail: 'PR create/update, then fe-sdlc-pr-until-green' },
  ],
}

const OPTS = { task: null, slug: null, issue: null, reviewers: 'coderabbit,cubic', maxImplementRounds: 5, maxQaLoops: 2 }
if (args != null) {
  if (typeof args === 'object') Object.assign(OPTS, args)
  else OPTS.task = String(args).trim()
}
if (OPTS.task && /github\.com\/.+\/issues\/\d+/.test(OPTS.task)) OPTS.issue = OPTS.task

const PLUGIN_ROOT = [
  'Resolve the react-frontend-sdlc plugin root into P and echo it:',
  '  P="$CLAUDE_PLUGIN_ROOT"',
  '  [ -n "$P" ] || P="$(ls -d ~/.claude/plugins/cache/*/react-frontend-sdlc/*/ 2>/dev/null | sort -V | tail -1)"',
  '  [ -n "$P" ] || P="$(find "$HOME" -maxdepth 5 -path "*/plugins/react-frontend-sdlc/.claude-plugin/plugin.json" 2>/dev/null | head -1 | xargs -r dirname | xargs -r dirname)"',
  'If P is empty return status BLOCKED. Commands to follow live under "$P/commands/", agents under "$P/agents/", scripts under "$P/scripts/".',
].join('\n')

const journal = []
const degradeNotes = []
const counters = { implement: 0, qa_loops: 0 }
const note = (l) => { journal.push(l); log(l) }

function escalation(stage, iteration, finding, action) {
  return [
    '=== SDLC ESCALATION ===',
    `stage: ${stage}   iteration: ${iteration}`,
    'exit_condition: PR open, CI green, zero unresolved review threads, every reachable AI reviewer approves the head',
    'status: NOT MET',
    `blocking_finding: ${finding}`,
    `iteration_log: ${journal.join(' | ')}`,
    `recommended_action: ${action}`,
    '=== END ===',
  ].join('\n')
}
const escalate = (stage, iteration, finding, action, extra) => ({ result: 'ESCALATED', stage, escalation: escalation(stage, iteration, finding, action), journal, degrade_notes: degradeNotes, ...extra })

// --- stage 0 ---------------------------------------------------------------
phase('Setup check')
const setup = await agent(
  [PLUGIN_ROOT, '', 'Run "$P/scripts/validate-profile.sh" then "$P/scripts/setup-preflight.sh" in the repository root. Return {ok, message} — ok is false on any non-zero exit, message carries the verbatim failing line. Edit nothing.'].join('\n'),
  { label: 'setup-check', phase: 'Setup check', effort: 'low', schema: { type: 'object', required: ['ok', 'message'], properties: { ok: { type: 'boolean' }, message: { type: 'string' } } } },
)
if (!setup?.ok) return escalate('setup-check', '-', setup?.message || 'no result', 'run /fe-sdlc-setup, then re-run the workflow')
note('setup-check ok')

// --- stages 1–2 --------------------------------------------------------------
phase('Resolve plan')
const PLAN_SCHEMA = {
  type: 'object',
  required: ['issue_url', 'slug', 'readiness_pass', 'stories'],
  properties: {
    issue_url: { type: ['string', 'null'] },
    slug: { type: ['string', 'null'] },
    readiness_pass: { type: 'boolean' },
    stories: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'done', 'independent'],
        properties: { id: { type: 'string' }, title: { type: 'string' }, done: { type: 'boolean' }, independent: { type: 'boolean' }, files_hint: { type: 'array', items: { type: 'string' } } },
      },
    },
    blocked: { type: ['string', 'null'] },
  },
}
const plan = await agent(
  [
    PLUGIN_ROOT,
    '',
    `Task: ${OPTS.task || '(none given — use the current branch and the newest specs bundle)'}${OPTS.issue ? `\nIssue: ${OPTS.issue}` : ''}${OPTS.slug ? `\nSlug: ${OPTS.slug}` : ''}`,
    'Resolve the planning artifacts exactly as "$P/commands/fe-sdlc.md" describes for stages 1 and 2, re-using what exists and never duplicating:',
    '1. Issue: `gh issue list --state open --label react-frontend-sdlc --json number,url,title,body --limit 100`; adopt the issue that covers the task (or the given URL). If none exists, follow "$P/commands/fe-sdlc-issue.md" once to create it.',
    '2. Specs: find specs/<slug>/ whose brief or prd names the issue; if absent or readiness is not PASS, follow "$P/commands/fe-sdlc-plan.md" once (non-interactive) and re-check.',
    '3. Stories: read epics-stories.md (and @fix_plan.md when present) into stories[] with id, title, done (checked), independent (marked so in the file), files_hint (paths the story names).',
    'Return the structured output. If after one attempt the issue or a readiness PASS is still missing, set blocked to what is missing.',
  ].join('\n'),
  { label: 'resolve-plan', phase: 'Resolve plan', schema: PLAN_SCHEMA },
)
if (!plan || plan.blocked || !plan.issue_url || !plan.readiness_pass) {
  return escalate('plan', '1/1', plan?.blocked || 'issue or readiness PASS missing', 'run /fe-sdlc-issue and /fe-sdlc-plan interactively, then re-run')
}
OPTS.slug = plan.slug
OPTS.issue = plan.issue_url
note(`plan resolved: ${plan.issue_url} specs/${plan.slug}/ stories=${plan.stories.length} done=${plan.stories.filter((s) => s.done).length}`)

// --- stage 3 -----------------------------------------------------------------
const STORY_SCHEMA = {
  type: 'object',
  required: ['status', 'exit_signal'],
  properties: {
    status: { type: 'string', enum: ['COMPLETE', 'IN_PROGRESS', 'BLOCKED'] },
    exit_signal: { type: 'boolean' },
    tests_status: { type: 'string' },
    files_modified: { type: 'integer' },
    recommendation: { type: 'string' },
  },
}
function storyPrompt(story, round, feedback) {
  return [
    PLUGIN_ROOT,
    '',
    `Implement story ${story.id} — ${story.title} (implement round ${round}/${OPTS.maxImplementRounds}) from specs/${OPTS.slug}/epics-stories.md for issue ${OPTS.issue}.`,
    story.files_hint?.length ? `Files the story names: ${story.files_hint.join(', ')}.` : '',
    feedback ? `Loop-back feedback to satisfy first:\n${feedback}` : '',
    'Follow your agent contract end to end (TDD, container-only execution through the profile make map, bulletproof-react layering, no suppression, semantic selectors), toggle the story checkbox only when its acceptance criteria are met, run no git, and end with the ---RALPH_STATUS--- block. Mirror that block into the structured output.',
  ].filter(Boolean).join('\n')
}

async function implement(stories, feedback) {
  let pending = stories.filter((s) => !s.done)
  while (pending.length) {
    if (counters.implement >= OPTS.maxImplementRounds) {
      return escalate('implement', `${counters.implement}/${OPTS.maxImplementRounds}`, `stories still open: ${pending.map((s) => s.id).join(', ')}`, 'inspect the open stories and their RALPH_STATUS recommendations, then re-run')
    }
    counters.implement += 1
    phase('Implement')
    const independent = pending.filter((s) => s.independent)
    const batch = independent.length ? independent : [pending[0]]
    const results = await parallel(
      batch.map((s) => () =>
        agent(storyPrompt(s, counters.implement, feedback), { label: `story ${s.id}`, phase: 'Implement', agentType: 'react-frontend-sdlc:react-implementer', schema: STORY_SCHEMA }).then((r) => ({ story: s, r })),
      ),
    )
    const blocked = results.filter(Boolean).find(({ r }) => r?.status === 'BLOCKED')
    if (blocked) return escalate('implement', `${counters.implement}/${OPTS.maxImplementRounds}`, `story ${blocked.story.id} BLOCKED — ${blocked.r.recommendation || ''}`, 'resolve the blocker (missing capability, breaker, failing dependency), then re-run')
    for (const { story, r } of results.filter(Boolean)) if (r?.status === 'COMPLETE') story.done = true
    note(`implement round ${counters.implement}: ${results.filter(Boolean).filter(({ r }) => r?.status === 'COMPLETE').length}/${batch.length} stories complete`)
    pending = stories.filter((s) => !s.done)
    feedback = null
  }
  return null
}

let failed = await implement(plan.stories, null)
if (failed) return failed

// --- stages 4–5 (loop-back QA → implement) -----------------------------------
const QA_SCHEMA = {
  type: 'object',
  required: ['verdict'],
  properties: { verdict: { type: 'string', enum: ['PASS', 'FAIL', 'SKIPPED'] }, failures: { type: 'array', items: { type: 'string' } }, degrade_notes: { type: 'array', items: { type: 'string' } } },
}
while (true) {
  phase('Review')
  let review
  try {
    review = await workflow('react-frontend-sdlc:fe-sdlc-review-panel', { slug: OPTS.slug })
  } catch (e) {
    return escalate('review', '-', `nested workflow unavailable: ${e?.message || e}`, 'run /react-frontend-sdlc:fe-sdlc-review-panel, then /react-frontend-sdlc:fe-sdlc-pr-until-green by hand')
  }
  if (!review || review.result === 'ESCALATED') return escalate('review', review?.iterations ?? '-', 'review panel escalated', 'read its escalation block above', { review })
  degradeNotes.push(...(review.degrade_notes || []))
  note(`review panel: ${review.result} confirmed_total=${review.confirmed_total ?? 0}`)

  phase('QA')
  const qa = await agent(
    [
      PLUGIN_ROOT,
      '',
      `Black-box QA of issue ${OPTS.issue} against its acceptance criteria (specs/${OPTS.slug}/), per your agent contract: boot the production-parity stack through the profile make map, exercise every acceptance criterion (positive, negative, edge) through Playwright, visual regression, Lighthouse budgets and axe-core where the profile capabilities allow, and return PASS or FAIL with exact reproduction steps per failure. Set verdict SKIPPED with degrade_notes only when the profile maps the start target to null.`,
    ].join('\n'),
    { label: 'qa-visual-tester', phase: 'QA', agentType: 'react-frontend-sdlc:qa-visual-tester', schema: QA_SCHEMA },
  )
  if (!qa) return escalate('qa', '-', 'qa-visual-tester returned nothing', 'run /fe-sdlc-qa by hand')
  degradeNotes.push(...(qa.degrade_notes || []))
  if (qa.verdict !== 'FAIL') { note(`qa: ${qa.verdict}`); break }
  counters.qa_loops += 1
  note(`qa: FAIL (${(qa.failures || []).length} failures) → loop-back ${counters.qa_loops}/${OPTS.maxQaLoops}`)
  if (counters.qa_loops > OPTS.maxQaLoops) return escalate('qa', `${counters.qa_loops}/${OPTS.maxQaLoops}`, `QA still failing: ${(qa.failures || []).slice(0, 3).join('; ')}`, 'fix the failures by hand, then re-run')
  for (const s of plan.stories) s.done = false
  failed = await implement(plan.stories, (qa.failures || []).map((f) => `- ${f}`).join('\n'))
  if (failed) return failed
}

// --- stage 6 -----------------------------------------------------------------
phase('Finish PR')
const pr = await agent(
  [
    PLUGIN_ROOT,
    '',
    `Create or update the pull request for issue ${OPTS.issue} exactly as step 1 of "$P/commands/fe-sdlc-finish-pr.md" describes (spec-linked description from specs/${OPTS.slug}/, acceptance-criteria checklist).`,
    'Before that: if the working tree has changes, run the profile format target when mapped, then commit with a Conventional Commits header under 100 characters carrying the issue number, e.g. `feat(<scope>): <summary> (#N)`, hooks enabled, and `git push origin HEAD` (set upstream when missing). Never force-push and never push to the default branch.',
    'A MERGED or CLOSED PR, or a failing `gh pr create`, is blocked. Return {pr, url, blocked}.',
  ].join('\n'),
  { label: 'pr create/update', phase: 'Finish PR', schema: { type: 'object', required: ['pr'], properties: { pr: { type: ['integer', 'null'] }, url: { type: ['string', 'null'] }, blocked: { type: ['string', 'null'] } } } },
)
if (!pr?.pr || pr.blocked) return escalate('finish-pr', '0/5', pr?.blocked || 'no PR', 'fix the PR state or gh access, then run /react-frontend-sdlc:fe-sdlc-pr-until-green')
note(`PR #${pr.pr} ${pr.url || ''}`)

let finish
try {
  finish = await workflow('react-frontend-sdlc:fe-sdlc-pr-until-green', { pr: pr.pr, reviewers: OPTS.reviewers })
} catch (e) {
  return escalate('finish-pr', '-', `nested workflow unavailable: ${e?.message || e}`, `run /react-frontend-sdlc:fe-sdlc-pr-until-green ${pr.pr} by hand`)
}
if (!finish || finish.result === 'ESCALATED') return escalate('finish-pr', '-', 'pr-until-green escalated', 'read its escalation block above', { finish })
degradeNotes.push(...(finish.degrade_notes || []))

return {
  result: degradeNotes.length ? 'SUCCESS-WITH-REPORT' : 'SUCCESS',
  issue: OPTS.issue,
  specs: `specs/${OPTS.slug}/`,
  pr: pr.url || pr.pr,
  counters,
  degrade_notes: degradeNotes,
  journal,
}
