#!/usr/bin/env bats
# Unit tests for scripts/teams-config.sh.
# Covers: enable creates/merges, disable preserves other keys, status
# reports the three states, idempotency, jq merge correctness.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/teams-config.sh"
  WORK=$(mktemp -d)
  cd "$WORK"
}

teardown() {
  cd /
  rm -rf "$WORK"
}

@test "help flag exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Usage: teams-config.sh'
}

@test "no args prints help" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Usage:'
}

@test "unknown command exits 1" {
  run bash "$SCRIPT" bogus
  [ "$status" -eq 1 ]
}

@test "status when not configured reports not-configured" {
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"state": "not-configured"'
}

@test "enable from scratch creates file with env key" {
  run bash "$SCRIPT" enable
  [ "$status" -eq 0 ]
  [ -f .claude/settings.local.json ]
  result=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' .claude/settings.local.json)
  [ "$result" = "1" ]
}

@test "status after enable reports active" {
  bash "$SCRIPT" enable >/dev/null
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"state": "active"'
  echo "$output" | grep -q '"env_value": "1"'
}

@test "enable is idempotent" {
  bash "$SCRIPT" enable >/dev/null
  run bash "$SCRIPT" enable
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'already active'
  # File still has exactly one env entry with value "1"
  result=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' .claude/settings.local.json)
  [ "$result" = "1" ]
}

@test "enable preserves pre-existing unrelated keys" {
  mkdir -p .claude
  cat > .claude/settings.local.json <<'JSON'
{
  "theme": "dark",
  "permissions": { "allow": ["Bash(git *)"] }
}
JSON
  run bash "$SCRIPT" enable
  [ "$status" -eq 0 ]
  theme=$(jq -r '.theme' .claude/settings.local.json)
  allow=$(jq -r '.permissions.allow[0]' .claude/settings.local.json)
  flag=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' .claude/settings.local.json)
  [ "$theme" = "dark" ]
  [ "$allow" = "Bash(git *)" ]
  [ "$flag" = "1" ]
}

@test "enable preserves pre-existing env keys" {
  mkdir -p .claude
  cat > .claude/settings.local.json <<'JSON'
{
  "env": {
    "DEBUG": "true",
    "SOME_OTHER": "x"
  }
}
JSON
  run bash "$SCRIPT" enable
  [ "$status" -eq 0 ]
  debug=$(jq -r '.env.DEBUG' .claude/settings.local.json)
  other=$(jq -r '.env.SOME_OTHER' .claude/settings.local.json)
  flag=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' .claude/settings.local.json)
  [ "$debug" = "true" ]
  [ "$other" = "x" ]
  [ "$flag" = "1" ]
}

@test "disable removes only the flag, preserves other env keys" {
  mkdir -p .claude
  cat > .claude/settings.local.json <<'JSON'
{
  "env": {
    "DEBUG": "true",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "theme": "dark"
}
JSON
  run bash "$SCRIPT" disable
  [ "$status" -eq 0 ]
  debug=$(jq -r '.env.DEBUG' .claude/settings.local.json)
  flag=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // "absent"' .claude/settings.local.json)
  theme=$(jq -r '.theme' .claude/settings.local.json)
  [ "$debug" = "true" ]
  [ "$flag" = "absent" ]
  [ "$theme" = "dark" ]
}

@test "disable removes env object when it becomes empty" {
  mkdir -p .claude
  cat > .claude/settings.local.json <<'JSON'
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "theme": "dark"
}
JSON
  run bash "$SCRIPT" disable
  [ "$status" -eq 0 ]
  env_exists=$(jq 'has("env")' .claude/settings.local.json)
  theme=$(jq -r '.theme' .claude/settings.local.json)
  [ "$env_exists" = "false" ]
  [ "$theme" = "dark" ]
}

@test "disable when not configured is no-op" {
  run bash "$SCRIPT" disable
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'not configured'
  [ ! -f .claude/settings.local.json ]
}

@test "disable when already inactive is no-op" {
  mkdir -p .claude
  echo '{"theme": "dark"}' > .claude/settings.local.json
  run bash "$SCRIPT" disable
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'already inactive'
  theme=$(jq -r '.theme' .claude/settings.local.json)
  [ "$theme" = "dark" ]
}

@test "status emits valid JSON" {
  bash "$SCRIPT" enable >/dev/null
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "active"'
}
