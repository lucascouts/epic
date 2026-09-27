#!/usr/bin/env bats
# The suite lints itself for `!`-inverted assertions.
#
# THIS FILE HOSTS TWO LINTS, each with its own header and its own walker.
# The one documented immediately below flags `!`-inverted assertions. The
# second, further down, refuses to let a WINDOW PATTERN — `A[^.]{0,N}B`, the
# shape that says A and B share a sentence but cannot say in which direction —
# sit in tests/ without a row in an allowlist table naming a verdict and its
# justification.
#
# THAT LINT CHECKS THE ROW EXISTS. It does NOT check that the row's sentence is
# true, and it cannot: whether a window pattern survives an inversion depends
# on the prose it reads, not on the regex. A green census means every window
# pattern has been written down for a reviewer, nothing more. Reading it as a
# guarantee of polarity is unearned confidence.
#
# WHY THIS FILE EXISTS. Bash exempts a command inverted with the reserved word
# `!` from `errexit`: `! cmd` never trips `set -e`, whatever cmd returns. A bats
# test body runs under errexit, so `! grep -q x` anywhere but the LAST statement
# of a case is inert — it asserts nothing, and the case stays green however the
# file under test changes. In last position it happens to work, because bats
# reads the body's final status; that is an accident of placement, not a
# property of the assertion, and one appended line away from silence. The rule
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
# THREE DISCRIMINATIONS, each exercised by a fixture case below:
#
#   1. `[ ! -f x ]` and `[[ ! "$a" =~ b ]]` are CONFORMING. The `!` there
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
#      file. Without heredoc skipping, this file would report itself.
#
# SCOPE. The repo-wide case globs `tests/*.bats`, which is not recursive: a
# `.bats` file added under a subdirectory of tests/ would escape it.
#
# THE WALKER IS LOCAL TO THIS LINT ON PURPOSE. The window-pattern lint below
# asks a different question; a shared walker would couple two lints for no
# gain.
#
# Case names carry a section prefix (`1.1:` for this lint, `1.4:` for the
# window-pattern lint), so `bats --filter '^1\.1:'` selects exactly this
# contract.

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
    # Discrimination 1: a conditional operator, not the reserved word.
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

# BATS COLLECTS ANY LINE THAT STARTS WITH `@test`, HEREDOC OR NOT: bats 1.10,
# the version `apt` ships on ubuntu-latest, registers a `@test` inside
# `<<'BODY'` as a case, indented or in column 1 alike. A fixture that plants
# `@test "planted"` verbatim therefore makes this file fail to load with
# duplicate test names, and `bats tests/` aborts the whole suite on a load
# error.
#
# The fixtures therefore carry `%%TEST%%` and this turns it back into `@test`
# on the way to disk, so the lint reads a real test header while bats'
# preprocessor sees no case. The census case asserts that no line in this file
# starts with `@test` except a real header, which is the condition stated as a
# check rather than as a comment.
plant() { # $1 = fixture path; body on stdin, `%%TEST%%` for `@test`
  sed 's/^%%TEST%%/@test/' > "$1"
}

# --- 1.1: the lint, proved on planted input ----------------------------------
# Fixtures are written under $WORK, never into tests/: they are input to the
# lint, not cases bats should collect. They are read, never executed, so what
# matters about each one is its SHAPE. Each goes through `plant` and writes
# `%%TEST%%` where the fixture needs `@test`, because bats collects `@test`
# lines even inside a heredoc. See `plant`.

@test "1.1: a !-inverted command outside last position is flagged, naming file and line" {
  plant "$WORK/nonfinal.bats" <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
  ! true
  [ 1 -eq 1 ]
}
BODY
  offenders="$(inverted_commands "$WORK/nonfinal.bats")"
  [ "$(line_count "$offenders")" -eq 1 ]
  # File AND line, in the `file:line: <the line>` shape — the trailing
  # space is part of the format, so a bare grep-style `file:line:` would fail.
  printf '%s\n' "$offenders" | command grep -qF "$WORK/nonfinal.bats:3: "
  printf '%s\n' "$offenders" | command grep -qF '! true'
}

@test "1.1: a !-inverted command in LAST position is flagged too — no position exemption" {
  plant "$WORK/final.bats" <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
  [ 1 -eq 1 ]
  ! true
}
BODY
  # Green by accident of placement, inert the moment a line is appended. The
  # rule forbids the shape, not the position, so this must red exactly as above.
  offenders="$(inverted_commands "$WORK/final.bats")"
  [ "$(line_count "$offenders")" -eq 1 ]
  printf '%s\n' "$offenders" | command grep -qF "$WORK/final.bats:4: "
}

@test "1.1: [ ! ] , [[ ! ]] and a ! inside an if condition are conforming" {
  plant "$WORK/conforming.bats" <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
  # so flagging one would be a false red on the sanctioned shape.
  offenders="$(inverted_commands "$WORK/conforming.bats")"
  [ -z "$offenders" ]
}

