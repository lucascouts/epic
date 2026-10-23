#!/usr/bin/env bats
# Story 028 — the security and infra rules that hold for any project, moved
# from a personal CLAUDE.md into the plugin: the CI mirror, the audit report's
# untested/verified_at keys, per-language secure-coding rules, the log rules,
# the supply-chain items and the eval/exec rule.
#
# The surface is agent-executed prose, so every case asserts keywords inside
# the block that carries the rule — a whole-file grep would pass on a mention
# in the wrong place. No case requires a sentence verbatim.
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."
CATALOG="$ROOT/references/quality-catalog.md"

section() { # section <file> <start regex> <end regex>
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

row() { # row <block> <item> — the table line whose first cell is <item>
  printf '%s\n' "$1" | command grep -F -- "| $2 |" | head -1
}

has() { # has <label> <block> <extended regex> — case-insensitive
  if ! printf '%s' "$2" | command grep -Eqi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

# --- R1: the CI mirror -------------------------------------------------------

@test "S1: CI mirror is a By context row with the workflows signal and act -j" {
  ctx=$(section "$CATALOG" '^## By context' '^## ')
  r=$(row "$ctx" "CI mirror")
  [ -n "$r" ]
  has "S1 signal" "$r" '`\.github/workflows/`'
  has "S1 command" "$r" '`act -j <job>`'
}

@test "S2: the CI mirror row mirrors the runner's clean checkout" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "CI mirror")
  has "S2 clean" "$r" 'clean checkout'
  has "S2 artifacts" "$r" 'build artifacts'
  has "S2 deps" "$r" 'dependenc'
  has "S2 env" "$r" '`\.env`'
}

@test "S3: the CI mirror row names the root false red and the normal-user run" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "CI mirror")
  has "S3 unreadable" "$r" 'unreadable'
  has "S3 root" "$r" 'root'
  has "S3 normal user" "$r" 'normal user'
}

@test "S4: product activates the CI mirror — in the catalog's level bound" {
  line=$(command grep -F 'The engineering level bounds the set' "$CATALOG")
  [ -n "$line" ]
  product=${line#*\`product\`}
  has "S4 product" "$product" 'CI mirror'
}

@test "S5: product activates the CI mirror — in engineering-level.md's product cell" {
  pays=$(section "$ROOT/references/engineering-level.md" '^## What each level pays for' '^## ')
  r=$(printf '%s\n' "$pays" | command grep -F '**Quality catalog**')
  [ -n "$r" ]
  product=$(printf '%s' "$r" | awk -F' [|] ' '{print $NF}')
  has "S5 product" "$product" 'CI mirror'
}

# --- R4: logs that cannot leak, tracing on request ---------------------------

@test "S6: the logs row forbids secrets and PII, redacted at the logger" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Structured logs and health")
  [ -n "$r" ]
  has "S6 secret" "$r" 'secret'
  has "S6 token" "$r" 'token'
  has "S6 credential" "$r" 'credential'
  has "S6 pii" "$r" 'PII'
  has "S6 at the logger" "$r" 'redact[a-z]* at the logger'
}

@test "S7: the logs row gives each level a meaning and a level switch with no redeploy" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Structured logs and health")
  has "S7 error" "$r" 'ERROR[^|]*human'
  has "S7 warn" "$r" 'WARN[^|]*(degraded|recovered)'
  has "S7 info" "$r" 'INFO[^|]*business event'
  has "S7 debug" "$r" 'DEBUG[^|]*off in production'
  has "S7 no redeploy" "$r" 'without a redeploy'
}

@test "S8: tracing (OpenTelemetry) is an on-request row" {
  req=$(section "$CATALOG" '^## On request' '^## ')
  r=$(row "$req" "Tracing (OpenTelemetry)")
  [ -n "$r" ]
}

# --- R5: supply-chain items --------------------------------------------------

@test "S9: the security-floor Secrets row keeps its exact text" {
  floor=$(section "$CATALOG" '^### The security floor' '^## ')
  r=$(row "$floor" "Secrets")
  [ "$r" = '| Secrets | a credential leaked from a script leaks exactly as far as one leaked from a product | `gitleaks detect` |' ]
}

@test "S10: trufflehog is the CI-side scanner of the always-tier Secrets row" {
  # `### The security floor` sits inside `## Always`, so the always tier is
  # scoped to end at that heading — a mention in the floor row must not count.
  always=$(section "$CATALOG" '^## Always' '^### The security floor')
  r=$(row "$always" "Secrets")
  [ -n "$r" ]
  has "S10 trufflehog" "$r" '`trufflehog'
  has "S10 ci" "$r" 'CI'
  has "S10 gitleaks kept" "$r" '`gitleaks'
}

@test "S11: Harden-Runner is named in the Hardened workflows row" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Hardened workflows")
  [ -n "$r" ]
  has "S11 harden-runner" "$r" 'Harden-Runner'
}

@test "S12: Scorecard and Socket are on-request rows" {
  req=$(section "$CATALOG" '^## On request' '^## ')
  [ -n "$(row "$req" "Repo posture score (OpenSSF Scorecard)")" ]
  [ -n "$(row "$req" "Behavioural malware scan (Socket)")" ]
}

# --- R1.4: the CI mirror gate without a container runtime --------------------

ci_mirror_rule() { # ci_mirror_rule <label> <block> — the rule sits on one line
  line=$(printf '%s\n' "$2" | command grep -F 'CI mirror' | command grep -F 'not run — no container runtime' | head -1)
  if [ -z "$line" ]; then
    echo "$1: no line names the CI mirror gate as 'not run — no container runtime'" >&2
    return 1
  fi
  has "$1 docker" "$line" 'docker'
  has "$1 podman" "$line" 'podman'
  has "$1 not a failure" "$line" 'never (a )?FAIL|not a failure'
}

@test "S13: validate-mode.md settles the CI mirror gate as not run without Docker or Podman" {
  part1=$(section "$ROOT/references/validate-mode.md" '^## Validation — Part 1' '^## ')
  ci_mirror_rule "S13" "$part1"
}

@test "S14: the validation protocol the Auditor runs carries the same rule" {
  proto=$(section "$ROOT/references/validation-protocol.md" '^Then settle the' '^Then write')
  ci_mirror_rule "S14" "$proto"
}
