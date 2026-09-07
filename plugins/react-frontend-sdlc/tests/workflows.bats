#!/usr/bin/env bats
# Tests for workflows/*.js — the plugin's Workflow-tool orchestration scripts.
#
# Claude Code evaluates a workflow as a top-level-await script with agent(),
# parallel(), pipeline(), phase(), log(), workflow(), args and budget in scope.
# tests/lib/workflow-harness.mjs reproduces that contract in node with
# scripted agent replies (tests/fixtures/workflows/*.json), so every loop,
# counter and escalation path is pinned without a model in the loop.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HARNESS="$BATS_TEST_DIRNAME/lib/workflow-harness.mjs"
  FX="$BATS_TEST_DIRNAME/fixtures/workflows"
  WF="$PLUGIN_ROOT/workflows"
  command -v node >/dev/null || skip "node is required for the workflow harness"
}

run_wf() { # <workflow-file> <scenario-file>
  run node "$HARNESS" "$WF/$1" "$FX/$2"
}

# --- contract every workflow file must meet ----------------------------------

@test "every workflow exports a meta literal whose name equals the file name and carries a description" {
  for f in "$WF"/*.js; do
    run node "$HARNESS" "$f" /dev/null
    name="$(basename "$f" .js)"
    echo "$output" | jq -e --arg n "$name" '.meta.name == $n and (.meta.description | length > 40) and (.meta.phases | length > 0)' >/dev/null \
      || { echo "meta contract failed for $f: $output"; return 1; }
  done
}

@test "every workflow parses as a Claude Code workflow script (no TypeScript, no Date.now / Math.random)" {
  for f in "$WF"/*.js; do
    ! grep -nE 'Date\.now\(|Math\.random\(|new Date\(\)' "$f" || { echo "non-deterministic call in $f"; return 1; }
    ! grep -nE '^\s*(interface |type [A-Z][A-Za-z]* =)' "$f" || { echo "TypeScript syntax in $f"; return 1; }
    ! grep -nE '\$\{CLAUDE_PLUGIN_ROOT\}' "$f" || { echo "$f interpolates CLAUDE_PLUGIN_ROOT inside JavaScript; use \$CLAUDE_PLUGIN_ROOT in the shell text"; return 1; }
  done
}

@test "every plugin agent a workflow dispatches exists under agents/" {
  for f in "$WF"/*.js; do
    for a in $(grep -oE "react-frontend-sdlc:[a-z-]+" "$f" | sed 's/react-frontend-sdlc://' | sort -u); do
      [ -f "$PLUGIN_ROOT/agents/$a.md" ] || [ -f "$WF/$a.js" ] \
        || { echo "$f references react-frontend-sdlc:$a but neither agents/$a.md nor workflows/$a.js exists"; return 1; }
    done
  done
}

@test "every plugin script a workflow invokes exists under scripts/" {
  for f in "$WF"/*.js; do
    for s in $(grep -oE 'scripts/[a-z-]+\.sh' "$f" | sort -u); do
      [ -f "$PLUGIN_ROOT/$s" ] || { echo "$f references $s which does not exist"; return 1; }
    done
  done
}

# --- fe-sdlc-pr-until-green ------------------------------------------------------

@test "pr-until-green: a READY snapshot ends SUCCESS after exactly one agent call" {
  run_wf fe-sdlc-pr-until-green.js pug-ready.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and (.calls | length == 1) and (.calls[0].prompt | contains("--pr 7 --reviewers coderabbit,cubic"))'
}

@test "pr-until-green: fix → publish → request → wait → ready drives the full loop in order" {
  run_wf fe-sdlc-pr-until-green.js pug-full-loop.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.counters.fix == 1 and .result.counters.request == 1'
  echo "$output" | jq -r '.calls[].label' >"$BATS_TEST_TMPDIR/labels"
  diff <(cat "$BATS_TEST_TMPDIR/labels") <(printf '%s\n' pr-state 'ci-fixer 1/5' 'pr-comment-resolver 1/5' 'publish 1' pr-state 'request 1' 'wait 120s' 'wait 540s')
  echo "$output" | jq -e '.calls[1].agentType == "react-frontend-sdlc:ci-fixer" and .calls[2].agentType == "react-frontend-sdlc:pr-comment-resolver"'
  echo "$output" | jq -e '.calls[0].prompt | contains("--pr 7 --reviewers coderabbit,cubic")'
  echo "$output" | jq -e '.calls[5].prompt | contains("request-ai-reviews.sh\" --pr 7 --reviewers coderabbit,cubic")'
  echo "$output" | jq -e '.calls[7].prompt | contains("--wait-seconds 540 --interval-seconds 60 --wait-verdicts WAIT")'
}

@test "pr-until-green: the publish agent is told to keep hooks, cite the task number and never force-push" {
  run_wf fe-sdlc-pr-until-green.js pug-full-loop.json
  echo "$output" | jq -e '.calls[3].prompt | (contains("never pass --no-verify") and contains("(#N)") and contains("Never force-push"))'
}

@test "pr-until-green: BLOCKED escalates with the canonical block" {
  run_wf fe-sdlc-pr-until-green.js pug-blocked.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("=== SDLC ESCALATION ===") and contains("stage: pr-until-green") and contains("PR is MERGED"))'
}

@test "pr-until-green: the fix budget is bounded at 5 rounds" {
  run_wf fe-sdlc-pr-until-green.js pug-fix-exhausted.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.counters.fix == 5 and (.result.escalation | contains("fix budget exhausted"))'
  echo "$output" | jq -e '[.calls[] | select(.label | startswith("publish"))] | length == 5'
}

@test "pr-until-green: a reviewer that never reviews after 3 requests is dropped with a degrade note, never passed silently" {
  run_wf fe-sdlc-pr-until-green.js pug-silent-reviewer.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and .result.counters.request == 3'
  echo "$output" | jq -e '.result.degrade_notes | any(contains("did not review head") and contains("reported as missing, not passed"))'
  echo "$output" | jq -e '[.calls[] | select(.label | startswith("request"))] | length == 3'
}

@test "pr-until-green: inside the CodeRabbit interval it waits through REQUEST verdicts instead of re-mentioning" {
  run_wf fe-sdlc-pr-until-green.js pug-coderabbit-interval.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT"'
  echo "$output" | jq -e '.calls[2].prompt | contains("--wait-verdicts WAIT,REQUEST")'
  echo "$output" | jq -e '.result.degrade_notes | any(contains("cubic: status-check bot"))'
}

# --- fe-sdlc-review-panel ----------------------------------------------------------

@test "review-panel: an invalid profile escalates before any lens runs" {
  run_wf fe-sdlc-review-panel.js rp-scope-blocked.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.calls | length == 1) and (.result.escalation | contains("run /fe-sdlc-setup"))'
}

@test "review-panel: lenses fan out, findings are verified by three refuters, fixes dispatch, and the panel converges" {
  run_wf fe-sdlc-review-panel.js rp-converges.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and .result.iterations == 2 and .result.confirmed_total == 1'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:accessibility-auditor")] | length == 8'
  echo "$output" | jq -e '[.calls[] | select(.label | startswith("verify:"))] | length == 3'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:react-implementer")] | length == 1'
  echo "$output" | jq -e '.result.degrade_notes | any(contains("dynamic_a11y_testing"))'
  echo "$output" | jq -e '[.calls[] | select(.label | startswith("skills:"))][0].prompt | contains("frontend-component-development/SKILL.md")'
}

@test "review-panel: a finding refuted by the majority is dropped and the panel exits clean" {
  run_wf fe-sdlc-review-panel.js rp-all-refuted.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.iterations == 1 and .result.confirmed_total == 0'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:fr-nfr-reviewer")] | length == 0'
}

# --- fe-sdlc-feature -----------------------------------------------------------------

@test "feature: a failed setup check halts with the /fe-sdlc-setup instruction" {
  run_wf fe-sdlc-feature.js feat-setup-fails.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.stage == "setup-check" and (.result.escalation | contains("run /fe-sdlc-setup"))'
}

@test "feature: stories fan out, QA FAIL loops back to implement, and the nested workflows finish the PR" {
  run_wf fe-sdlc-feature.js feat-happy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and .result.counters.qa_loops == 1 and .result.pr == "https://github.com/acme/stub-frontend/pull/7"'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:react-implementer")] | length == 6'
  echo "$output" | jq -e '[.calls[] | select(.label == "workflow:react-frontend-sdlc:fe-sdlc-review-panel")] | length == 2'
  echo "$output" | jq -e '[.calls[] | select(.label == "workflow:react-frontend-sdlc:fe-sdlc-pr-until-green")][0].args == {"pr":7,"reviewers":"coderabbit,cubic"}'
  echo "$output" | jq -e '.phases == ["Setup check","Resolve plan","Implement","Implement","Review","QA","Implement","Implement","Review","QA","Finish PR"]'
}

@test "feature: when the nested workflow cannot be resolved it escalates with the manual commands" {
  run_wf fe-sdlc-feature.js feat-no-nested.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("/react-frontend-sdlc:fe-sdlc-review-panel"))'
}

# --- review-fix regressions ------------------------------------------------------------

@test "pr-until-green: a reviewer that reviewed the head without approving escalates instead of being dropped" {
  run_wf fe-sdlc-pr-until-green.js pug-not-approved.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("coderabbit reviewed head bbbb222 and did not approve"))'
  echo "$output" | jq -e '.result.degrade_notes == []'
}

@test "pr-until-green: a READY snapshot without the full sensor payload is rejected" {
  run_wf fe-sdlc-pr-until-green.js pug-malformed-ready.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("malformed sensor payload"))'
}

@test "review-panel: a lens that returns nothing escalates instead of vanishing" {
  run_wf fe-sdlc-review-panel.js rp-missing-lens.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("lens returned no result: fr-nfr-reviewer"))'
}

@test "review-panel: a confirmed finding whose fix is incomplete is carried into the next iteration" {
  run_wf fe-sdlc-review-panel.js rp-carry.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.iterations == 3 and .result.confirmed_total == 1'
  echo "$output" | jq -e '[.calls[] | select(.label | startswith("fix:"))] | length == 2'
  echo "$output" | jq -e '.result.triage.not_applicable[0].skill == "storybook-visual-baselines"'
}

@test "review-panel: a finding with a missing refuter vote is kept, not silently confirmed or dropped by majority" {
  run_wf fe-sdlc-review-panel.js rp-unverified.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.confirmed_total == 1'
  echo "$output" | jq -e '.logs | any(contains("kept unverified"))'
}

@test "feature: a QA SKIPPED verdict is accepted only when the profile really maps no start target" {
  run_wf fe-sdlc-feature.js feat-qa-skipped-rejected.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("returned SKIPPED although the profile maps a start target"))'
  run_wf fe-sdlc-feature.js feat-qa-skipped-accepted.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and (.result.degrade_notes | any(contains("verified against the profile")))'
}

@test "feature: COMPLETE without exit_signal never marks a story done" {
  run_wf fe-sdlc-feature.js feat-incomplete-story.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.counters.implement == 5 and (.result.escalation | contains("stories still open: 1.1"))'
}

@test "feature: a plan without a specs slug escalates before implementation" {
  run_wf fe-sdlc-feature.js feat-null-slug.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.stage == "plan"'
}
