export const meta = {
  name: 'fe-sdlc-fr-nfr-review',
  description:
    'The BMAD FR/NFR review gate as a bounded loop: locate the specs/<slug>/ bundle the implemented feature was planned against, run fr-nfr-reviewer (exactly one gate run per iteration) to build the per-requirement matrix, hand every new finding to react-implementer as a root-cause fix, and repeat until the gate reports zero new findings with verdict PASS — when no BMAD spec bundle exists the gate is not applicable and the run ends with a report, never with invented findings',
  whenToUse:
    'After implementation and the review panel, when the feature was planned with BMAD specs under specs/<slug>/. Give it the slug (or let it locate the bundle whose stories name the changed files) and optionally --base <ref> and --summary "<one line>". Without a spec bundle it reports SUCCESS-WITH-REPORT and changes nothing.',
  phases: [
    { title: 'Scope', detail: 'profile, diff base, changed files, spec bundle presence' },
    { title: 'Gate', detail: 'fr-nfr-reviewer: one gate run + requirement matrix' },
    { title: 'Fix', detail: 'react-implementer per disjoint file group' },
  ],
}

const OPTS = { slug: null, base: null, summary: null, maxIterations: 5 }
if (args != null) {
  if (typeof args === 'object') Object.assign(OPTS, args)
  else {
    const tokens = String(args).trim().split(/\s+/).filter(Boolean)
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i] === '--base') OPTS.base = tokens[++i] ?? null
      else if (tokens[i] === '--slug') OPTS.slug = tokens[++i] ?? null
      else if (tokens[i] === '--summary') OPTS.summary = tokens[++i] ?? null
      else if (!OPTS.slug && !tokens[i].startsWith('--')) OPTS.slug = tokens[i]
    }
  }
}

const PLUGIN_ROOT = [
  'Resolve the react-frontend-sdlc plugin root into P and echo it:',
  '  P="$CLAUDE_PLUGIN_ROOT"',
  '  [ -n "$P" ] || P="$(ls -d ~/.claude/plugins/cache/*/react-frontend-sdlc/*/ 2>/dev/null | sort -V | tail -1)"',
  '  [ -n "$P" ] || P="$(find "$HOME" -maxdepth 8 -path "*/plugins/react-frontend-sdlc/.claude-plugin/plugin.json" 2>/dev/null | head -1 | xargs -r dirname | xargs -r dirname)"',
  'If P is empty return status BLOCKED. Plugin skills live under "$P/skills/<name>/SKILL.md", scripts under "$P/scripts/".',
].join('\n')

const SCOPE_SCHEMA = {
  type: 'object',
  required: ['profile_valid', 'base', 'files', 'specs_present', 'summary'],
  properties: {
    profile_valid: { type: 'boolean' },
    blocked: { type: ['string', 'null'] },
    base: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    specs_present: { type: 'boolean' },
    slug: { type: ['string', 'null'] },
    spec_files: { type: 'array', items: { type: 'string' } },
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
    `4. summary: ${OPTS.summary ? `use "${OPTS.summary}"` : 'one line describing the change set (what the changed files implement), for the gate impact context'}.`,
    'Return the structured output only; edit nothing.',
  ].join('\n'),
  { label: 'scope', phase: 'Scope', schema: SCOPE_SCHEMA },
)
if (!scope || scope.blocked || scope.profile_valid !== true) {
  return escalate(0, scope?.blocked || 'scope agent returned nothing', 'run /fe-sdlc-setup, then re-run')
}
if (!scope.files.length) return { result: 'SUCCESS', note: 'empty change set — nothing to gate', iterations: 0, skipped: false, scope }
if (!scope.specs_present || !scope.slug) {
  const where = OPTS.slug ? `specs/${OPTS.slug}/` : 'specs/'
  const noteText = `no BMAD spec bundle found for this change set under ${where} — the FR/NFR gate is not applicable and was not run; run /fe-sdlc-plan first when the feature should be spec-gated`
  degradeNotes.push(noteText)
  log(noteText)
  return { result: 'SUCCESS-WITH-REPORT', skipped: true, iterations: 0, degrade_notes: degradeNotes, scope }
}
log(`scope: ${scope.files.length} files against ${scope.base}; spec bundle specs/${scope.slug}/ (${(scope.spec_files || []).join(', ') || 'files unlisted'})`)

