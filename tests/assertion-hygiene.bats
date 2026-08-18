#!/usr/bin/env bats
# Story 020, sub-task 1.1 — the suite lints itself for `!`-inverted assertions
# (R4.1, R4.2, R4.3).
#
# WHY THIS FILE EXISTS. Bash exempts a command inverted with the reserved word
# `!` from `errexit`: `! cmd` never trips `set -e`, whatever cmd returns. A bats
# test body runs under errexit, so `! grep -q x` anywhere but the LAST statement
# of a case is inert — it asserts nothing, and the case stays green however the
# file under test changes. In last position it happens to work, because bats
# reads the body's final status; that is an accident of placement, not a
# property of the assertion, and one appended line away from silence. R4.1
# therefore admits no position exemption and this lint flags both.
#
# THE SANCTIONED SHAPE is a conditional, whose status errexit does honour:
#
#   if <cmd>; then echo "<what went wrong>"; return 1; fi
#
# WHAT COUNTS AS A STATEMENT START. The reserved word `!` inverts the pipeline
# that follows it, so it is only a negation where a command may begin: at the
# start of a line, and after `&&`, `||`, `;`, `&`, `{`, `(`, `then`, `do` and
# `else`. Each of those is exercised by a case below, not assumed.
#
# THREE DISCRIMINATIONS, settled rather than discovered — each one measured
# before it was coded:
#
#   1. `[ ! -f x ]` and `[[ ! "$a" =~ b ]]` are CONFORMING (R4.3). The `!` there
#      is a conditional operator, not the reserved word: `[`/`[[` returns
#      non-zero itself and errexit does NOT exempt it, so the assertion bites.
#      The lint tracks bracket regions and never flags inside one — including
#      across `&&`, as in `[[ -f a && ! -f b ]]`.
#
#   2. `if ! grep …; then` is CONFORMING. The negation sits in a condition,
#      whose status the `if` consumes rather than errexit discarding it. The
#      lint follows the condition from `if`/`elif`/`while`/`until` to its
#      `then`/`do`, across line continuations, so `if a && ! b; then` is
#      conforming too — while `if a; then ! b; fi` is not: past `then` the
#      exemption is back.
#
#   3. A `!` inside a quoted string, inside a comment, inside an `awk` program
#      or inside a heredoc body is not a shell negation at all. The lint blanks
#      quoted spans, drops comments and skips heredoc bodies before matching.
#      That last one is load-bearing HERE: this file plants its fixtures with
#      heredocs whose bodies are deliberate offenders, and an apostrophe in a
#      skipped body would otherwise desync quote tracking for the rest of the
#      file. Measured — with heredoc skipping removed, this file reports itself.
#
# SCOPE. The repo-wide case globs `tests/*.bats`, which is the story's own
# wording; a `.bats` file added under a subdirectory of tests/ would escape it.
# There is none today.
#
# THE WALKER IS LOCAL TO THIS FILE ON PURPOSE. Sub-task 1.4 lints a different
# question; a shared walker would couple two lints for no gain.
#
# Case names carry the sub-task that owns them, so `bats --filter '^1\.1:'`
# answers for exactly this contract.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# THE LINT. Prints `file:line: <the line>` for every `!`-inverted command used
# as an assertion in the .bats files given as arguments — one line per offending
# line, and it never stops at the first, because an author converting a batch
# wants the whole list. Exit status is always 0: the caller decides what an
# offender means, which is what lets a fixture case and the repo-wide case share
# one walker without either dictating the other's verdict.
inverted_commands() { # $@ = .bats files
  awk '
# Renders ONE line as code only: quoted spans blanked, comment dropped, heredoc
# openers consumed and their delimiters queued. Quote state carries across lines
# deliberately — an awk program in single quotes spans several of them.
function code_of(s,   i, n, c, out, d, q, strip) {
  out = ""; i = 1; n = length(s)
  while (i <= n) {
    c = substr(s, i, 1)
    if (sq) { if (c == "\047") sq = 0; out = out " "; i++; continue }
    if (dq) {
      if (c == "\\" && i < n) { out = out "  "; i += 2; continue }
      if (c == "\"") dq = 0
      out = out " "; i++; continue
    }
    if (c == "\\") { out = out "  "; i += 2; continue }
    if (c == "\047") { sq = 1; out = out " "; i++; continue }
    if (c == "\"") { dq = 1; out = out " "; i++; continue }
    # A # opens a comment only where a word may begin, so ${#a[@]} and $# stay.
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|(]/)) break
    if (c == "<" && substr(s, i + 1, 1) == "<") {
      if (substr(s, i + 2, 1) == "<") { out = out "   "; i += 3; continue }
      out = out "  "; i += 2
      strip = 0
      if (substr(s, i, 1) == "-") { strip = 1; out = out " "; i++ }
      while (i <= n && substr(s, i, 1) ~ /[ \t]/) { out = out " "; i++ }
      d = ""; q = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (q == "") {
          if (c == "\047" || c == "\"") { q = c; out = out " "; i++; continue }
          if (c == "\\") { i++; if (i <= n) { d = d substr(s, i, 1); out = out "  "; i++ }; continue }
          if (c ~ /[ \t;&|()<>]/) break
          d = d c; out = out " "; i++
        } else {
          if (c == q) { q = ""; out = out " "; i++; continue }
          d = d c; out = out " "; i++
        }
      }
      if (d != "") { nhd++; hd[nhd] = d; hdstrip[nhd] = strip }
      continue
    }
    out = out c; i++
  }
  return out
}

