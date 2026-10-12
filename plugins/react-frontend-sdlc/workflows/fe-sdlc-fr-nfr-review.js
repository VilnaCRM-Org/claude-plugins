export const meta = {
  name: 'fe-sdlc-fr-nfr-review',
  description:
    'The BMAD FR/NFR review gate as a bounded loop, mandatory for every pull request: resolve the requirement sources (the specs/<slug>/ bundle when the feature was BMAD-planned, else the PR description and its linked issues, plus the baseline NFR catalog), run fr-nfr-reviewer (exactly one real gate run per iteration, which posts the BMAD FR/NFR Review Gate commit status) to build the per-requirement matrix, hand every new finding to react-implementer as a root-cause fix, and repeat until the gate reports zero new findings with verdict PASS — a change with no traceable requirement source, or a gate that could not run, escalates; it is never skipped or passed with a report',
  whenToUse:
    'After implementation and the review panel, and on every PR head before it may be called finished (fe-sdlc-pr-until-green runs it on its GATE verdict). Give it the slug when a BMAD bundle exists (or let it locate the bundle whose stories name the changed files), and optionally --pr <n>, --head <sha> (the PR head the local checkout must match), --base <ref> and --summary "<one line>". Without a spec bundle the PR description and linked issues are the requirement source; without either it escalates.',
  phases: [
    { title: 'Scope', detail: 'profile, diff base, changed files, requirement sources (spec bundle, PR, linked issues)' },
    { title: 'Gate', detail: 'fr-nfr-reviewer: one gate run + requirement matrix' },
    { title: 'Fix', detail: 'react-implementer per disjoint file group' },
  ],
}

