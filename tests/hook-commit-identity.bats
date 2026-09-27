#!/usr/bin/env bats
# scripts/hook-commit-identity-guard.sh — a commit is authored by the identity
# git already has. A headless run on a repository with no identity committed
# as the account's name and e-mail, passed with `git -c`; these cases pin that
# every inline identity is denied and every ordinary git call passes.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# decide <command> → prints "deny" or "allow"
decide() {
  out=$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' \
    | bash "$ROOT/scripts/hook-commit-identity-guard.sh")
  if [ -n "$out" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null; then
    echo deny
  else
    echo allow
  fi
}

@test "I1: the exact command the headless run used is denied" {
  [ "$(decide 'cd /tmp/w; epic-close 001 1.1; git add a.js && git -c user.name=lucascs -c user.email=l@example.invalid commit -q -m "chore(001): x"')" = deny ]
}

@test "I2: --author and GIT_AUTHOR/GIT_COMMITTER variables are denied" {
  [ "$(decide 'git commit --author="A <a@example.invalid>" -m x')" = deny ]
  [ "$(decide 'GIT_AUTHOR_EMAIL=a@example.invalid git commit -m x')" = deny ]
  [ "$(decide 'GIT_COMMITTER_NAME=A git commit -m x')" = deny ]
}

@test "I3: writing an identity with git config is denied, in any scope" {
  [ "$(decide 'git config user.email a@example.invalid')" = deny ]
  [ "$(decide 'git config --global user.name "A B"')" = deny ]
  [ "$(decide 'git config --local user.email a@example.invalid && git commit -m x')" = deny ]
}

@test "I4: reading the identity and an ordinary commit pass" {
  [ "$(decide 'git config user.email')" = allow ]
  [ "$(decide 'git config --get user.name; git log -1')" = allow ]
  [ "$(decide 'git add a.js && git commit -q -m "feat(001): add a"')" = allow ]
  [ "$(decide 'npm test')" = allow ]
}

@test "I5: the deny tells the model what to do instead" {
  out=$(jq -n '{tool_name: "Bash", tool_input: {command: "git -c user.email=a@example.invalid commit -m x"}}' \
    | bash "$ROOT/scripts/hook-commit-identity-guard.sh")
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'do not commit'
}

@test "I6: hooks.json registers the guard on every Bash call, with no if filter" {
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
         | select(.command | test("hook-commit-identity-guard.sh")) | select(has("if") | not)' \
    "$ROOT/hooks/hooks.json" > /dev/null
}

@test "I7: run-mode.md states the rule the guard enforces" {
  grep -q '\*\*Commit as the identity git already has — never supply one.\*\*' "$ROOT/references/run-mode.md"
}
