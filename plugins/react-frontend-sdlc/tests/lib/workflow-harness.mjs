#!/usr/bin/env node
// workflow-harness.mjs — run a plugin workflow script against scripted agent
// replies, without Claude Code. Usage:
//   node workflow-harness.mjs <workflow.js> <scenario.json>
// The scenario is {"args": <any>, "replies": [{"match": "<regex over label
// then prompt>", "reply": <object | array of objects consumed in order>}],
// "workflows": {"<name>": <object>}}. Prints {"meta", "result", "calls",
// "phases", "logs"} as JSON. Exit 1 when the script throws or an agent call
// matches no reply (a scenario gap, reported with the offending label).
import { readFileSync } from 'node:fs'

const [, , scriptPath, scenarioPath] = process.argv
if (!scriptPath) {
  console.error('usage: workflow-harness.mjs <workflow.js> [scenario.json]')
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
  throw new Error(`scenario gap: no reply for agent label="${label}" prompt starts "${prompt.slice(0, 80).replace(/\n/g, ' ')}"`)
}

const api = {
  agent: async (prompt, opts = {}) => {
    calls.push({ label: opts.label || null, phase: opts.phase || null, agentType: opts.agentType || null, prompt })
    return reply(opts.label, prompt)
  },
  parallel: async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null))),
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
    const w = (scenario.workflows || {})[name]
    if (w === undefined) throw new Error(`unknown workflow: ${name}`)
    return w
  },
  budget: { total: null, spent: () => 0, remaining: () => Infinity },
  args: scenario.args,
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
let result
try {
  const fn = new AsyncFunction(...Object.keys(api), body)
  result = await fn(...Object.values(api))
} catch (e) {
  console.log(JSON.stringify({ meta, error: String(e && e.stack ? e.stack.split('\n')[0] : e), calls, phases, logs }, null, 2))
  process.exit(1)
}
console.log(JSON.stringify({ meta, result, calls, phases, logs }, null, 2))