const OPTS = { slug: null, base: null, summary: null, pr: null, head: null, maxIterations: 5 }
const FLAGS = { '--base': 'base', '--slug': 'slug', '--summary': 'summary', '--pr': 'pr', '--head': 'head' }
function parseTokens(text) {
  const tokens = text.trim().split(/\s+/).filter(Boolean)
  for (let i = 0; i < tokens.length; i++) {
    const key = FLAGS[tokens[i]]
    if (key) OPTS[key] = tokens[++i] ?? null
    else if (!OPTS.slug && !tokens[i].startsWith('--')) OPTS.slug = tokens[i]
  }
}
if (args != null && typeof args === 'object') Object.assign(OPTS, args)
else if (args != null) parseTokens(String(args))
// --pr accepts the forms fe-sdlc-pr-until-green accepts — N, #N or a
// pull-request URL — and nothing else: trailing digits of a malformed value
// must never become a PR number.
const PR_ARG = /^(?:#?([1-9]\d*)|https?:\/\/\S+\/pull\/([1-9]\d*)\/?)$/
let badPrArg = null
if (OPTS.pr != null) {
  const m = String(OPTS.pr).trim().match(PR_ARG)
  if (m) OPTS.pr = m[1] ?? m[2]
  else { badPrArg = String(OPTS.pr); OPTS.pr = null }
}
const shellQuote = (t) => `'${String(t).replace(/'/g, `'\\''`)}'`

const PLUGIN_ROOT = [
  'Resolve the react-frontend-sdlc plugin root into P and echo it:',
  '  P="$CLAUDE_PLUGIN_ROOT"',
  '  [ -n "$P" ] || P="$(ls -d ~/.claude/plugins/cache/*/react-frontend-sdlc/*/ 2>/dev/null | sort -V | tail -1)"',
  '  [ -n "$P" ] || P="$(find "$HOME" -maxdepth 8 -path "*/plugins/react-frontend-sdlc/.claude-plugin/plugin.json" 2>/dev/null | head -1 | xargs -r dirname | xargs -r dirname)"',
  'If P is empty return status BLOCKED. Plugin skills live under "$P/skills/<name>/SKILL.md", scripts under "$P/scripts/".',
].join('\n')

const SCOPE_SCHEMA = {
  type: 'object',
  required: ['profile_valid', 'base', 'files', 'specs_present', 'summary', 'pr', 'pr_requirements', 'clean', 'head_matches_pr'],
  properties: {
    profile_valid: { type: 'boolean' },
    blocked: { type: ['string', 'null'] },
    base: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    specs_present: { type: 'boolean' },
    slug: { type: ['string', 'null'] },
    spec_files: { type: 'array', items: { type: 'string' } },
    pr: { type: ['integer', 'null'] },
    pr_requirements: { type: 'boolean' },
    clean: { type: 'boolean' },
    head_matches_pr: { type: ['boolean', 'null'] },
    linked_issues: { type: 'array', items: { type: 'integer' } },
    summary: { type: 'string' },
  },
}

const GATE_SCHEMA = {
  type: 'object',
  required: ['status', 'verdict', 'new_findings', 'findings', 'gate_run'],
  properties: {
    status: { type: 'string', enum: ['OK', 'BLOCKED'] },
    verdict: { type: 'string', enum: ['PASS', 'FAIL', 'DEGRADED'] },
    new_findings: { type: ['integer', 'null'] },
    gate_run: { type: 'string' },
    note: { type: ['string', 'null'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['requirement', 'file', 'title', 'evidence', 'fix'],
        properties: {
          requirement: { type: 'string' },
          file: { type: 'string' },
          line: { type: ['integer', 'null'] },
          title: { type: 'string' },
          evidence: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
  },
}

const FIX_SCHEMA = {
  type: 'object',
  required: ['status', 'files_modified'],
  properties: {
    status: { type: 'string', enum: ['COMPLETE', 'IN_PROGRESS', 'BLOCKED'] },
    files_modified: { type: 'integer' },
    tests_status: { type: 'string' },
    recommendation: { type: 'string' },
  },
}

const journal = []
const degradeNotes = []
const ledger = []

function escalationBlock(iteration, finding, action) {
  return [
    '=== SDLC ESCALATION ===',
    `stage: fr-nfr-review      iteration: ${iteration}/${OPTS.maxIterations}`,
    'exit_condition: fr-nfr-reviewer reports new_findings=0 with verdict=PASS in the last gate iteration',
    'status: NOT MET',
    `blocking_finding: ${finding}`,
    `iteration_log: ${journal.join(' | ') || 'none'}`,
    `recommended_action: ${action}`,
    '=== END ===',
  ].join('\n')
}
const escalate = (iteration, finding, action, extra) => ({
  result: 'ESCALATED',
  escalation: escalationBlock(iteration, finding, action),
  iterations: iteration,
  ledger,
  journal,
  degrade_notes: degradeNotes,
  ...extra,
})

if (badPrArg != null) return escalate(0, `malformed --pr value "${badPrArg}"`, 'pass a PR number, #N, or a pull-request URL')

// ---------------------------------------------------------------------------
phase('Scope')
const scope = await agent(
  [
    PLUGIN_ROOT,
    '',
    'Establish the FR/NFR gate scope for this repository. Steps:',
    '1. Run "$P/scripts/validate-profile.sh"; profile_valid=false and blocked="run /fe-sdlc-setup" on exit 1.',
    `2. Diff base: ${OPTS.base ? `use "${OPTS.base}"` : 'the default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`), as origin/<default>'}.`,
    '   files = `git diff --name-only <base>...HEAD` plus uncommitted changes (`git status --porcelain` paths).',
    `3. Spec bundle: ${OPTS.slug ? `specs/${OPTS.slug}/` : 'the newest specs/<slug>/ directory whose prd, epics-stories or brief names the changed files or their feature; none when no directory qualifies'}.`,
    '   specs_present is true only when that directory exists and holds at least one of prd, architecture, epics-stories (list what exists in spec_files); set slug to the directory name or null. Never create or edit a spec.',
    `4. Pull request: ${OPTS.pr ? `PR #${OPTS.pr}` : 'the current branch\'s PR (`gh pr view --json number --jq .number`), or null when the branch has none'}. Read its body (\`gh pr view <n> --json body\`) and its closing issues (each with its own repository): pr_requirements is true only when the PR body is non-blank or at least one linked issue has a non-blank BODY — a title-only issue is no requirement source, exactly as the gate script judges it; list the qualifying issue numbers in linked_issues.`,
    OPTS.head
      ? `5. Head check: \`git rev-parse HEAD\` must equal ${OPTS.head} and \`git status --porcelain\` must print nothing — the gate posts its commit status for the local HEAD, so it must run on exactly that PR head. Otherwise set blocked to "local checkout is not at PR head ${OPTS.head.slice(0, 7)} with a clean tree — check out and pull the PR branch".`
      : '5. Head check: report clean (true when `git status --porcelain` prints nothing) and, when a PR exists, head_matches_pr (true when `git rev-parse HEAD` equals `gh pr view <n> --json headRefOid --jq .headRefOid`; null without a PR). Do not block on either.',
    `6. summary: ${OPTS.summary ? `use "${OPTS.summary}"` : 'one line describing the change set (what the changed files implement), for the gate impact context'}.`,
    'Return the structured output only; edit nothing.',
  ].join('\n'),
  { label: 'scope', phase: 'Scope', schema: SCOPE_SCHEMA },
)
if (!scope || scope.blocked || scope.profile_valid !== true) {
  const action = scope?.profile_valid === true ? 'resolve the blocking cause above, then re-run' : 'run /fe-sdlc-setup, then re-run'
  return escalate(0, scope?.blocked || 'scope agent returned nothing', action)
}
if (!scope.files.length) return { result: 'SUCCESS', note: 'empty change set — nothing to gate', iterations: 0, skipped: false, scope }
const hasSpecs = Boolean(scope.specs_present && scope.slug)
if (OPTS.slug && !hasSpecs) {
  return escalate(0, `the caller named specs/${OPTS.slug}/ but no BMAD spec bundle exists there`, 'run /fe-sdlc-plan for this feature, then re-run')
}
if (!hasSpecs && !(scope.pr && scope.pr_requirements)) {
  // Run the gate script anyway: its fail-closed path posts the failure status,
  // so the head carries a durable red verdict instead of no gate status at all.
  phase('Gate')
  const recorded = await agent(
    [
      PLUGIN_ROOT,
      '',
      `Record the fail-closed FR/NFR gate verdict for the current HEAD: run "$P/scripts/fr-nfr-gate.sh"${scope.pr ? ` --pr ${scope.pr}` : ''} exactly once, in the repository root.`,
      'With no requirement source it posts a failure "BMAD FR/NFR Review Gate" status and exits 1 naming "cannot trace this change to any requirement". Return {status_posted: true} when it did, else {status_posted: false, note: "<its last error line>"}. Edit nothing.',
    ].join('\n'),
    { label: 'record-no-source', phase: 'Gate', effort: 'low', schema: { type: 'object', required: ['status_posted'], properties: { status_posted: { type: 'boolean' }, note: { type: ['string', 'null'] } } } },
  )
  return escalate(
    0,
    `no requirement source for this change set — no specs/<slug>/ bundle, and ${scope.pr ? `PR #${scope.pr} has an empty description and no linked issue` : 'the branch has no PR'}; the FR/NFR gate is mandatory for every PR and cannot pass an untraceable change`,
    'open the PR if there is none (a draft is fine), link the issue it implements (Closes #N) or write its acceptance criteria into the PR description (or run /fe-sdlc-plan), then re-run',
    { requirement_source: 'none', status_posted: recorded?.status_posted === true },
  )
}
// The gate posts its status for the local HEAD, so a run on uncommitted changes
// or on a commit that is not the PR head reviews code the status would not
// describe: such a run is advisory (no status, no comment) and the
// authoritative run happens on the published head (fe-sdlc-pr-until-green).
// Fail safe: a missing field counts as unverified, so the run publishes nothing.
const advisory = scope.clean !== true || (scope.pr != null && scope.head_matches_pr !== true)
if (advisory) degradeNotes.push('advisory gate run: uncommitted changes or HEAD is not the PR head — no BMAD FR/NFR Review Gate status or comment was posted; the authoritative run happens on the published PR head')
const requirementSource = hasSpecs ? `specs/${scope.slug}/` : `PR #${scope.pr} description${(scope.linked_issues || []).length ? ` + issue(s) ${scope.linked_issues.map((n) => `#${n}`).join(', ')}` : ''}`
const runnerArgs = [hasSpecs ? `--spec-path ${shellQuote(`specs/${scope.slug}`)}` : null, scope.pr ? `--pr ${scope.pr}` : null, scope.summary ? `--impact-context ${shellQuote(scope.summary)}` : null, advisory ? '--advisory' : null].filter(Boolean).join(' ')
log(`scope: ${scope.files.length} files against ${scope.base}; requirement source ${requirementSource}${hasSpecs ? ` (${(scope.spec_files || []).join(', ') || 'files unlisted'})` : ''}`)

