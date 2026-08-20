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
# above a row would otherwise invalidate it, silently. That is not a caution,
# it is this repo's record: story 019 wrote its census as a comment block of
# line references, sub-task 1.2 turned six one-line negations into three lines
# each, sub-task 5.1 shifted roughly two hundred more, and by the close of task
# 5 not one of those references still pointed at what it named — some at a
# blank line, some at another comment. Sub-task 5.2 replaced every one of them
# with the NAME of the case that owns the claim, which cannot drift. A pattern
# moves only when someone rewrites it, which is exactly when its row should be
# revisited; a case name moves only when someone renames it, which `1.4: the
# window-pattern census cannot be silently disabled or emptied` turns Red for
# each of the ten names on its roster.
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
#             only two verdicts that say the site is sound. NO ROW CARRIES IT
#             TODAY — tasks 2, 3 and 4 closed every one 1.5 recorded, so the
#             value is in the vocabulary for the next failed measurement rather
#             than describing anything below. Measured, not remembered — with
#             the table-bounded count above, never a whole-file grep, which the
#             planted fixtures answer.
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
# files answered the 12 keys and 15 sites the tree held THEN — the table has
# grown since and the two counts above give its present size — plus the two
# non-window candidates
# the story named by hand, both inside tests/anchor-lint.bats's `3.2 ...
# no-double-fire precedence` case — AT 1.5 neither was a window pattern, so no
# row here could hold either: a row whose pattern is not a site is an orphan
# and reds the census. Their verdicts live in 1.5's report. Sub-task 2.4
# repaired the first of the two by pinning which side wins, which MADE it a
# window pattern — hence the FIRST tests/anchor-lint.bats row below. Sub-task
# 3.3 did the same to the second: `only when` was a bare literal that three
# spans of that file answered, two of them unrelated to the rule, so deleting
# the rule outright left the case green; scoping the assertion to the section
# and pinning the condition the words govern made it a window pattern too, and
# it is the second row of that file.
#
# THE RESULT WAS NOT THE ONE THE STORY ASSUMED — and this sentence is 1.5's
# RECORD, not the table's present state, which is why it is in the past tense
# and why no live number follows it. At the close of 1.5 the sweep answered 2
# rows PINNED and 10 DIRECTION-BLIND. Both of the story's LEAD rows
# (`before…summar`, `command…output`) reproduced as direction-blind, and
# `creat…\.draft` with them, so nothing was inherited from story 019's header —
# every row here names a run of its own. For what the table says NOW, count it
# rather than read a sentence about it — and BOUND THE COUNT TO THE TABLE, for
# the same reason the `UNMEASURED — 1.5` grep above is anchored on its field:
# the planted fixtures below write rows too, so a whole-file grep answers 32
# FILE lines against the table's 20 (measured, sub-task 5.2):
#
#   sed -n '/^allowlist_table() {/,/^ROWS$/p' tests/assertion-hygiene.bats \
#     | command grep '^VERDICT' | sort | uniq -c
#
# R5.2 is met by the sentence, not by the verdict: a row states the exact
# inversion applied and the colour observed, so a reader can re-run it rather
# than trust it.
#
# WHAT COUNTS AS A SITE, settled by measurement rather than by preference:
#
#   1. A COMMENT IS NOT A SITE. Prose that DISCUSSES a window pattern quotes
#      it, and one of those quotations — `the run[^.]{0,40}fail`, the defect
#      this story exists to close — belongs to no assertion at all. The gap
#      between the two readings is not small and it is not stable: this file's
#      headers and tests/reports-by-artifact-policy.bats's both quote real
#      patterns while explaining them, so every header edit moves the
#      comments-kept number and none of them moves the shipped one. Measured on
#      demand rather than quoted here — comment out the `#` break in `scan()`
#      and re-run `window_sites tests/*.bats | wc -l` against the shipped
#      walker. Sub-task 5.2 did exactly that and the two readings differed by
#      fourteen sites, all of them sentences.
#
#   2. A HEREDOC BODY IS NOT A SITE, and here that is load-bearing rather than
#      tidy. The allowlist below is a heredoc whose every row quotes a window
#      pattern in full; a walker that read heredoc bodies would report each row
#      as a new unlisted site, which would need a row, which would be a new
#      site. Measured, on this file: skipping ON reports ZERO sites here, and
#      that zero is the invariant — this file holds no window pattern outside a
#      heredoc, so the census never has to list itself. Skipping OFF reports
#      one per allowlist row plus the planted fixtures, a number that grows
#      with the table by construction, and the table can then never close. The
#      cost is real and named: an assertion written inside a heredoc body would
#      escape this lint. None exists today.
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
# --- tests/anchor-lint.bats ---

FILE    tests/anchor-lint.bats
PATTERN anchored_commits == 0[^.]{0,40}wins
VERDICT PINNED
WHY     MEASURED 2.4, and it is a site only because of that repair: the
        predecessor was the bare literal `wins`, which is not a window pattern
        and so could hold no row. Inversion: references/validate-mode.md:276
        ``anchored_commits == 0` **wins** over rule 3 because it is the more
        specific finding` became `Rule 3 **wins** over `anchored_commits ==
        0` because the integration warning is the more specific finding` —
        predecessor GREEN, this pattern RED. Deleting the rule reds both, so
        the predecessor detected only the word's absence. Rewordings measured
        GREEN: ``anchored_commits == 0` therefore always **wins** over the
        integration warning at rule 3`, and the same line reflowed across
        three lines without a word changed (the case flattens whitespace, so a
        wrap must not decide it). `wins` occurs exactly once in the file and
        the real gap is four characters, so the 40-character window is slack
        for a connective, not reach: under the swap the nearest
        `anchored_commits == 0` is the precedence table ~200 characters back.
        Residual, named rather than hidden: a rewording that keeps the same
        side winning while replacing the verb — `rule 3 yields to
        `anchored_commits == 0`` — false-reds; pinning the order of the two
        sides is what the direction costs.

