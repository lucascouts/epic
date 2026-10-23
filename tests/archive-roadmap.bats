#!/usr/bin/env bats
# The two optional manifest keys: `roadmap` (the ROADMAP task IDs a story worked
# on) and `validated_sha` (the commit epico-validated recorded). Optional, so an
# entry without them — every entry an older release wrote — still reads as
# complete; placed before overrides_used, the sentinel epico-index trusts.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  MANIFEST="$PROJ/.epico/archive/manifest.yaml"
  mkdir -p "$PROJ/.epico/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

SHA=0123456789abcdef0123456789abcdef01234567

make_story() { # make_story <dir-name> <roadmap line or ""> <with-validated: yes|no>
  local dir="$PROJ/.epico/stories/$1"
  mkdir -p "$dir/.draft"
  printf -- '---\nstory: x\ntype: feature\nscale: standard\nversion: 1\ncreated: 2026-10-19\nstatus: validated\n---\n\n# Story\n' > "$dir/story.md"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-10-19'
    [ -z "$2" ] || echo "$2"
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1 - Done'
    echo '  - Validation: ok'
  } > "$dir/tasks.md"
  if [ "$3" = yes ]; then
    printf 'sha: %s\ndirty: false\nrecorded_at: 2026-10-19T10:00:00-03:00\n' "$SHA" > "$dir/.draft/validated.yaml"
  fi
}

@test "roadmap and validated_sha are recorded, before overrides_used, and reported" {
  make_story 001-a 'roadmap: [2.4.1 ,2.4.2]' yes
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/001-a --skip-secrets
  [ "$status" -eq 0 ]
  grep -qxF '    roadmap: [2.4.1, 2.4.2]' "$MANIFEST"
  grep -qxF "    validated_sha: \"$SHA\"" "$MANIFEST"
  r=$(grep -n '^    roadmap:' "$MANIFEST" | cut -d: -f1)
  o=$(grep -n '^    overrides_used' "$MANIFEST" | cut -d: -f1)
  [ "$r" -lt "$o" ]
  echo "$output" | jq -e --arg s "$SHA" '.manifest_entry.roadmap == ["2.4.1","2.4.2"] and .manifest_entry.validated_sha == $s'
}

@test "without them the entry carries neither key and is still complete" {
  make_story 001-b '' no
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/001-b --skip-secrets
  [ "$status" -eq 0 ]
  if grep -qE '^    (roadmap|validated_sha):' "$MANIFEST"; then echo "wrote an optional key it did not have"; return 1; fi
  echo "$output" | jq -e '(.manifest_entry | has("roadmap") | not) and (.manifest_entry | has("validated_sha") | not)'
}

@test "a malformed roadmap is left out of the permanent record" {
  make_story 001-c 'roadmap: 2.4.1 and more' no
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/001-c --skip-secrets
  [ "$status" -eq 0 ]
  if grep -q '^    roadmap:' "$MANIFEST"; then echo "recorded a malformed roadmap"; return 1; fi
}

@test "an interrupted archive with both keys resumes once and reports them from the record" {
  make_story 001-d 'roadmap: [3.1.1]' yes
  chmod 555 "$PROJ/.epico/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/001-d --skip-secrets
  chmod 755 "$PROJ/.epico/stories"
  [ "$status" -ne 0 ]
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/001-d --skip-secrets
  [ "$status" -eq 0 ]
  [ "$(grep -c 'story: "001-d"' "$MANIFEST")" -eq 1 ]
  echo "$output" | jq -e --arg s "$SHA" '.manifest_entry.roadmap == ["3.1.1"] and .manifest_entry.validated_sha == $s'
}

@test "epico-index still renders the entry as complete" {
  make_story 001-e 'roadmap: [2.4.1]' yes
  bash "$ARCHIVE_SH" .epico/stories/001-e --skip-secrets >/dev/null 2>&1
  run bash "$PLUGIN_ROOT/scripts/epico-index.sh" --epico-dir "$PROJ/.epico"
  [ "$status" -eq 0 ]
  grep -q '001' "$PROJ/.epico/EPICO.md"
  if grep -qi 'incomplete\|partial' "$PROJ/.epico/EPICO.md"; then echo "index read the entry as torn"; return 1; fi
}