function gatePrompt(iteration) {
  const prior = ledger.length
    ? ['Prior iteration ledger (resume the counter from it; a finding is NEW only when absent from every prior iteration):', ...ledger.map((l) => `  iteration ${l.iteration}: new_findings=${l.new_findings ?? 'unknown (transport)'} verdict=${l.verdict} findings=[${l.findings.join('; ') || 'none'}]`)]
    : ['No prior ledger — this is the first gate iteration.']
  return [
    PLUGIN_ROOT,
    '',
    `Review iteration ${iteration}/${OPTS.maxIterations}. Requirement source: ${requirementSource}${hasSpecs ? '' : ' (no BMAD spec bundle — derive the FRs from the PR description and linked issues)'}; the baseline NFR catalog applies on top. Diff base: ${scope.base}. Change summary: "${scope.summary}".`,
    'Changed files:',
    ...scope.files.map((f) => `  - ${f}`),
    ...prior,
    '',
    `Per your agent contract: resolve the gate runner from make.fr_nfr_gate in .claude/react-sdlc.yml (the plugin script "$P/scripts/fr-nfr-gate.sh" ${runnerArgs} --iteration ${iteration} when null), run it exactly once — it must really run${advisory ? ' (advisory: it posts no status by design)' : ' and post the "BMAD FR/NFR Review Gate" commit status'}; a manually built matrix does not satisfy the mandatory gate — build the full per-requirement matrix, and mirror the FR_NFR_REVIEWER last line into the structured output: verdict, new_findings (null only when the gate run failed for transport or a malformed contract line), gate_run (the runner used, or SKIPPED (<reason>)).`,
    'Every NEW finding is one findings[] entry with the requirement id, the file it points at, evidence, and a root-cause fix — never a suppression, a threshold change, or a skipped test. Edit nothing.',
  ].join('\n')
}