@test "1.1: a ! in a comment, a quoted string, an awk program or a heredoc is not a negation" {
  plant "$WORK/lookalikes.bats" <<'BODY'
#!/usr/bin/env bats
# A comment may quote the forbidden shape: `! grep -q x`, and even `; ! true`.
%%TEST%% "planted" {
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
  # Discrimination 3. Without it the lint reds on text it should ignore,
  # including the `!inb && …` awk shape this suite uses.
  offenders="$(inverted_commands "$WORK/lookalikes.bats")"
  [ -z "$offenders" ]
}

@test "1.1: every statement start is caught and every offender is listed, not just the first" {
  plant "$WORK/starts.bats" <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
  ! true
  true && ! true
  true || ! true
  true; ! true
  { ! true; }
  if true; then ! true; fi
  if false; then :; else ! true; fi
}
BODY
  plant "$WORK/second.bats" <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
    echo "is discarded and the assertion is inert. Rewrite each one as"
    echo "  if <cmd>; then echo '<what went wrong>'; return 1; fi"
    printf '%s\n' "$offenders"
    return 1
  fi
}

# --- 1.4: the window-pattern lint --------------------------------------------
#
# WHY THIS SECOND LINT EXISTS. A window pattern is a regex of the shape
# `A[^.]{0,N}B`: match A, then anything up to N characters that is not a full
# stop, then B. It is how this suite asserts that two things are said in the
# same sentence however the sentence wraps. What it cannot say is in WHICH
# DIRECTION they are said: `the run[^.]{0,40}fail` is satisfied by "the run is
# **not** failed" exactly as by "the run is failed", so an inversion of the very
# rule the assertion guards leaves it green.
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
# above a row would otherwise invalidate it, silently. For the same reason a
# claim is referenced by the NAME of the case that owns it, never by a line
# number. A pattern moves only when someone rewrites it, which is exactly when
# its row should be revisited; a case name moves only when someone renames it,
# which `1.4: the window-pattern census cannot be silently disabled or emptied`
# turns Red for every name on its roster.
#
# THE VERDICT COLUMN takes four values:
#
#   PINNED  — the claim is directional and its polarity token sits INSIDE the
#             match, so a negation cannot be parked between the anchors.
#   ALLOWED — the pattern makes NO directional claim (a filename, a field name,
#             a topic), so it has no polarity to pin. This is NOT an escape
#             hatch for a directional claim. The lint cannot tell the two
#             apart — the row's sentence is what a reviewer reads, and it is
#             the only thing standing between the two.
#   DIRECTION-BLIND
#           — the rule the pattern guards was inverted in the prose file and
#             the owning case stayed GREEN. The row records the inversion and
#             the colour and names the repair still owed. THIS IS NOT A PASS,
#             and the word is chosen so it cannot be read as one: PINNED and
#             ALLOWED are the only two verdicts that say the site is sound.
#   PENDING — the verdict is not settled yet. Writing PINNED or ALLOWED on a
#             row nobody has checked would fabricate evidence, so the table
#             says PENDING out loud instead.
#
# EVERY PENDING ROW CARRIES THE MARKER `UNMEASURED` in its sentence, and the
# lint enforces the equivalence in both directions: a PENDING row without the
# marker fails, and any other verdict that still carries the marker fails.
# That makes the worklist a grep, not a reading:
#
#   command grep -n '^WHY     UNMEASURED' tests/assertion-hygiene.bats
#
# Anchored on the WHY field at column 1, not on the bare marker: the marker
# also appears in this header, in row_defects' own diagnostics, and once in a
# planted fixture — the one at "a row missing a field, a verdict or its
# marker is a structural defect", which carries the marker on a PINNED row on
# purpose, to exercise the stale-marker half of the rule. The grep is the
# interface because a .bats file cannot be sourced — `@test "x" {` is not valid
# bash, so allowlist_table and allowlist_rows are reachable from a case and
# nowhere else.
#
# HOW A ROW IS SETTLED. Invert, in the prose file the owning case reads, the
# rule that case exists to guard, run the case, and restore the file — one
# mutation at a time, never two at once. A candidate that is not a window
# pattern cannot hold a row: a row whose pattern is not a site is an orphan
# and reds the census.
#
# For the table's present verdicts, count them rather than read a sentence
# about them — and BOUND THE COUNT TO THE TABLE, for the same reason the
# `UNMEASURED` grep above is anchored on its field: the planted fixtures below
# write rows too, so a whole-file grep overcounts:
#
#   sed -n '/^allowlist_table() {/,/^ROWS$/p' tests/assertion-hygiene.bats \
#     | command grep '^VERDICT' | sort | uniq -c
#
# A row's sentence states the exact inversion applied and the colour
# observed, so a reader can re-run it rather than trust it.
#
# WHAT COUNTS AS A SITE:
#
#   1. A COMMENT IS NOT A SITE. Prose that DISCUSSES a window pattern quotes
#      it without asserting anything — `the run[^.]{0,40}fail` above belongs to
#      no assertion at all — and counting comments would make the census move
#      with every header edit. To see the gap, comment out the `#` break in
#      `scan()` and re-run `window_sites tests/*.bats | wc -l`.
#
#   2. A HEREDOC BODY IS NOT A SITE, and here that is load-bearing rather than
#      tidy. The allowlist below is a heredoc whose every row quotes a window
#      pattern in full; a walker that read heredoc bodies would report each row
#      as a new unlisted site, which would need a row, which would be a new
#      site. With heredoc skipping on, this file reports ZERO sites, and that
#      zero is the invariant — this file holds no window pattern outside a
#      heredoc, so the census never has to list itself. With skipping off,
#      every allowlist row becomes a site and the table can never close. The
#      cost is named: an assertion written inside a heredoc body would escape
#      this lint.
#
#   3. THE UNIT IS `file:pattern`, NOT `file:line`. Two sites that run the same
#      pattern share one row: `story\.md[^.]{0,120}(first|wins)` appears twice
#      in scale-resolution.bats — once as the assertion and once in the
#      diagnostic that prints the offending block when it fails. The lint makes
#      NO attempt to tell an assertion from a diagnostic: it cannot, and a rule
#      it cannot enforce would be a claim it has not earned. Both occurrences
#      key to the one row, which is the honest outcome anyway — the diagnostic
#      is the assertion's own echo, and one justification covers both.
#
#   4. A WINDOW PATTERN OUTSIDE ANY QUOTED SPAN is reported under the literal
#      key `UNQUOTED-WINDOW`, which no row can plausibly match, so it fails
#      until a human looks. Dropping it silently instead would be the exact
#      failure mode this lint exists to prevent.
#
# SCOPE, and its limit, the same as the `!` lint's: the repo-wide cases glob
# `tests/*.bats`, which is NOT recursive. A .bats file added under
# tests/<subdir>/ would escape both lints.
#
# THE WALKER BELOW IS THIS LINT'S OWN, not a helper shared with the `!` lint.
# The two answer different questions and want opposite things from the same
# line: that one BLANKS quoted spans, because a `!` inside a string is not a
# negation, while this one KEEPS them, because the string is the pattern it
# must key on. A shared walker would be a parameter and two behaviours, for no
# gain.

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
      # `<<<` is a here-string: one line, no body to skip. Window-pattern
      # assertions feed grep that way, so getting this wrong would swallow the
      # very lines the census is for.
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
  # token alone would collapse every pattern that uses the same width into one
  # row, and distinct claims do share widths.
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
# counting a header as a row reports orphans that are not there.
#
# The lint checks that the row EXISTS. It does not, and cannot, check that its
# sentence is true.
allowlist_table() {
  cat <<'ROWS'
# --- tests/anchor-lint.bats ---

FILE    tests/anchor-lint.bats
PATTERN anchored_commits == 0[^.]{0,40}wins
VERDICT PINNED
WHY     Pins which side wins, not that the word `wins` is somewhere in
        the file. Inversion: in references/validate-mode.md,
        ``anchored_commits == 0` **wins** over rule 3` rewritten so that
        rule 3 wins over `anchored_commits == 0` turns the case RED;
        deleting the rule turns it RED too. Rewordings and reflows that
        keep the same side winning stay GREEN (the case flattens
        whitespace, so a wrap must not decide it). `wins` occurs once in
        the file, so the 40-character window is slack for a connective,
        not reach. Residual: a rewording that keeps the same side
        winning while replacing the verb — `rule 3 yields to
        `anchored_commits == 0`` — false-Reds; pinning the order of the
        two sides is what the direction costs.

FILE    tests/anchor-lint.bats
PATTERN integration warning[^.]{0,40}fires[^.]{0,20}only when[^.]{0,40}ha(s|ve) anchored commits
VERDICT PINNED
WHY     The bare literal `only when` recurs in
        references/validate-mode.md for unrelated rules (a status
        transition, a shell comment in a code block), so on its own it
        would stay GREEN with this rule deleted. Scoped to `##
        Integration Warning` … `^## `, which owns both warnings and the
        precedence between them, `###` subsection included, so the
        unrelated spans cannot answer for the rule. The trailing space
        in `^## ` is load-bearing: `^##` stops at the `### The anchor
        warning` heading, before any `only when`, and would Red on
        unmutated prose. Three anchors, three inversions, each RED:
        `only when` -> `except when`; the rule reassigned to the anchor
        warning; and the condition negated to `has no anchored commits`.
        Rewordings and a reflow with no word changed stay GREEN.
        Residuals: a pronoun subject (`It therefore fires only when …`)
        false-Reds, and the second conjunct reversed (`and at least one
        of them reached the main branch`) stays GREEN — reaching it
        costs a fourth anchor over a negation alternation whose
        false-Red surface is wider than the inversion it catches.

# --- tests/reports-by-artifact-policy.bats ---

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])never +composing[^.]{0,60}first
VERDICT PINNED
WHY     Pins the prohibition itself in both agent files: `, never
        composing any textual summary first,`. The negation sits
        ADJACENT to the verb it governs, which leaves a negation nowhere
        to park. Each turns RED in both files: `never` dropped; `never
        before composing`; `first` -> `last`; and the clause deleted.
        The object reworded and the sentence reflowed at 72 columns stay
        GREEN. The ` +` absorbs a line wrap between the two words: a
        break there with a trailing space reaches `flat` as two spaces,
        and only whitespace fits, so the widening admits no reversal.
        `summar` is deliberately NOT an anchor — a faithful rewording
        drops the word — and 60 characters is rewording slack. Residual:
        restating the rule without the token false-Reds; the prose
        carries the token or the direction goes unpinned.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos
VERDICT PINNED
WHY     Pins the `LAST step before composing` ordering in each of the
        three copies in references/validate-mode.md — the Validator
        prompt template, the Auditor prompt template, and the procedure
        section — which carry a different token from the agent files for
        the same ordering. SCOPED PER COPY, and the scope is
        load-bearing: a whole-file grep would let one copy answer for
        another that states the opposite. Each scope holds one span, so
        a `-q` reaches a single-copy inversion. `last` and `before` are
        both polarity and no reversal keeps both: `FIRST step after
        composing` in any single copy, and the clause deleted in any
        copy, turn RED. The 40-character leashes are rewording slack;
        the `(^|[^A-Za-z])` boundary keeps `ballast` and `lastly` out.
        `compos` rather than `summar` because the copies use different
        nouns (`textual summary`, `prose`). WHAT THIS PATTERN DOES NOT
        CARRY: a negation parked in FRONT of both anchors (`never as the
        LAST step …`). That is refused by the companion guard in each
        case, `(never|not|no)` plus the file's hedge list, which is not
        a window pattern and holds no row; it is silent on unmutated
        prose, including the procedure section's other `last` tokens.
        Sanctioned shape, not a `!`: `if … then return 1; fi`.

FILE    tests/reports-by-artifact-policy.bats
PATTERN creat[a-zA-Z]*[^.]{0,80}\.draft
VERDICT PINNED
WHY     Counts the `.draft/` creation allowance at exactly 2 spans per
        agent file, because each file states it twice and a `-q` is
        answered by whichever span survives: deleting either statement
        turns RED. The count is `grep -o | wc -l` over flattened text,
        not `grep -c`, so a reflow that puts a newline inside a span
        cannot change it; rewordings and reflows stay GREEN. In each
        prompt-template section of references/validate-mode.md, which
        holds a single `creat`, it is a presence check (`-q`), RED with
        the clause deleted. It does not carry the DIRECTION: a negation
        prefixing `creat` is refused by the sibling `\.draft[^.]{0,40}is
        +part of` assertion and, in the templates, also by an adjacency
        guard on `creat` carrying the file's hedge list, which is not a
        window pattern and holds no row. Residuals: a legitimate third
        statement in an agent file false-Reds (exactness was chosen
        because duplication is what hides a removal), and a rewording
        that renames the verb (`making `.draft/` yourself`) false-Reds.

