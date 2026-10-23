#!/usr/bin/env bats
# epico-checkpoint: the mechanical step of a stage checkpoint — a stage's ROADMAP
# tasks against the stories that worked on them. Synthetic fixture, two stages.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  P=$(mktemp -d)
  mkdir -p "$P/.epico/archive" "$P/.epico/stories" "$P/docs"
  # Stage 1 in a single-file ROADMAP: a table row plus task lines.
  cat > "$P/docs/ROADMAP.md" <<'EOF'
| 1.1.1 | Set up the repository | Trivial | done |

## Stage 1

- [x] **1.1.1 Set up the repository** · Trivial · `done`
- [x] **1.1.2 Add the linter** · Simple · `done`
- [ ] **1.1.3 Write the guide** · Simple · `todo`
- [ ] **1.1.4 Pin the tools** · Medium · `todo`
- [x] **1.1.5 Reserve the domain** · Trivial · `done`
- [ ] **1.1.6 Add the dashboard** · High · `todo`

## Stage 2

- [ ] **2.1.1 The schema** · Medium · `todo`
EOF
  cat > "$P/.epico/archive/manifest.yaml" <<'EOF'
archived:
  - story: "001-repo"
    number: "001"
    roadmap: [1.1.1, 1.1.2]
    overrides_used: []
  - story: "002-old"
    number: "002"
    overrides_used: []
  - story: "003-tools"
    number: "003"
    roadmap: [1.1.4, 1.9.9]
    overrides_used: []
EOF
  mkdir -p "$P/.epico/stories/004-dash"
  printf -- '---\nversion: 1\nroadmap: [1.1.6]\n---\n\n## Task List\n' > "$P/.epico/stories/004-dash/tasks.md"
}

teardown() { rm -rf "$P"; }

rec() { bash "$PLUGIN_ROOT/scripts/checkpoint-reconcile.sh" --root "$P" "$@"; }
state() { printf '%s' "$1" | jq -r --arg id "$2" '.tasks[] | select(.id == $id) | .state'; }

@test "each task gets its state from the checkbox and the stories that name it" {
  run rec --stage 1
  [ "$status" -eq 0 ]
  [ "$(state "$output" 1.1.1)" = closed ]     # [x], archived story names it
  [ "$(state "$output" 1.1.2)" = closed ]
  [ "$(state "$output" 1.1.3)" = open ]       # [ ], nothing names it
  [ "$(state "$output" 1.1.4)" = mismatch ]   # [ ], an archived story closed it
  [ "$(state "$output" 1.1.5)" = unmapped ]   # [x], no story names it
  [ "$(state "$output" 1.1.6)" = in-work ]    # an open story names it
  echo "$output" | jq -e '.counts == {closed: 2, "in-work": 1, unmapped: 1, mismatch: 1, open: 1}'
}

@test "the task line wins over the table row, and the closing stories are named" {
  run rec --stage 1
  echo "$output" | jq -e '[.tasks[] | select(.id == "1.1.1")] | length == 1'
  echo "$output" | jq -e '.tasks[] | select(.id == "1.1.1") | .checkbox == "x" and .closed_by == ["001-repo"] and .file == "docs/ROADMAP.md"'
  echo "$output" | jq -e '.tasks[] | select(.id == "1.1.6") | .in_work_by == ["004-dash"]'
}

@test "IDs a story names that no ROADMAP holds, and stories with no roadmap, are listed" {
  run rec --stage 1
  echo "$output" | jq -e '.unknown_ids == ["1.9.9"]'
  echo "$output" | jq -e '.stories_without_roadmap == ["002-old (archived)"]'
}

@test "only the asked stage is read, from stage files too" {
  mkdir -p "$P/docs/stages"
  printf -- '- [ ] **3.1.1 Stage three task** · Simple · `todo`\n' > "$P/docs/stages/03-three.md"
  run rec --stage 3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stage == 3 and (.tasks | map(.id)) == ["3.1.1"] and .tasks[0].file == "docs/stages/03-three.md"'
}

@test "a stage no ROADMAP holds exits 2; a missing --stage exits 2" {
  run rec --stage 7
  [ "$status" -eq 2 ]
  run rec
  [ "$status" -eq 2 ]
}

@test "it writes nothing" {
  before=$(find "$P" -type f -exec md5sum {} + | sort)
  rec --stage 1 >/dev/null
  after=$(find "$P" -type f -exec md5sum {} + | sort)
  [ "$before" = "$after" ]
}
