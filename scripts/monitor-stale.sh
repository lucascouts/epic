#!/usr/bin/env bash
# Background monitor: detects epic stories with no progress past a staleness
# threshold. Each stdout line becomes a notification to the main agent.
#
# TWO rules, one measurement (see find_stale):
#   - every scale but spike — pending `[ ]` work untouched past the story
#     threshold (7 days by default)
#   - `scale: spike` — a `## Verdict` still not concluded past the spike
#     threshold (14 days, story 007 R1.5): a spike's deadline is its answer,
#     not its boxes
#
# Lifecycle: started by monitors/monitors.json on the first /epic:epic
# invocation (when: on-skill-invoke:epic).
#
# The Claude Code runtime — not this script — is responsible for skipping
# plugin monitors on Bedrock/Vertex/Foundry and when DISABLE_TELEMETRY or
# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC are set. See plugins-reference#monitors.
#
# Opt-in: the user activates the monitor by setting the plugin option
# `enableStaleMonitor=true` (surfaced via userConfig in plugin.json). When
# unset, the monitor exits immediately without polling. The option governs the
# LOOP only — `--once` is a synchronous single pass a command asks for, and it
# answers whether or not the watcher was ever enabled (see the Mode block).

set -euo pipefail

USAGE='Usage: monitor-stale.sh [--once]
  (no argument)  background loop: one pass every staleCheckIntervalSeconds,
                 and only when the enableStaleMonitor option is true
  --once         one pass on stdout, then exit 0 — the synchronous read a
                 command makes (references/list-mode.md), never the loop'

# --- Mode ---------------------------------------------------------------
# Parsed BEFORE the opt-in gate on purpose. `enableStaleMonitor` governs the
# BACKGROUND WATCHER — the thing that polls unasked — and nothing else. `--once`
# is a synchronous read inside a command the user just typed, and R1.5 asks for
# the spike flag "in the story list" unconditionally; gating it on an option
# that defaults to false would leave that requirement unmet for every default
# install. Do NOT "simplify" by moving the gate above this block.
MODE="monitor"
if [ "$#" -gt 1 ]; then
  printf '%s\n' "$USAGE" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  case "$1" in
    --once) MODE="once" ;;
    --help | -h)
      printf '%s\n' "$USAGE"
      exit 0
      ;;
    *)
      printf '%s\n' "$USAGE" >&2
      exit 2
      ;;
  esac
fi

ENABLED="${CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR:-false}"
if [ "$MODE" = "monitor" ] && [ "$ENABLED" != "true" ]; then
  exit 0
fi

# All three parameters are configurable via userConfig in plugin.json and
# injected as environment variables at plugin load:
#   CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS        — default 7
#   CLAUDE_PLUGIN_OPTION_SPIKESTALETHRESHOLDDAYS   — default 14
#   CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS — default 3600
# The defaults below apply when the options are unset (older plugin
# installs or explicit user override to empty string).
#
# THIS IS WHERE THE 14 DAYS LIVES (story 007 R1.5). references/list-mode.md
# renders the flag and points here for the number; nothing else re-derives it,
# and no consumer runs its own `stat` — see find_stale. The spike threshold is
# a SEPARATE knob from the story one so that lengthening the story nag does not
# silently move a spike's deadline: they measure different things.
THRESHOLD_DAYS="${CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS:-7}"
SPIKE_THRESHOLD_DAYS="${CLAUDE_PLUGIN_OPTION_SPIKESTALETHRESHOLDDAYS:-14}"
POLL_INTERVAL_SECONDS="${CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS:-3600}"