FILE    tests/reports-by-artifact-policy.bats
PATTERN \.draft[^.]{0,40}is +part of
VERDICT PINNED
WHY     Pins the direction the count above cannot reach: the prose
        frames the allowance as `creating `.draft/` on demand is part of
        …`, a frame a negation must SPLIT rather than prefix. Anchored
        AFTER `.draft` because `[^.]` cannot cross the full stop inside
        `` `.draft/` ``, so a `creat…is part of` window could never
        reach the verb. Counted at 2 per agent file and 1 per
        prompt-template section of references/validate-mode.md, so a
        reversal at any single span turns RED: `is NOT part of this
        step`, `never creating`, `though creating `.draft/` on demand is
        forbidden`, and the clause deleted. Rewordings around the frame
        and reflows (the ` +` carries a break) stay GREEN. Residual: a
        rewording that drops the frame (`so this step creates `.draft/`
        itself whenever it finds none`) false-Reds; the prose carries
        the token or the direction goes unpinned.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (delet|remov)[a-z]*[^.]{0,40}stale
VERDICT PINNED
WHY     Counts the deletion rule at exactly 2 sites inside `## Validate
        Mode Procedure` of references/validate-mode.md — step 3 and the
        `Before the spawn` heading — so reversing (`Keep the
        stale …`) or deleting any single site turns RED. The scope keeps
        the `stale rendering` decoy in `## Index Refresh` out by
        construction; the trailing space in `^## ` keeps the `###`
        heading in scope, where `^##` would drop the third site and Red
        on unmutated prose. `remov` rides beside `delet` because the
        document uses both verbs. Rewordings and reflows at 72 and 40
        columns stay GREEN. It does not carry the DIRECTION: `never
        delete that agent's stale report file` still counts three, and
        is refused by the companion guard
        `(never|not|no)[^A-Za-z]{1,3}(...)?(delet|remov)`, which is not
        a window pattern and holds no row and is silent on unmutated
        prose. Residual: a legitimate fourth statement false-Reds.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (before[^.]{0,20}spawn[a-z]*[^.]{0,30}(delet|remov)|(delet|remov)[a-z]*[^.]{0,60}before[^.]{0,20}spawn)
