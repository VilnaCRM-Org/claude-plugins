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

@test "pr-until-green: GATE runs the FR/NFR gate on the PR head, publishes its fixes, re-gates the new head, then finishes" {
  run_wf fe-sdlc-pr-until-green.js pug-gate.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.counters.gate == 2'
  echo "$output" | jq -r '.calls[].label' >"$BATS_TEST_TMPDIR/labels"
  diff <(cat "$BATS_TEST_TMPDIR/labels") <(printf '%s\n' pr-state workflow:react-frontend-sdlc:fe-sdlc-fr-nfr-review 'publish gate 1' pr-state workflow:react-frontend-sdlc:fe-sdlc-fr-nfr-review pr-state)
  echo "$output" | jq -e '.calls[1].args == {"pr":7,"head":"aaaa111"} and .calls[4].args == {"pr":7,"head":"bbbb222"}'
  echo "$output" | jq -e '.calls[2].prompt | contains("FR/NFR gate fixes") and contains("never pass --no-verify")'
}

@test "pr-until-green: an escalated FR/NFR gate escalates the PR — the gate is never skipped" {
  run_wf fe-sdlc-pr-until-green.js pug-gate-escalated.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("FR/NFR gate escalated on head aaaa111") and contains("cannot be skipped")) and .result.gate.requirement_source == "none"'
  echo "$output" | jq -e '[.calls[] | select(.label | test("^(publish|request)"))] | length == 0'
}

@test "pr-until-green: a gate that never turns green is bounded by maxGateRounds" {
  run_wf fe-sdlc-pr-until-green.js pug-gate-exhausted.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.counters.gate == 3 and (.result.escalation | contains("still failure on head aaaa111 after 3 gate rounds") and contains("gate 3/3"))'
  echo "$output" | jq -e '[.calls[] | select(.label == "workflow:react-frontend-sdlc:fe-sdlc-fr-nfr-review")] | length == 3'
}

@test "pr-until-green: a READY snapshot without a green FR/NFR gate is a contradiction, never SUCCESS" {
  run_wf fe-sdlc-pr-until-green.js pug-ready-without-gate.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("contradicting facts") and contains("BMAD FR/NFR Review Gate green on the head"))'
}

@test "pr-until-green: a sensor payload without fr_nfr is malformed and blocks" {
  echo '{"args":"7","replies":[{"match":"^pr-state$","reply":{"verdict":"READY","next":"x","pr":7,"head":"aaaa111","ci":{"status":"green","failing":[],"pending":[]},"unresolved":{"total":0},"reviewers":[],"notes":[]}}]}' >"$BATS_TEST_TMPDIR/no-gate-field.json"
  run node "$HARNESS" "$WF/fe-sdlc-pr-until-green.js" "$BATS_TEST_TMPDIR/no-gate-field.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("malformed sensor payload") and contains("fr_nfr.status"))'
}

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
  echo "$output" | jq -e '[.calls[] | select(.label == "fr-nfr-reviewer")] | length == 1 and (.[0].prompt | contains("the PR description and its linked issues") and contains("baseline NFR catalog"))'
}

# --- fe-sdlc-feature -----------------------------------------------------------------

@test "feature: every story prompt carries the component-first UI order (UI kit → Storybook → composition)" {
  run_wf fe-sdlc-feature.js feat-happy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:react-implementer")] | length > 0 and all(.prompt | contains("work component-first") and contains("when Storybook is available") and contains("SKIPPED: storybook") and (index("reuse UI-kit components") < index("build every missing component")) and (index("build every missing component") < index("before any page or feature uses it")) and (index("before any page or feature uses it") < index("then compose the page/feature from those components")))'
}

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
  echo "$output" | jq -e '[.calls[] | select(.label == "workflow:react-frontend-sdlc:fe-sdlc-fr-nfr-review")] | length == 2 and (.[0].args == {"slug":"currency-field"})'
  echo "$output" | jq -e '.result.degrade_notes | any(contains("findings count unknown"))'
  echo "$output" | jq -e '.phases == ["Setup check","Resolve plan","Implement","Implement","Review","FR/NFR gate","QA","Implement","Implement","Review","FR/NFR gate","QA","Finish PR"]'
}

@test "feature: an escalated FR/NFR gate stops the feature before QA and names the gate stage" {
  run_wf fe-sdlc-feature.js feat-gate-escalated.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.stage == "fr-nfr-gate" and (.result.escalation | contains("FR/NFR gate escalated") and contains("read its escalation block")) and (.result.gate.escalation | contains("no BMAD spec bundle exists"))'
  echo "$output" | jq -e '.phases == ["Setup check","Resolve plan","Implement","Implement","Review","FR/NFR gate"]'
  echo "$output" | jq -e '[.calls[] | select(.label == "qa-visual-tester")] | length == 0'
}

