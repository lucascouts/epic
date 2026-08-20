#!/usr/bin/env bats
# Story 012, sub-task 1.1 — the per-agent reasoning-effort policy is DATA the
# suite reads, not a sentence someone remembers to keep true.
#
# WHAT IS PINNED, AND WHY EACH ONE. The Validator drops to `medium`: that is
# the change this story buys, measured at 44% of all Epic sessions doing
# majority-mechanical work. The Auditor and the Executor stay at `max` — they
# are the mitigation the trade-off was priced against, so a silent drop there
# would remove the safety net while leaving the saving in place. The Analyst is
# pinned at `medium` because it is the precedent the change cites.
#
# NO CASE HERE ASSERTS HOW MANY AGENTS THERE ARE. A count is the shape that
# goes stale the first time an agent is added — story 017's lesson, one
# directory over. The sweep derives the set from `agents/*.md` and checks a
# property of each member instead, so a ninth agent is caught by its own
# frontmatter rather than by a number nobody updated.

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  AGENTS="$PLUGIN_ROOT/agents"
}

@test "1.1: the Validator declares medium — the tier this story buys" {
  run grep -c '^effort: medium' "$AGENTS/validator.md"
  if [ "$output" != "1" ]; then
    echo "agents/validator.md must declare exactly one 'effort: medium' line; grep -c answered '$output'"
    echo "it currently declares: $(grep -m1 '^effort:' "$AGENTS/validator.md")"
    return 1
  fi
}

@test "1.1: judgment stays at max — the Auditor and the Executor are the mitigation" {
  for a in auditor executor; do
    run grep -c '^effort: max' "$AGENTS/$a.md"
    if [ "$output" != "1" ]; then
      echo "agents/$a.md must declare exactly one 'effort: max' line; grep -c answered '$output'"
      echo "it currently declares: $(grep -m1 '^effort:' "$AGENTS/$a.md")"
      return 1
    fi
  done
}

@test "1.1: the Analyst's medium is the precedent this change cites, and it still stands" {
  run grep -c '^effort: medium' "$AGENTS/analyst.md"
  if [ "$output" != "1" ]; then
    echo "agents/analyst.md must declare exactly one 'effort: medium' line; grep -c answered '$output'"
    return 1
  fi
}

@test "1.1: every agent declares exactly one effort line, and its value is sanctioned" {
  shopt -s nullglob
  local offenders=() seen=0 f name count value

  for f in "$AGENTS"/*.md; do
    seen=$((seen + 1))
    name=$(basename "$f")
    count=$(grep -c '^effort:' "$f" || true)
    if [ "$count" != "1" ]; then
      offenders+=("$name: declares $count 'effort:' lines, expected exactly 1")
      continue
    fi
    value=$(grep -m1 '^effort:' "$f" | sed 's/^effort:[[:space:]]*//')
    case "$value" in
      medium|high|max) ;;
      *) offenders+=("$name: effort '$value' is outside the sanctioned set {medium, high, max}") ;;
    esac
  done

  # An empty agents/ directory would satisfy every loop above while measuring
  # nothing. Asserting the sweep saw somebody kills that without writing down
  # how many somebodies there are.
  if [ "$seen" -eq 0 ]; then
    echo "the sweep read no file at all under $AGENTS — the glob, not the policy, is what went green"
    return 1
  fi

  if [ "${#offenders[@]}" -gt 0 ]; then
    printf '%s\n' "${offenders[@]}"
    return 1
  fi
}

# Sub-task 1.2 — the documented table is the DECLARED side and the frontmatters
# are the DERIVATION, so ARCHITECTURE.md cannot drift from the tree in silence.
# This case is what makes 1.2's own claim ("the policy test enforces the table")
# true; without it the doc would say it is guarded and nothing would guard it,
# which is the defect story 020 spent itself closing one directory over.
@test "1.2: ARCHITECTURE.md's effort table matches the frontmatters, agent for agent" {
  local doc="$PLUGIN_ROOT/ARCHITECTURE.md" declared actual

  declared=$(awk -F'|' '
    $2 ~ /^ `[a-z-]+` $/ && $3 ~ /^ `(medium|high|max)` $/ {
      a = $2; e = $3; gsub(/[ `]/, "", a); gsub(/[ `]/, "", e); print a, e
    }' "$doc" | sort)

  if [ -z "$declared" ]; then
    echo "ARCHITECTURE.md carries no parseable effort table — expected rows shaped"
    echo "  | \`<agent>\` | \`<medium|high|max>\` | <why> |"
    return 1
  fi

  actual=$(for f in "$AGENTS"/*.md; do
    printf '%s %s\n' "$(basename "$f" .md)" "$(grep -m1 '^effort:' "$f" | sed 's/^effort:[[:space:]]*//')"
  done | sort)

  if [ "$declared" != "$actual" ]; then
    echo "the table in ARCHITECTURE.md and the agent frontmatters disagree"
    echo "(< = documented, > = declared in agents/):"
    diff <(printf '%s\n' "$declared") <(printf '%s\n' "$actual") || true
    return 1
  fi
}