VERDICT PINNED
WHY     The other half of the same case, pinned as its own assertion so
        a reader sees which half broke: the count above reads every word
        of `After each spawn, delete that agent's stale report file` and
        stays at 3; the polarity token `before` is what that reversal
        cannot keep. Inverting the heading `Before each spawn` -> `After
        each spawn` turns RED; so does deleting it. The scoped section
        holds one span — the heading — so a `-q` reaches a single-site
        inversion, where a bare `before … spawn` would also match the
        paragraph under it. Both word orders, for rewording tolerance:
        `Delete that agent's stale report file before spawning it` and
        reflows stay GREEN. Residual: the paragraph's own restatement
        inverted alone (`each immediately after spawning`), heading
        intact, stays GREEN.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (SendMessage[^.]{0,60}never +a +second|never +a +second[^.]{0,60}SendMessage)
VERDICT PINNED
WHY     Pins the retry bound in row 2 of the retry table in
        references/validate-mode.md with a token a reversal BREAKS
        rather than contains: `never a second`. A bare `one` would not
        do — it is a substring of every phrase that reverses it. RED:
        `never a second` -> `always a second`, and the token dropped at
        either site. GREEN: the token moved and the objects reworded,
        and a reflow with the break between `never a` and `second`,
        which the ` +` absorbs. Both word orders, for rewording
        tolerance. It does not carry the bound at the paragraph (held by
        the `never a second` count in the same case, not a window
        pattern) or at row 3 (held by the `one request … the run is
        failed` row below). Row 2's `**one**` -> `**more than one**`
        with the token left standing is caught by the modifier guard
        below, not here.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (^|[^A-Za-z])(one|single) +request[^.]{0,60}the run is failed
VERDICT PINNED
WHY     Pins row 3 of the retry table, which states the bound from the
        failure side — `Still absent or still unparseable after that one
        request | **the run is failed**`. It exists because a bound's
        scope can be narrowed: with the token above left standing, row 3
        rewritten to `after the last of those requests` and `repeat the
        row as often as it takes` appended, the pin above and the count
        stay GREEN and this pattern turns RED. The count word sits next
        to the noun it counts, so a reversal that licenses repeats must
        change the noun and loses the phrase, while one that keeps `one`
        needs a modifier, which the guard below refuses. `single` rides
        beside `one` as the document's other word for the count.
        Rewordings (`after that single request`) and reflows stay GREEN.
        Residual: dropping the count altogether (`after that request`)
        false-Reds.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)
VERDICT PINNED
WHY     Refuses a modifier in front of `one` on the retry count (`more
        than one`, `at least one`, `one or more`…): row 2's `**one**` ->
        `**more than one**` turns RED here. It bites only the phrasings
        it enumerates, so it never carries the bound on its own — that
        is pinned in the prose by the two rows above, and a reversal
        using none of these modifiers is caught there. It stays because
        `**more than one**` with `**never a second**` left standing
        passes both of those and is caught here alone. Silent on
        unmutated prose. Red-on-correct: `never more than one
        `SendMessage`` false-Reds, and the prose has no need of that
        phrasing. Sanctioned shape, not a `!`: `if … then return 1; fi`.

FILE    tests/reports-by-artifact-policy.bats
PATTERN carries[^.]{0,60}(command[^.]{0,120}output|output[^.]{0,120}command)
VERDICT PINNED
WHY     Scoped to `## Measurement, Not Argument` in
        agents/tech-reviewer.md, where the command/output pair has one
        span — whole-file, the report-format bullet would answer for the
        rule. RED: the rule deleted; `carries` -> `need not carry`;
        `does not carry`; the section deleted. GREEN: rewordings, the
        pair in the other order, the rule reflowed, and the
        report-format bullet rewritten with the rule intact. The
        60-character leash is rewording tolerance for a parenthetical
        between the verb and its object. Residual: a sentence where
        `carries` governs another noun with the pair in a later clause;
        the companion row below is what refuses a negation.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?carries|carries[^A-Za-z]{1,3}(no|neither|nothing)[^.]{0,80}output)