# Guard against non-numeric overrides.
[[ "$THRESHOLD_DAYS" =~ ^[0-9]+$ ]] || THRESHOLD_DAYS=7
[[ "$SPIKE_THRESHOLD_DAYS" =~ ^[0-9]+$ ]] || SPIKE_THRESHOLD_DAYS=14
[[ "$POLL_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || POLL_INTERVAL_SECONDS=3600

# --- Spike readers ------------------------------------------------------
# Both are pure bash: they run for every story on every pass of a background
# loop, and a fork per story per hour buys nothing a `while read` does not.
# `\r?` throughout tolerates a CRLF checkout — a delimiter test that rejects
# `\r` does not fail loudly, it just makes every artifact look frontmatter-less
# (the same trap archive-story.sh documents at FM_DELIM_RE).

# declares_spike_scale <tasks.md> — true when the file's OWN frontmatter says
# `scale: spike`. A spike is tasks-only, so tasks.md is the only place that
# declaration can be: there is no story.md here to read it from.
declares_spike_scale() {
  local file="$1" line first=true
  local delim_re=$'^---\r?$'
  # Anchored at column 0 like the templates write it, so a nested or compound
  # key can never fake the value; a trailing YAML comment is tolerated, as it is
  # in archive-story.sh's frontmatter_field. `[[:space:]]` already covers the
  # `\r` of a CRLF line, so no explicit `\r?` is needed here.
  local scale_re='^scale:[[:space:]]*spike[[:space:]]*(#.*)?$'
  {
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$first" = true ]; then
        first=false
        # No opening delimiter: no frontmatter, so nothing was declared.
        if ! [[ "$line" =~ $delim_re ]]; then
          return 1
        fi
        continue
      fi
      # Closing delimiter: the block ended without saying `scale: spike`.
      if [[ "$line" =~ $delim_re ]]; then
        return 1
      fi
      if [[ "$line" =~ $scale_re ]]; then
        return 0
      fi
    done
    :
  } 2>/dev/null < "$file" || return 1
  return 1
}

# verdict_status <tasks.md> — the `status:` of the spike's `## Verdict`, or
# nothing when there is no readable one.
#
# The GRAMMAR — heading_re, verdict_re, status_re — is copied VERBATIM from the
# parse_verdict shared by scripts/epic-index.sh, scripts/archive-story.sh and
# scripts/validate-story.sh. FOUR readers of that grammar now, and if 007 ever
# amends it all four move together. This is the only PARTIAL one: staleness
# keys on the status alone, so the fourth regex there (`promoted-to:`) is
# deliberately absent — a `promote` with no target recorded is still a DECIDED
# verdict, and nagging "promote or close" at it would state something false;
# reporting the missing target is validate-story.sh's job, not a monitor's.
verdict_status() {
  local file="$1" line in_verdict=false
  local heading_re='^#{2,}[[:space:]]'
  local verdict_re='^#{2,}[[:space:]]+[Vv]erdict([[:space:]].*)?$'
  local status_re='^[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*([^[:space:]|]+)'
  {
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ $heading_re ]]; then
        # The section ends at the next `##`-or-deeper heading.
        if [[ "$line" =~ $verdict_re ]]; then in_verdict=true; else in_verdict=false; fi
        continue
      fi
      [ "$in_verdict" = true ] || continue
      # Only the FIRST status: line inside the section is read.
      if [[ "$line" =~ $status_re ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
      fi
    done
    :
  } 2>/dev/null < "$file" || return 0
  return 0
}

find_stale() {
  local now_epoch
  now_epoch=$(date +%s)
  local cutoff=$((now_epoch - THRESHOLD_DAYS * 86400))
  local spike_cutoff=$((now_epoch - SPIKE_THRESHOLD_DAYS * 86400))

  for tasks_file in .epic/stories/*/tasks.md; do
    [ -f "$tasks_file" ] || continue

    # ONE mtime read, hoisted above both rules (story 007). The THRESHOLD
    # differs per scale; the MEASUREMENT must not. A second `stat` down in the
    # spike branch would be a second dialect of "how old is this story?" — the
    # exact duplication the story's constraint forbids.
    local mtime
    mtime=$(stat -c %Y "$tasks_file" 2>/dev/null || stat -f %m "$tasks_file" 2>/dev/null || echo "$now_epoch")
    local story_name
    story_name="${tasks_file%/tasks.md}"
    story_name="${story_name##*/}"
    local days_stale=$(( (now_epoch - mtime) / 86400 ))

    # A spike's deadline is its VERDICT (story 007 R1.5), and this rule
    # REPLACES the pending-work rule below rather than adding to it. A spike's
    # boxes are probe steps, not a contract — the same reading archive-story.sh
    # makes when it lets the Verdict alone decide completion — so an open box
    # in a spike is not work owed: a spike that already concluded would
    # otherwise be nagged forever about probe steps nobody will ever tick.
    if declares_spike_scale "$tasks_file"; then
      case "$(verdict_status "$tasks_file")" in
        # Terminal: the question was answered, so there is nothing left to nag
        # about whatever the checkboxes still say. (`continue` here leaves the
        # for loop — a case is not a loop.)
        promote | wont-do) continue ;;
      esac
      # Everything else — `open`, absent, unreadable, an invented value — counts
      # as NOT concluded: fail-closed, like every other reader of this grammar.
      # A Verdict nobody can read is not a conclusion.
      if [ "$mtime" -lt "$spike_cutoff" ]; then
        echo "Epic spike '${story_name}' has an open Verdict untouched for ${days_stale} days — promote or close."
      fi
      continue
    fi

    # Skip stories with no incomplete tasks. Pending work is `[ ]` and ONLY
    # `[ ]` (R4.3): a `[~]` box is closed by grammar — the work was waived,
    # ruled n-a, superseded, or deferred to an external actor — so a story
    # whose only non-`[x]` boxes are `[~]` is not sitting on pending work and
    # must never be nagged about.
    # This is the DELIBERATE EXCEPTION to the `[ x~]` class used by
    # validate-story.sh, cross-reference.sh and hook-task-completed.sh. Those
    # ask "is this line a task?" — all three box states are. This one asks
    # "is work still owed here?" — only `[ ]` is. Do NOT widen it to
    # `\[[ x~]\]` for the sake of consistency: that resurrects stale
    # notifications for work that was explicitly closed.
    if ! grep -qE '^\s*- \[ \]' "$tasks_file" 2>/dev/null; then
      continue
    fi

    if [ "$mtime" -lt "$cutoff" ]; then
      # The word "spike" never appears in this line: it is the generic nag, and
      # a consumer telling the two rules apart reads the first two words
      # (`Epic story` vs `Epic spike`).
      echo "Epic story '${story_name}' has pending tasks untouched for ${days_stale} days."
    fi
  done
}

if [ "$MODE" = "once" ]; then
  find_stale
  exit 0
fi

while true; do
  find_stale
  sleep "$POLL_INTERVAL_SECONDS"
done