FILE    tests/anchor-lint.bats
PATTERN integration warning[^.]{0,40}fires[^.]{0,20}only when[^.]{0,40}ha(s|ve) anchored commits
VERDICT PINNED
WHY     MEASURED 3.3, and like the row above it is a site only because of the
        repair: the predecessor was the bare literal `only when`, which is not
        a window pattern and could hold no row. That literal occurs THREE times
        in references/validate-mode.md and is this rule at only one of them —
        `:195` writes `done` "only when no `[ ]` and no deferred `[~]` remains"
        (a status transition) and `:263` is a shell comment inside a code block
        ("then, only when the table below says so") — so any one of them
        answered for the rule and DELETING the rule outright left the case
        GREEN. Measured, and it is the R1.3 vector: rule at :276 deleted —
        predecessor GREEN, this pattern RED. Scoped first (R3.1) to
        `## Integration Warning` … `^## `, which owns both warnings and the
        precedence between them, `###` subsection included; `:195` sits in
        `## Status Transition` and is out by construction, measured in the
        other direction too — `:195` reworded with the rule intact stays GREEN,
        as does `:263` reworded. The `##` boundary is taken over the `###` one
        that also excludes `:195`, because the rule may legitimately move
        between the section and its own subsection: 66 lines against 31, the
        same two `only when` spans and the same one pinned span either way,
        measured. The trailing space in `^## ` IS load-bearing here — `^##`
        stops at the `### The anchor warning` heading, capturing 33 lines with
        no `only when` in them at all, which would Red on unmutated prose.
        Then the pin, because a scope alone still admits `:263`. Three anchors,
        three measured vectors: `only when` -> `except when` (the reversal) —
        RED; `The anchor warning therefore fires only when …`, the other
        warning and the opposite rule — RED; and the condition negated to `has
        no anchored commits` — RED, which is the vector no count and no scope
        would have reached. Rewordings measured GREEN: `Which means the
        integration warning fires **only when** the story does have anchored
        commits, none of which reached the main branch`, and the sentence
        reflowed across five lines with not a word changed. Residuals, named
        rather than hidden and both measured: a pronoun subject (`It therefore
        fires only when …`) false-Reds, and the SECOND conjunct reversed (`and
        at least one of them reached the main branch`) stays GREEN — reaching
        it costs a fourth anchor over a `none|no|not one|never` alternation
        whose false-Red surface is wider than the vector it buys.

# --- tests/reports-by-artifact-policy.bats ---

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])never +composing[^.]{0,60}first
VERDICT PINNED
WHY     MEASURED 4.1, and this key REPLACES `before[^.]{0,160}summar`, which
        1.5 recorded DIRECTION-BLIND and which no longer occurs in the suite.
        That predecessor could not be repaired as a pattern: `before` was the
        anchor AND the polarity, so `, never before composing any textual
        summary,` — one word inserted — left both owning cases GREEN under the
        reversed rule, re-measured on this tree and not inherited. One span per
        file, so neither scoping nor counting reaches it. 4.1 therefore
        rewrote the PROSE, in both agent files identically and inside the
        existing sentence: `, before composing any textual summary,` became
        `, never composing any textual summary first,`. The pin is the
        prohibition itself, with the negation ADJACENT to the verb it governs,
        which is what leaves a negation nowhere to park. Four vectors per file,
        one at a time, restored between, eight Reds: `never` dropped; `never
        before composing`, the exact mutation that defeated the predecessor;
        `first` -> `last`; and the clause deleted outright. The predecessor was
        GREEN on the second of those four and RED on the other three, run on
        the same mutated trees. Measured GREEN in the other direction too: the
        object reworded (`never composing the prose reply for the human
        first`) and the sentence reflowed at 72 columns with not a word
        changed. The ` +` inside the token is that reflow's doing and is
        measured, not defensive: a break falling BETWEEN the two words with a
        trailing space reaches `flat` as two spaces and false-Reds a
        single-space literal. Only whitespace fits there, so the widening
        admits no reversal. `summar` is deliberately NOT an anchor — that
        rewording drops the word — and 60 characters is the leash because
        the widest rewording measured puts 31 between the anchors. `compos`
        and `first` each occur exactly once per agent file, both inside this
        clause. Residual, named and accepted: the rule restated in its own
        pre-4.1 words false-Reds, which is R1.4's trade — the prose carries
        the token or the direction goes unpinned.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos
VERDICT PINNED
WHY     MEASURED 5.1, and NO PROSE WAS TOUCHED to get there — the repair is a
        SCOPE and a PIN, so references/validate-mode.md is byte-identical to
        the tree 4.3 left. THREE SITES, ONE KEY, by the file:pattern unit
        stated above: the ordering 4.1 rewrote and pinned in the two agent
        DEFINITIONS is stated three more times in references/validate-mode.md
        and was guarded at none of them — the Validator prompt template (:33)
        and the Auditor's (:90) both read `as the LAST step before composing
        any textual summary`, and the R2.1 paragraph (:147) reads `as the
        **last** step of their protocol, before composing any prose`. 4.1's own
        key cannot reach them: it pins `never composing ... first`, the token
        4.1 put into the agent files, and these three copies carry a DIFFERENT
        token for the same ordering. 5.1 pinned the token each copy already
        carries rather than rewriting three sites to match a fourth. Measured
        on this tree before the repair, whole suite, all three reversed at
        once: `1..498`, 498 ok, 0 not ok. `last` and `before` are BOTH polarity
        here and no reversal keeps both — RED, one mutation at a time, restored
        and cmp-verified between: `FIRST step after composing` at :33 alone, at
        :90 alone, `**first** step ... after composing any prose` at :147
        alone, and the clause deleted outright at each of the three. Six
        vectors, six Reds, where the predecessor stayed GREEN on all six.
        SCOPED PER COPY, and the scope is load-bearing rather than tidy: this
        pattern has TWO spans in the whole file, one per template, so a
        whole-file grep would let the Auditor's copy answer for the Validator's
        while that one states the opposite. Measured per scope — 1 span in
        `## Validator Sub-agent`, 1 in `## Auditor Sub-agent`, 1 in
        `## Validate Mode Procedure` — which is what lets a `-q` reach a
        single-site inversion, the reason 4.2 took one. The 40-character
        leashes are rewording slack, not reach: the real gaps are 6 characters
        at :33 and :90 (` step `) and 27 at :147 (`** step of their protocol,
        `). The `(^|[^A-Za-z])` boundary is measured free — one span per scope
        with it or without — and keeps `ballast` and `lastly` out. `compos`
        rather than `summar` for 4.1's measured reason, and here it is not
        theoretical: :147 already writes `prose` where :33 and :90 write
        `textual summary`, so a `summar` anchor could not have read all three.
        Rewordings measured GREEN: `as the LAST step of the protocol, before
        composing ...` and `as the **last** thing they do, before composing any
        prose`. WHAT THIS PATTERN DOES NOT CARRY, said plainly and in 4.2's
        words: a negation parked in FRONT of both anchors. `never as the LAST
        step before composing any textual summary` keeps every word it reads —
        the exact shape that defeated 4.1's predecessor — and it is refused by
        the companion guard in each of the three cases, `(never|not|no)` plus
        the file's own hedge list widened by `as` and `the` and repeated up to
        three times before `last`, which is not a window pattern and so holds
        no row of its own: measured RED on `never as the LAST step` at :33,
        `not as the LAST step` at :90 and `no longer as the **last** step` at
        :147, and measured SILENT on unmutated prose in all three scopes,
        including the procedure section's other two `last` tokens (`writes that
        file as its last step`, `reads last week's `pass``). Sanctioned shape,
        not a `!`: `if ... then return 1; fi`.