VERDICT PINNED
WHY     The negation-refusal guard for the row above: `carries neither
        the exact command nor its observed output`, `never carries` and
        `no longer carries` all pass the positive match and are RED
        here. Only the second branch carries a window, and its `output`
        leash is the discrimination: `carries no command it did not
        actually run` — the rule's own closing clause — stays GREEN,
        while `carries no exact command and no observed output` and the
        reversed-order `carries neither the observed output nor the
        exact command` both Red. Sanctioned shape, not a `!`: `if … then
        return 1; fi`.

FILE    tests/reports-by-artifact-policy.bats
PATTERN verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)
VERDICT PINNED
WHY     The polarity is the OBJECT: a verdict comes from a file or from
        disk, and a message is neither. Rewriting steps 3 and 4 of
        references/validate-mode.md to `Take the verdict from the final
        message` — filenames left in place — turns RED on the first of
        the two greps; an occurrence check on the filenames alone would
        stay GREEN. `The verdict is read from that report file rather
        than from the reply` and `read off that report file` stay GREEN,
        which is what `off` and the 30-character tail are for. Residual:
        `the verdict not from the file but from the reply` parks a
        negation between the anchors and passes.

FILE    tests/reports-by-artifact-policy.bats
PATTERN (message|repl(y|ies))[^.]{0,120}[^A-Za-z](no|not|never)[^A-Za-z][^.]{0,40}(pass/fail|verdict|decision)
VERDICT PINNED
WHY     Pins that the reply is the source of NO verdict: the polarity
        token sits inside the match and governs the reply. Rewriting the
        paragraph in references/validate-mode.md so steps 3-5 conclude
        from the final message and the report file is `the source of no
        pass/fail decision` — the negation kept, moved onto the file —
        turns RED. `the final message is a convenience … and decides no
        pass/fail` stays GREEN. The word boundaries around
        `(no|not|never)` stop the retry table's `asking it to write its
        report file now` from answering the assertion by itself.

FILE    tests/reports-by-artifact-policy.bats
PATTERN ((^|[^A-Za-z])(never|not)[^A-Za-z]|rather than|instead of)[^.]{0,80}(chat|message|repl(y|ies)|said|prose)
VERDICT PINNED
WHY     Pins that rules 1-3 in references/validate-mode.md do not turn
        on what an agent said in chat. Rewriting the rule to `Rules 1-3
        turn on what an agent said in chat — never on the `verdict`
        field of `.draft/validation-report.yaml` …`, every filename
        kept, turns RED: the negation now governs the file, and the full
        stops in `.draft/…yaml` close the window before any word for the
        reply. `… rather than from the agents' replies` stays GREEN.
        Only one line of that section names a report file, so the
        feeding grep scopes to the rule's own paragraph.

# --- tests/scale-resolution.bats ---

FILE    tests/scale-resolution.bats
PATTERN tasks\.md[^.]{0,40}authoritative
VERDICT PINNED
WHY     Two sites share this key: the references/tasks.md contract case,
        and the comment census over scripts/validate-story.sh, which
        COUNTS exactly 3 spans (the shared-rule header, the
        written-contract paragraph, the disagreement warning's
        rationale). The count is `grep -o | wc -l` over flattened
        comment blocks, because `grep -c` counts LINES and
        comment_blocks joins adjacent `#` lines, so two spans can land
        on one line. The pattern matches the anchors POSITIVELY; the
        direction is refused at each site by the sibling guard
        `(never|not|no)[^A-Za-z]{1,3}(hedge|the)?authoritative`, which
        is not a window pattern and holds no row. So `is always
        authoritative`, `is strictly authoritative` and `is and remains
        authoritative` stay GREEN, while `is not authoritative`, `is
        never authoritative` and the subject swapped to `story.md` turn
        RED; deleting any one span of the three in the script turns RED
        at the count. A literal verb phrase such as `is (the
        )?authoritative` would false-Red every inserted adverb at the
        same assertion line a genuine inversion fires. One span in
        references/tasks.md, so that site needs no section scope.
        Residual: a legitimate fourth statement in the script
        false-Reds; exactness was chosen because duplication is what
        hides a removal.

FILE    tests/scale-resolution.bats
PATTERN story\.md[^.]{0,200}(reported[^.]{0,40}(not|never) honou?red|(not|never) honou?red[^.]{0,40}reported)
VERDICT PINNED
WHY     The polarity is the PAIRING: both halves are required, in either
        arrangement (`is **reported**, not honoured` or `is **not
        honoured**, but merely reported`). Inverting references/tasks.md
        to `is **honoured**, not reported` turns RED — it holds
        `reported` and a negation, but never a negation on `honoured`,
        which both branches require. Deleting `, not honoured` also
        turns RED. `never` is admitted as the same negation of the same
        verb. Rewordings and a reflow between the halves stay GREEN.
        `honour` occurs once in the file. Residual: more than 40
        characters between the halves false-Reds; the leash stays at 40
        because the halves are one clause in every phrasing.

