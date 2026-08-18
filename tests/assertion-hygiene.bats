#!/usr/bin/env bats
# Story 020, sub-task 1.1 — the suite lints itself for `!`-inverted assertions
# (R4.1, R4.2, R4.3).
#
# THIS FILE NOW HOSTS TWO LINTS, each with its own header and its own walker.
# The one documented immediately below is 1.1's, on `!`-inverted assertions.
# The second, further down, is sub-task 1.4's (R5.1, R5.2, R5.3): it refuses to
# let a WINDOW PATTERN — `A[^.]{0,N}B`, the shape that says A and B share a
# sentence but cannot say in which direction — sit in tests/ without a row in
# an allowlist table naming a verdict and the measurement behind it.
#
# THAT LINT CHECKS THE ROW EXISTS. It does NOT check that the row's sentence is
# true, and it cannot: whether a window pattern survives an inversion depends
# on the prose it reads, not on the regex. A green census means every window
# pattern has been written down for a reviewer, nothing more. Reading it as a
# guarantee of polarity is the unearned confidence this suite keeps refusing to
# buy — and it is the same misreading that let the defect through four times.
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

# --- 1.4: the window-pattern lint (R5.1, R5.2, R5.3) -------------------------
#
# WHY THIS SECOND LINT EXISTS. A window pattern is a regex of the shape
# `A[^.]{0,N}B`: match A, then anything up to N characters that is not a full
# stop, then B. It is how this suite asserts that two things are said in the
# same sentence however the sentence wraps. What it cannot say is in WHICH
# DIRECTION they are said: `the run[^.]{0,40}fail` is satisfied by "the run is
# **not** failed" exactly as by "the run is failed", so an inversion of the very
# rule the assertion guards leaves it green. That is measured, in this repo,
# more than once — it is the defect story 020 exists to close.
#
# The lint therefore does NOT try to judge a window pattern. It cannot: whether
# `A[^.]{0,N}B` survives a negation depends on the prose it reads, not on the
# regex. What it does is refuse to let one exist UNREVIEWED — every window
# pattern in tests/*.bats must appear in the allowlist below, and the allowlist
# is a table a human writes.
#
# WHAT THE LINT CHECKS IS THAT THE ROW EXISTS — NOT THAT ITS SENTENCE IS TRUE.
# Say it plainly, because the opposite is the tempting reading: a green census
# means every window pattern has been WRITTEN DOWN, with a verdict and a
# justification a reviewer can read. It does not mean the verdict is right, and
# no machine here checks that. The sentence in each row is addressed to a
# reader; the lint only enforces that a reader was given one.
#
# THE TABLE LIVES IN THIS FILE, as a heredoc, deliberately — not in a data file
# beside it. A separate file drifts from the suite it describes and, worse, it
# offers a future author somewhere to add a row without ever reading why the
# other rows are there. Here the justification of every neighbour is one screen
# away from the row being added.
#
# ROWS ARE KEYED ON THE PATTERN TEXT, NEVER ON A LINE NUMBER. Every insertion
# above a row would otherwise invalidate it, silently — story 019's header
# carries `:172`, `:181`, `:341` and `:296` and every one of them is already
# stale, because sub-task 1.2 of this story turned six one-line negations into
# three lines each and shifted everything below. A pattern moves only when
# someone rewrites it, which is exactly when its row should be revisited.
#
# THE VERDICT COLUMN takes four values. Two of them are deviations from the
# sub-task's wording, explained rather than hidden:
#
#   PINNED  — the claim is directional and its polarity token sits INSIDE the
#             match, so a negation cannot be parked between the anchors.
#   ALLOWED — the pattern makes NO directional claim (a filename, a field name,
#             a topic), so it has no polarity to pin. This is NOT an escape
#             hatch for a directional claim. The lint cannot tell the two
#             apart — the row's sentence is what a reviewer reads, and it is
#             the only thing standing between the two.
#   DIRECTION-BLIND
#           — MEASURED, and it failed. The rule the pattern guards was
#             inverted in the prose file and the owning case stayed GREEN. The
#             row records the inversion and the colour, and names the task
#             (2, 3 or 4) that repairs it. THIS IS NOT A PASS, and the word is
#             chosen so it cannot be read as one: PINNED and ALLOWED are the
#             only two verdicts that say the site is sound.
#   PENDING — the verdict is not settled yet. Sub-task 1.5 was this story's
#             measured sweep and it left no PENDING row behind; tasks 2-4 fix
#             what it found. Writing PINNED or ALLOWED on a row nobody has
#             measured would fabricate exactly the evidence this story exists
#             to demand, so the table says PENDING out loud instead. The value
#             stays in the vocabulary for the next pattern somebody adds.
#
# EVERY PENDING ROW CARRIES THE MARKER `UNMEASURED — 1.5` in its sentence, and
# the lint enforces the equivalence in both directions: a PENDING row without
# the marker fails, and any other verdict that still carries the marker fails.
# That made sub-task 1.5's worklist a grep, not a reading:
#
#   command grep -n '^WHY     UNMEASURED — 1.5' tests/assertion-hygiene.bats
#
# Anchored on the WHY field at column 1, not on the bare marker: the marker
# also appears in this header, in row_defects' own diagnostics, and once in a
# planted fixture. At the close of 1.4 that grep answered 13 — the table's 12
# PENDING rows plus the fixture at "a row missing a field, a verdict or its
# marker is a structural defect", which carries the marker on a PINNED row on
# purpose, to exercise the stale-marker half of the rule. AT THE CLOSE OF 1.5
# IT ANSWERS 1: that fixture, and nothing else. The grep is the interface
# because a .bats file cannot be sourced — `@test "x" {` is not valid bash, so
# allowlist_table and allowlist_rows are reachable from a case and nowhere
# else.
#
# WHAT SUB-TASK 1.5 MEASURED, and what it cost the story to know. Every row
# below was settled by inverting, in the prose file the owning case reads, the
# rule that case exists to guard, running the case, and restoring the file —
# one mutation at a time, never two at once. 25 mutation runs over 6 prose
# files answered 12 keys covering 15 sites, plus the two non-window candidates
# at tests/anchor-lint.bats:306-307 that the story named by hand — those two
# are NOT window patterns, so no row here can hold them: a row whose pattern is
# not a site is an orphan and reds the census. Their verdicts live in 1.5's
# report, and the repair belongs in a task, not in this comment.
#
# THE RESULT IS NOT THE ONE THE STORY ASSUMED: 2 rows PINNED, 10
# DIRECTION-BLIND. Both of the story's LEAD rows (`before…summar`,
# `command…output`) reproduced as direction-blind, and `creat…\.draft` with
# them, so nothing was inherited from story 019's header — every row here
# names a run of its own. R5.2 is met by the sentence, not by the verdict: a
# row states the exact inversion applied and the colour observed, so a reader
# can re-run it rather than trust it.
#
# WHAT COUNTS AS A SITE, settled by measurement rather than by preference:
#
#   1. A COMMENT IS NOT A SITE. Prose that DISCUSSES a window pattern quotes
#      it, and one of those quotations — `the run[^.]{0,40}fail`, the defect
#      this story exists to close — belongs to no assertion at all. Measured on
#      the tree this ships into: dropping comments, the census reports 15
#      sites; keeping them, 23 — eight sentences, four in
#      tests/reports-by-artifact-policy.bats and four in this file's own
#      headers, which quote real patterns in the course of explaining them.
#
#   2. A HEREDOC BODY IS NOT A SITE, and here that is load-bearing rather than
#      tidy. The allowlist below is a heredoc whose every row quotes a window
#      pattern in full; a walker that read heredoc bodies would report each row
#      as a new unlisted site, which would need a row, which would be a new
#      site. Measured, on this file: skipping ON reports 0 sites here, skipping
#      OFF reports 28 — one per allowlist row, plus the planted fixtures — and
#      the table can never close. The cost is real and named: an assertion
#      written inside a heredoc body would escape this lint. None exists today.
#
#   3. THE UNIT IS `file:pattern`, NOT `file:line`. Two sites that run the same
#      pattern share one row: `before[^.]{0,160}summar` is asserted of the
#      Validator and of the Auditor, and `story\.md[^.]{0,120}(first|wins)`
#      appears twice in scale-resolution.bats — once as the assertion and once
#      in the diagnostic that prints the offending block when it fails. The
#      lint makes NO attempt to tell an assertion from a diagnostic: it cannot,
#      and a rule it cannot enforce would be a claim it has not earned. Both
#      occurrences key to the one row, which is the honest outcome anyway —
#      the diagnostic is the assertion's own echo, and one justification covers
#      both.
#
#   4. A WINDOW PATTERN OUTSIDE ANY QUOTED SPAN is reported under the literal
#      key `UNQUOTED-WINDOW`, which no row can plausibly match, so it fails
#      until a human looks. There is none today; the alternative — dropping it
#      silently — is the failure mode this whole story is about.
#
# SCOPE, and its limit, the same one 1.1's lint carries: the repo-wide cases
# glob `tests/*.bats`, which is the sub-task's own wording and is NOT
# recursive. A .bats file added under tests/<subdir>/ would escape both lints.
# There is none today.
#
# THE WALKER BELOW IS THIS LINT'S OWN, not a helper shared with 1.1's. The two
# answer different questions and want opposite things from the same line: 1.1
# BLANKS quoted spans, because a `!` inside a string is not a negation, while
# this one KEEPS them, because the string is the pattern it must key on. A
# shared walker would be a parameter and two behaviours, for no gain.

