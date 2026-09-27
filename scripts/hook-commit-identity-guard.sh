#!/usr/bin/env bash
# PreToolUse hook: a commit is authored by the identity git already has, never
# by one the session supplies. It denies, for every agent and the orchestrator:
#   - a commit that forces its author: `git -c user.name=…`/`-c user.email=…`,
#     `--author`, or GIT_AUTHOR_*/GIT_COMMITTER_* set on the command line;
#   - writing an identity: `git config [scope] user.name|user.email <value>`.
# Reading an identity (`git config user.email`, `--get`) passes.
#
# Why a hook and not only a rule: a headless run on a repository with no
# identity committed as the account's name and e-mail, passed inline — the
# plugin put someone's name on a commit nobody asked them to sign.
#
# No `if` filter in hooks.json: `Bash(git commit *)` does not match
# `cd x; git -c user.email=… commit`, the exact shape that run used. The grep
# below exits in milliseconds on every command that is not git.

set -euo pipefail

INPUT=$(cat)
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
printf '%s' "$CMD" | grep -q 'git' || exit 0

REASON=""
if printf '%s' "$CMD" | grep -Eq '(^|[;&|(`[:space:]])git[[:space:]].*commit' &&
   printf '%s' "$CMD" | grep -Eq -- '-c[[:space:]]+user\.(name|email)=|--author([=[:space:]])|GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)='; then
  REASON="Commits use the identity git already has. Do not pass one on the command line."
elif printf '%s' "$CMD" | grep -Eq '(^|[;&|(`[:space:]])git[[:space:]]+config([[:space:]]+--(global|local|system|worktree|replace-all|add))*[[:space:]]+user\.(name|email)[[:space:]]+[^;&|[:space:]]'; then
  REASON="Never write a git identity on the user's behalf."
fi

[ -n "$REASON" ] || exit 0
REASON="$REASON When \`git config user.email\` is empty, do not commit: leave the changes uncommitted, and tell the user the two \`git config\` commands that set their identity, then the pending commit message to run."
jq -n --arg r "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
