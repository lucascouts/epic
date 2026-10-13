#!/usr/bin/env bats
# epic-report: the two Auditor reports, read for the orchestrator in summary.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  S=$(mktemp -d)
  mkdir -p "$S/.draft"
  printf 'story: "004-x"\ngenerated_at: "2026-10-13T10:00:00Z"\nverdict: pass\nresults:\n  - task: "1.1"\n    status: PASS\n  - task: "1.2"\n    status: PASS\ngates: []\n' > "$S/.draft/validation-report.yaml"
  printf 'story: "004-x"\nverdict: fail-record   # register only\ngaps: []\nrecord_issues:\n  - record: ".draft/deviations.yaml"\n    entry: "2"\n    fix: "impact: two callers"\nfindings:\n  - severity: info\n    detail: "naming"\n  - severity: warning\n    detail: "dead code"\nnot_verified: []\n' > "$S/.draft/audit-report.yaml"
}

teardown() {
  rm -rf "$S"
}

@test "summary: both verdicts and the size of every list, nothing else" {
  run bash "$PLUGIN_ROOT/scripts/report.sh" --story "$S"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.validation == {"present":true,"verdict":"pass","story":"004-x","lists":{"results":2,"gates":0}}'
  echo "$output" | jq -e '.audit.verdict == "fail-record" and .audit.lists == {"gaps":0,"record_issues":1,"findings":2,"not_verified":0}'
  [[ "$output" != *"dead code"* ]]
}

@test "--list prints one list's items as written; a missing report is present: false" {
  run bash "$PLUGIN_ROOT/scripts/report.sh" --story "$S" --list record_issues
  [ "$status" -eq 0 ]
  [[ "$output" == *'fix: "impact: two callers"'* ]]
  [[ "$output" != *"findings"* ]]
  rm "$S/.draft/audit-report.yaml"
  run bash "$PLUGIN_ROOT/scripts/report.sh" --story "$S"
  echo "$output" | jq -e '.audit == {"present": false}'
  run bash "$PLUGIN_ROOT/scripts/report.sh" --story /nope
  [ "$status" -eq 2 ]
}