# THE LINT, part one: the sites. Prints `file<TAB>line<TAB>pattern` for every
# window pattern used in code in the .bats files given as arguments — one line
# per occurrence, tab-separated because a pattern may contain `:` (it does) but
# never a tab. Exit status is always 0: the caller decides what a site means,
# which is what lets the fixture cases and the repo-wide census share one
# walker without either dictating the other's verdict.
window_sites() { # $@ = .bats files
  awk '
# Walks ONE line left to right and answers two questions at once: which quoted
# spans does it contain, and does it open a heredoc? Comments end the walk,
# because a `#` where a word may begin makes the rest of the line prose.
# Quote state is per line on purpose: the alternative, carrying it across
# lines, mis-attributes every apostrophe inside a multi-line awk program, and
# nothing in this suite writes a window pattern across a line break.
function scan(s,   i, n, c, q, cur, strip, d, qq) {
  nspan = 0; outside = ""; q = ""
  i = 1; n = length(s)
  while (i <= n) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == q) { nspan++; span[nspan] = cur; cur = ""; q = ""; i++; continue }
      # Inside double quotes a backslash keeps its next character, and the pair
      # survives into the regex: `"tasks\.md"` reaches grep as `tasks\.md`, so
      # the key must carry the backslash too.
      if (q == "\"" && c == "\\" && i < n) { cur = cur substr(s, i, 2); i += 2; continue }
      cur = cur c; i++; continue
    }
    if (c == "\\" && i < n) { outside = outside "  "; i += 2; continue }
    if (c == "\047" || c == "\"") { q = c; cur = ""; i++; continue }
    # A # opens a comment only where a word may begin, so ${#a[@]} and $# stay.
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|(]/)) break
    if (c == "<" && substr(s, i + 1, 1) == "<") {
      # `<<<` is a here-string: one line, no body to skip. Both files that hold
      # window patterns today feed grep that way, so getting this wrong would
      # swallow the very lines the census is for.
      if (substr(s, i + 2, 1) == "<") { i += 3; continue }
      i += 2
      strip = 0
      if (substr(s, i, 1) == "-") { strip = 1; i++ }
      while (i <= n && substr(s, i, 1) ~ /[ \t]/) i++
      d = ""; qq = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (qq == "") {
          if (c == "\047" || c == "\"") { qq = c; i++; continue }
          if (c == "\\") { i++; if (i <= n) { d = d substr(s, i, 1); i++ }; continue }
          if (c ~ /[ \t;&|()<>]/) break
          d = d c; i++
        } else {
          if (c == qq) { qq = ""; i++; continue }
          d = d c; i++
        }
      }
      if (d != "") { nhd++; hd[nhd] = d; hdstrip[nhd] = strip }
      continue
    }
    outside = outside c; i++
  }
  # An unterminated quote is the first line of a multi-line quoted program.
  # Keep what it accumulated: dropping it would hide a window pattern there.
  if (q != "") { nspan++; span[nspan] = cur }
}