function gatePrompt(iteration) {
  const prior = ledger.length
    ? ['Prior iteration ledger (resume the counter from it; a finding is NEW only when absent from every prior iteration):', ...ledger.map((l) => `  iteration ${l.iteration}: new_findings=${l.new_findings ?? 'unknown (transport)'} verdict=${l.verdict} findings=[${l.findings.join('; ') || 'none'}]`)]
    : ['No prior ledger — this is the first gate iteration.']
  return [
    PLUGIN_ROOT,
    '',
    `Review iteration ${iteration}/${OPTS.maxIterations}. Spec bundle: specs/${scope.slug}/. Diff base: ${scope.base}. Change summary: "${scope.summary}".`,
    'Changed files:',
    ...scope.files.map((f) => `  - ${f}`),
    ...prior,
    '',
    'Per your agent contract: resolve the gate runner from make.fr_nfr_gate in .claude/react-sdlc.yml (the plugin script "$P/scripts/fr-nfr-gate.sh" --spec-path specs/<slug> --impact-context "<summary>" when null), run it exactly once, build the full per-requirement matrix, and mirror the FR_NFR_REVIEWER last line into the structured output: verdict, new_findings (null only when the gate run failed for transport or a malformed contract line), gate_run (the runner used, or SKIPPED (<reason>)).',
    'Every NEW finding is one findings[] entry with the requirement id, the file it points at, evidence, and a root-cause fix — never a suppression, a threshold change, or a skipped test. Edit nothing.',
  ].join('\n')
}

const keyOf = (f) => `${f.requirement}:${f.title.toLowerCase().replace(/\s+/g, ' ').trim()}`
let iteration = 0
let unknownStreak = 0