FILE    tests/reports-by-artifact-policy.bats
PATTERN creat[a-zA-Z]*[^.]{0,80}\.draft
VERDICT PINNED
WHY     MEASURED 1.5, HALF REPAIRED BY 3.2, CLOSED BY 4.3 — and the verdict
        turns only now, because the direction was exactly the half 3.2 left
        open. 1.5's inversion: the permission reversed at BOTH spans of one
        file — `so creating `.draft/` on demand is part of this step` became
        `... is NOT part of this step — an absent `.draft/` is a precondition
        you report rather than fix`, and the Rules bullet's `creating `.draft/`
        on demand.**` became `never creating `.draft/` on demand.**` — run on
        agents/validator.md, then on agents/auditor.md. Both cases stayed
        GREEN, with the pattern still finding 2 spans per file. Two defects,
        both measured: the file states the rule twice, AND the negation
        prefixes the anchor `creat`, so scoping to one span would not close it
        either. 3.2 CLOSED THE FIRST (R3.2): the two cases no longer ask
        whether the pattern occurs, they count its spans and require exactly 2
        per file. Measured RED at the new count and GREEN at the `-q`
        predecessor, eight mutations, one at a time — the allowance dropped
        from the Rules bullet only, then from the protocol step only, then each
        of those four spans deleted outright. Measured GREEN both ways, which
        is what keeps a count from being a sentence pin: the allowance reworded
        at both sites of a file (`so this step creates the `.draft/` directory
        itself whenever it finds none` and `; you create `.draft/` yourself
        when the story has none`), and a file reflowed with not a word changed.
        That reflow is why the count is `grep -o | wc -l` over flattened text
        and not `grep -c`: reflowing agents/validator.md at 72 columns puts a
        newline inside the Rules bullet's span, and raw `grep -c` answers 1,
        raw `grep -o` answers 1 — both false Reds — while flat + `grep -o`
        answers 2; with a newline inside BOTH spans the raw forms answer 0 and
        this one still answers 2. Cost accepted and measured, not assumed: a
        legitimate THIRD statement of the allowance false-Reds — `-ge 2`
        would buy it silence,
        and exactness was taken instead because duplication is what made this
        site blind. 3.2 DID NOT CLOSE THE SECOND and re-measured it rather than
        inheriting it: 1.5's both-spans reversal still finds 2 spans and both
        cases were still GREEN. 4.3 CLOSED IT IN THE PROSE rather than in this
        pattern, because no count and no scope reaches a negation that PREFIXES
        the anchor: each agent file's Rules bullet now reads `, and creating
        `.draft/` on demand is part of it.**`, and the direction is pinned by
        `\.draft[^.]{0,40}is +part of`, counted at 2 per file, the row below.
        This count keeps a job of its own and the two do not overlap, measured:
        the both-spans reversal leaves this one at 2 while Redding that one,
        and either span deleted outright Reds both. WHAT THIS PATTERN DOES NOT
        CARRY, said plainly and in 4.2's words: the DIRECTION. It is refused by
        the sibling assertion in the same case, not by anything here.
        TWO MORE SITES ON THIS KEY, ADDED BY 5.1, and they were measured into
        the sub-task rather than named by it: the same allowance is stated once
        in each prompt template of references/validate-mode.md (:33, :90), and
        reversing it at BOTH — `never creating `.draft/` on demand` — left the
        whole suite at `1..498`, 498 ok, 0 not ok. There it is a `-q`, not a
        count: each template scope holds exactly ONE `creat`, measured, so a
        count of 1 would assert nothing the `-q` does not, where the agent
        files state the allowance twice and any survivor answers a `-q`. RED
        measured at each template separately with the clause deleted, and the
        DIRECTION is refused there the way 4.2 refused it rather than the way
        4.3 did — by an adjacency guard on `creat` carrying the file's own
        hedge list, not a window pattern and so no row of its own. That choice
        is measured, not preferred: the guard is silent on both unmutated
        template scopes (0 hits) because each holds a single `creat`, which the
        agent files' whole-file scope could not promise, and it costs no prose
        edit — this story's rule is to pin the token the prose already carries.
        RED on `never creating `.draft/` on demand` and on `do not create
        `.draft/` yourself`; GREEN on `you create `.draft/` yourself when the
        story has none`. ONE OF THOSE TWO RESIDUALS IS NOW PAID FOR, and 6.1
        paid it in the prose rather than in this pattern: a reversal parking
        the negation AFTER the anchor (`though creating `.draft/` on demand is
        forbidden`) passed both assertions on both templates — measured on the
        pre-repair tree, both cases GREEN, while the control `never creating`
        Redded, so one form of the same reversal was caught and the other was
        not. That is D6, and it was R1.1 unmet in the two copies this key
        covers. Closed by the edit 4.3 took in the agent files, taken verbatim
        here: `in the story directory, creating `.draft/` on demand — fast and
        spike stories have none.` became `in the story directory — creating
        `.draft/` on demand is part of that step, since fast and spike stories
        have none.`, so the direction now rests on `\.draft[^.]{0,40}is +part
        of` at 1 per template section, the row below. The negation guard here
        was NOT widened, deliberately: enumerating the ways English says "no"
        is the mechanism this story replaced. The second residual stands — a
        rewording that renames the verb (`making `.draft/` yourself`)
        false-Reds — R1.4's trade, taken to keep one key with the twin rather
        than widening the anchor on the copies alone.

FILE    tests/reports-by-artifact-policy.bats
PATTERN \.draft[^.]{0,40}is +part of
VERDICT PINNED
WHY     MEASURED 4.3, and it is the direction half the count above cannot
        reach. 1.5's inversion, re-run on this tree rather than inherited: the
        permission reversed at BOTH spans of agents/validator.md — the protocol
        step's `so creating `.draft/` on demand is part of this step rather
        than a precondition for it.` to `... is NOT part of this step — an
        absent `.draft/` is a precondition you report rather than fix.`, and
        the Rules bullet to `never creating `.draft/` on demand.**` —
        predecessor GREEN with the count above still at 2, this pattern RED at
        0. The same two mutations on agents/auditor.md: predecessor GREEN, RED
        here. The defect was that the negation PREFIXES the anchor `creat`, so
        4.3 rewrote the bullet to carry a frame a negation must SPLIT instead —
        `, creating `.draft/` on demand.**` became `, and creating `.draft/` on
        demand is part of it.**`, the same frame the protocol step already
        used, in both agent files identically, one clause and no paragraph
        restructured. ANCHORED AFTER `.draft` rather than before it, which is
        arithmetic: `[^.]` cannot cross the full stop inside `` `.draft/` ``,
        so a `creat...is part of` window could never reach the verb. `is part
        of` occurs exactly twice per file, both inside the carve-out, so no
        neighbouring sentence can answer for either span. COUNTED at 2 per file
        because a `-q` is answered by whichever span survives — the one-span
        reversal is what 1.5 and 3.2 both left open: measured, one mutation at
        a time, the reversal at the protocol step alone and at the Rules bullet
        alone each count 1 and RED, in each file. Four one-span vectors, four
        Reds, where the predecessor stayed GREEN on all four. Measured GREEN in
        the other direction: both spans of both files reworded around the frame
        (`creating `.draft/` when you find none is part of this step rather
        than something you wait for`, `creating `.draft/` yourself, on demand,
        is part of that path`), and both files reflowed at 72 columns with not
        a word changed — the break falls between `creating` and `` `.draft/` ``
        and the ` +` carries it. Residual, named and accepted: a rewording that
        drops the frame (`so this step creates `.draft/` itself whenever it
        finds none` — one of the two 3.2 measured GREEN) now false-Reds, which
        is R1.4's trade: the prose carries the token or the direction goes
        unpinned.
        TWO MORE SITES ON THIS KEY, ADDED BY 6.1, and they close D6 — the one
        place a requirement of this story (R1.1) was not met in its own tree.
        The two prompt templates of references/validate-mode.md stated the
        allowance with no frame to split, so the reversal `though creating
        `.draft/` on demand is forbidden` kept the `creat` span, sat outside
        the reach of the adjacency guard that reads only in FRONT of the verb,
        and left both template cases GREEN — measured on the pre-repair tree,
        against the control `never creating`, which Redded. The prose took 4.3's
        edit verbatim in both templates, and this pattern reads them COUNTED AT
        1 PER TEMPLATE SECTION rather than `-q`: the file holds two spans, one
        per template, and the defect this story is about is the copy that
        contradicts its twin, which a `-q` over either scope answers from its
        own span. Measured on each template scope, one mutation at a time, each
        restored before the next: `though ... is forbidden` — 0, RED; the frame
        negated in place (`is NOT part of that step`) — 0, RED; `never
        creating` — 0, RED here and RED at the adjacency guard beside it; the
        clause deleted outright — 0, RED. Measured GREEN in the other
        direction: `creating `.draft/` when you find none is part of that step`
        and the sentence reflowed across lines with not a word changed.

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
PATTERN (delet|remov)[a-z]*[^.]{0,40}stale
VERDICT PINNED
WHY     MEASURED 4.2, and it REPLACES a predecessor that could hold no row:
        `command grep -i 'stale' | grep -qiE 'validation-report|audit-report|
        report file'` is not a window pattern, so the DIRECTION-BLIND verdict
        1.5 gave it lives in that file's header rather than here. It asked only
        that some LINE mentioning `stale` also name a report file, and so
        pinned neither half of its own case name. Re-measured on this tree
        rather than inherited: the deletion verb reversed at all three sites of
        references/validate-mode.md in one edit — steps 3 and 4 to `Keep`/`keep
        the stale ...`, the R2.2 heading to `never delete that agent's ...` —
        predecessor GREEN, this count RED at 1. NO PROSE WAS TOUCHED to get
        there; the repair is a SCOPE (R3.1). All three sites sit inside
        `## Validate Mode Procedure` and the `stale rendering` decoy at :363
        sits in `## Index Refresh`, so the boundary excludes it by construction
        rather than by the predecessor's co-location trick. Measured in the
        other direction twice: the decoy reworded away, and the decoy rewritten
        to plant BOTH `never delete a stale rendering` and a second `deleting a
        stale rendering` span — precisely the two mutations that would break
        this count and its companion guard if the scope leaked — GREEN on both.
        The end pattern's TRAILING SPACE is load-bearing: `^## ` captures 42
        lines including the `###` R2.2 heading, `^##` stops at the first `###`
        and captures 10, dropping the third site and Redding on unmutated
        prose. COUNTED rather than matched because the rule stands at THREE
        sites and any two survivors answer a `-q`: measured one site at a time,
        step 3 alone, step 4 alone and the heading's verb alone each take the
        count to 2 and RED where the predecessor stayed GREEN, as do the
        heading deleted outright and the whole R2.2 subsection deleted. `-eq 3`
        rather than `-ge 3` for the reason 3.2 and 3.3 both took it, at the same
        measured cost: a legitimate fourth statement false-Reds. `remov` rides
        beside `delet` because the document calls the act by both names — the
        R2.2 paragraph writes `Step 3 removes ... and step 4 removes ...` and
        this case's own name says `removes` — and the widening is measured
        free: 3 spans either way, and the section holds exactly three `stale`
        tokens, so no verb elsewhere can raise the count. Rewordings measured
        GREEN: steps 3 and 4 rewritten to `Remove the stale ...`, the heading
        rewritten to `Delete that agent's stale report file before spawning
        it`, and the section reflowed at 72 and at 40 columns with not a word
        changed — the reflow matters because it breaks between `delete the` and
        `stale` and hands `flat` TWO spaces, the false Red 4.1 measured. WHAT
        THIS PATTERN DOES NOT CARRY, said plainly: the DIRECTION. `never delete
        that agent's stale report file` counts three and passes here, because
        the negation PREFIXES the anchor. It is refused by the companion guard
        in the same case, `(never|not|no)[^A-Za-z]{1,3}(...)?(delet|remov)`,
        which is not a window pattern and so holds no row of its own — measured
        RED on that exact mutation and silent on unmutated prose, including the
        section's own `Deleting what is not there is a no-op, never an error`
        and `**Never respawn silently.**`