const keyOf = (f) => `${f.requirement}:${f.title.toLowerCase().replace(/\s+/g, ' ').trim()}`
const dedupe = (list) => list.filter((f, i, all) => all.findIndex((g) => keyOf(g) === keyOf(f)) === i)
const isComplete = (r) => Boolean(r) && r.status === 'COMPLETE'

function gateEscalation(gate, iteration) {
  if (!gate) return escalate(iteration, 'fr-nfr-reviewer returned nothing', 're-run; if it repeats, check the agent definition')
  if (gate.status === 'BLOCKED') return escalate(iteration, `fr-nfr-reviewer BLOCKED — ${gate.note || ''}`, 'fix the blocking cause (plugin root, profile, gate runner), then re-run')
  // A skipped runner is checked first: the reviewer may pair it with DEGRADED,
  // and its remedy (restore the runner) differs from a missing source's.
  if (/^SKIPPED/i.test(gate.gate_run || '')) {
    return escalate(iteration, `gate runner ${gate.gate_run} — no "BMAD FR/NFR Review Gate" commit status was posted, and the gate is mandatory and must be green on every PR`, 'restore the gate runner (claude and gh on PATH, a resolvable repository, gh auth), then re-run; a manually built matrix never satisfies the gate')
  }
  if (gate.verdict === 'DEGRADED') {
    return escalate(iteration, `fr-nfr-reviewer reported the requirement source ${requirementSource} missing or empty although scope found it — ${gate.note || ''}`, hasSpecs ? 'run /fe-sdlc-plan for this feature, then re-run' : 'restore the PR description or linked issue, then re-run')
  }
  return null
}

function recordGate(gate, iteration, findings) {
  ledger.push({ iteration, new_findings: gate.new_findings, verdict: gate.verdict, findings: findings.map((f) => `${f.requirement}: ${f.title}`) })
  journal.push(`iteration ${iteration}: gate=${gate.gate_run} new_findings=${gate.new_findings ?? 'unknown'} verdict=${gate.verdict}`)
}

function logConvergence(iteration, count) {
  const previous = ledger.slice(-3, -1).map((l) => l.new_findings).filter(Number.isInteger)
  if (previous.length === 2 && Math.min(...previous) <= count) {
    log(`iteration ${iteration}: new findings did not decrease across the last three iterations (${previous.join(', ')}, ${count}) — the loop is not converging`)
  }
}

function success(iteration) {
  return {
    result: degradeNotes.length ? 'SUCCESS-WITH-REPORT' : 'SUCCESS',
    skipped: false,
    iterations: iteration,
    exit_condition: 'fr-nfr-reviewer reported new_findings=0 with verdict=PASS',
    requirement_source: requirementSource,
    status_posted: !advisory,
    specs: hasSpecs ? `specs/${scope.slug}/` : null,
    pr: scope.pr ?? null,
    fixed: ledger.flatMap((l) => l.findings),
    ledger,
    degrade_notes: degradeNotes,
    journal,
  }
}

