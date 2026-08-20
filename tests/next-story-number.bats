#!/usr/bin/env bats
# Unit tests for scripts/next-story-number.sh (story 013 — quick-create).
# Authored by the Test Advisor BEFORE implementation (TDD Red phase).
#
# Contract under test (design.md component 3, R2.1-R2.4):
#   next-story-number.sh [--reserve N], run from a project root containing
#   .epic/stories/ and .epic/archive/  →  ONE JSON object on stdout:
#     {next, reserved: [], collisions: []}
#   - next: zero-padded 3-digit string = max NNN- prefix across BOTH roots + 1;
#     an empty project starts at "001"
#   - --reserve N: creates N placeholder directories (one per number,
#     NNN- prefixed — directory existence IS the reservation); `reserved`
#     lists the N consecutive zero-padded numbers; a re-scan after creation
#     detects a concurrent creator, re-slots the colliding tail, records it
#     in `collisions`, and NEVER removes or overwrites a foreign directory
#   - allocation past 999: refuse with exit 1 naming the cap, reserving nothing
#   - house contract: JSON on stdout, diagnostics on stderr, exit 0/1/2
#
# Fixtures are real directory trees under mktemp — the script's only
# dependency is the filesystem.
#
# THE COLLISION CASE injects a concurrent creator through a PATH shim around
# `mkdir`: the first time the allocator creates a NNN-* placeholder, a foreign
# NNN-taken directory with the SAME number is dropped first — exactly the
# scan→mkdir race window R2.2 closes. ASSUMPTION, stated for the implementer:
# placeholder creation must go through the `mkdir` command resolved via PATH
# (plain `mkdir`, not an absolute /bin/mkdir). If the implementation creates
# directories any other way, adapt the fixture's interception point — never
# the assertions.
#
# EPIC_PLUGIN_ROOT overrides root resolution so the draft copy under
# .draft/authored-tests/tests/ can run before materialization into tests/.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="${EPIC_PLUGIN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  SCRIPT="$PLUGIN_ROOT/scripts/next-story-number.sh"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epic/stories" "$WORK/.epic/archive"
}

teardown() {
  rm -rf "$WORK"
}

# Run the allocator from the fixture project root.
run_alloc() {
  ( cd "$WORK" && bash "$SCRIPT" "$@" )
}

@test "1.1: empty project allocates 001 and stdout is exactly one JSON object" {
  run --separate-stderr run_alloc
  [ "$status" -eq 0 ]
  echo "$output" | jq -e -s 'length == 1 and (.[0] | type == "object")'
  [ "$(echo "$output" | jq -r '.next')" = "001" ]
  [ "$(echo "$output" | jq -c '.reserved')" = "[]" ]
}

@test "1.1: next is the max across stories AND archive (archived max wins)" {
  # the 0.3.1 skill's stories-only scan is the known bug shape: an archived
  # story holding the true max must not let a number be recycled
  mkdir "$WORK/.epic/stories/003-live-story"
  mkdir "$WORK/.epic/archive/007-archived-story"
  run --separate-stderr run_alloc
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.next')" = "008" ]
}

@test "1.1: next stays zero-padded across the width boundary (009 -> 010)" {
  mkdir "$WORK/.epic/stories/009-nine"
  run --separate-stderr run_alloc
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.next')" = "010" ]
  echo "$output" | jq -e '.next | test("^[0-9]{3}$")'
}

@test "1.1: a plain call reserves nothing on disk" {
  mkdir "$WORK/.epic/stories/004-existing"
  run run_alloc
  [ "$status" -eq 0 ]
  [ "$(ls "$WORK/.epic/stories" | wc -l)" -eq 1 ]
  [ "$(ls "$WORK/.epic/archive" | wc -l)" -eq 0 ]
}

@test "1.1: --reserve 3 returns consecutive zero-padded numbers and the dirs ARE the reservation" {
  mkdir "$WORK/.epic/stories/004-existing"
  run --separate-stderr run_alloc --reserve 3
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.reserved')" = '["005","006","007"]' ]
  [ "$(echo "$output" | jq -c '.collisions')" = "[]" ]
  # one placeholder directory per reserved number, in the stories root
  for n in 005 006 007; do
    ls -d "$WORK/.epic/stories/$n-"* >/dev/null
  done
  # directory existence is the reservation: a second scan starts after them
  run --separate-stderr run_alloc
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.next')" = "008" ]
}

@test "1.1: 999 cap — a plain call past the cap refuses with exit 1 naming it" {
  mkdir "$WORK/.epic/stories/999-last"
  run run_alloc
  [ "$status" -eq 1 ]
  [[ "$output" == *999* ]]
}

@test "1.1: 999 cap — a --reserve that would cross the cap refuses whole, reserving nothing" {
  # allocate-N-exactly-once (R2.1) means all-or-nothing: a refusal must not
  # leave a partial reservation behind
  mkdir "$WORK/.epic/stories/998-penultimate"
  run run_alloc --reserve 2
  [ "$status" -eq 1 ]
  [[ "$output" == *999* ]]
  [ "$(ls "$WORK/.epic/stories" | wc -l)" -eq 1 ]
}

@test "1.1: concurrent creator between scan and mkdir — tail re-slotted, collision recorded, foreign dir untouched" {
  mkdir "$WORK/.epic/stories/004-existing"

  # PATH shim: the first NNN-* placeholder mkdir also drops a foreign dir
  # claiming the SAME number, simulating a concurrent create in the race
  # window between the scan and the reservation.
  SHIM="$WORK/shim"
  mkdir -p "$SHIM"
  cat > "$SHIM/mkdir" <<'SH'
#!/usr/bin/env bash
real=/bin/mkdir; [ -x "$real" ] || real=/usr/bin/mkdir
flag="${SHIM_FLAG:-}"
if [ -n "$flag" ] && [ ! -e "$flag" ]; then
  for a in "$@"; do
    case "$a" in -*) continue ;; esac
    base=$(basename -- "$a")
    case "$base" in
      [0-9][0-9][0-9]-*)
        : > "$flag"
        "$real" -p -- "$(dirname -- "$a")/${base%%-*}-taken"
        break ;;
    esac
  done
fi
exec "$real" "$@"
SH
  chmod +x "$SHIM/mkdir"
  export SHIM_FLAG="$WORK/.shim-fired"
  export PATH="$SHIM:$PATH"

  run --separate-stderr run_alloc --reserve 2
  [ "$status" -eq 0 ]
  # the shim actually fired — otherwise this case proved nothing
  [ -e "$SHIM_FLAG" ]
  # the collision is recorded and names the collided number
  echo "$output" | jq -e '.collisions | length >= 1'
  echo "$output" | jq -e '.collisions | any(tostring | contains("005"))'
  # the batch still got 2 distinct numbers, none of them the foreign 005
  echo "$output" | jq -e '.reserved | (length == 2) and (unique | length == 2) and ((index("005")) | not)'
  # the foreign dir was never removed or overwritten, and now solely owns 005
  [ -d "$WORK/.epic/stories/005-taken" ]
  [ "$(ls -d "$WORK/.epic/stories/005-"* | wc -l)" -eq 1 ]
  # every re-slotted number has its placeholder on disk
  while IFS= read -r n; do
    ls -d "$WORK/.epic/stories/$n-"* >/dev/null
  done < <(echo "$output" | jq -r '.reserved[]')
  # and a fresh scan starts strictly after everything reserved
  last=$(echo "$output" | jq -r '.reserved | max')
  expected=$(printf '%03d' $((10#$last + 1)))
  run --separate-stderr run_alloc
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.next')" = "$expected" ]
}