FILE    tests/reports-by-artifact-policy.bats
PATTERN (before[^.]{0,20}spawn[a-z]*[^.]{0,30}(delet|remov)|(delet|remov)[a-z]*[^.]{0,60}before[^.]{0,20}spawn)
VERDICT PINNED
WHY     MEASURED 4.2, and it is the OTHER half of the same case, pinned as an
        assertion of its own so a future reader sees which half broke. The
        count above reads every word of `After each spawn, delete that agent's
        stale report file` and stays at 3; the polarity token `before` is what
        that reversal cannot keep. Inversion: the R2.2 heading of
        references/validate-mode.md, `Before each spawn` -> `After each spawn`
        — predecessor GREEN, this pattern RED. The heading deleted outright,
        RED. ONE span in the scoped section, measured — the heading itself —
        which is what lets a `-q` reach a single-site inversion. A bare
        `before ... spawn` would not: the paragraph under the heading says
        `each immediately before spawning` too, so that form has TWO spans and
        the heading could be inverted alone and stay green. Both orders,
        because this task group's risk is a pin so tight a faithful rewording
        false-Reds: `Delete that agent's stale report file before spawning it`
        exercises the second branch and is GREEN, as is the section reflowed at
        72 and at 40 columns with not a word changed. Neither branch matches
        anything else in the section, measured on unmutated prose and again
        under the `After` mutation, where the `.` inside `(R2.2)` closes the
        second branch's window before it can reach the paragraph's own `before
        spawning`. Residual, named rather than hidden: that paragraph's
        restatement inverted ALONE — `each immediately after spawning`, the
        heading intact — stays GREEN, measured. Reaching it costs a second
        count over `before ... spawn`, whose price is a false Red the day that
        paragraph legitimately stops restating the heading above it.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (SendMessage[^.]{0,60}never +a +second|never +a +second[^.]{0,60}SendMessage)
