export const meta = {
  name: 'fe-sdlc-review-panel',
  description:
    'Stage-4 review as a fan-out: independent code-quality, FR/NFR, accessibility and technique-skill lenses review the change set in parallel, every finding is adversarially verified by three refuters, confirmed findings are fixed by react-implementer, and the panel re-runs until an iteration reports zero new confirmed findings',
  whenToUse:
    'After implementation and before QA or finish-pr, when the change set deserves more than one reviewer perspective. Give it the specs slug (specs/<slug>/) and optionally the diff base.',
  phases: [
    { title: 'Scope', detail: 'diff base, changed files, spec bundle, skill triage' },
    { title: 'Review', detail: 'parallel lenses' },
    { title: 'Verify', detail: 'three refuters per finding' },
    { title: 'Fix', detail: 'react-implementer per disjoint file group' },
  ],
}

const OPTS = { slug: null, base: null, maxIterations: 5, a11yFamilies: ['forms', 'keyboard', 'semantics-and-names', 'contrast-and-motion'] }
if (args != null) {
  if (typeof args === 'object') Object.assign(OPTS, args)
  else {
    const tokens = String(args).trim().split(/\s+/).filter(Boolean)
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i] === '--base') OPTS.base = tokens[++i] ?? null
      else if (tokens[i] === '--slug') OPTS.slug = tokens[++i] ?? null
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

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    lens: { type: 'string' },
    status: { type: 'string', enum: ['OK', 'BLOCKED', 'SKIPPED'] },
    note: { type: ['string', 'null'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'title', 'severity', 'evidence', 'fix'],
        properties: {
          file: { type: 'string' },
          line: { type: ['integer', 'null'] },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          evidence: { type: 'string' },
          fix: { type: 'string' },
          requirement: { type: ['string', 'null'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } },
}

const SCOPE_SCHEMA = {
  type: 'object',
  required: ['base', 'files', 'specs_present', 'execute_skills', 'not_applicable', 'profile_valid'],
  properties: {
    base: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    ui_files: { type: 'array', items: { type: 'string' } },
    specs_present: { type: 'boolean' },
    slug: { type: ['string', 'null'] },
    execute_skills: { type: 'array', items: { type: 'string' } },
    not_applicable: {
      type: 'array',
      items: { type: 'object', required: ['skill', 'reason'], properties: { skill: { type: 'string' }, reason: { type: 'string' } } },
    },
    profile_valid: { type: 'boolean' },
    blocked: { type: ['string', 'null'] },
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

// ---------------------------------------------------------------------------
phase('Scope')
const scope = await agent(
  [
    PLUGIN_ROOT,
    '',
    'Establish the review scope for this repository. Steps:',
    '1. Run "$P/scripts/validate-profile.sh"; profile_valid=false and blocked="run /fe-sdlc-setup" on exit 1.',
    `2. Diff base: ${OPTS.base ? `use "${OPTS.base}"` : 'the default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`), as origin/<default>'}.`,
    '   files = `git diff --name-only <base>...HEAD` plus uncommitted changes (`git status --porcelain` paths). ui_files = the .tsx/.css/.scss subset.',
    `3. specs bundle: ${OPTS.slug ? `specs/${OPTS.slug}/` : 'the newest specs/<slug>/ directory whose stories mention the changed files, else none'} — specs_present says whether prd/architecture/epics-stories exist there; set slug.`,
    '4. Skill triage per "$P/skills/SKILL-DECISION-GUIDE.md": read every skill description under "$P/skills/*/SKILL.md", decide EXECUTE or NOT-APPLICABLE from the changed files,',
    '   list the EXECUTE skill names in execute_skills and every other skill in not_applicable as {skill, reason} — the reason names the absent symptom (every verdict recorded, no silent skips). The process skills code-review and quality-standards are always EXECUTE.',
    'Return the structured output only; edit nothing.',
  ].join('\n'),
  { label: 'scope', phase: 'Scope', schema: SCOPE_SCHEMA },
)
if (!scope || scope.blocked || scope.profile_valid !== true) {
  return { result: 'ESCALATED', escalation: escalationBlock(0, scope?.blocked || 'scope agent returned nothing', 'run /fe-sdlc-setup, then re-run') }
}
if (!scope.files.length) return { result: 'SUCCESS', note: 'empty change set — nothing to review', scope }
log(`scope: ${scope.files.length} files, ${scope.execute_skills.length} EXECUTE / ${(scope.not_applicable || []).length} NOT-APPLICABLE skills, specs ${scope.specs_present ? 'present' : 'absent'}`)
const triage = { execute: scope.execute_skills, not_applicable: scope.not_applicable || [] }

function escalationBlock(iteration, finding, action) {
  return [
    '=== SDLC ESCALATION ===',
    `stage: review-panel      iteration: ${iteration}/${OPTS.maxIterations}`,
    'exit_condition: zero new confirmed findings in the last panel iteration; a11y lens clean',
    'status: NOT MET',
    `blocking_finding: ${finding}`,
    `iteration_log: ${journal.join(' | ')}`,
    `recommended_action: ${action}`,
    '=== END ===',
  ].join('\n')
}

function lenses(iteration) {
  const common = [
    PLUGIN_ROOT,
    '',
    `Review iteration ${iteration}/${OPTS.maxIterations}. Diff base: ${scope.base}. Changed files:`,
    ...scope.files.map((f) => `  - ${f}`),
    '',
    'Report only findings you can point at (file, line, evidence); a finding without a root-cause fix is not a finding. Never propose a suppression, a threshold change, or a skipped test. Edit nothing.',
    `Skill triage for this change set — EXECUTE: ${triage.execute.join(', ') || 'none'}; NOT-APPLICABLE: ${triage.not_applicable.map((n) => `${n.skill} (${n.reason})`).join('; ') || 'none'}.`,
  ]
  const out = []
  out.push({
    label: 'code-quality-reviewer',
    agentType: 'react-frontend-sdlc:code-quality-reviewer',
    prompt: [...common, '', 'Lens: code quality per your agent contract — run the read-only quality targets from the profile make map and map every FAIL row to a finding.'].join('\n'),
  })
  if (scope.specs_present) {
    out.push({
      label: 'fr-nfr-reviewer',
      agentType: 'react-frontend-sdlc:fr-nfr-reviewer',
      prompt: [...common, '', `Lens: FR/NFR spec compliance against specs/${scope.slug}/ per your agent contract (run the gate script once). Each unmet requirement is one finding with requirement set to its id.`].join('\n'),
    })
  }
  if ((scope.ui_files || []).length) {
    for (const family of OPTS.a11yFamilies) {
      out.push({
        label: `accessibility-auditor:${family}`,
        agentType: 'react-frontend-sdlc:accessibility-auditor',
        prompt: [...common, '', `Lens: accessibility, family "${family}" only, per your agent contract (static JSX/ARIA audit always; dynamic probing only when the profile capability allows — set status SKIPPED with a note otherwise). Every verified WCAG 2.2 AA barrier is a blocker finding.`].join('\n'),
      })
    }
  }
  const technique = scope.execute_skills.filter((s) => !['code-review', 'quality-standards', 'accessibility-audit', 'bmad-fr-nfr-review-gate'].includes(s))
  for (let i = 0; i < technique.length; i += 4) {
    const group = technique.slice(i, i + 4)
    out.push({
      label: `skills:${group.join('+')}`.slice(0, 60),
      prompt: [...common, '', `Lens: technique skills. Read these plugin skills in full and review the change set strictly against them: ${group.map((s) => `"$P/skills/${s}/SKILL.md"`).join(', ')}. One finding per violated rule.`].join('\n'),
    })
  }
  return out
}

const REFUTERS = [
  { lens: 'correctness', prompt: 'Read the cited file and lines. Refute the finding if the code does not do what the finding claims, or the claimed defect cannot occur.' },
  { lens: 'standards', prompt: 'Refute the finding if it is a style preference rather than a violation of a plugin skill rule, a profile threshold, a spec requirement, or WCAG 2.2 AA.' },
  { lens: 'remedy', prompt: 'Refute the finding if the proposed fix is a suppression, would break a test or a gate, or if the issue is already handled elsewhere in the change set.' },
]

const keyOf = (f) => `${f.file}:${f.title.toLowerCase().replace(/\s+/g, ' ').trim()}`
const seen = new Set()
const confirmedAll = []
let carry = []
let iteration = 0

while (iteration < OPTS.maxIterations) {
  iteration += 1
  phase('Review')
  const expected = lenses(iteration)
  const rawAll = await parallel(
    expected.map((l) => () =>
      agent(l.prompt, { label: l.label, phase: 'Review', schema: FINDINGS_SCHEMA, ...(l.agentType ? { agentType: l.agentType } : {}) })
        .then((r) => (r ? { ...r, lens: l.label } : null)),
    ),
  )
  const missingLenses = expected.filter((_, i) => !rawAll[i]).map((l) => l.label)
  if (missingLenses.length) {
    return { result: 'ESCALATED', escalation: escalationBlock(iteration, `lens returned no result: ${missingLenses.join(', ')}`, 'a required review perspective is missing — re-run; if it repeats, check the agent definition'), journal }
  }
  const raw = rawAll.filter(Boolean)
  const blockedLens = raw.find((r) => r.status === 'BLOCKED')
  if (blockedLens) {
    return { result: 'ESCALATED', escalation: escalationBlock(iteration, `${blockedLens.lens} BLOCKED — ${blockedLens.note || ''}`, 'fix the blocking cause and re-run'), journal }
  }
  const skipped = raw.filter((r) => r.status === 'SKIPPED').map((r) => `${r.lens}: ${r.note || 'skipped'}`)
  const fresh = raw.flatMap((r) => r.findings.map((f) => ({ ...f, lens: r.lens }))).filter((f) => !seen.has(keyOf(f)))
  fresh.forEach((f) => seen.add(keyOf(f)))
  log(`iteration ${iteration}: ${raw.length} lenses, ${fresh.length} new candidate findings, ${carry.length} carried from the last iteration`)

  phase('Verify')
  const confirmed = (
    await parallel(
      fresh.map((f) => () =>
        parallel(
          REFUTERS.map((r) => () =>
            agent(
              [
                `Adversarially verify one review finding (lens: ${r.lens}). Default to refuted=true when uncertain.`,
                `Finding from ${f.lens}: ${f.title}`,
                `File: ${f.file}${f.line ? `:${f.line}` : ''}`,
                `Evidence: ${f.evidence}`,
                `Proposed fix: ${f.fix}`,
                r.prompt,
                'Edit nothing. Return {refuted, reason}.',
              ].join('\n'),
              { label: `verify:${r.lens}:${f.file.split('/').pop()}`, phase: 'Verify', schema: VERDICT_SCHEMA, effort: 'low' },
            ),
          ),
        ).then((votes) => {
          const cast = votes.filter(Boolean)
          const unverified = cast.length < REFUTERS.length
          return { ...f, votes: cast, unverified, survives: unverified || cast.filter((v) => !v.refuted).length >= 2 }
        }),
      ),
    )
  )
    .filter(Boolean)
    .filter((f) => f.survives)
  const unverifiedCount = confirmed.filter((f) => f.unverified).length
  if (unverifiedCount) log(`${unverifiedCount} finding(s) kept unverified: a refuter returned no vote, so the finding stands`)
  confirmedAll.push(...confirmed.filter((f) => !carry.includes(f)))
  const toFix = [...carry, ...confirmed]
  journal.push(`iteration ${iteration}: candidates=${fresh.length} confirmed=${confirmed.length} carried=${carry.length}${skipped.length ? ` skipped=[${skipped.join('; ')}]` : ''}`)

  if (!toFix.length) {
    return {
      result: skipped.length ? 'SUCCESS-WITH-REPORT' : 'SUCCESS',
      iterations: iteration,
      exit_condition: 'zero new confirmed findings in the last iteration',
      confirmed_total: confirmedAll.length,
      fixed: confirmedAll.map((f) => `${f.file}: ${f.title}`),
      triage,
      degrade_notes: skipped,
      journal,
    }
  }

  phase('Fix')
  const groups = new Map()
  for (const f of toFix) {
    const dir = f.file.split('/').slice(0, 3).join('/')
    groups.set(dir, [...(groups.get(dir) || []), f])
  }
  const fixes = await parallel(
    [...groups.values()].slice(0, 4).map((group) => () =>
      agent(
        [
          `Fix these ${group.length} confirmed review finding(s) in iteration ${iteration}/${OPTS.maxIterations}; touch only the files they cite plus their tests. TDD: reproduce with a failing test where the finding is behavioral, then fix the root cause.`,
          ...group.map((f) => `- ${f.file}${f.line ? `:${f.line}` : ''} — ${f.title}\n  evidence: ${f.evidence}\n  fix: ${f.fix}${f.requirement ? `\n  requirement: ${f.requirement}` : ''}`),
          'Never suppress a finding, edit a threshold, or add data-testid. Run no git. Report status, files_modified, tests_status, recommendation.',
        ].join('\n'),
        { label: `fix:${[...groups.keys()][[...groups.values()].indexOf(group)]}`, phase: 'Fix', agentType: 'react-frontend-sdlc:react-implementer', schema: FIX_SCHEMA },
      ),
    ),
  )
  const groupList = [...groups.values()]
  const deferred = groupList.slice(4).flat()
  if (groups.size > 4) log(`fix fan-out capped at 4 groups; ${groups.size - 4} group(s) carried to the next iteration`)
  const blockedFix = fixes.filter(Boolean).find((r) => r.status === 'BLOCKED')
  if (blockedFix) {
    return { result: 'ESCALATED', escalation: escalationBlock(iteration, `react-implementer BLOCKED — ${blockedFix.recommendation}`, 'resolve the blocker by hand, then re-run'), journal }
  }
  const incomplete = groupList.slice(0, 4).flatMap((group, i) => (fixes[i] && fixes[i].status === 'COMPLETE' ? [] : group))
  carry = [...deferred, ...incomplete]
  if (carry.length) log(`${carry.length} confirmed finding(s) carried to iteration ${iteration + 1}: not yet fixed`)
  journal.push(`iteration ${iteration}: fixed groups=${fixes.filter(Boolean).length} files=${fixes.filter(Boolean).reduce((n, r) => n + (r.files_modified || 0), 0)}`)
}

return {
  result: 'ESCALATED',
  escalation: escalationBlock(iteration, `${OPTS.maxIterations} iterations still produced confirmed findings`, 'review the last confirmed findings by hand; the change set is not converging'),
  confirmed_total: confirmedAll.length,
  journal,
}