FILE    tests/scale-resolution.bats
PATTERN story\.md[^.]{0,120}(first|wins)
VERDICT PINNED
WHY     A NEGATIVE assertion, so the inversion is to restore the claim
        it retracts: the shared-rule comment rewritten to `… —
        `story.md` is read first and wins for `scale:`` turns the case
        RED at this row's `return 1`, and the diagnostic prints the
        offending block. Nothing matches it otherwise, which is the
        assertion's whole content — it claims an absence and detects the
        absence being ended.
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
# Output is `file:line: pattern` — the file AND the line, in the shape
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

# Structural defects in the parsed rows. Structural is the whole claim:
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
      marked = (index($4, "UNMEASURED") > 0)
      if ($3 == "PENDING" && marked == 0)
        printf "row %d (%s): PENDING, but its sentence carries no UNMEASURED marker\n", n, $2
      if ($3 != "PENDING" && marked)
        printf "row %d (%s): verdict %s, but its sentence still carries the UNMEASURED marker\n", n, $2, $3
    }
  '
}

# --- 1.4: the lint, proved on planted input ----------------------------------
# As in the `!` lint's cases, fixtures are written under $WORK through `plant`
# and read, never executed. Each one cds into $WORK first so the planted table
# can name `a.bats` literally, the way the real table names a path relative to
# the repo root.

@test "1.4: a window pattern absent from the allowlist is flagged, naming file and line" {
  cd "$WORK"
  plant a.bats <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
  # File AND line, in the `file:line: ` shape the `!` lint also emits.
  printf '%s\n' "$offenders" | command grep -qF 'a.bats:4: '
  # ...and the pattern itself, so the message says what to write a row about.
  printf '%s\n' "$offenders" | command grep -q 'absent.*window'
}