FNR == 1 { nhd = 0; hdi = 1; inbody = 0 }

{
  # Discrimination 2: a heredoc body is content, never code.
  if (inbody) {
    body = $0
    if (hdstrip[hdi]) sub(/^\t+/, "", body)
    if (body == hd[hdi]) { hdi++; if (hdi > nhd) { inbody = 0; nhd = 0; hdi = 1 } }
    next
  }
  nhd = 0; hdi = 1
  scan($0)
  # The whole quoted span is the key, not the `[^.]{0,N}` token inside it: the
  # token alone would collapse every pattern that happens to use the same width
  # into one row, and four distinct claims in this suite share `{0,80}`.
  for (k = 1; k <= nspan; k++)
    if (span[k] ~ /\[\^\.\]\{0,[0-9]+\}/) printf "%s\t%d\t%s\n", FILENAME, FNR, span[k]
  if (outside ~ /\[\^\.\]\{0,[0-9]+\}/) printf "%s\t%d\t%s\n", FILENAME, FNR, "UNQUOTED-WINDOW"
  if (nhd > 0) { inbody = 1; hdi = 1 }
}
' "$@"
}

# THE ALLOWLIST. One row per `file:pattern`, four fields each, a blank line
# between rows. Field lines start at column 1 with the field name; a line that
# starts with whitespace continues the WHY of the row above, so a sentence may
# wrap without a delimiter to escape. A `#` line is a note and is never a row —
# a header counted as a row is how the repo's cross-reference check came to
# report orphans that were not there.
#
# The lint checks that the row EXISTS. It does not, and cannot, check that its
# sentence is true.
allowlist_table() {
  cat <<'ROWS'
# --- tests/reports-by-artifact-policy.bats ---

FILE    tests/reports-by-artifact-policy.bats
PATTERN before[^.]{0,160}summar
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: `, before composing any textual summary,`
        became `, not before composing any textual summary but after it,` in
        agents/validator.md, then the same in agents/auditor.md — one file per
        run. Both owning cases stayed GREEN. The blunter swap `before` ->
        `after` does red it, so the pattern catches a REWRITE and misses a
        NEGATION parked in front of its own anchor. One span per file, so
        scoping or counting cannot reach it, and the polarity word IS the
        anchor, so there is nothing left to pin in place. TASK 4 — the rule's
        prose has to state the ordering in a phrase a negation cannot prefix.

FILE    tests/reports-by-artifact-policy.bats
PATTERN creat[a-zA-Z]*[^.]{0,80}\.draft
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: the permission reversed at BOTH spans of one
        file — `so creating `.draft/` on demand is part of this step` became
        `... is NOT part of this step — an absent `.draft/` is a precondition
        you report rather than fix`, and the Rules bullet's `creating `.draft/`
        on demand.**` became `never creating `.draft/` on demand.**` — run on
        agents/validator.md, then on agents/auditor.md. Both cases stayed
        GREEN, with the pattern still finding 2 spans per file. Two defects,
        both measured: the file states the rule twice, AND the negation
        prefixes the anchor `creat`, so scoping to one span would not close it
        either. TASK 4 — the permission needs a phrase whose negation is not a
        superstring of it.

FILE    tests/reports-by-artifact-policy.bats
PATTERN memory director[a-z]*[^.]{0,160}is your own store
VERDICT PINNED
WHY     MEASURED 1.5, twice. Inversion: `Your memory directory is not a second
        path in the code under audit — it is your own store` became `... is a
        second path in the code under audit — it is not your own store, and
        writing to it is a protocol violation too` in
        references/validate-mode.md — the case went RED on the memory-clause
        line. Dropping the clause outright went RED too. One span in the whole
        file, and the polarity token `is your own store` is a literal the
        negation breaks rather than prefixes.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: the count reversed WITHOUT any modifier the
        companion row names — table row 2 became `**one** `SendMessage` ... per
        attempt ... — repeat the row as often as it takes`, the paragraph
        became `**One request per attempt, ...**` and row 3 became `after the
        last of those requests`. The case stayed GREEN under a rule that now
        licenses unbounded re-requests. `one` is a substring of every phrase
        that reverses it, so there is no token to move inside the match. TASK 4
        — with row 5 below, as one repair: the prose must bound the count in a
        phrase that can be pinned (`exactly one`, `a single`).

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5, both ways, and the two results are the whole point.
        Inversion A — table row 2's `**one** `SendMessage`` became `**more than
        one** `SendMessage` ... repeating until it writes its report file`: the
        case went RED here, at this row's `return 1`. Inversion B — the same
        count reversed as `one ... per attempt ... repeat the row as often as
        it takes`, which uses none of the five modifiers named above: GREEN.
        The guard bites the phrasings it enumerates and no others, so the PAIR
        does not carry the claim. TASK 4, with row 4 above, as one repair.

FILE    tests/reports-by-artifact-policy.bats
PATTERN never[^.]{0,80}respawn
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: `**Never respawn silently.**` and its
        following sentence became `**Never conclude without a respawn.** A
        respawn ... is the price of a verdict you can trust ...` — a rule that
        now MANDATES the respawn. The case stayed GREEN: both anchors survive
        because the negation's object moved, not the negation. Replacing the
        header with `**Always respawn silently.**` does red it. One span in the
        section, so this is the phrase and not the file. TASK 2 — pin `never
        respawn` adjacent, the phrase the rule's own name already uses.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (never|not)[^.]{0,80}mutat
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: `**`Bash` is for measurement only — never
        mutate files or git state.**` became `**`Bash` is not for measurement
        only — mutate files or git state when the fix is trivial.**` in
        agents/tech-reviewer.md. The case stayed GREEN — the alternation's own
        `not` matched the negation of the RESTRICTION rather than of the
        mutation. Deleting both tokens (`is for measurement and repair — fix
        files ...`) does red it. One span, so it is the phrase. TASK 2 — pin
        `measurement only` and `never mutate` adjacent.

FILE    tests/reports-by-artifact-policy.bats
PATTERN command[^.]{0,120}output
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5, three inversions, all GREEN. (a) `carries the exact
        command and its observed output, quoted rather than paraphrased`
        became `need not carry the exact command or its observed output, and a
        paraphrase is enough`: GREEN. (b) the same plus the checklist span at
        `— the command and its output` rewritten to `— a paraphrase of what you
        ran`: GREEN. (c) R3.2's rule DELETED outright, leaving only the
        checklist span: GREEN, so the obligation can vanish from
        agents/tech-reviewer.md without a red. Two spans in one file, and the
        phrase is permeable on top of that. TASK 3 — scope to the rule and
        count its spans; the scoped pattern still has to pin the obligation.

# --- tests/scale-resolution.bats ---

FILE    tests/scale-resolution.bats
PATTERN tasks\.md[^.]{0,160}authoritative|authoritative[^.]{0,160}tasks\.md
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: `**`tasks.md` is authoritative for the
        declared `scale`.**` became `**`tasks.md` is not authoritative for the
        declared `scale` — `story.md` is.**` in references/tasks.md. The case
        stayed GREEN — `is not authoritative` sits inside the window as
        comfortably as `is authoritative`. Swapping the noun to `**`story.md`
        is authoritative ...**` does red it, so the pattern catches the wrong
        file and misses the wrong direction. One span. TASK 2 — pin `is
        authoritative` adjacent to its subject.

FILE    tests/scale-resolution.bats
PATTERN story\.md[^.]{0,200}(reported|not honoured|not honored)
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: `A `story.md` declaring a different `scale` is
        **reported**, not honoured: validation warns ... proceeds with the one
        `tasks.md` declares.` became `... is **honoured**, not reported:
        validation stays quiet, and then proceeds with the one `story.md`
        declares.` The case stayed GREEN — the alternation's first branch is
        the bare token `reported`, which the reversed sentence still contains.
        The other two branches carry the polarity and would have reddened.
        TASK 2 — drop the polarity-free branch so the pin is the phrase the
        rule already states.

FILE    tests/scale-resolution.bats
PATTERN tasks\.md[^.]{0,120}(owns|authoritative|wins)|(authoritative)[^.]{0,120}tasks\.md
VERDICT DIRECTION-BLIND
WHY     MEASURED 1.5. Inversion: all THREE spans of scripts/validate-story.sh
        negated in one edit — `is AUTHORITATIVE for `scale:``, `— tasks.md is
        authoritative, and an` and `is authoritative for `scale:`, so its` each
        gained a `not`. The case stayed GREEN. Measured separately: replacing
        one of the three with `story.md is read first and wins` leaves the
        other two, and this assertion green. Two defects — the comment states
        the rule at three sites, and the negation prefixes the anchor. TASK 3 —
        scope and count the spans; the scoped pattern still has to pin `is
        authoritative`.

FILE    tests/scale-resolution.bats
PATTERN story\.md[^.]{0,120}(first|wins)
VERDICT PINNED
WHY     MEASURED 1.5. This one is a NEGATIVE assertion, so the inversion is to
        restore the claim it retracts: `# THE SHARED SCALE RULE — `tasks.md` is
        AUTHORITATIVE for `scale:`` became `... — `story.md` is read first and
        wins for `scale:``. The case went RED at this row's `return 1`, and the
        diagnostic printed the offending block. Nothing matches it today, which
        is the assertion's whole content — it claims an absence and it detects
        the absence being ended.
ROWS
}

# THE LINT, part two: the table. Reads the table on stdin and prints one
# `file<TAB>pattern<TAB>verdict<TAB>why` per row. Any field may come out empty
# — reporting a malformed row is row_defects' job, not this parser's, so that
# a broken row is diagnosed rather than silently skipped.
allowlist_rows() {
  awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function value(s) { sub(/^[A-Z]+[ \t]+/, "", s); return trim(s) }
function flush() {
  if (started) printf "%s\t%s\t%s\t%s\n", f, p, v, w
  started = 0; f = ""; p = ""; v = ""; w = ""
}
/^#/ { next }
/^FILE[ \t]/ { flush(); started = 1; f = value($0); next }
started && /^PATTERN[ \t]/ { p = value($0); next }
started && /^VERDICT[ \t]/ { v = value($0); next }
started && /^WHY[ \t]/ { w = value($0); next }
started && /^[ \t]+[^ \t]/ { w = w " " trim($0); next }
/^[ \t]*$/ { flush(); next }
END { flush() }
'
}

# Every window pattern in the sites file that no row of the rows file names.
# Output is `file:line: pattern` — the file AND the line (R5.1), in the shape
# an author pastes into an editor.
unlisted_sites() { # $1 = rows file, $2 = sites file
  awk -F'\t' -v rowsfile="$1" '
    BEGIN { while ((getline r < rowsfile) > 0) { split(r, c, "\t"); listed[c[1] SUBSEP c[2]] = 1 } }
    { if (($1 SUBSEP $3) in listed) next; printf "%s:%s: %s\n", $1, $2, $3 }
  ' "$2"
}

# The dual, and it is what keeps the table from being an escape-hatch factory:
# a row whose pattern no longer occurs in the suite. A dead row is a
# justification nobody can check against anything, and pre-adding rows for
# patterns that do not exist yet is how an allowlist becomes a rubber stamp.
orphan_rows() { # $1 = rows file, $2 = sites file
  awk -F'\t' -v sitesfile="$2" '
    BEGIN { while ((getline s < sitesfile) > 0) { split(s, c, "\t"); present[c[1] SUBSEP c[3]] = 1 } }
    { if (($1 SUBSEP $2) in present) next; printf "%s: %s\n", $1, $2 }
  ' "$1"
}

# Structural defects in the parsed rows (R5.2). Structural is the whole claim:
# these checks see whether a reviewer was given a verdict and a sentence, never
# whether the sentence is true. The 20-character floor on WHY is a floor
# against a stub, nothing more.
row_defects() { # stdin = parsed rows
  awk -F'\t' '
    { n++
      if ($1 == "") printf "row %d: no FILE\n", n
      if ($2 == "") printf "row %d: no PATTERN\n", n
      if ($3 == "") printf "row %d (%s): no VERDICT\n", n, $2
      if ($3 != "" && $3 != "PINNED" && $3 != "ALLOWED" && $3 != "PENDING" && $3 != "DIRECTION-BLIND")
        printf "row %d (%s): verdict %s is none of PINNED, ALLOWED, PENDING, DIRECTION-BLIND\n", n, $2, $3
      if (length($4) < 20) printf "row %d (%s): no justifying sentence\n", n, $2
      marked = (index($4, "UNMEASURED — 1.5") > 0)
      if ($3 == "PENDING" && marked == 0)
        printf "row %d (%s): PENDING, but its sentence carries no UNMEASURED — 1.5 marker\n", n, $2
      if ($3 != "PENDING" && marked)
        printf "row %d (%s): verdict %s, but its sentence still carries the UNMEASURED — 1.5 marker\n", n, $2, $3
    }
  '
}

# --- 1.4: the lint, proved on planted input ----------------------------------
# As in 1.1, fixtures are written under $WORK and read, never executed. Each
# one cds into $WORK first so the planted table can name `a.bats` literally,
# the way the real table names a path relative to the repo root.

@test "1.4: a window pattern absent from the allowlist is flagged, naming file and line" {
  cd "$WORK"
  cat > a.bats <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  command grep -qiE 'listed[^.]{0,40}window' /dev/null
  command grep -qiE 'absent[^.]{0,40}window' /dev/null
}
BODY
  cat > table <<'ROWS'
FILE    a.bats
PATTERN listed[^.]{0,40}window
VERDICT ALLOWED
WHY     a fixture row, long enough to clear the stub floor.
ROWS
  allowlist_rows < table > rows
  window_sites a.bats > sites
  offenders="$(unlisted_sites rows sites)"
  [ "$(line_count "$offenders")" -eq 1 ]
  # File AND line (R5.1), in the `file:line: ` shape 1.1's lint also emits.
  printf '%s\n' "$offenders" | command grep -qF 'a.bats:4: '
  # ...and the pattern itself, so the message says what to write a row about.
  printf '%s\n' "$offenders" | command grep -q 'absent.*window'
}

@test "1.4: a tree whose every window pattern has a row passes" {
  cd "$WORK"
  cat > a.bats <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  command grep -qiE 'listed[^.]{0,40}window' /dev/null
  command grep -qiE 'absent[^.]{0,40}window' /dev/null
}
BODY
  cat > table <<'ROWS'
FILE    a.bats
PATTERN listed[^.]{0,40}window
VERDICT ALLOWED
WHY     a fixture row, long enough to clear the stub floor.

FILE    a.bats
PATTERN absent[^.]{0,40}window
VERDICT PINNED
WHY     the second fixture row, also long enough to clear the floor.
ROWS
  allowlist_rows < table > rows
  window_sites a.bats > sites
  # Both directions green: nothing unlisted, and no row left pointing at a
  # pattern the tree no longer has.
  [ -z "$(unlisted_sites rows sites)" ]
  [ -z "$(orphan_rows rows sites)" ]
  [ -z "$(row_defects < rows)" ]
}

@test "1.4: deleting a row while its pattern survives flags the site again" {
  cd "$WORK"
  cat > a.bats <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  command grep -qiE 'listed[^.]{0,40}window' /dev/null
  command grep -qiE 'absent[^.]{0,40}window' /dev/null
}
BODY
  cat > full <<'ROWS'
FILE    a.bats
PATTERN listed[^.]{0,40}window
VERDICT ALLOWED
WHY     a fixture row, long enough to clear the stub floor.

FILE    a.bats
PATTERN absent[^.]{0,40}window
VERDICT PINNED
WHY     the second fixture row, also long enough to clear the floor.
ROWS
  window_sites a.bats > sites
  allowlist_rows < full > rows
  [ -z "$(unlisted_sites rows sites)" ]
  # Now drop the second row and nothing else. The table shrinking while the
  # assertion it justified stays in the suite is the silent path this case
  # closes: the site comes straight back, named.
  head -n 4 full > shrunk
  allowlist_rows < shrunk > rows
  offenders="$(unlisted_sites rows sites)"
  [ "$(line_count "$offenders")" -eq 1 ]
  printf '%s\n' "$offenders" | command grep -qF 'a.bats:4: '
}

@test "1.4: a window pattern in a comment or a heredoc body is not a site" {
  cd "$WORK"
  cat > a.bats <<'BODY'
#!/usr/bin/env bats
# A comment may quote the shape under discussion: `the run[^.]{0,40}fail`.
@test "planted" {
  cat > /dev/null <<'INNER'
PATTERN quoted[^.]{0,40}inside a heredoc body
an apostrophe here would desync quote tracking if this body were not skipped
INNER
  command grep -qiE 'real[^.]{0,40}site' /dev/null
}
BODY
  # Both discriminations at once. Without the first, four sentences in this
  # suite demand rows; without the second, every row of the allowlist below
  # becomes a site that needs a row of its own, and the table never closes.
  window_sites a.bats > sites
  [ "$(wc -l < sites)" -eq 1 ]
  command grep -qF 'real' sites
  if command grep -qF 'the run' sites; then
    echo "the comment on line 2 was read as an assertion site"
    return 1
  fi
  if command grep -qF 'quoted' sites; then
    echo "the heredoc body was read as an assertion site"
    return 1
  fi
}

@test "1.4: a row whose pattern no longer occurs is reported as an orphan" {
  cd "$WORK"
  cat > a.bats <<'BODY'
#!/usr/bin/env bats
@test "planted" {
  command grep -qiE 'listed[^.]{0,40}window' /dev/null
}
BODY
  cat > table <<'ROWS'
FILE    a.bats
PATTERN listed[^.]{0,40}window
VERDICT ALLOWED
WHY     a fixture row, long enough to clear the stub floor.

FILE    a.bats
PATTERN retired[^.]{0,40}window
VERDICT PINNED
WHY     a row for an assertion that no longer exists in the fixture.
ROWS
  allowlist_rows < table > rows
  window_sites a.bats > sites
  orphans="$(orphan_rows rows sites)"
  [ "$(line_count "$orphans")" -eq 1 ]
  printf '%s\n' "$orphans" | command grep -q 'retired.*window'
}

@test "1.4: a row missing a field, a verdict or its marker is a structural defect" {
  cd "$WORK"
  # The last row below carries the real `UNMEASURED — 1.5` marker on purpose,
  # to exercise the stale-marker half of the rule. It is therefore one extra
  # hit for sub-task 1.5's worklist grep — inside a heredoc, verdict PINNED,
  # and so not a worklist item; the real ones are the PENDING rows above.
  cat > table <<'ROWS'
FILE    a.bats
PATTERN no-verdict
WHY     a row whose verdict line someone deleted in a hurry.

FILE    a.bats
PATTERN bad-verdict
VERDICT PROBABLY-FINE
WHY     a verdict outside the three the table admits.

FILE    a.bats
PATTERN stub
VERDICT ALLOWED
WHY     too short.

FILE    a.bats
PATTERN unmarked-pending
VERDICT PENDING
WHY     a pending row whose marker went missing, so no grep finds it.

FILE    a.bats
PATTERN stale-marker
VERDICT PINNED
WHY     UNMEASURED — 1.5, on a row that claims to have been measured.
ROWS
  # R5.2 is structural here and says so: these checks see whether a reviewer
  # was handed a verdict and a sentence, never whether the sentence is true.
  defects="$(allowlist_rows < table | row_defects)"
  printf '%s\n' "$defects" | command grep -qF 'row 1 (no-verdict): no VERDICT'
  printf '%s\n' "$defects" | command grep -qF 'row 2 (bad-verdict): verdict PROBABLY-FINE'
  printf '%s\n' "$defects" | command grep -qF 'row 3 (stub): no justifying sentence'
  printf '%s\n' "$defects" | command grep -qF 'row 4 (unmarked-pending): PENDING'
  printf '%s\n' "$defects" | command grep -qF 'row 5 (stale-marker): verdict PINNED'
  # A note line is a note, never a row — a header counted as a row is how the
  # repo's cross-reference check came to report orphans that were not there.
  if printf '# --- a note ---\n\n' | allowlist_rows | command grep -q .; then
    echo "a note line was parsed as a row"
    return 1
  fi
}

# --- 1.4: the lint, over the suite it governs --------------------------------

@test "1.4: every window pattern in tests/ carries an allowlist row" {
  # Relative paths on purpose, so the table's FILE column reads the way an
  # author would type it. This file is in scope too — it lints itself.
  ( cd "$PLUGIN_ROOT" && window_sites tests/*.bats ) > "$WORK/sites"
  allowlist_table | allowlist_rows > "$WORK/rows"
  offenders="$(unlisted_sites "$WORK/rows" "$WORK/sites")"
  if [ -n "$offenders" ]; then
    echo "A window pattern \`A[^.]{0,N}B\` cannot say in WHICH DIRECTION the two"
    echo "anchors are related, so it survives an inversion of the rule it guards"
    echo "(R5.1). Every one of them is reviewed in the allowlist table in"
    echo "tests/assertion-hygiene.bats. Add a row — file, pattern, verdict and"
    echo "the measurement that justifies it — for each site below:"
    printf '%s\n' "$offenders"
    return 1
  fi
}

@test "1.4: no allowlist row names a pattern tests/ no longer contains" {
  ( cd "$PLUGIN_ROOT" && window_sites tests/*.bats ) > "$WORK/sites"
  allowlist_table | allowlist_rows > "$WORK/rows"
  orphans="$(orphan_rows "$WORK/rows" "$WORK/sites")"
  if [ -n "$orphans" ]; then
    echo "These allowlist rows justify a pattern that is no longer in the suite."
    echo "A dead row is a justification nothing can be checked against, and a"
    echo "table that keeps them becomes a place to pre-approve patterns nobody"
    echo "has written yet. Delete the row, or restore the assertion:"
    printf '%s\n' "$orphans"
    return 1
  fi
}

@test "1.4: every allowlist row carries file, pattern, verdict and a justifying sentence" {
  # R5.2, and only the half a machine can hold: the row exists and is complete.
  # Whether its sentence is true is a reviewer's judgement, and the lint makes
  # no claim about it.
  defects="$(allowlist_table | allowlist_rows | row_defects)"
  if [ -n "$defects" ]; then
    echo "Malformed allowlist rows in tests/assertion-hygiene.bats:"
    printf '%s\n' "$defects"
    return 1
  fi
  # A table that parsed to nothing would make every case above vacuously green.
  [ "$(allowlist_table | allowlist_rows | wc -l)" -ge 1 ]
}

@test "1.4: the window-pattern census cannot be silently disabled or emptied" {
  # R5.3. What this covers, exactly: a case emptied, a case renamed away, a
  # case commented out, a `skip` added, or the census body gutted while its
  # name stays. What it does NOT cover, stated rather than implied: deleting
  # this file, deleting this case, or dropping tests/ from the runner. A guard
  # that lives inside the artifact it guards cannot outlive the artifact, and
  # this story owns nothing outside tests/ to put it in. The roster below is
  # where the regress stops.
  SELF="$PLUGIN_ROOT/tests/assertion-hygiene.bats"
  [ -f "$SELF" ]

  roster=(
    "1.4: a window pattern absent from the allowlist is flagged, naming file and line"
    "1.4: a tree whose every window pattern has a row passes"
    "1.4: deleting a row while its pattern survives flags the site again"
    "1.4: a window pattern in a comment or a heredoc body is not a site"
    "1.4: a row whose pattern no longer occurs is reported as an orphan"
    "1.4: a row missing a field, a verdict or its marker is a structural defect"
    "1.4: every window pattern in tests/ carries an allowlist row"
    "1.4: no allowlist row names a pattern tests/ no longer contains"
    "1.4: every allowlist row carries file, pattern, verdict and a justifying sentence"
    "1.4: the window-pattern census cannot be silently disabled or emptied"
  )
  # Matched as `@test "<name>" {`, never as the bare name: the roster lines
  # here carry the names too, so a bare match would find itself and every
  # deletion would look like a pass.
  for name in "${roster[@]}"; do
    if command grep -qF "@test \"$name\" {" "$SELF"; then
      continue
    fi
    echo "the case named below is gone from tests/assertion-hygiene.bats:"
    echo "  $name"
    return 1
  done

  # bats' `skip` disables a case while leaving it green and looking present.
  disabled="$(command grep -nE '^[[:space:]]*skip([[:space:]]|$)' "$SELF" || true)"
  if [ -n "$disabled" ]; then
    echo "a case in this file is skipped, which reads as green:"
    printf '%s\n' "$disabled"
    return 1
  fi

  # The census body, gutted, would keep its name and assert nothing.
  census="1.4: every window pattern in tests/ carries an allowlist row"
  body="$(awk -v name="$census" '
    index($0, "@test \"" name "\" {") == 1 { inb = 1; next }
    inb && /^}/ { inb = 0 }
    inb
  ' "$SELF")"
  for needed in window_sites allowlist_table allowlist_rows unlisted_sites "return 1"; do
    if printf '%s\n' "$body" | command grep -qF "$needed"; then
      continue
    fi
    echo "the census case body no longer mentions \`$needed\` — it has been gutted"
    return 1
  done
  [ "$(line_count "$body")" -ge 8 ]
}
