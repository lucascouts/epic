#!/usr/bin/env bash
# Stop hook: a process word that reached a layperson with no legend blocks the
# end of the turn, once, naming each word.
#
# The words leak in short status lines written between tool calls ("Red
# confirmed, now the implementation") — never in the closing, which epic-jargon
# already checks. Asking the model not to narrate did not work (a plain-register
# rule and a PostToolUse hook both stayed within noise), so this hook does not
# ask: it reads every assistant text block of the turn from the transcript, runs
# jargon-check.sh over all of it, and when a term has no legend anywhere in the
# turn it asks for the legend in the closing (`*term* — what it means here`).
# A term without its meaning is the defect, not the term (plain-register.md).
#
# Only for a layperson: the newest live story's tasks.md carries `requester:
# layperson` in its frontmatter (references/tasks.md). Fails open, so a guard
# defect never traps a turn: unreadable input, a second stop attempt
# (stop_hook_active, the documented loop guard), no transcript, no live story,
# or a requester that is not `layperson`.

set -euo pipefail

INPUT=$(cat)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0
CWD=${CWD:-$PWD}
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")
[ -d "$ROOT/.epic/stories" ] || exit 0

# The newest live story is the one this turn is about.
NEWEST=$(find "$ROOT/.epic/stories" -mindepth 2 -maxdepth 2 -name tasks.md -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | head -n 1 | cut -d' ' -f2- || true)
[ -n "$NEWEST" ] || exit 0
LEVEL=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
             /^requester:[[:space:]]*/ { sub(/^requester:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }' "$NEWEST")
[ "$LEVEL" = "layperson" ] || exit 0

# The turn's assistant text: every text block after the last real user prompt (a
# tool result arrives as a user entry too, and does not start a turn).
TEXT=$(jq -rs '
  def prompt: .type == "user" and (
    (.message.content | type) == "string"
    or ([.message.content[]? | select(.type == "text")] | length > 0));
  (map(prompt) | rindex(true)) as $start
  | .[(($start // -1) + 1):]
  | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
  | join("\n")' "$TRANSCRIPT" 2>/dev/null || true)
[ -n "$TEXT" ] || exit 0

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jargon-check.sh"
RESULT=$(printf '%s\n' "$TEXT" | bash "$CHECK" 2>/dev/null || true)
TERMS=$(printf '%s' "$RESULT" | jq -r '[.hits[]?.term] | join(", ")' 2>/dev/null || true)
[ -n "$TERMS" ] || exit 0

jq -n --arg t "$TERMS" '{
  decision: "block",
  reason: ("These words reached the requester this turn with no legend: " + $t + ". End your closing with one legend line for each — `*term* — what it means here`, in the requester'"'"'s language and about this request — then end the turn. Do not mention this check or apologize for the words.")
}'