function fixPrompt(group, iteration) {
  return [
    `Fix these ${group.length} FR/NFR gate finding(s) from iteration ${iteration}/${OPTS.maxIterations} against ${requirementSource}; touch only the files they cite plus their tests. TDD: reproduce with a failing test where the requirement is behavioral, then fix the root cause.`,
    ...group.map((f) => `- ${f.requirement} — ${f.file}${f.line ? `:${f.line}` : ''} — ${f.title}\n  evidence: ${f.evidence}\n  fix: ${f.fix}`),
    'Never suppress a finding, edit a threshold or a spec, or add data-testid. Run no git. Report status, files_modified, tests_status, recommendation.',
  ].join('\n')
}

async function dispatchFixes(findings, iteration) {
  const groups = new Map()
  for (const f of findings) {
    const dir = f.file.split('/').slice(0, 3).join('/')
    groups.set(dir, [...(groups.get(dir) || []), f])
  }
  const groupKeys = [...groups.keys()].slice(0, 4)
  if (groups.size > 4) log(`fix fan-out capped at 4 groups; ${groups.size - 4} group(s) are left for the next gate iteration to re-detect`)
  const fixes = await parallel(
    groupKeys.map((key) => () =>
      agent(fixPrompt(groups.get(key), iteration), { label: `fix:${key}`, phase: 'Fix', agentType: 'react-frontend-sdlc:react-implementer', schema: FIX_SCHEMA }),
    ),
  )
  const blockedFix = fixes.find((r) => r && r.status === 'BLOCKED')
  if (blockedFix) return escalate(iteration, `react-implementer BLOCKED — ${blockedFix.recommendation || ''}`, 'resolve the blocker by hand, then re-run')
  const completed = fixes.filter(isComplete)
  if (completed.length < groupKeys.length) log(`${groupKeys.length - completed.length} fix group(s) did not complete; the next gate iteration re-detects what is still unmet`)
  journal.push(`iteration ${iteration}: fixed groups=${completed.length}/${groups.size} files=${completed.reduce((n, r) => n + (r.files_modified || 0), 0)}`)
  return null
}

let iteration = 0
let unknownStreak = 0

while (iteration < OPTS.maxIterations) {
  iteration += 1
  phase('Gate')
  const gate = await agent(gatePrompt(iteration), { label: `fr-nfr-reviewer ${iteration}/${OPTS.maxIterations}`, phase: 'Gate', agentType: 'react-frontend-sdlc:fr-nfr-reviewer', schema: GATE_SCHEMA })
  const halted = gateEscalation(gate, iteration)
  if (halted) return halted
  const findings = dedupe(gate.findings || [])
  recordGate(gate, iteration, findings)

  if (!Number.isInteger(gate.new_findings)) {
    unknownStreak += 1
    log(`iteration ${iteration}: the gate run reported no findings count (${gate.note || 'transport failure or malformed contract line'}); consumed one iteration`)
    if (unknownStreak >= 2) return escalate(iteration, `the gate run could not report a findings count in ${unknownStreak} consecutive iterations — ${gate.note || ''}`, 'restore the claude/gh transport for the gate runner, then re-run')
    degradeNotes.push(`iteration ${iteration}: gate findings count unknown (${gate.note || 'transport'}); the next iteration re-ran the gate`)
    continue
  }
  unknownStreak = 0
  logConvergence(iteration, gate.new_findings)

  if (gate.new_findings === 0 && gate.verdict === 'PASS') return success(iteration)
  if (!findings.length) {
    return escalate(iteration, `verdict ${gate.verdict} with new_findings=${gate.new_findings} but no actionable finding — ${gate.note || 'a matrix row fails without a cited fix'}`, 'read the fr-nfr-reviewer matrix; a failing row without a root-cause fix needs a human decision (spec and implementation may disagree)')
  }

  phase('Fix')
  const blocked = await dispatchFixes(findings, iteration)
  if (blocked) return blocked
}

return escalate(iteration, `${OPTS.maxIterations} gate iterations still report findings: ${ledger[ledger.length - 1]?.findings.slice(0, 3).join('; ') || 'see the ledger'}`, 'review the last fr-nfr-reviewer matrix by hand; the change set is not converging on the spec')
