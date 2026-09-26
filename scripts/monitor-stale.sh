#!/usr/bin/env bash
# Stale-story check: one pass over .epic/stories, one stdout line per story
# with no progress past its threshold. The story list runs it
# (references/list-mode.md); nothing runs it in the background.
#
# TWO rules, one measurement (see find_stale):
#   - every scale but spike — pending `[ ]` work untouched past the story
#     threshold (7 days by default)
#   - `scale: spike` — a `## Verdict` still not concluded past the spike
#     threshold (14 days by default): a spike's deadline is its answer,
#     not its boxes
#
# Thresholds come as arguments. Commands Claude runs through the Bash tool do
# not receive plugin options as environment variables, so the caller passes
# the values SKILL.md's Plugin options section shows.

set -euo pipefail

USAGE='Usage: monitor-stale.sh [--once] [--story-days N] [--spike-days N]
  one pass on stdout, then exit 0
  --story-days N  days before pending [ ] work is stale (default 7)
  --spike-days N  days before an open spike Verdict is stale (default 14)
  --once          accepted for compatibility; every run is a single pass'

THRESHOLD_DAYS=7
SPIKE_THRESHOLD_DAYS=14
while [ "$#" -gt 0 ]; do
  case "$1" in
    --once) shift ;;
    --story-days) [ "$#" -ge 2 ] || { printf '%s\n' "$USAGE" >&2; exit 2; }; THRESHOLD_DAYS="$2"; shift 2 ;;
    --spike-days) [ "$#" -ge 2 ] || { printf '%s\n' "$USAGE" >&2; exit 2; }; SPIKE_THRESHOLD_DAYS="$2"; shift 2 ;;
    --help | -h) printf '%s\n' "$USAGE"; exit 0 ;;
    *) printf '%s\n' "$USAGE" >&2; exit 2 ;;
  esac
done

# A non-numeric value (an unsaved option's literal placeholder included)
# falls back to the default rather than failing the listing.
[[ "$THRESHOLD_DAYS" =~ ^[0-9]+$ ]] || THRESHOLD_DAYS=7
[[ "$SPIKE_THRESHOLD_DAYS" =~ ^[0-9]+$ ]] || SPIKE_THRESHOLD_DAYS=14

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

    # ONE mtime read, hoisted above both rules. The THRESHOLD
    # differs per scale; the MEASUREMENT must not. A second `stat` down in the
    # spike branch would be a second dialect of "how old is this story?" — the
    # exact duplication the story's constraint forbids.
    local mtime
    mtime=$(stat -c %Y "$tasks_file" 2>/dev/null || stat -f %m "$tasks_file" 2>/dev/null || echo "$now_epoch")
    local story_name
    story_name="${tasks_file%/tasks.md}"
    story_name="${story_name##*/}"
    local days_stale=$(( (now_epoch - mtime) / 86400 ))

    # A spike's deadline is its VERDICT, and this rule
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
    # `[ ]`: a `[~]` box is closed by grammar — the work was waived,
    # ruled n-a, superseded, or deferred to an external actor — so a story
    # whose only non-`[x]` boxes are `[~]` is not sitting on pending work and
    # must never be nagged about.
    # This is the DELIBERATE EXCEPTION to the `[ x~]` class used by
    # validate-story.sh and cross-reference.sh. Those
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

find_stale
exit 0
