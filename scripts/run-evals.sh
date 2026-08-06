#!/usr/bin/env bash
# Runs the eval suite at evals/evals.json and evals/trigger-queries.json
# against the local plugin copy using `claude -p`. Useful as a pre-release
# smoke test and as a CI gate for SKILL.md description regressions.
#
# Usage:
#   bash scripts/run-evals.sh               # all suites
#   bash scripts/run-evals.sh --cases       # only evals.json cases
#   bash scripts/run-evals.sh --triggers    # only trigger-queries.json
#
# Requires: jq, claude CLI, plugin-dir-compatible Claude Code.
# Exit codes: 0 = all pass, 1 = any failure, 2 = setup error.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Error: not in a git repo" >&2; exit 2; })
cd "$ROOT"

command -v claude >/dev/null 2>&1 || { echo "Error: 'claude' CLI not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1     || { echo "Error: 'jq' not on PATH" >&2; exit 2; }

MODE="${1:-all}"
FAILURES=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_case() {
  local id="$1" prompt="$2"
  local workdir="$TMP/$id"
  mkdir -p "$workdir"

  echo ">> eval case: $id"

  ( cd "$workdir" && git init -q && git commit --allow-empty -qm initial 2>/dev/null ) || true

  local output
  if ! output=$(
    cd "$workdir" && \
    claude -p "$prompt" \
      --plugin-dir "$ROOT" \
      --allowedTools "Read,Write,Glob,Grep,Bash,Agent,EnterWorktree,ExitWorktree,TodoWrite" \
      --bare --output-format json 2>&1
  ); then
    echo "  FAIL: claude -p returned non-zero"
    echo "$output" | head -20 | sed 's/^/    /'
    FAILURES=$((FAILURES + 1))
    return
  fi

  # Assertion: Epic should have created .epic/stories/ for Create-mode cases.
  if [[ "$id" != "ambiguous-input" ]]; then
    if ! find "$workdir/.epic/stories" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
      echo "  FAIL: no story directory created"
      FAILURES=$((FAILURES + 1))
      return
    fi
    # Every Epic story must have tasks.md.
    if ! find "$workdir/.epic/stories" -mindepth 2 -maxdepth 2 -name tasks.md 2>/dev/null | grep -q .; then
      echo "  FAIL: tasks.md missing"
      FAILURES=$((FAILURES + 1))
      return
    fi
    # Validate the story artifact. Capture the real exit status: `$?` right
    # after `if ! cmd` reads the negated status (always 0) — dead code.
    local story_dir rc=0
    story_dir=$(find "$workdir/.epic/stories" -mindepth 1 -maxdepth 1 -type d | head -1)
    bash "$ROOT/scripts/validate-story.sh" "$story_dir" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "  FAIL: validate-story.sh reported errors"
      FAILURES=$((FAILURES + 1))
      return
    fi
  fi

  echo "  PASS"
}

run_trigger() {
  local phrase="$1" expect_trigger="$2"
  local workdir
  workdir="$TMP/trigger-$(echo "$phrase" | tr -cd 'a-zA-Z0-9' | head -c 30)"
  mkdir -p "$workdir"

  local output
  output=$(
    if cd "$workdir"; then
      claude -p "$phrase" \
        --plugin-dir "$ROOT" \
        --allowedTools "Read,Glob,Grep,Agent" \
        --bare --output-format json 2>&1 || true
    fi
  )

  local triggered=false
  if echo "$output" | grep -q '"skill"\s*:\s*"epic:epic"' 2>/dev/null; then
    triggered=true
  fi

  if [ "$triggered" = "$expect_trigger" ]; then
    return 0
  else
    echo "  FAIL trigger: '$phrase' — expected triggered=$expect_trigger, got $triggered"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

# Feed the loops via process substitution, not a pipe: the right side of a
# pipe runs in a subshell, so FAILURES increments there never reached the
# parent and the suite always exited 0 ("All evals passed").
if [[ "$MODE" == "all" || "$MODE" == "--cases" ]]; then
  echo "=== evals/evals.json ==="
  while read -r case_json; do
    id=$(echo "$case_json" | jq -r '.id')
    prompt=$(echo "$case_json" | jq -r '.prompt')
    run_case "$id" "$prompt"
  done < <(jq -c '.test_cases[]' evals/evals.json)
fi

if [[ "$MODE" == "all" || "$MODE" == "--triggers" ]]; then
  echo
  echo "=== evals/trigger-queries.json ==="
  while read -r p; do run_trigger "$p" true  || true; done < <(jq -r '.should_trigger[]' evals/trigger-queries.json)
  while read -r p; do run_trigger "$p" false || true; done < <(jq -r '.should_not_trigger[]' evals/trigger-queries.json)
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All evals passed."
  exit 0
else
  echo "$FAILURES eval(s) failed."
  exit 1
fi
