#!/usr/bin/env bats
# The per-agent reasoning-effort policy is DATA the suite reads, not a sentence
# someone remembers to keep true.
#
# WHAT IS PINNED, AND WHY EACH ONE. The Validator runs at `medium` because its
# verification is mechanical. The Auditor and the Executor stay at `max` —
# they carry the judgment that trade-off relies on, so a silent drop there
# would remove the safety net while leaving the saving in place. The Analyst is
# pinned at `medium`: its work is discovery — it scans structure, samples
# representative files and reports what it found.
#
# NO CASE HERE ASSERTS HOW MANY AGENTS THERE ARE. A count goes stale the first
# time an agent is added. The sweep derives the set from `agents/*.md` and
# checks a property of each member instead, so a new agent is caught by its own
# frontmatter rather than by a number nobody updated.

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  AGENTS="$PLUGIN_ROOT/agents"
}

@test "the Validator declares medium" {
  run grep -c '^effort: medium' "$AGENTS/validator.md"
  if [ "$output" != "1" ]; then
    echo "agents/validator.md must declare exactly one 'effort: medium' line; grep -c answered '$output'"
    echo "it currently declares: $(grep -m1 '^effort:' "$AGENTS/validator.md")"
    return 1
  fi
}

@test "judgment stays at max — the Auditor and the Executor declare max" {
  for a in auditor executor; do
    run grep -c '^effort: max' "$AGENTS/$a.md"
    if [ "$output" != "1" ]; then
      echo "agents/$a.md must declare exactly one 'effort: max' line; grep -c answered '$output'"
      echo "it currently declares: $(grep -m1 '^effort:' "$AGENTS/$a.md")"
      return 1
    fi
  done
}

@test "the Analyst declares medium" {
  run grep -c '^effort: medium' "$AGENTS/analyst.md"
  if [ "$output" != "1" ]; then
    echo "agents/analyst.md must declare exactly one 'effort: medium' line; grep -c answered '$output'"
    return 1
  fi
}

@test "every agent declares exactly one effort line, and its value is sanctioned" {
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

# The documented table is the DECLARED side and the frontmatters are the
# DERIVATION, so ARCHITECTURE.md cannot drift from the tree in silence. This
# case is what makes the doc's claim ("the policy test enforces the table")
# true; without it the doc would say it is guarded and nothing would guard it.
@test "ARCHITECTURE.md's effort table matches the frontmatters, agent for agent" {
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
