#!/usr/bin/env bash
# Background monitor: detects epic stories with no progress past a staleness
# threshold. Each stdout line becomes a notification to the main agent.
#
# Lifecycle: started by monitors/monitors.json on the first /epic:task
# invocation (when: on-skill-invoke:task).
#
# The Claude Code runtime — not this script — is responsible for skipping
# plugin monitors on Bedrock/Vertex/Foundry and when DISABLE_TELEMETRY or
# CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC are set. See plugins-reference#monitors.
#
# Opt-in: the user activates the monitor by setting the plugin option
# `enableStaleMonitor=true` (surfaced via userConfig in plugin.json). When
# unset, the monitor exits immediately without polling.

set -euo pipefail

ENABLED="${CLAUDE_PLUGIN_OPTION_ENABLESTALEMONITOR:-false}"
if [ "$ENABLED" != "true" ]; then
  exit 0
fi

# Both parameters are configurable via userConfig in plugin.json and
# injected as environment variables at plugin load:
#   CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS      — default 7
#   CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS — default 3600
# The defaults below apply when the options are unset (older plugin
# installs or explicit user override to empty string).
THRESHOLD_DAYS="${CLAUDE_PLUGIN_OPTION_STALETHRESHOLDDAYS:-7}"
POLL_INTERVAL_SECONDS="${CLAUDE_PLUGIN_OPTION_STALECHECKINTERVALSECONDS:-3600}"

# Guard against non-numeric overrides.
[[ "$THRESHOLD_DAYS" =~ ^[0-9]+$ ]] || THRESHOLD_DAYS=7
[[ "$POLL_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || POLL_INTERVAL_SECONDS=3600

find_stale() {
  local now_epoch
  now_epoch=$(date +%s)
  local cutoff=$((now_epoch - THRESHOLD_DAYS * 86400))

  for tasks_file in .epic/stories/*/tasks.md; do
    [ -f "$tasks_file" ] || continue

    # Skip stories with no incomplete tasks.
    if ! grep -qE '^\s*- \[ \]' "$tasks_file" 2>/dev/null; then
      continue
    fi

    local mtime
    mtime=$(stat -c %Y "$tasks_file" 2>/dev/null || stat -f %m "$tasks_file" 2>/dev/null || echo "$now_epoch")

    if [ "$mtime" -lt "$cutoff" ]; then
      local story_dir
      story_dir=$(dirname "$tasks_file")
      local story_name
      story_name=$(basename "$story_dir")
      local days_stale=$(( (now_epoch - mtime) / 86400 ))
      echo "Epic story '${story_name}' has pending tasks untouched for ${days_stale} days."
    fi
  done
}

while true; do
  find_stale
  sleep "$POLL_INTERVAL_SECONDS"
done