@test "feature: when the nested workflow cannot be resolved it escalates with the manual commands" {
  run_wf fe-sdlc-feature.js feat-no-nested.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("/react-frontend-sdlc:fe-sdlc-review-panel"))'
}

# --- fe-sdlc-fr-nfr-review ------------------------------------------------------------

@test "fr-nfr-review: an invalid profile escalates before the gate runs" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-scope-blocked.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.calls | length == 1) and (.result.escalation | contains("stage: fr-nfr-review") and contains("run /fe-sdlc-setup"))'
}

@test "fr-nfr-review: a named spec bundle that does not exist escalates — the gate is never skipped" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-no-specs.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.iterations == 0 and (.calls | length == 1) and (.result | has("skipped") | not)'
  echo "$output" | jq -e '.result.escalation | contains("specs/ghost/") and contains("/fe-sdlc-plan")'
  echo "$output" | jq -e '.calls[0].prompt | contains("specs/ghost/")'
}

@test "fr-nfr-review: without a spec bundle the PR description and linked issues are the requirement source and the gate runs" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-pr-source.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.specs == null and .result.pr == 7 and .result.requirement_source == "PR #7 description + issue(s) #12"'
  echo "$output" | jq -e '.calls[0].prompt | contains("Pull request: PR #7") and contains("non-blank BODY") and contains("title-only issue is no requirement source")'
  echo "$output" | jq -e '.calls[1].prompt | contains("fr-nfr-gate.sh\" --pr 7 --impact-context '"'"'currency field with two-decimal validation'"'"'") and (contains("--spec-path") | not) and contains("no BMAD spec bundle") and contains("baseline NFR catalog")'
}

@test "fr-nfr-review: a malformed --pr value escalates instead of borrowing its trailing digits" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-bad-pr.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.calls | length == 0) and (.result.escalation | contains("malformed --pr value \"repo/pull/456-invalid123\""))'
}

@test "fr-nfr-review: a change with no spec bundle, no PR description and no linked issue escalates as untraceable" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-no-source.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.requirement_source == "none" and .result.status_posted == true and (.calls | length == 2)'
  echo "$output" | jq -e '.calls[1].label == "record-no-source" and (.calls[1].prompt | contains("fr-nfr-gate.sh\" --pr 7 exactly once"))'
  echo "$output" | jq -e '.result.escalation | contains("no requirement source") and contains("mandatory for every PR") and contains("Closes #N")'
}

@test "fr-nfr-review: --head pins the run to the PR head; a mismatched or dirty checkout escalates before any gate run" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-head-mismatch.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.calls[0].prompt | contains("must equal bbbb2222cccc") and contains("git status --porcelain")'
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.calls | length == 1) and (.result.escalation | contains("not at PR head bbbb222") and contains("resolve the blocking cause"))'
}

@test "fr-nfr-review: findings are fixed by react-implementer, the reviewer resumes from the ledger, and the loop exits on new_findings=0 PASS" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-converges.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS" and .result.skipped == false and .result.iterations == 2 and .result.specs == "specs/alpha-login/" and (.result.fixed | length == 2)'
  echo "$output" | jq -r '.calls[].label' >"$BATS_TEST_TMPDIR/labels"
  diff <(cat "$BATS_TEST_TMPDIR/labels") <(printf '%s\n' scope 'fr-nfr-reviewer 1/5' 'fix:src/modules/alpha' 'fix:tests/unit/modules' 'fr-nfr-reviewer 2/5')
  echo "$output" | jq -e '.phases == ["Scope","Gate","Fix","Gate"]'
  echo "$output" | jq -e '.calls[1].agentType == "react-frontend-sdlc:fr-nfr-reviewer" and .calls[2].agentType == "react-frontend-sdlc:react-implementer"'
  echo "$output" | jq -e '.calls[0].prompt | contains("use \"origin/main\"") and contains("specs/alpha-login/")'
  echo "$output" | jq -e '.calls[1].prompt | contains("No prior ledger") and contains("fr-nfr-gate.sh") and contains("run it exactly once") and contains("Edit nothing")'
  echo "$output" | jq -e '.calls[2].prompt | contains("FR-2") and contains("Never suppress a finding") and contains("Run no git")'
  echo "$output" | jq -e '.calls[4].prompt | contains("iteration 1: new_findings=2 verdict=FAIL findings=[FR-2: validation error not announced; NFR-3: negative case untested]")'
  echo "$output" | jq -e '.result.ledger | length == 2 and .[1].new_findings == 0'
}

@test "fr-nfr-review: the gate loop is bounded at 5 iterations and escalates with the canonical block" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-exhausted.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.iterations == 5 and (.result.escalation | contains("iteration: 5/5") and contains("5 gate iterations still report findings") and contains("FR-2"))'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:fr-nfr-reviewer")] | length == 5'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:react-implementer")] | length == 5'
  echo "$output" | jq -e '.logs | any(contains("not converging"))'
}

