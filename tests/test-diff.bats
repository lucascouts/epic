#!/usr/bin/env bats
# epico-test-diff: a materialized pre-authored test against its authored copy.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  S="$WORK/.epico/stories/004-login"
  mkdir -p "$S/.draft/authored-tests/tests" "$WORK/tests"
  cat > "$S/.draft/authored-tests/tests/login.test.ts" <<'EOF'
import { describe, it, expect } from 'vitest'
import { login } from '../src/login'
const fixture = { user: 'a', pass: 'b' }

describe('login', () => {
  it('accepts valid credentials', () => {
    expect(login(fixture.user, fixture.pass)).toBe(true)
  })
})
EOF
  cp "$S/.draft/authored-tests/tests/login.test.ts" "$WORK/tests/login.test.ts"
}

teardown() {
  rm -rf "$WORK"
}

diffit() { bash "$PLUGIN_ROOT/scripts/test-diff.sh" --story "$S" "$@"; }

@test "identical copy: clean, exit 0" {
  run diffit
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "clean" and .files[0].status == "unchanged" and .story == "004-login"'
}

@test "setup repair (import path, fixture, a new import of expect): surface, exit 0" {
  sed -i -e "s#'../src/login'#'../src/auth/login'#" -e "s#pass: 'b'#pass: 'b', remember: false#" "$WORK/tests/login.test.ts"
  sed -i "1i import { expect as e } from 'vitest'" "$WORK/tests/login.test.ts"
  run diffit
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "surface" and .files[0].status == "changed" and (.files[0].assertion_changes | length) == 0'
}

@test "a changed assertion blocks, exit 1, and names the removed and the added line" {
  sed -i 's/toBe(true)/toBe(false)/' "$WORK/tests/login.test.ts"
  run diffit
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "blocked" and .files[0].status == "assertion-changed"'
  echo "$output" | jq -e '[.files[0].assertion_changes[].change] | sort == ["added","removed"]'
}

@test "a deleted assertion blocks too" {
  sed -i '/toBe(true)/d' "$WORK/tests/login.test.ts"
  run diffit
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.files[0].assertion_changes == [{"change":"removed","text":"    expect(login(fixture.user, fixture.pass)).toBe(true)"}]'
}

@test "Go, Python and Rust assertion forms are recognised" {
  for pair in 't.Errorf("x")|t.Logf("x")' 'assert x == 1|x == 1' 'panic!("no")|println!("no")' 'raise ValueError()|pass' 'require.Equal(t, 1, x)|_ = x'; do
    a=${pair%%|*} b=${pair#*|}
    printf '%s\n' "$a" > "$S/.draft/authored-tests/tests/one.txt"
    mkdir -p "$WORK/tests"; printf '%s\n' "$b" > "$WORK/tests/one.txt"
    run diffit --file tests/one.txt
    [ "$status" -eq 1 ] || { echo "not blocked: $a -> $b"; return 1; }
  done
}

@test "a missing materialized test blocks; --file limits the check" {
  mkdir -p "$S/.draft/authored-tests/tests/extra"
  printf 'x\n' > "$S/.draft/authored-tests/tests/extra/gone.test.ts"
  run diffit
  [ "$status" -eq 1 ]
  echo "$output" | jq -e 'any(.files[]; .status == "missing")'
  run diffit --file tests/login.test.ts
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.files | length) == 1'
}

@test "quotes and backslashes in a changed assertion keep the JSON parseable" {
  sed -i "s/toBe(true)/toBe(\"a\\\\\\\\b\")/" "$WORK/tests/login.test.ts"
  run diffit
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "blocked"'
}

@test "no authored tests: clean with no files; bad usage exits 2" {
  rm -rf "$S/.draft/authored-tests"
  run diffit
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "clean" and .files == []'
  run bash "$PLUGIN_ROOT/scripts/test-diff.sh" --story "$WORK/nope"
  [ "$status" -eq 2 ]
}