@test "1.4: a tree whose every window pattern has a row passes" {
  cd "$WORK"
  plant a.bats <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
  plant a.bats <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
  plant a.bats <<'BODY'
#!/usr/bin/env bats
# A comment may quote the shape under discussion: `the run[^.]{0,40}fail`.
%%TEST%% "planted" {
  cat > /dev/null <<'INNER'
PATTERN quoted[^.]{0,40}inside a heredoc body
an apostrophe here would desync quote tracking if this body were not skipped
INNER
  command grep -qiE 'real[^.]{0,40}site' /dev/null
}
BODY
  # Both discriminations at once. Without the first, every prose sentence that
  # quotes a window pattern would demand a row; without the second, every row
  # of the allowlist becomes a site that needs a row of its own, and the table
  # never closes.
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
  plant a.bats <<'BODY'
#!/usr/bin/env bats
%%TEST%% "planted" {
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
  # The last row below carries the real `UNMEASURED` marker on purpose, to
  # exercise the stale-marker half of the rule. It is therefore one extra hit
  # for the worklist grep — inside a heredoc, verdict PINNED, and so not a
  # worklist item.
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
WHY     UNMEASURED, on a row that claims to have been measured.
ROWS
  # The check is structural and says so: it sees whether a reviewer was handed
  # a verdict and a sentence, never whether the sentence is true.
  defects="$(allowlist_rows < table | row_defects)"
  printf '%s\n' "$defects" | command grep -qF 'row 1 (no-verdict): no VERDICT'
  printf '%s\n' "$defects" | command grep -qF 'row 2 (bad-verdict): verdict PROBABLY-FINE'
  printf '%s\n' "$defects" | command grep -qF 'row 3 (stub): no justifying sentence'
  printf '%s\n' "$defects" | command grep -qF 'row 4 (unmarked-pending): PENDING'
  printf '%s\n' "$defects" | command grep -qF 'row 5 (stale-marker): verdict PINNED'
  # A note line is a note, never a row — counting a header as a row reports
  # orphans that are not there.
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
    echo "anchors are related, so it survives an inversion of the rule it guards."
    echo "Every one of them is reviewed in the allowlist table in"
    echo "tests/assertion-hygiene.bats. Add a row — file, pattern, verdict and"
    echo "the inversion that justifies it — for each site below:"
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
  # Only the half a machine can hold: the row exists and is complete.
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
  # WHAT THIS COVERS, per rostered case, each mutation applied alone:
  #
  #                                  the census case   every other case
  #   a `skip` added                 SKIP-GREEN <-open RED    (file-wide grep)
  #   the case renamed away          RED              RED    (roster below)
  #   the case commented out         RED              RED    (anchored match)
  #   the body gutted, name intact   GREEN      <-open RED    (per-case tokens)
  #
  #   COMMENTED OUT is caught because the roster match is anchored at COLUMN 1
  #   (`index($0, want) == 1`), the idiom the body walker below also uses, so a
  #   commented header is not a header — `grep -F` would find `# @test "..." {`
  #   as readily as the real one. Commenting out the whole case, header through
  #   closing brace, is the shape a silent removal takes; commenting the header
  #   alone leaves the body as top-level shell and the file stops parsing,
  #   which Reds for another reason.
  #
  #   GUTTED is caught because the body check runs per rostered case, over that
  #   case's own tokens.
  #
  # THE TWO OPEN CELLS ARE BOTH THE CENSUS'S OWN, in the two mutations that stop
  # the guard from running at all. A `skip` here is not caught because the grep
  # that finds a `skip` is in the body that gets skipped; a gutted body here is
  # not caught because the check that reads bodies is the body that was gutted.
  # They are the same limit as deleting this case, one step in: a guard cannot
  # outlive the artifact that holds it, and a second case asserting THIS one
  # would move the hole rather than close it.
  #
  # WHAT NOTHING HERE COVERS, stated rather than implied: deleting this file,
  # deleting this case, or dropping tests/ from the runner. The roster below is
  # where the regress stops.
  SELF="$PLUGIN_ROOT/tests/assertion-hygiene.bats"
  [ -f "$SELF" ]

  # THE ROSTER NAMES EVERY REAL CASE IN THIS FILE, the `1.1:` cases included —
  # the last of them, `no .bats file in tests/ inverts a command as an
  # assertion`, imposes the `!` rule on the WHOLE suite, so commenting it out or
  # gutting it must not go silently green.
  #
  # Each entry is `<case name>|<token>;<token>;...`. The tokens are what the
  # case CANNOT assert without — its lint function, its fixture, its diagnosis
  # — so an emptied body loses them while a reworded one keeps them. No name
  # holds a `|` and no token holds a `;`.
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

  # NO LINE IN THIS FILE STARTS WITH `@test` EXCEPT A REAL CASE HEADER, and
  # that check does two jobs at once.
  #
  # It keeps the roster's census honest: every real case is named `N.N: ...`,
  # so if nothing else can start a line with `@test`, the count of `^@test
  # "[0-9]` lines IS the count of cases that must be rostered — and a fixture
  # planting a `N.N: ` name would otherwise be counted as a real case and would
  # forge the boundary the body walker below stops at.
  #
  # And it keeps this file LOADABLE, which is not a style rule. bats (1.10, the
  # version `apt` ships on ubuntu-latest, included) collects any line beginning
  # `@test`, heredoc body or not, indented or in column 1, so a fixture planting
  # `@test "planted"` verbatim makes the file fail to load with duplicate test
  # names, and `bats tests/` aborts the whole suite on a load error. The
  # fixtures carry `%%TEST%%` and `plant` restores it on the way to disk; this
  # assertion stops the next fixture from re-opening that hole silently.
  stray="$(command grep -nE '^[[:space:]]*@test' "$SELF" \
    | command grep -vE '^[0-9]+:@test "[0-9]+\.[0-9]+: ' || true)"
  if [ -n "$stray" ]; then
    echo "these lines begin with \`@test\` but are not a real \`N.N: \` case header."
    echo "bats collects every one of them — a fixture that plants \`@test\` verbatim"
    echo "makes this file refuse to load on bats 1.10, taking the whole suite with"
    echo "it. Write \`%%TEST%%\` in the fixture and pipe it through \`plant\`:"
    printf '%s\n' "$stray"
    return 1
  fi
  real_headers="$(command grep -c '^@test "[0-9]' "$SELF")"
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
  # NEXT HEADER: this file puts the helpers and the allowlist table between the
  # `1.1:` cases and the `1.4:` ones, so a walk to the next header would hand a
  # gutted `1.1:` case unrelated code to satisfy its tokens with.
  #
  # HEREDOC BODIES ARE CARRIED, NOT PARSED. Fixtures in this file close with a
  # `}` in column 1 inside a heredoc — the planted case's own brace — so a
  # walker that stopped at the first `^}` would stop inside the fixture, before
  # the assertions it was called to read. Every heredoc here opens with a
  # quoted delimiter and none is `<<-`, so the delimiter is the second field
  # when the opening line is split on a quote, and the body is skipped to the
  # line that equals it.
  #
  # A COMMENT IS PROSE AND IS DROPPED BEFORE EITHER RULE LOOKS AT THE LINE,
  # the same discrimination `window_sites` makes: a comment that QUOTES a
  # heredoc opener would otherwise be taken as one, with a delimiter that never
  # recurs, and run the walk to end of file. Dropping comments first also makes
  # the tokens below code-only: a body whose code was deleted keeps its comment
  # block, and a token quoted in prose must not answer for the assertion that
  # is gone.
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
    # and an unanchored match would find the header commented out.
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