# Walks the code of one line as a token stream and answers ONE question: is
# there a bare `!` where a command may begin, outside an if/while/until
# condition and outside [ ] / [[ ]]? Returns at the first one — one report line
# per offending line — and never aborts the file loop.
function offends(code,   i, n, c, tok, cmdpos) {
  i = 1; n = length(code); cmdpos = 1
  while (i <= n) {
    c = substr(code, i, 1)
    if (c ~ /[ \t]/) { i++; continue }
    if (c ~ /[;&|]/) { while (i <= n && substr(code, i, 1) ~ /[;&|]/) i++; cmdpos = 1; continue }
    if (c == "(" || c == ")") { i++; cmdpos = 1; continue }
    tok = ""
    while (i <= n && substr(code, i, 1) !~ /[ \t;&|()]/) { tok = tok substr(code, i, 1); i++ }
    # Discrimination 1: a conditional operator, not the reserved word (R4.3).
    if (tok == "[" || tok == "[[") { if (cmdpos) inbr = 1; cmdpos = 0; continue }
    if (tok == "]" || tok == "]]") { inbr = 0; cmdpos = 0; continue }
    if (inbr) { cmdpos = 0; continue }
    if (tok == "!") { if (cmdpos && cond == 0) return 1; cmdpos = 1; continue }
    # Discrimination 2: the condition owns the status until then/do.
    if (cmdpos && (tok == "if" || tok == "elif" || tok == "while" || tok == "until")) { cond = 1; continue }
    if (cmdpos && (tok == "then" || tok == "do")) { cond = 0; continue }
    if (tok == "{" || tok == "}" || (cmdpos && tok == "else")) { cmdpos = 1; continue }
    cmdpos = 0
  }
  return 0
}

FNR == 1 { sq = 0; dq = 0; cond = 0; inbr = 0; nhd = 0; hdi = 1; inbody = 0 }

{
  # Discrimination 3: a heredoc body is content, never code.
  if (inbody) {
    body = $0
    if (hdstrip[hdi]) sub(/^\t+/, "", body)
    if (body == hd[hdi]) { hdi++; if (hdi > nhd) { inbody = 0; nhd = 0; hdi = 1 } }
    next
  }
  nhd = 0; hdi = 1
  codeline = code_of($0)
  if (offends(codeline)) { printf "%s:%d: %s\n", FILENAME, FNR, $0 }
  if (nhd > 0) { inbody = 1; hdi = 1; sq = 0; dq = 0 }
}
' "$@"
}

# `wc -l` reports 1 for the empty string, because printf supplies the newline.
line_count() { # $1 = captured lint output
  if [ -z "$1" ]; then
    echo 0
    return 0
  fi
  printf '%s\n' "$1" | wc -l
}

# --- 1.1: the lint, proved on planted input ----------------------------------
# Fixtures are written under $WORK, never into tests/: they are input to the
# lint, not cases bats should collect. They are read, never executed, so what
# matters about each one is its SHAPE.

@test "1.1: a !-inverted command outside last position is flagged, naming file and line" {
  cat > "$WORK/nonfinal.bats" <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  ! true
  [ 1 -eq 1 ]
}
BODY
  offenders="$(inverted_commands "$WORK/nonfinal.bats")"
  [ "$(line_count "$offenders")" -eq 1 ]
  # File AND line (R4.2), in the `file:line: <the line>` shape — the trailing
  # space is part of the format, so a bare grep-style `file:line:` would fail.
  printf '%s\n' "$offenders" | command grep -qF "$WORK/nonfinal.bats:3: "
  printf '%s\n' "$offenders" | command grep -qF '! true'
}