@test "fr-nfr-review: a gate run without a findings count consumes one iteration and is re-run once, twice in a row escalates" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-transport.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and .result.iterations == 2 and (.result.degrade_notes | any(contains("findings count unknown")))'
  echo "$output" | jq -e '[.calls[] | select(.agentType == "react-frontend-sdlc:react-implementer")] | length == 0'
  run_wf fe-sdlc-fr-nfr-review.js fnr-transport-twice.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.iterations == 2 and (.result.escalation | contains("2 consecutive iterations"))'
}

@test "fr-nfr-review: a FAIL verdict without an actionable finding escalates instead of looping or passing" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-fail-no-findings.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.iterations == 1 and (.result.escalation | contains("no actionable finding") and contains("manual evidence absent"))'
}

@test "fr-nfr-review: a SKIPPED runner reported with verdict DEGRADED gets the runner remedy, not the missing-source one" {
  echo '{"args":"alpha-login","replies":[{"match":"^scope$","reply":{"profile_valid":true,"blocked":null,"base":"origin/main","files":["src/a.tsx"],"specs_present":true,"slug":"alpha-login","spec_files":["prd.md"],"pr":null,"pr_requirements":false,"summary":"x"}},{"match":"^fr-nfr-reviewer ","reply":{"status":"OK","verdict":"DEGRADED","new_findings":null,"gate_run":"SKIPPED (claude not on PATH)","note":null,"findings":[]}}]}' >"$BATS_TEST_TMPDIR/skip-degraded.json"
  run node "$HARNESS" "$WF/fe-sdlc-fr-nfr-review.js" "$BATS_TEST_TMPDIR/skip-degraded.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("restore the gate runner") and (contains("/fe-sdlc-plan") | not))'
}

@test "fr-nfr-review: each gate run is told its attempt number for the PR comment" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-converges.json
  echo "$output" | jq -e '(.calls[1].prompt | contains("--iteration 1 when null")) and (.calls[4].prompt | contains("--iteration 2 when null"))'
}

@test "fr-nfr-review: the spec path and summary reach the runner shell-quoted" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-converges.json
  echo "$output" | jq -e '.calls[1].prompt | contains("fr-nfr-gate.sh\" --spec-path '"'"'specs/alpha-login'"'"' --impact-context '"'"'login form with polite validation status'"'"'")'
}

@test "fr-nfr-review: a Scope reply that omits clean / head_matches_pr is treated as advisory, never publishable" {
  echo '{"args":"alpha-login","replies":[{"match":"^scope$","reply":{"profile_valid":true,"blocked":null,"base":"origin/main","files":["src/a.tsx"],"specs_present":true,"slug":"alpha-login","spec_files":["prd.md"],"pr":7,"pr_requirements":true,"summary":"x"}},{"match":"^fr-nfr-reviewer ","reply":{"status":"OK","verdict":"PASS","new_findings":0,"gate_run":"plugin script","note":null,"findings":[]}}]}' >"$BATS_TEST_TMPDIR/scope-missing.json"
  run node "$HARNESS" "$WF/fe-sdlc-fr-nfr-review.js" "$BATS_TEST_TMPDIR/scope-missing.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.status_posted == false and (.calls[1].prompt | contains("--advisory"))'
}

@test "fr-nfr-review: a dirty checkout or a HEAD that is not the PR head runs the gate advisory, publishing nothing" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-advisory.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "SUCCESS-WITH-REPORT" and .result.status_posted == false and (.result.degrade_notes | any(contains("advisory gate run")))'
  echo "$output" | jq -e '.calls[1].prompt | contains("--advisory") and contains("advisory: it posts no status by design")'
  run_wf fe-sdlc-fr-nfr-review.js fnr-converges.json
  echo "$output" | jq -e '.result.status_posted == true and (.calls[1].prompt | contains("--advisory") | not)'
}

@test "fr-nfr-review: a manually built matrix (runner SKIPPED) never passes the mandatory gate — it escalates" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-skipped-runner.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and .result.iterations == 1 and (.result.escalation | contains("SKIPPED (gh not on PATH)") and contains("no \"BMAD FR/NFR Review Gate\" commit status") and contains("mandatory"))'
}

@test "fr-nfr-review: a BLOCKED react-implementer and a DEGRADED reviewer both escalate" {
  run_wf fe-sdlc-fr-nfr-review.js fnr-fix-blocked.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("react-implementer BLOCKED") and contains("contradicts the design"))'
  run_wf fe-sdlc-fr-nfr-review.js fnr-degraded.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("SPECS MISSING") and contains("run /fe-sdlc-plan"))'
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
  echo "$output" | jq -e '.result.result == "ESCALATED" and (.result.escalation | contains("returned SKIPPED although the profile maps a production-parity start target"))'
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
