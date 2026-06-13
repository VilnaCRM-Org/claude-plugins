#!/usr/bin/env bash
# Local entrypoint: run every tier of the prompt-quality guardrails.
#   ./run.sh                 lint + self-tests, and the LLM-judge if creds exist
#   ./run.sh --no-judge      deterministic tiers only
#   ./run.sh --judge-only    LLM-judge only
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

NO_JUDGE=0
JUDGE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --no-judge) NO_JUDGE=1 ;;
    --judge-only) JUDGE_ONLY=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

if [ "$NO_JUDGE" -eq 1 ] && [ "$JUDGE_ONLY" -eq 1 ]; then
  echo 'error: --no-judge and --judge-only are mutually exclusive' >&2
  exit 2
fi

if [ "$JUDGE_ONLY" -eq 0 ]; then
  echo "== Tier 1: static lint =="
  python3 lint/lint_all.py

  echo "== Self-tests (validators + judge engine) =="
  python3 -m unittest discover -s tests

  echo "== Tier 2: claude plugin validate (best-effort) =="
  if command -v claude >/dev/null 2>&1; then
    for dir in ../../plugins/*/; do
      [ -f "${dir}.claude-plugin/plugin.json" ] || continue
      claude plugin validate "$dir" --strict || echo "  (validate reported issues or is auth-gated — see above)"
    done
  else
    echo "  SKIP: claude CLI not on PATH"
  fi
fi

if [ "$NO_JUDGE" -eq 0 ]; then
  echo "== Tier 3: LLM-as-judge (sonnet) =="
  if command -v claude >/dev/null 2>&1; then
    python3 judge/run_judge.py --jobs "${JUDGE_JOBS:-6}" --report judge-report.md || true
    echo "  report: $HERE/judge-report.md"
  else
    echo "  SKIP: claude CLI not on PATH"
  fi
fi