VERDICT PINNED
WHY     MEASURED 4.3, and this key REPLACES `(^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage`,
        which 1.5 recorded DIRECTION-BLIND and which no longer occurs in the
        suite. That predecessor could not be repaired as a pattern: `one` is a
        SUBSTRING of every phrase that reverses it, so a reversal never has to
        come near the anchors. 1.5's inversion, re-run on this tree rather than
        inherited — row 2 of references/validate-mode.md rewritten to `**one**
        `SendMessage` ... per attempt ... — repeat the row as often as it
        takes`, the paragraph to `**One request per attempt, ...**` and row 3
        to `after the last of those requests` — left the owning case GREEN
        under a rule that now licenses unbounded re-requests. 4.3 therefore
        rewrote the PROSE, inside the existing sentences and moving no word:
        `and **never a second**` inserted into row 2, `and never a second` into
        the paragraph. On that same mutated tree: predecessor GREEN, this
        pattern RED. The token is one the reversal BREAKS rather than contains,
        which is the whole difference from `one`. Also RED, one mutation at a
        time: `never a second` -> `always a second` at both sites; the token
        dropped from row 2 alone; dropped from the paragraph alone. Row 2's
        `**one**` -> `**more than one**` with the token left standing Reds at
        the modifier guard below rather than here, which is what keeps that
        guard from being redundant. Measured GREEN in the other direction: the
        token MOVED inside row 2 and inside the paragraph with the objects
        reworded, and both reflowed at 60 columns with the break falling
        between `never a` and `second` — which is what the ` +` is for, 4.1's
        measured false Red. `SendMessage` occurs exactly once in the scoped
        section (row 2), the gap to the token is 30 characters, and neither
        branch matches anywhere else — measured on unmutated prose and again
        under every mutation above. BOTH ORDERS for rewording tolerance, the
        reason 4.2 took them. WHAT THIS PATTERN DOES NOT CARRY, said plainly:
        the bound at the PARAGRAPH and at ROW 3. The first is held by the
        `never a second` count in the same case — not a window pattern, so no
        row of its own, measured RED at 1 on either single-site removal — and
        the second by the `one request ... the run is failed` pairing below.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])(one|single) +request[^.]{0,60}the run is failed
VERDICT PINNED
WHY     MEASURED 4.3, and it is the THIRD site of the same rule: row 3 of
        references/validate-mode.md, which states the bound from the failure
        side — `Still absent or still unparseable after that one request |
        **the run is failed**`. It REPLACES a bare `the run is failed` literal
        that was not a window pattern and so held no row; that literal is
        subsumed here, since this pattern cannot match without it. Why it
        exists at all, measured rather than argued: the token pinned above is a
        bound whose SCOPE can be narrowed, and narrowing is the exact defeat
        1.5 recorded. With `never a second per attempt` at both token sites,
        row 3 rewritten to `after the last of those requests` and `repeat the
        row as often as it takes` appended — a section that now licenses
        unbounded re-requests — the pin above stayed GREEN, the count stayed
        GREEN, and this pattern went RED. Row 3 reversed ALONE, both tokens
        untouched: RED, where the predecessor stayed GREEN. The count word sits
        ADJACENT to the noun it counts, which is what makes `one` usable here
        after 1.5 proved it unpinnable on its own: a reversal that licenses
        repeats must change the noun (`the last of those requests`) and so
        loses the phrase, while a reversal that KEEPS `one` needs a modifier in
        front of it (`more than one request`), which the guard below refuses.
        Complementary, measured both ways. `single` rides beside `one` as this
        document's other word for the same count, and the widening is measured
        free: one span either way, and no other `one` in the section is within
        60 characters of the failure phrase. Rewordings measured GREEN: `after
        that single request`, and the section reflowed at 60 columns with not a
        word changed. Residual, named rather than hidden: row 3 reworded to
        drop the count altogether (`after that request`) false-Reds — R1.4's
        trade, the same one 4.1 took at the ordering clause.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)
VERDICT PINNED
WHY     MEASURED 1.5, then RE-MEASURED 4.3 once the pair it belongs to was
        repaired. 1.5 ran it both ways and the two results are the whole point.
        Inversion A — table row 2's `**one** `SendMessage`` became `**more than
        one** `SendMessage` ... repeating until it writes its report file`: RED
        here, at this row's `return 1`. Inversion B — the same count reversed
        as `one ... per attempt ... repeat the row as often as it takes`, which
        uses none of the five modifiers named above: GREEN. The guard bites the
        phrasings it enumerates and no others, so it never carried the claim on
        its own. 4.3 did NOT extend the list — an enumeration of the ways to
        say `more than one` is the mechanism this story replaces — and put the
        bound in the PROSE instead, pinned by the two rows above. KEPT rather
        than deleted, and measured NOT redundant: row 2's `**one**` swapped for
        `**more than one**` with `**never a second**` left standing passes both
        of those and Reds here alone, which is the one vector nothing else in
        the case reaches. Both of 1.5's inversions re-run on the rewritten
        tree: A still RED here, B now RED at the pin above. Silent on unmutated
        prose, which holds four `one`s, measured. One red-on-correct vector,
        named and accepted: `never more than one `SendMessage`` Reds here, and
        row 2 has no need of that phrasing now that its prohibition is stated
        adjacent as `**never a second**`. Sanctioned shape, not a `!`: `if ...
        then return 1; fi`, which errexit honours wherever it sits in the body.

FILE    tests/reports-by-artifact-policy.bats
PATTERN carries[^.]{0,60}(command[^.]{0,120}output|output[^.]{0,120}command)
VERDICT PINNED
WHY     MEASURED 3.1, and the scope had to come first: the predecessor
        `command[^.]{0,120}output` read the WHOLE of agents/tech-reviewer.md,
        where two spans answer it — the rule at :44 and the report-format
        bullet at :55 — so 1.5's inversion (`carries the exact command and its
        observed output` -> `need not carry … and a paraphrase is enough`) and
        even DELETING the rule outright both stayed GREEN. Scoped to
        `## Measurement, Not Argument` the pair has one span and `output`
        occurs once. Measured: rule DELETED — predecessor GREEN, this pattern
        RED; `carries` -> `need not carry` — predecessor GREEN, this pattern
        RED; whole section deleted — RED. Also RED: `does not carry` and `is
        not required to carry`, both of which lose the inflection the way
        English negates this rule. Rewordings measured GREEN: `carries the
        command it ran and the output that command produced`, `carries, quoted
        rather than paraphrased, the exact command you ran and the output you
        saw`, the pair in the other order, and the rule reflowed across lines
        without a word changed. GREEN too, and it is the point of the scope:
        the :55 bullet rewritten to `— a paraphrase of what you ran` with the
        rule intact. The 60-character leash is rewording tolerance, not reach
        — parentheticals between the verb and its object measure 40-44 — and
        tightening it buys nothing, because a sentence where `carries` governs
        another noun with the pair in a later clause measures 39. That shape
        is the residual; the companion row below is what refuses a negation.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?carries|carries[^A-Za-z]{1,3}(no|neither|nothing)[^.]{0,80}output)