@test "1.1: a !-inverted command in LAST position is flagged too — no position exemption" {
  cat > "$WORK/final.bats" <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  [ 1 -eq 1 ]
  ! true
}
BODY
  # Green today by accident of placement, inert the moment a line is appended.
  # R4.1 forbids the shape, not the position, so this must red exactly as above.
  offenders="$(inverted_commands "$WORK/final.bats")"
  [ "$(line_count "$offenders")" -eq 1 ]
  printf '%s\n' "$offenders" | command grep -qF "$WORK/final.bats:4: "
}

@test "1.1: [ ! ] , [[ ! ]] and a ! inside an if condition are conforming" {
  cat > "$WORK/conforming.bats" <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  [ ! -f /nonexistent ]
  [[ ! -d /nonexistent ]]
  [[ -f /etc/hosts && ! -d /etc/hosts ]]
  if ! true; then return 1; fi
  if grep -q a /dev/null && ! grep -q b /dev/null; then return 1; fi
  while ! false; do break; done
  until ! false; do break; done
  test ! -f /nonexistent
}
BODY
  # Discriminations 1 and 2. Every line here returns a status errexit honours,
  # so flagging one would be a false red on the very shape R4.1 asks for.
  offenders="$(inverted_commands "$WORK/conforming.bats")"
  [ -z "$offenders" ]
}

@test "1.1: a ! in a comment, a quoted string, an awk program or a heredoc is not a negation" {
  cat > "$WORK/lookalikes.bats" <<'BODY'
#!/usr/bin/env bats
# A comment may quote the forbidden shape: `! grep -q x`, and even `; ! true`.
@test "planted" {
  echo "a double-quoted ; ! true"
  echo 'a single-quoted ; ! true'
  awk '
    !inb && $0 ~ /x/ {inb = 1; next}
    inb {print}' /dev/null
  grep -q x <<< "a here-string is not a heredoc" || true
  cat > /dev/null <<'INNER'
! true
; ! true
an apostrophe here would desync quote tracking if this body were not skipped
INNER
  [ "${#WORK}" -gt 0 ]
}
BODY
  # Discrimination 3. Without it the lint reds on text it should ignore — and
  # the awk line is not hypothetical: `!inb && …` appears twice in this suite.
  offenders="$(inverted_commands "$WORK/lookalikes.bats")"
  [ -z "$offenders" ]
}

@test "1.1: every statement start is caught and every offender is listed, not just the first" {
  cat > "$WORK/starts.bats" <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  ! true
  true && ! true
  true || ! true
  true; ! true
  { ! true; }
  if true; then ! true; fi
  if false; then :; else ! true; fi
}
BODY
  cat > "$WORK/second.bats" <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  ! true
  [ 1 -eq 1 ]
}
BODY
  # Eight offenders over two files — seven statement starts (`^`, `&&`, `||`,
  # `;`, `{`, `then`, `else`) plus one more file, so the walker is shown to
  # carry on past the first offender both within a file and across files.
  offenders="$(inverted_commands "$WORK/starts.bats" "$WORK/second.bats")"
  [ "$(line_count "$offenders")" -eq 8 ]
  for line in 3 4 5 6 7 8 9; do
    printf '%s\n' "$offenders" | command grep -qF "$WORK/starts.bats:$line: "
  done
  printf '%s\n' "$offenders" | command grep -qF "$WORK/second.bats:3: "
}

# --- 1.1: the lint, over the suite it governs --------------------------------

@test "1.1: no .bats file in tests/ inverts a command as an assertion" {
  # Relative paths on purpose: `tests/spike-stale.bats:85` is what an author
  # pastes into an editor. This file is in scope too — it lints itself.
  offenders="$(cd "$PLUGIN_ROOT" && inverted_commands tests/*.bats)"
  if [ -n "$offenders" ]; then
    echo "A \`!\`-inverted command is exempt from errexit, so its non-zero status"
    echo "is discarded and the assertion is inert (R4.1). Rewrite each one as"
    echo "  if <cmd>; then echo '<what went wrong>'; return 1; fi"
    printf '%s\n' "$offenders"
    return 1
  fi
}