while (iteration < OPTS.maxIterations) {
  iteration += 1
  phase('Gate')
  const gate = await agent(gatePrompt(iteration), { label: `fr-nfr-reviewer ${iteration}/${OPTS.maxIterations}`, phase: 'Gate', agentType: 'react-frontend-sdlc:fr-nfr-reviewer', schema: GATE_SCHEMA })
  if (!gate) return escalate(iteration, 'fr-nfr-reviewer returned nothing', 're-run; if it repeats, check the agent definition')
  if (gate.status === 'BLOCKED') return escalate(iteration, `fr-nfr-reviewer BLOCKED — ${gate.note || ''}`, 'fix the blocking cause (plugin root, profile, gate runner), then re-run')
  if (gate.verdict === 'DEGRADED') {
    return escalate(iteration, `fr-nfr-reviewer reported the spec bundle specs/${scope.slug}/ missing or empty although scope found it — ${gate.note || ''}`, 'run /fe-sdlc-plan for this feature, then re-run')
  }
  if (/^SKIPPED/i.test(gate.gate_run || '')) {
    const skipNote = `iteration ${iteration}: gate runner ${gate.gate_run} — matrix built manually by fr-nfr-reviewer, no "BMAD FR/NFR Review Gate" commit status was posted`
    if (!degradeNotes.includes(skipNote)) degradeNotes.push(skipNote)
  }
  const findings = (gate.findings || []).filter((f, i, all) => all.findIndex((g) => keyOf(g) === keyOf(f)) === i)
  ledger.push({ iteration, new_findings: gate.new_findings, verdict: gate.verdict, findings: findings.map((f) => `${f.requirement}: ${f.title}`) })
  journal.push(`iteration ${iteration}: gate=${gate.gate_run} new_findings=${gate.new_findings ?? 'unknown'} verdict=${gate.verdict}`)

  if (gate.new_findings === null || gate.new_findings === undefined) {
    unknownStreak += 1
    log(`iteration ${iteration}: the gate run reported no findings count (${gate.note || 'transport failure or malformed contract line'}); consumed one iteration`)
    if (unknownStreak >= 2) return escalate(iteration, `the gate run could not report a findings count in ${unknownStreak} consecutive iterations — ${gate.note || ''}`, 'restore the claude/gh transport for the gate runner, then re-run')
    degradeNotes.push(`iteration ${iteration}: gate findings count unknown (${gate.note || 'transport'}); the next iteration re-ran the gate`)
    continue
  }
  unknownStreak = 0

  const previous = ledger.length >= 3 ? ledger.slice(-3, -1).map((l) => l.new_findings) : []
  if (previous.length === 2 && previous.every((n) => typeof n === 'number' && gate.new_findings >= n)) {
    log(`iteration ${iteration}: new findings did not decrease across the last three iterations (${previous.join(', ')}, ${gate.new_findings}) — the loop is not converging`)
  }

  if (gate.new_findings === 0 && gate.verdict === 'PASS') {
    return {
      result: degradeNotes.length ? 'SUCCESS-WITH-REPORT' : 'SUCCESS',
      skipped: false,
      iterations: iteration,
      exit_condition: 'fr-nfr-reviewer reported new_findings=0 with verdict=PASS',
      specs: `specs/${scope.slug}/`,
      fixed: ledger.flatMap((l) => l.findings),
      ledger,
      degrade_notes: degradeNotes,
      journal,
    }
  }
  if (!findings.length) {
    return escalate(iteration, `verdict ${gate.verdict} with new_findings=${gate.new_findings} but no actionable finding — ${gate.note || 'a matrix row fails without a cited fix'}`, 'read the fr-nfr-reviewer matrix; a failing row without a root-cause fix needs a human decision (spec and implementation may disagree)')
  }

  phase('Fix')
  const groups = new Map()
  for (const f of findings) {
    const dir = f.file.split('/').slice(0, 3).join('/')
    groups.set(dir, [...(groups.get(dir) || []), f])
  }
  const groupList = [...groups.values()]
  const groupKeys = [...groups.keys()]
  if (groups.size > 4) log(`fix fan-out capped at 4 groups; ${groups.size - 4} group(s) are left for the next gate iteration to re-detect`)
  const fixes = await parallel(
    groupList.slice(0, 4).map((group, i) => () =>
      agent(
        [
          `Fix these ${group.length} FR/NFR gate finding(s) from iteration ${iteration}/${OPTS.maxIterations} against specs/${scope.slug}/; touch only the files they cite plus their tests. TDD: reproduce with a failing test where the requirement is behavioral, then fix the root cause.`,
          ...group.map((f) => `- ${f.requirement} — ${f.file}${f.line ? `:${f.line}` : ''} — ${f.title}\n  evidence: ${f.evidence}\n  fix: ${f.fix}`),
          'Never suppress a finding, edit a threshold or a spec, or add data-testid. Run no git. Report status, files_modified, tests_status, recommendation.',
        ].join('\n'),
        { label: `fix:${groupKeys[i]}`, phase: 'Fix', agentType: 'react-frontend-sdlc:react-implementer', schema: FIX_SCHEMA },
      ),
    ),
  )
  const blockedFix = fixes.filter(Boolean).find((r) => r.status === 'BLOCKED')
  if (blockedFix) return escalate(iteration, `react-implementer BLOCKED — ${blockedFix.recommendation || ''}`, 'resolve the blocker by hand, then re-run')
  const incomplete = groupList.slice(0, 4).filter((_, i) => !fixes[i] || fixes[i].status !== 'COMPLETE').length
  if (incomplete) log(`${incomplete} fix group(s) did not complete; the next gate iteration re-detects what is still unmet`)
  journal.push(`iteration ${iteration}: fixed groups=${fixes.filter((r) => r && r.status === 'COMPLETE').length}/${groupList.length} files=${fixes.filter(Boolean).reduce((n, r) => n + (r.files_modified || 0), 0)}`)
}

return escalate(iteration, `${OPTS.maxIterations} gate iterations still report findings: ${ledger[ledger.length - 1]?.findings.slice(0, 3).join('; ') || 'see the ledger'}`, 'review the last fr-nfr-reviewer matrix by hand; the change set is not converging on the spec')