VERDICT PINNED
WHY     MEASURED 3.1. It is the same case's negation-refusal guard, and it
        exists because the inflection alone is not the whole rule: `carries
        neither the exact command nor its observed output`, `never carries`
        and `no longer carries` all pass the positive match above. All three
        RED at this guard, measured. Only the second branch carries a window,
        and its `output` leash is the discrimination, measured both ways: a
        negation beside `carries` reverses the rule only when it reaches the
        pair, so `carries no command it did not actually run` — the rule's own
        closing clause restated — stays GREEN, while `carries no exact command
        and no observed output` and the reversed-order `carries neither the
        observed output nor the exact command` both Red. Sanctioned shape, not
        a `!`: the guard is `if … then return 1; fi`, which errexit honours
        wherever it sits in the body.

FILE    tests/reports-by-artifact-policy.bats
PATTERN verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)
VERDICT PINNED
WHY     MEASURED 2.1. It replaced a bare `validation-report` / `audit-report`
        occurrence check, which asserted a FILENAME and so survived the rule
        being reversed. Inversion: steps 3 and 4 of
        references/validate-mode.md rewritten to `Take the verdict from the
        final message` and `take its verdict from its final message the same
        way`, both deletes — and so both filenames — left in place. The
        predecessor stayed GREEN; this pattern went RED, on the first of the
        two greps. Rewording: `The verdict is read from that report file
        rather than from the reply` and `its verdict is read off that report
        file the same way` — GREEN, which is what `off` and the 30-character
        tail are there for. The polarity here is the OBJECT: a verdict comes
        from a file or from disk, and a message is neither. Residual, named
        rather than hidden: `the verdict not from the file but from the reply`
        parks a negation between the anchors and would pass — an inversion
        states the new rule positively, but this pattern does not detect the
        stilted form.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (message|repl(y|ies))[^.]{0,120}[^A-Za-z](no|not|never)[^A-Za-z][^.]{0,40}(pass/fail|verdict|decision)
VERDICT PINNED
WHY     MEASURED 2.1, and it is the other half of the same case: the reply is
        the source of NO verdict. Inversion: the R2.1 paragraph at
        references/validate-mode.md:147 rewritten so that `steps 3-5 conclude
        from the final message` and `The report file is a convenience ... and
        **the source of no pass/fail decision**` — the negation kept, moved
        onto the FILE — RED. Rewording: `the final message is a convenience
        ... and decides no pass/fail` — GREEN. The polarity token sits inside
        the match AND governs the reply, which is exactly what the reversal
        cannot keep. The boundaries around `(no|not|never)` are measured, not
        decorative: without them R2.3's table row 2, which ends `asking it to
        write its report file now`, answers the assertion by itself.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((^|[^A-Za-z])(never|not)[^A-Za-z]|rather than|instead of)[^.]{0,80}(chat|message|repl(y|ies)|said|prose)
VERDICT PINNED
WHY     MEASURED 2.1. Inversion: references/validate-mode.md:183 rewritten to
        `Rules 1-3 turn on what an agent said in chat — never on the `verdict`
        field of `.draft/validation-report.yaml` and
        `.draft/audit-report.yaml`` — every filename kept, so the predecessor
        (`validation-report|audit-report|report file` alone) stayed GREEN on a
        section that now states the opposite rule; this pattern went RED,
        because the negation now governs the file and the full stops in
        `.draft/...yaml` close the window before any word for the reply.
        Rewording: `the verdict is read from the report files ... rather than
        from the agents' replies` — GREEN. Exactly one line of that section
        names a report file, so the grep that feeds this one scopes it to the
        rule's own paragraph rather than to the section.

# --- tests/scale-resolution.bats ---

FILE    tests/scale-resolution.bats
PATTERN tasks\.md[^.]{0,24}is (the )?authoritative
VERDICT PINNED
WHY     TWO SITES, ONE KEY, the second added by 3.3: the references/tasks.md
        contract case reads this pattern, and so now does the comment census
        over scripts/validate-story.sh, which COUNTS its spans. One row covers
        both, by the file:pattern unit stated above; the two measurements are
        separate and both are recorded here.
        MEASURED 2.3, and it is the repair 1.5 asked for: the predecessor
        `tasks\.md[^.]{0,160}authoritative|authoritative[^.]{0,160}tasks\.md`
        was DIRECTION-BLIND and is gone. Inversion, re-run against this
        pattern: references/tasks.md:68 `**`tasks.md` is authoritative for the
        declared `scale`.**` became `**`tasks.md` is not authoritative for the
        declared `scale` — `story.md` is.**` — predecessor GREEN, this one
        RED, because `is authoritative` is now the match rather than a
        neighbour of it and a negation has nowhere to park. Swapping the noun
        to `**`story.md` is authoritative ...**` still reds, so that vector did
        not regress. Rewordings measured GREEN: line 68 reflowed with the break
        falling between `tasks.md`` and `is authoritative` (the case reads
        flattened text, so a wrap must not bite), and `**`tasks.md` is the
        authoritative artifact for the declared `scale`.**`. One span in the
        whole file, so the flatten stays whole-file and needs no section
        scope. Residual, named rather than hidden: an adverb between the two
        words — `is always authoritative` — false-reds, measured. Admitting an
        arbitrary word there would admit `is not authoritative`, which is the
        inversion itself, so the pin keeps its edge and the row records where
        it lies.
        MEASURED 3.3 AT THE SECOND SITE, where the same pin is also a COUNT.
        That site had a row of its own —
        `tasks\.md[^.]{0,120}(owns|authoritative|wins)|(authoritative)[^.]{0,120}tasks\.md`,
        DIRECTION-BLIND, TASK 3 — and it is DELETED rather than moved: this key
        replaced it, and a row whose pattern is gone is an orphan.
        scripts/validate-story.sh states the rule in THREE comment spans (:136
        the shared-rule header, :148 the written-contract paragraph, :233 the
        disagreement warning's rationale) and the predecessor asked only whether
        ONE of them existed. Eight removal mutations, one at a time, each run
        against both patterns: a `not` in all three spans, a `not` in each span
        alone, and each span's rule deleted outright — predecessor GREEN on
        every one, this pattern RED on every one. Counted: 0 spans for the
        three-span negation, 2 for every single-span negation or deletion. The
        polarity is the half a count cannot reach and the pin does: 1.5's
        negation PREFIXES the anchor (`is not authoritative`), so three negated
        spans would still COUNT three, and it is `is authoritative` being the
        match rather than a neighbour of it that takes them to 0. Rewording
        measured GREEN — all three spans rewritten, each with its line break
        falling at a different point inside the phrase, still counts 3. The
        representation is measured, not assumed: `grep -c` counts matching
        LINES, and comment_blocks joins a run of `#` lines, so :136 and :148
        land on ONE line and it answers 2 pristine AND 2 with either of those
        two spans deleted — blind to two of the three removals. Counting over
        the raw file instead answers 1 on the rewording, a false Red on prose
        that still states the rule three times. `grep -o | wc -l` over the
        flattened blocks is the form that answers 3, 2 and 3. The cost of
        `-eq 3` is measured too: a legitimate FOURTH statement of the rule
        counts 4 and false-Reds, and `-ge 3` Reds all eight removals just as
        well while buying that fourth span silence. Exactness taken because
        DUPLICATION is what blinded this site — the rule already stands three
        times, which is why one could vanish unseen — the same trade 3.2 took
        at the `.draft/` carve-out.

