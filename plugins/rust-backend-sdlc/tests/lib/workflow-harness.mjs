#!/usr/bin/env node
// workflow-harness.mjs — run a plugin workflow script against scripted agent
// replies, without Claude Code (react-frontend-sdlc port). Usage:
//   node workflow-harness.mjs [--as-child] <workflow.js> [scenario.json]
// Scenario: {"args": <any>, "replies": [{"match": "<regex over label, then
// prompt>", "reply": <value | array consumed in order>}], "workflows":
// {"rust-backend-sdlc:rs-sdlc-<name>": <value | array consumed in order>}}.
// Prints {"meta", "result" | "error", "calls", "phases", "logs"} as JSON. Exit 2
// usage; exit 1 no meta literal, script threw, scenario gap (no reply) or schema
// gap (a non-null reply lacking a top-level `required` key of opts.schema; a
// null reply models an agent that returned nothing). A gap fails the run even
// when the script catches it. --as-child: every workflow() call throws.
import { readFileSync } from 'node:fs'

const USAGE = 'usage: workflow-harness.mjs [--as-child] <workflow.js> [scenario.json]'
const argv = process.argv.slice(2)
const asChild = argv.includes('--as-child')
const positional = argv.filter((a) => a !== '--as-child')
const [scriptPath, scenarioPath] = positional
if (!scriptPath || positional.length > 2 || positional.some((a) => a.startsWith('--'))) {
  console.error(USAGE)
  process.exit(2)
}
const source = readFileSync(scriptPath, 'utf8')
const scenarioText = scenarioPath ? readFileSync(scenarioPath, 'utf8').trim() : ''
const scenario = scenarioText ? JSON.parse(scenarioText) : { replies: [] }

const metaMatch = source.match(/^export const meta = (\{[\s\S]*?\n\})\n/m)
if (!metaMatch) {
  console.error('no `export const meta = {...}` literal at the top of the script')
  process.exit(1)
}
const meta = new Function(`return ${metaMatch[1]}`)()
const body = source.replace(metaMatch[0], `const meta = ${metaMatch[1]}\n`)

const calls = []
const phases = []
const logs = []
const cursors = new Map()
const rules = (scenario.replies || []).map((r) => ({ re: new RegExp(r.match, 's'), reply: r.reply }))
const WORKFLOW_NAME = /^rust-backend-sdlc:rs-sdlc-[a-z0-9]+(?:-[a-z0-9]+)*$/
const own = (o, k) => o !== null && typeof o === 'object' && !Array.isArray(o) && Object.prototype.hasOwnProperty.call(o, k)
let gap = null

function fail(message) {
  const e = new Error(message)
  gap = gap || e
  throw e
}

function reply(label, prompt) {
  for (let i = 0; i < rules.length; i++) {
    const { re, reply } = rules[i]
    if (re.test(label || '') || re.test(prompt)) {
      if (Array.isArray(reply)) {
        const k = cursors.get(i) || 0
        cursors.set(i, k + 1)
        return reply[Math.min(k, reply.length - 1)]
      }
      return reply
    }
  }
  return fail(`scenario gap: no reply for agent label="${label}" prompt starts "${prompt.slice(0, 80).replace(/\n/g, ' ')}"`)
}

function checkSchema(label, schema, r) {
  const required = schema && Array.isArray(schema.required) ? schema.required : []
  const missing = r === null ? [] : required.filter((k) => !own(r, k))
  if (missing.length) fail(`schema gap: reply for agent label="${label}" lacks required key(s) ${missing.map((k) => `"${k}"`).join(', ')}`)
  return r
}

const api = {
  agent: async (prompt, opts = {}) => {
    calls.push({ label: opts.label || null, phase: opts.phase || null, agentType: opts.agentType || null, prompt })
    return checkSchema(opts.label, opts.schema, reply(opts.label, String(prompt)))
  },
  parallel: async (thunks) =>
    Promise.all(thunks.map(async (t) => { try { return await t() } catch { return null } })),
  pipeline: async (items, ...stages) =>
    Promise.all(
      items.map(async (item, i) => {
        let v = item
        for (const s of stages) {
          try { v = await s(v, item, i) } catch { return null }
        }
        return v
      }),
    ),
  phase: (t) => phases.push(t),
  log: (m) => logs.push(m),
  workflow: async (name, wfArgs) => {
    calls.push({ label: `workflow:${name}`, args: wfArgs })
    if (asChild) throw new Error('workflow() nesting is one level only')
    const workflows = scenario.workflows || {}
    if (!WORKFLOW_NAME.test(String(name)) || !own(workflows, name)) throw new Error(`unknown workflow: ${name}`)
    const w = workflows[name]
    if (Array.isArray(w)) {
      const k = cursors.get(`workflow:${name}`) || 0
      cursors.set(`workflow:${name}`, k + 1)
      return w[Math.min(k, w.length - 1)]
    }
    return w
  },
  budget: { total: null, spent: () => 0, remaining: () => Infinity },
  args: scenario.args,
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
let result
let failure = null
try {
  const fn = new AsyncFunction(...Object.keys(api), body)
  result = await fn(...Object.values(api))
} catch (e) {
  failure = { e }
}
if (gap || failure) {
  const e = gap || failure.e
  console.log(JSON.stringify({ meta, error: String(e && e.stack ? e.stack.split('\n')[0] : e), calls, phases, logs }, null, 2))
  process.exit(1)
}
console.log(JSON.stringify({ meta, result: result ?? null, calls, phases, logs }, null, 2))
