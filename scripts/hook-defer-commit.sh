#!/usr/bin/env bash
# PreToolUse hook: defers git commit calls in headless CI sessions so a
# wrapper (GitHub Actions, Slack approval bot, etc.) can gate the commit
# before the session resumes.
#
# In interactive sessions, exits 0 silently — the normal permission flow
# handles approval. The "defer" decision is only valid in -p mode.
#
# Detection: CI=true (GitHub Actions, GitLab CI, etc.) or an explicit
# CLAUDE_CODE_HEADLESS=true set by the caller.

set -euo pipefail

if [ "${CI:-}" = "true" ] || [ "${CLAUDE_CODE_HEADLESS:-}" = "true" ]; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}
JSON
fi

exit 0