FILE    tests/scale-resolution.bats
PATTERN story\.md[^.]{0,200}reported[^.]{0,40}(not|never) honou?red
VERDICT PINNED
WHY     MEASURED 2.3, and it is the repair 1.5 asked for: the predecessor
        `story\.md[^.]{0,200}(reported|not honoured|not honored)` offered a
        polarity-free first branch and is gone. Inversion, re-run against this
        pattern: references/tasks.md:70 `A `story.md` declaring a different
        `scale` is **reported**, not honoured: validation warns ... proceeds
        with the one `tasks.md` declares.` became `... is **honoured**, not
        reported: validation stays quiet, and then proceeds with the one
        `story.md` declares.` — predecessor GREEN, this one RED. The polarity
        here is the PAIRING, not either word: both halves are required, in the
        order the rule states them, so a sentence that keeps `reported` while
        dropping `not honoured` no longer answers. Deleting `, not honoured`
        outright also reds it, measured. Rewordings measured GREEN: the
        sentence reflowed with the break between `**reported**,` and `not
        honoured`, and `When a `story.md` declares a different `scale`, the
        disagreement is **reported**, never honoured: ... and resolves from
        `tasks.md` anyway.` — hence the `never` branch, which negates the same
        verb rather than adding a second claim. One span in the whole file:
        `honour` occurs once in it. Residual, named rather than hidden: the
        pairing stated the other way round — `is not honoured but merely
        reported` — false-reds, measured; the pin is the order the rule states.

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
  # R5.3. WHAT THIS COVERS AND WHAT IT DOES NOT, measured by sub-task 6.2 as
  # 4 mutations x 16 rostered cases, one at a time, each restored before the
  # next — 64 runs, not a table restated from the sub-task that wrote it.
  #
  # The table 5.2 left here read (10 cases, and only 2 of the 4 columns held):
  #
  #                                  the census case   the other nine
  #   a `skip` added                 RED              RED    (file-wide grep)
  #   the case renamed away          RED              RED    (roster below)
  #   the case commented out         RED              GREEN  <- was open
  #   the body gutted, name intact   RED              GREEN  <- was open
  #
  # What 6.2 measures (16 cases — the 10 above plus the six `1.1:` cases,
  # which were rostered nowhere):
  #
  #                                  the census case   the other fifteen
  #   a `skip` added                 SKIP-GREEN <-open RED    (file-wide grep)
  #   the case renamed away          RED              RED    (roster below)
  #   the case commented out         RED              RED    (anchored match)
  #   the body gutted, name intact   GREEN      <-open RED    (per-case tokens)
  #
  # 62 of 64 RED. The two former holes are closed, and neither needed a new
  # mechanism — only the two existing checks applied to every name:
  #
  #   COMMENTED OUT was green because the roster matched with `grep -F`, which
  #   finds `# @test "..." {` as readily as the real header. The match is now
  #   anchored at COLUMN 1 (`index($0, want) == 1`), the idiom the body walker
  #   below already used, so a commented header is not a header. Measured on
  #   the whole case commented out, header through closing brace — the shape a
  #   silent removal actually takes; the header alone leaves the body as
  #   top-level shell and the file stops parsing, which Reds for another reason.
  #
  #   GUTTED was green because the body check read ONE case — the census — by
  #   construction. It now runs per rostered case, over that case's own tokens.
  #
  # THE TWO CELLS THAT REPLACE THEM ARE BOTH THE CENSUS'S OWN, and they are
  # narrower than what they replace — nine cases' worth of hole became one
  # case's, in the two mutations that stop the guard from running at all. A
  # `skip` here is not caught because the grep that finds a `skip` is in the
  # body that gets skipped; a gutted body here is not caught because the check
  # that reads bodies is the body that was gutted. They are the same limit as
  # deleting this case, one step in: a guard cannot outlive the artifact that
  # holds it, and a second case asserting THIS one would move the hole rather
  # than close it. Measured and named, not left to be found.
  #
  # WHAT NOTHING HERE COVERS, stated rather than implied: deleting this file,
  # deleting this case, or dropping tests/ from the runner. This story owns
  # nothing outside tests/ to put such a guard in. The roster below is where
  # the regress stops.
  SELF="$PLUGIN_ROOT/tests/assertion-hygiene.bats"
  [ -f "$SELF" ]

  # THE ROSTER IS NOW EVERY REAL CASE IN THIS FILE, not the ten of 5.2. The six
  # `1.1:` cases were the same hole one file-section up — and the last of them,
  # `no .bats file in tests/ inverts a command as an assertion`, is the case
  # that imposes R4.1/R4.2 on the WHOLE suite. It was in no roster and had no
  # body check: commented out or gutted, it went silently green. Nobody asked
  # for it; it is the defect this case exists to refuse, one file-section over.
  #
  # Each entry is `<case name>|<token>;<token>;...`. The tokens are what the
  # case CANNOT assert without — its lint function, its fixture, its diagnosis
  # — so an emptied body loses them while a reworded one keeps them. No name
  # holds a `|` and no token holds a `;`, measured on this table.
  roster=(
    "1.1: a !-inverted command outside last position is flagged, naming file and line|inverted_commands;line_count;nonfinal.bats"
    "1.1: a !-inverted command in LAST position is flagged too — no position exemption|inverted_commands;line_count;final.bats"
    "1.1: [ ! ] , [[ ! ]] and a ! inside an if condition are conforming|inverted_commands;conforming.bats"
    "1.1: a ! in a comment, a quoted string, an awk program or a heredoc is not a negation|inverted_commands;lookalikes.bats"
    "1.1: every statement start is caught and every offender is listed, not just the first|inverted_commands;starts.bats;second.bats"
    "1.1: no .bats file in tests/ inverts a command as an assertion|inverted_commands;PLUGIN_ROOT;return 1"
    "1.4: a window pattern absent from the allowlist is flagged, naming file and line|window_sites;unlisted_sites;allowlist_rows"
    "1.4: a tree whose every window pattern has a row passes|unlisted_sites;orphan_rows;row_defects"
    "1.4: deleting a row while its pattern survives flags the site again|window_sites;unlisted_sites;shrunk"
    "1.4: a window pattern in a comment or a heredoc body is not a site|window_sites;return 1"
    "1.4: a row whose pattern no longer occurs is reported as an orphan|orphan_rows;window_sites;allowlist_rows"
    "1.4: a row missing a field, a verdict or its marker is a structural defect|row_defects;allowlist_rows;return 1"
    "1.4: every window pattern in tests/ carries an allowlist row|window_sites;allowlist_table;allowlist_rows;unlisted_sites;return 1"
    "1.4: no allowlist row names a pattern tests/ no longer contains|window_sites;allowlist_table;orphan_rows;return 1"
    "1.4: every allowlist row carries file, pattern, verdict and a justifying sentence|allowlist_table;allowlist_rows;row_defects;return 1"
    "1.4: the window-pattern census cannot be silently disabled or emptied|roster;body_of;SELF;return 1"
  )

  # THE ROSTER IS COMPLETE, AND THAT IS ASSERTED RATHER THAN INTENDED. Every
  # real case in this file is named `N.N: ...`; every case this file PLANTS in
  # a fixture is named `planted`. So the two shapes partition the `^@test "`
  # lines, and the count of the first is the count of cases that must be
  # rostered. Measured on this tree: 27 header lines, 16 real, 11 planted.
  #
  # The partition is checked, not assumed: a fixture planting a `N.N: ` name
  # would be counted as a real case and would also forge the boundary the body
  # walker below stops at. If that ever happens this Reds and says so, which is
  # the only warning either mechanism needs.
  all_headers="$(command grep -c '^@test "' "$SELF")"
  real_headers="$(command grep -c '^@test "[0-9]' "$SELF")"
  planted_headers="$(command grep -c '^@test "planted" {' "$SELF")"
  if [ "$((real_headers + planted_headers))" -ne "$all_headers" ]; then
    echo "this file holds a case header that is neither a real \`N.N: \` case nor a"
    echo "planted \`@test \"planted\" {\` fixture — the roster's census cannot count"
    echo "it, and the body walker's boundary cannot tell it from a real case:"
    command grep '^@test "' "$SELF" | command grep -v '^@test "[0-9]' | command grep -v '^@test "planted" {'
    return 1
  fi
  # A case added to this file without a roster entry is the silent removal this
  # case is about, arriving from the other side. The cost is stated: adding a
  # case here means adding its row, the same trade the allowlist table takes.
  if [ "$real_headers" -ne "${#roster[@]}" ]; then
    echo "this file holds $real_headers real cases but the roster names ${#roster[@]}."
    echo "Every case in this file carries a roster entry — add one, or remove the"
    echo "stale entry, so that a deletion cannot pass as a rename."
    return 1
  fi

  # THE BODY WALKER, AND ITS BOUNDARY IS THE CASE'S OWN `}` RATHER THAN THE
  # NEXT HEADER, which is measured rather than preferred: this file puts ~1000
  # lines of helpers and the allowlist table between the `1.1:` cases and the
  # `1.4:` ones, so a walk to the next header would hand a gutted `1.1:` case
  # a thousand lines of other people's code to satisfy its tokens with.
  #
  # HEREDOC BODIES ARE CARRIED, NOT PARSED. Eleven fixtures in this file close
  # with a `}` in column 1 inside a heredoc — the planted case's own brace — so
  # a walker that stopped at the first `^}` would stop inside the fixture,
  # before the assertions it was called to read. Every heredoc here opens with
  # a quoted delimiter and none is `<<-` (measured: 19 opens, 0 dash-stripped),
  # so the delimiter is the second field when the opening line is split on a
  # quote, and the body is skipped to the line that equals it.
  #
  # A COMMENT IS PROSE AND IS DROPPED BEFORE EITHER RULE LOOKS AT THE LINE,
  # which is the discrimination `window_sites` makes for the same reason and
  # is measured here rather than assumed: the first draft of this walker read
  # the sentence above — which QUOTES a heredoc opener — as an opener, took a
  # delimiter that never recurs, and ran the census's own body to end of file.
  # Dropping comments first fixes that at the source and makes the tokens below
  # code-only for free: a body whose code was deleted keeps its comment block,
  # and a token quoted in prose must not answer for the assertion that is gone.
  q="'"
  body_of() { # $1 = case name -> its code lines, heredoc bodies included
    awk -v want="@test \"$1\" {" -v q="$q" '
      index($0, want) == 1 { inb = 1; next }
      inb == 0 { next }
      hd != "" { print; if ($0 == hd) hd = ""; next }
      /^[[:space:]]*#/ { next }
      index($0, "<<" q) > 0 { split($0, parts, q); hd = parts[2]; print; next }
      $0 == "}" { exit }
      { print }
    ' "$SELF"
  }

  # bats' `skip` disables a case while leaving it green and looking present.
  # File-wide, because a `skip` anywhere in this file is the same defect.
  disabled="$(command grep -nE '^[[:space:]]*skip([[:space:]]|$)' "$SELF" || true)"
  if [ -n "$disabled" ]; then
    echo "a case in this file is skipped, which reads as green:"
    printf '%s\n' "$disabled"
    return 1
  fi

  for entry in "${roster[@]}"; do
    name="${entry%%|*}"
    tokens="${entry#*|}"

    # Matched at column 1 as `@test "<name>" {`, never as the bare name and
    # never with `grep -F`: the roster lines here carry the names too, so a
    # bare match would find itself and every deletion would look like a pass —
    # and an unanchored match would find the header commented out, which is
    # the cell 5.2 left open.
    if awk -v want="@test \"$name\" {" '
         index($0, want) == 1 { found = 1 }
         END { exit !found }
       ' "$SELF"
    then
      :
    else
      echo "the case named below is gone from tests/assertion-hygiene.bats, or"
      echo "its header is commented out, which is the same thing to bats:"
      echo "  $name"
      return 1
    fi

    code="$(body_of "$name")"
    if [ "$(line_count "$code")" -lt 3 ]; then
      echo "the case named below has fewer than three lines of code left — it has"
      echo "been emptied:"
      echo "  $name"
      return 1
    fi
    IFS=';' read -r -a needed <<< "$tokens"
    for tok in "${needed[@]}"; do
      if printf '%s\n' "$code" | command grep -qF "$tok"; then
        continue
      fi
      echo "the body of the case named below no longer mentions \`$tok\` — it has"
      echo "been gutted:"
      echo "  $name"
      return 1
    done
  done
}
