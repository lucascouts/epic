#!/usr/bin/env bats
# Story 011, Task 2.2 — policy test for the wave-011 contract.
#
# WHAT THIS SUITE PINS. Reports-by-artifact turns the Validator's and Auditor's
# verdicts into files (.draft/validation-report.yaml, .draft/audit-report.yaml)
# written BEFORE the textual summary, makes validate-mode conclude from those
# files rather than from the agent's final message, and gives the Tech Reviewer
# Bash restricted to measurement. All of that is prose in agent definitions and
# mode references — nothing executable — so the contract survives future edits
# only if a test names it. This file is that test (R1.5, R2.1, R3.1, R3.4).
#
# FIXTURES ARE THE REPO FILES THEMSELVES. Every case is a pure content
# assertion on agents/*.md, references/validate-mode.md and
# references/run-mode.md — no temp dirs, no mutation, so no mktemp/teardown.
#
# ASSERTIONS ARE BEHAVIOR-LEVEL, NOT SENTENCE-PINNED. The story has no
# design.md, so cases assert that a fact is stated (a filename, a grant, an
# ordering, a prohibition), matched case-insensitively on flattened text where
# a sentence may wrap — never an exact sentence, which would make every future
# rewording a false Red.
#
# ...BUT THEY PIN POLARITY, NOT CO-OCCURRENCE. Behavior-level is not
# direction-blind. A bare window pattern like `the run[^.]{0,40}fail` is
# satisfied by "the run is **not** failed" exactly as by the real row, so it
# stays green through an inversion of the rule it exists to guard — measured,
# not supposed. A directional claim therefore carries its polarity token INSIDE
# the match (`is failed`, `is a protocol violation`, `is your own store`,
# `never … respawn`), leaving no gap for a negation to slip between the anchors.
# Tighten only what is measured first: scope the section, count the candidate
# spans, and confirm the phrase is the one the rule's own name already uses —
# otherwise the pin becomes the sentence-pinning this header forbids above.
#
# Each such pattern is written out, never routed through a shared polarity
# helper. A helper that rejected a negation in the window before the match would
# false-Red on correct prose right here: auditor.md's memory clause reads "is
# not a second path in the code under audit — it is your own store", so a
# negation sits one clause ahead of the match by design.
#
# WHEN THE NEGATION PREFIXES A QUANTIFIER there is no polarity token to move
# inside. `is failed` works because the negation splits two anchors; `one`
# offers no such gap — it is a substring of every phrase that reverses it
# (`more than one`, `not just one`, `one or more`), so a pattern pinning `one`
# is satisfied by its own negation. Sub-task 4.3 measured that no pattern
# repairs that, so the repair is not a pattern. It is three assertions and a
# prose edit: the rule now carries a token a reversal BREAKS rather than
# contains (`never a second`), the case counts the sites that state it, and a
# third assertion pins the rule's CONSEQUENCE — one request, then the run is
# failed — because a document licensing repeats cannot also say that. The
# inline negated grep naming the claim's own modifiers survives BESIDE them,
# kept for one measured vector rather than as the sanctioned form, and never as
# a generic negation guard, for the reason the paragraph above gives. All four
# stand in `2.1: an absent or unparseable report is re-requested once via
# SendMessage, then the run is failed`, which argues each where it stands.
#
# A NEGATED ASSERTION MUST NOT REST ON BEING LAST. Bash exempts a `!`-inverted
# command from errexit, so anywhere but the final statement of an @test its
# non-zero status is discarded and the assertion is inert — green whatever the
# file under test says. Probed, not reasoned: `! true` followed by one more
# assertion passes, while `if true; then return 1; fi` in that same slot fails.
# The sanctioned shape is therefore `if …; then return 1; fi`, which is what
# every negated assertion in this file now uses. The subshell `( ! … )` also
# survives being moved and was rejected on diagnostics alone — bats named the
# `return 1` line for the `if` and only the `@test` line for the subshell,
# pointing at the case instead of the assertion.
#
# THAT RULE IS ENFORCED, NOT ADVISED, and it is one of the few sentences in
# this header that may say so. `1.1: no .bats file in tests/ inverts a command
# as an assertion`, in tests/assertion-hygiene.bats, scans every tests/*.bats
# and names each offender as file:line; it admits no position exemption, so
# sitting last is not a defence either. Do not look for a list of the sites
# here. There was one — it named five, the lint found six, and sub-task 1.2
# converted all six. That gap is the whole argument: a list has to be
# remembered, and the lint is re-derived on every run.
#
# WHERE THE POLARITY RULE DOES NOT HOLD, named rather than quietly excepted: a
# convention the file contradicts gets read as an invariant, which is worse
# than no convention. THIS HEADER IS NOT WHERE THOSE SITES ARE NAMED, and that
# is the correction sub-task 5.2 made rather than a gap it left. A hand-kept
# list of exceptions is the same instrument as the hand-kept list of negations
# above, with the same failure: three of the entries that stood here were
# closed by tasks 2, 3 and 4 and went on reading as open, and a fourth said the
# two prompt-template copies of `is a protocol violation` were unguarded on the
# day sub-task 5.1 guarded them in `1.1: validate-mode Validator prompt
# template mirrors the report file` and `1.2: validate-mode Auditor prompt
# template mirrors the report file`. Re-measured for this edit: that same
# inversion, applied to both copies at once, now Reds both cases.
#
# THE ALLOWLIST TABLE IN tests/assertion-hygiene.bats IS THE LIST. One row per
# `file:pattern`, each stating the inversion applied, the colour observed and
# every residual left open; and two cases keep the table and the suite in step
# in both directions, so a pattern cannot exist unreviewed and a row cannot
# outlive its pattern — `1.4: every window pattern in tests/ carries an
# allowlist row` and `1.4: no allowlist row names a pattern tests/ no longer
# contains`. Read it by verdict rather than from a sentence here — BOUNDED TO
# THE TABLE, because that file's planted fixtures write rows of their own and a
# whole-file grep is answered by them (measured while writing this paragraph:
# 24 against the table's 20, and five `ALLOWED` where the table has none):
#
#   sed -n '/^allowlist_table() {/,/^ROWS$/p' tests/assertion-hygiene.bats \
#     | command grep '^VERDICT' | sort | uniq -c
#
# PINNED and ALLOWED are the two verdicts that say a site is sound;
# DIRECTION-BLIND says it was measured and failed, and names the task that owes
# the repair. At the close of task 4 the table held 20 rows and every one was
# PINNED — a snapshot, which is why the command is written here and the number
# is not load-bearing.
#
# WHAT THE CENSUS CANNOT SEE, so that a green one is not read for more than it
# says. It recognises the window shape `A[^.]{0,N}B` and nothing else. Tighten
# a pattern out of that shape — as several pins in this file did, trading the
# window for an adjacency bound — and it leaves the census with it, so no row
# can hold its measurement; that evidence lives in the case's own comment and
# nowhere else. And the census checks that a row EXISTS, never that its
# sentence is TRUE: whether a pattern really survives an inversion depends on
# the prose it reads, which no machine here judges.
#
# A pattern naming only a file or a field (`audit-report.yaml`, `verdict`)
# makes no directional claim and so has no polarity to pin — the first
# paragraph governs those. `measurement` USED TO BE IN THAT LIST AND DOES NOT
# BELONG THERE: sub-task 2.2 measured that the rule states its own direction in
# words the pattern can hold (`for measurement only`), that pinning them Reds
# on `Bash is not limited to measurement`, and that the bare topic word stays
# green through the same inversion. That pin and its negation guard stand in
# `3.1: tech-reviewer's Bash is measurement-only and never mutates` and, for
# the run-mode copy, in `3.1: run-mode Tech Reviewer prompt template mirrors
# the measurement rule`. A word is a topic only until somebody measures it, so
# that class is a finding and never a guess.
#
# WHAT IN THIS HEADER IS UNDER TEST, AND WHAT IS NOT — the distinction matters
# more than either half, because a partial guard described as none misleads
# exactly as much as none described as a guard, and this paragraph used to be
# the first of those.
#
#   ENFORCED, each by a named case in tests/assertion-hygiene.bats. The
#   negated-assertion rule: `1.1: no .bats file in tests/ inverts a command as
#   an assertion`. The window-pattern rule, in both directions: `1.4: every
#   window pattern in tests/ carries an allowlist row` and `1.4: no allowlist
#   row names a pattern tests/ no longer contains`. The shape of a row: `1.4:
#   every allowlist row carries file, pattern, verdict and a justifying
#   sentence`. And those four against silent removal: `1.4: the window-pattern
#   census cannot be silently disabled or emptied`, which reds on a `skip`
#   anywhere in that file and on any of the ten rostered case names being
#   renamed away. Its limits are measured and written into its own comment
#   rather than left here — a commented-out or gutted case is caught for the
#   census case alone, and no guard inside a file can outlive that file.
#
#   GUIDANCE, held by nothing but the next author reading it: behavior-level
#   over sentence-pinned, fixtures being the repo files themselves, a polarity
#   token inside the match rather than a shared negation helper, and every
#   verdict the allowlist records. Dropping one of these turns nothing Red.
#   Implying otherwise is the unearned confidence story 018 refused to buy.
#
# A CASE NAME OPENS WITH THE SUB-TASK THAT OWNS ITS PROSE, so
# `bats --filter '^1\.1:'` answers for exactly that sub-task's contract; the
# one case here whose rule predates the story opens `convention:` instead. The
# `2.2:` grant-set cases are the least-privilege pins the policy sub-task
# itself owns: Write and Bash land on exactly the agents this story names, and
# Edit moves nowhere. The Edit case is a GREEN PIN — correct today, present so
# a grant that "comes along for the ride" reddens deliberately.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VALIDATOR="$PLUGIN_ROOT/agents/validator.md"
  AUDITOR="$PLUGIN_ROOT/agents/auditor.md"
  TECH_REVIEWER="$PLUGIN_ROOT/agents/tech-reviewer.md"
  VALIDATE_MODE="$PLUGIN_ROOT/references/validate-mode.md"
  RUN_MODE="$PLUGIN_ROOT/references/run-mode.md"
  # The Tech Reviewer prompt template moved to its own appendix, loaded only
  # when a sub-task carries a technology boundary. run-mode.md keeps a pointer.
  TECH_REVIEW="$PLUGIN_ROOT/references/run-tech-review.md"
}

# The tools: line inside the frontmatter block only — a tool named in prose
# ("do not use Write") must never satisfy a grant assertion.
frontmatter_tools() {
  awk 'NR==1 && $0=="---" {inb=1; next}
       inb && $0=="---" {exit}
       inb && $0 ~ /^tools:/ {print; exit}' "$1"
}

# Word-boundary match without \b (a GNU-ism): Write must not match WebSearch,
# Bash must not match a hypothetical BashOutput.
grants() { # $1 = agent file, $2 = tool name
  frontmatter_tools "$1" | command grep -qE "(^|[^A-Za-z])$2([^A-Za-z]|$)"
}

# Flatten to one line so a fact split across a soft wrap still matches.
flat() { tr '\n' ' ' < "$1"; }

# Lines of one markdown section: from the first heading matching $2 to the
# next heading matching $3 (exclusive).
md_section() { # $1 = file, $2 = start regex, $3 = end regex
  awk -v start="$2" -v end="$3" '
    !inb && $0 ~ start {inb=1; next}
    inb && $0 ~ end {exit}
    inb {print}' "$1"
}

# The sorted list of agents whose frontmatter grants a tool — the shape the
# grant-set pins compare against, so an agent ADDED to the grant is as loud as
# one removed.
agents_granting() { # $1 = tool name
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    if grants "$f" "$1"; then
      basename "$f" .md
    fi
  done | sort
}

# --- 1.1: Validator report contract ------------------------------------------

@test "1.1: validator frontmatter grants Write" {
  grants "$VALIDATOR" "Write"
}

@test "1.1: validator names .draft/validation-report.yaml, its verdict, and the write-before-summary ordering" {
  command grep -q 'validation-report\.yaml' "$VALIDATOR"
  # R1.4: the file carries the overall verdict, not only per-task lines.
  flat "$VALIDATOR" | command grep -qi 'verdict'
  # R1.1: the write precedes the textual summary — the ordering is the whole
  # point, because a summary-first agent can still end on an intermediate line
  # with no file written.
  #
  # THE PROSE HAD NO TOKEN TO PIN, so sub-task 4.1 gave it one. The rule read
  # `, before composing any textual summary,` and the predecessor pattern was
  # `before[^.]{0,160}summar`: `before` was the anchor AND the polarity at
  # once, so a negation had nowhere to go but in FRONT of it, where the window
  # never looks. Measured, twice — 1.5's sweep and again here on this tree:
  # `never before composing any textual summary` left this case GREEN under a
  # rule that now says the opposite. No scope and no count reaches that; only
  # different prose does, and the rewrite is the smallest one that carries the
  # rule: `before` became `never`, and `first` was inserted.
  #
  # WHAT IS PINNED IS `never composing … first`, not the sentence. The negation
  # is ADJACENT to the verb it governs, so the mutation that defeated the
  # predecessor has no slot: `never before composing` puts a word between the
  # two and Reds, as does dropping `never`, as does `first` -> `last`, as does
  # deleting the clause outright — four vectors, run on this file and on the
  # Auditor's separately, eight Reds.
  #
  # THE ANCHORS ARE UNIQUE IN THE FILE, measured rather than assumed: `compos`
  # occurs exactly once here and `first` exactly once, both inside this clause,
  # so no neighbouring span can answer for it the way the carve-out case below
  # was answered by a second `.draft/` span before 3.2 counted them. Named by
  # content rather than by line, because every `.bats` line number this suite
  # ever wrote down has since drifted.
  #
  # `summar` IS DELIBERATELY NOT AN ANCHOR, and 60 characters rather than the
  # predecessor's 160. Both are costs measured in the other direction: a
  # faithful rewording that renames the object (`never composing the prose
  # reply for the human first`) drops the word `summary` entirely and stays
  # GREEN, and the widest rewording measured puts 31 characters between the
  # anchors. What the leash proves is that the prohibition governs the
  # composing, and `composing` is this document's verb for the summary alone.
  # The `(^|[^A-Za-z])` guard is not decoration: `whenever composing` ends in
  # `never composing`. Nor is the ` +`: `flat` turns a newline into a space and
  # leaves any trailing one alone, so a reflow breaking between the two words
  # of the token hands the pattern TWO spaces and a single-space literal
  # false-Reds — measured, on prose with not a word changed. Only whitespace
  # can sit in that slot, so widening it admits no reversal.
  #
  # THE RESIDUAL, named rather than left to be found: the rule restated in its
  # OWN pre-4.1 words — `before composing any textual summary` — now false-Reds
  # here. That is R1.4's trade taken knowingly: a claim whose polarity cannot
  # be matched without matching most of a sentence is stated in prose that
  # carries a polarity token, and the token is then required. A reader who
  # wants the positive form back has to keep the prohibition with it.
  flat "$VALIDATOR" | command grep -qiE '(^|[^A-Za-z])never +composing[^.]{0,60}first'
}

@test "1.1: validator carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # R1.5: the no-modify rule narrows to a carve-out, it does not disappear.
  # The assertive frame `is a` is part of the match: the definition writes "Any
  # other write is a protocol violation" verbatim, and the inversion breaks it.
  flat "$VALIDATOR" | command grep -qiE 'is a protocol violation'

  # R1.3 + R3.2: fast/spike stories have no .draft/ until someone makes one,
  # and THIS FILE SAYS SO TWICE — the protocol step at agents/validator.md:36
  # and the Rules bullet at :74. That is what made the predecessor an assertion
  # about half the file rather than about the file: `flat … | grep -q` is
  # answered by either span alone, so dropping the allowance from the bullet
  # only left this case GREEN — story 019's recorded failure, re-measured here
  # before the repair. Counting the spans Reds it, and Reds the other three
  # one-site removals with it: eight mutations across the two files, eight Reds.
  # The count SUBSUMES the `-q` it replaces — 2 spans implies at least one — so
  # keeping both would be a second assertion that cannot fail while the first
  # passes.
  #
  # COUNTED OVER FLATTENED TEXT, and the representation is measured rather than
  # assumed, because the obvious `grep -c` is wrong twice over: it counts
  # matching LINES, so over `flat`'s single line it answers 1 however many
  # spans exist, and over the raw file it answers 2 only while both spans keep
  # to a line of their own. Not a hypothetical — measured, on prose with not a
  # word changed: this file reflowed at 72 columns puts a newline inside the
  # Rules bullet's span, and raw `grep -c` answers 1, raw `grep -o` answers 1,
  # `flat` + `grep -o` answers 2; with a newline inside BOTH spans the two raw
  # forms answer 0 and this one still answers 2. Spans over flattened text is
  # the tolerance every other assertion in this file is flattened for.
  #
  # EXACTLY TWO, AND THE COST IS REAL AND MEASURED: a legitimate THIRD
  # statement of the allowance false-Reds here. `-ge 2` Reds all eight removals
  # just as well and buys that third span silence; the exactness is taken
  # deliberately, because DUPLICATION is half of what made this site blind in
  # 1.5, so a third span belongs in front of a reader rather than under a
  # green. It is the trade the grant-set pins below take too — an addition as
  # loud as a removal.
  #
  # WHAT THE COUNT DOES NOT GUARD, AND WHAT NOW DOES: the DIRECTION. The
  # permission reversed at BOTH spans — `never creating .draft/ on demand` —
  # keeps the count at two and stayed GREEN, measured here exactly as 1.5
  # measured it, because the negation PREFIXES the anchor `creat`: no count and
  # no scope reaches it, only different prose does. Sub-task 4.3 wrote that
  # prose and pins it in the assertion below. The count stays because the two
  # answer different questions — this one whether the allowance is STATED at
  # both sites, that one in which DIRECTION — and neither subsumes the other:
  # measured, the both-spans reversal keeps this count at 2 while Redding the
  # pin, and either span deleted outright Reds both.
  #
  # The count is captured before it is compared, not inlined into `[ "$(…)" ]`,
  # and that is the census talking rather than taste: the window-pattern walker
  # keys a row on the WHOLE quoted span, and inlining puts the pattern inside a
  # `"…"` that runs from `|` to `)`, keying a row nobody would recognise and
  # orphaning the one this pattern already has. Measured on both shapes.
  spans=$(flat "$VALIDATOR" | command grep -oiE 'creat[a-zA-Z]*[^.]{0,80}\.draft' | wc -l)
  [ "$spans" -eq 2 ]

  # ...AND IN WHICH DIRECTION (R1.4). The Rules bullet had no token to pin:
  # `, creating `.draft/` on demand.**` is reversed by `, never creating
  # `.draft/` on demand.**` — a negation in FRONT of the anchor, where no
  # window looks. The protocol step one span above already carried one, and it
  # is the shape `the run is failed` uses: `is part of this step` SPLITS under
  # `is NOT part of this step`. So 4.3 moved that frame into the bullet rather
  # than inventing a second one — `, creating `.draft/` on demand.**` became
  # `, and creating `.draft/` on demand is part of it.**`, which reads as a
  # clause instead of the dangling participle it replaced — and both agent
  # files took the identical edit.
  #
  # ANCHORED AFTER `.draft`, NEVER BEFORE IT, which is arithmetic rather than
  # taste: `[^.]` cannot cross the full stop inside `` `.draft/` ``, so a
  # `creat…is part of` window could never reach the verb it needs. `is part of`
  # occurs exactly twice in this file, both inside the carve-out — measured —
  # so no neighbouring sentence can answer for either span.
  #
  # COUNTED, for the reason the span count above is: a `-q` is answered by
  # whichever span survives, and the ONE-span reversal is exactly what 1.5 and
  # 3.2 left open. Measured, one mutation at a time: reversed at both spans —
  # 0, RED; at the protocol step alone — 1, RED; at the Rules bullet alone —
  # 1, RED. Residual, named and accepted: a rewording that drops the frame
  # (`so this step creates `.draft/` itself whenever it finds none`) now
  # false-Reds, which is R1.4's trade — the prose carries the token or the
  # direction goes unpinned.
  allowed=$(flat "$VALIDATOR" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 2 ]
}

@test "1.1: validate-mode Validator prompt template mirrors the report file" {
  # R3.4: the duplicated template drifts unless it lands in the same story.
  #
  # THE FILENAME WAS THE WHOLE MIRROR, AND A FILENAME IS NOT A RULE. This case
  # asked only that the template name `.draft/validation-report.yaml`, which
  # every inversion of every rule stated around it keeps — a mirror case named
  # for mirroring that mirrored a path. Measured on this tree before the
  # repair, whole suite, one mutation at a time, each restored before the next:
  # the carve-out reversed to `any other write is **not** a protocol violation`
  # in BOTH templates left `1..498`, 498 ok, 0 not ok; the ordering reversed to
  # `as the FIRST step after composing any textual summary` at :33 and :90 and
  # to `as the **first** step ... after composing any prose` at :147 left
  # 498/0; the `.draft/` allowance reversed to `never creating `.draft/` on
  # demand` at :33 and :90 left 498/0. Three rules the agent-definition cases
  # above pin, three copies guarded by nothing — this story's half-guard defect
  # one level down, which is why the three pins land HERE rather than in cases
  # of their own.
  #
  # SCOPED TO THIS TEMPLATE, and the scope is load-bearing rather than tidy:
  # each phrase below occurs TWICE in references/validate-mode.md, once per
  # template, so a whole-file grep is answered by the Auditor's copy while the
  # Validator's says the opposite — the co-location defect 4.2 and 3.1 both had
  # to scope their way out of. Measured, spans per scope: `is a protocol
  # violation` 1 here / 1 in the Auditor section / 2 in the file, the ordering
  # window 1 / 1 / 2, `creat` 1 / 1.
  #
  # THE TRAILING SPACE IN `^## ` IS NOT LOAD-BEARING HERE, and that is measured
  # rather than copied from a neighbour, because four sub-tasks of this story
  # needed four different answers: this section holds no heading of any depth
  # and no line beginning `#` — the YAML comments inside it all sit behind a
  # `>` — so `^## `, `^##` and `^#` capture the identical 49 lines. The form
  # the case already used is kept for that reason, not defended.
  sec="$(md_section "$VALIDATE_MODE" '^## Validator Sub-agent' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  printf '%s\n' "$flatsec" | command grep -q 'validation-report\.yaml'

  # THE CARVE-OUT, IN THE DEFINITION'S OWN FRAME (R1.5), which is the whole of
  # what "mirrors" is supposed to mean: `is a protocol violation` is the phrase
  # agents/validator.md:74 writes verbatim and the `1.1: validator carve-out`
  # case above already pins there. No negation guard rides beside it and none
  # is needed — the assertive frame SPLITS under every reversal English writes
  # for it (`is not a protocol violation`, `is never a protocol violation`),
  # which is the property 019 chose it for. Measured, one mutation at a time:
  # reversed in this template alone — RED; in both templates at once, the
  # vector that was GREEN before this sub-task — RED; the clause deleted
  # outright — RED. GREEN in the other direction: the surrounding sentence
  # reworded with the frame standing.
  printf '%s\n' "$flatsec" | command grep -qiE 'is a protocol violation'

  # THE ORDERING, PINNED IN THE TOKEN THIS COPY ALREADY CARRIES rather than by
  # rewriting it to match the definitions. 4.1 rewrote agents/*.md to `never
  # composing any textual summary first` and left this copy reading `as the
  # LAST step before composing any textual summary` — not a contradiction, the
  # same ordering stated with its own token, so the measured question was
  # whether that token can be pinned. It can: `last` and `before` are BOTH
  # polarity, and every reversal loses at least one of them — `FIRST step
  # after`, `LAST step after`, and the clause dropped for a bare `after
  # composing any textual summary` are RED, as is the clause deleted outright.
  #
  # ONE SPAN IN THE SCOPE, measured, which is what lets a `-q` reach a
  # single-site inversion the way 4.2's `before ... spawn` pin does. The
  # leashes are 40 and 40: the real gaps are 6 characters here (` step `) and
  # 27 at the :147 copy this same pattern reads two cases below (`** step of
  # their protocol, `), so 40 is rewording slack, not reach. The `(^|[^A-Za-z])`
  # boundary is measured free — one span with or without it — and keeps
  # `ballast` and `lastly` out. `compos` rather than `summary` for 4.1's
  # measured reason: a faithful rewording renames the object, and the :147 copy
  # already writes `prose` where these two write `textual summary`.
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'

  # ...AND A WINDOW CANNOT CARRY A NEGATION PARKED IN FRONT OF IT. This is
  # exactly the shape that defeated 4.1's predecessor: `never before composing
  # any textual summary` keeps both anchors and reverses the rule. Applied
  # here, `never as the LAST step before composing any textual summary` leaves
  # the match above GREEN — so the negation is refused where it can reach the
  # ordering, and REFUSED RATHER THAN REPAIRED IN THE PROSE, which is what
  # keeps this sub-task from rewriting three sites to match a fourth.
  #
  # The hop `((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3})
  # {0,3}` is the file's own hedge vocabulary plus the two articles this
  # sentence puts between a negation and `last`. Measured RED on all four
  # reversals that keep the anchors — `never as the LAST step`, `not as the
  # LAST step`, `not the LAST step`, `no longer the LAST step` — and measured
  # SILENT on every scope it runs in: 0 hits in this template, 0 in the
  # Auditor's, 0 in `## Validate Mode Procedure`, whose three `last` tokens
  # include `reads last week's `pass`` and `writes that file as its last step`.
  # Silent too on the rewordings the pin above admits (`as the LAST step of the
  # protocol, before composing ...`, `as the **last** thing they do, before
  # composing any prose`).
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-summary ordering is stated with a negation on it — the template reverses the rule its definition states"
    return 1
  fi

  # THE `.draft/` ALLOWANCE, the third copy, and it was not in this sub-task's
  # ToDo — it was measured into it. R1.3 + R3.2: fast and spike stories have no
  # `.draft/`, so the agent makes one rather than reporting its absence, and
  # this template states that rule in the same sentence as the write. Measured
  # unguarded exactly as the other two were (the reversal at both templates,
  # whole suite, 498 ok / 0 not ok), so it is closed here rather than filed in
  # a comment.
  #
  # SAME PATTERN AS THE AGENT-DEFINITION TWIN, one key, and `-q` rather than
  # the count that case takes: the definitions state the allowance TWICE per
  # file and any survivor answers a `-q` there, while this scope holds exactly
  # one `creat` — measured — so a count of 1 would assert nothing the `-q`
  # does not.
  printf '%s\n' "$flatsec" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'

  # ...AND THE DIRECTION, WITHOUT TOUCHING THE PROSE. The negation PREFIXES the
  # anchor `creat` — `never creating `.draft/` on demand` keeps the span and
  # reverses the permission, which is precisely what 3.2's count could not
  # reach and what 4.3 had to rewrite the agent files to close. It does not
  # have to be rewritten here: the definitions' scope is a whole file, this one
  # is 49 lines with a single `creat` in it, so an adjacency guard reaches what
  # a count cannot. Measured RED on `never creating `.draft/` on demand` and on
  # `do not create `.draft/` yourself`; measured SILENT on the unmutated
  # section (0 hits) and on the rewording `you create `.draft/` yourself when
  # the story has none`.
  #
  # ONE RESIDUAL LEFT, AND IT IS NOT THE ONE THIS COMMENT USED TO NAME. The
  # reversal that parks the negation AFTER the anchor (`though creating
  # `.draft/` on demand is forbidden`) passed both assertions above, and the
  # comment that stood here filed it as a residual the story would not pay for.
  # It is paid for below, by the prose rewrite 4.3 already took in the
  # definitions — the same edit, so no new mechanism and no wider guard. What
  # remains is a rewording that renames the verb (`making `.draft/` yourself`),
  # which false-Reds — R1.4's trade, taken here to keep one key with the twin
  # rather than widening the anchor on this copy alone.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?creat'
  then
    echo "the template's .draft/ allowance is stated with a negation on the verb — the permission is reversed"
    return 1
  fi

  # ...AND THE RESIDUAL THAT LEFT, WHICH IS D6 (R1.1). The comment above named
  # it rather than closed it: a reversal that parks the negation AFTER the
  # anchor — `though creating `.draft/` on demand is forbidden` — keeps the
  # `creat` span and satisfies the guard above, because that guard reaches a
  # negation only immediately IN FRONT of the verb. Measured on this tree
  # before the repair: that form left this case GREEN, while the control
  # `never creating` Redded it — one form of the same reversal caught, the
  # other not.
  #
  # CLOSED THE WAY 4.3 CLOSED IT IN THE DEFINITIONS, by prose rather than by
  # enumeration: the permission now carries a frame a negation must SPLIT
  # instead of prefix — `in the story directory, creating `.draft/` on demand —
  # fast and spike stories have none.` became `in the story directory —
  # creating `.draft/` on demand is part of that step, since fast and spike
  # stories have none.`, the same `is part of` frame agents/validator.md:74
  # already writes, in both templates identically. Widening the negation guard
  # was the alternative and is refused: enumerating the ways English says "no"
  # is the mechanism this story replaced.
  #
  # SAME KEY AS THE DEFINITION TWIN — one row, `\.draft[^.]{0,40}is +part of` —
  # and ANCHORED AFTER `.draft` for that case's arithmetic: `[^.]` cannot cross
  # the full stop inside `` `.draft/` ``, so a `creat...is part of` window could
  # never reach the verb it needs. COUNTED rather than `-q`, at 1 per template
  # section, because the count is what makes the SCOPE assert something: the
  # file holds two spans, one per template, and this story's defect is the copy
  # that says the opposite of its twin.
  #
  # Measured, one mutation at a time, each restored before the next: D6's own
  # form `though creating `.draft/` on demand is forbidden` — 0, RED; the frame
  # negated in place, `is NOT part of that step` — 0, RED; the control `never
  # creating` — 0, RED here and RED at the guard above; the clause deleted
  # outright — 0, RED. Measured GREEN in the other direction: `creating
  # `.draft/` when you find none is part of that step` and the sentence
  # reflowed across lines without a word changed.
  #
  # The count is captured before it is compared for the census's reason, the
  # same one the twin states: inlining the pattern into `[ "$(...)" ]` keys a
  # row on a span running from `|` to `)` and orphans the row this pattern has.
  allowed=$(printf '%s\n' "$flatsec" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 1 ]
}

# --- 1.2: Auditor report contract --------------------------------------------

@test "1.2: auditor frontmatter grants Write" {
  grants "$AUDITOR" "Write"
}

@test "1.2: auditor names .draft/audit-report.yaml, its verdict, and the write-before-summary ordering" {
  command grep -q 'audit-report\.yaml' "$AUDITOR"
  flat "$AUDITOR" | command grep -qi 'verdict'
  # Same rewritten rule and the same pin as the Validator's — the two files
  # state this step in one another's words, and 4.1 rewrote both in the same
  # edit so a divergence could not open here. Measured on THIS file rather
  # than inherited from the twin: `never` dropped, `never before composing`,
  # `first` -> `last` and the clause deleted each Red on agents/auditor.md
  # with agents/validator.md untouched, and the object reworded stays GREEN.
  # Why the negation sits adjacent, why `summar` is not an anchor and what
  # that costs are argued once, on the 1.1 twin above.
  flat "$AUDITOR" | command grep -qiE '(^|[^A-Za-z])never +composing[^.]{0,60}first'
}

@test "1.2: auditor carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # Same assertive frame as the Validator's, and for the same reason.
  flat "$AUDITOR" | command grep -qiE 'is a protocol violation'

  # Same count and the same two sites — the protocol step at agents/auditor.md:74
  # and the Rules bullet at :125, in the Validator's own words — measured on THIS
  # file rather than inherited from the twin: the bullet-only removal and the
  # step-only removal each Red here, as does either span deleted outright, and
  # the both-sites rewording stays GREEN. The both-sites REVERSAL stays green
  # here too, and always will: it keeps both spans and only turns them round,
  # which is the DIRECTION — 4.3's half, pinned in the assertion below. Why the
  # count is taken over flattened text, why `-eq` rather than `-ge`, and why it
  # is captured before it is compared are all on the 1.1 twin above — one
  # decision, not two, so it is argued once.
  spans=$(flat "$AUDITOR" | command grep -oiE 'creat[a-zA-Z]*[^.]{0,80}\.draft' | wc -l)
  [ "$spans" -eq 2 ]

  # ...AND IN WHICH DIRECTION, the same token, the same count and the same two
  # sites as the Validator's — the two files state this rule in one another's
  # words and 4.3 rewrote both Rules bullets in one edit, so no divergence
  # could open here. Measured on THIS file rather than inherited: the carve-out
  # reversed at BOTH spans counts 0 and Reds, at the protocol step alone counts
  # 1 and Reds, at the Rules bullet alone counts 1 and Reds, and the rewording
  # that keeps the frame at both spans stays GREEN. Why the pattern anchors
  # AFTER `.draft`, why `is part of` carries the direction where the participle
  # could not, and what the token costs are argued once on the 1.1 twin above.
  allowed=$(flat "$AUDITOR" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 2 ]
}

@test "1.2: validate-mode Auditor prompt template mirrors the report file" {
  # The Validator's twin, phrase for phrase, and every decision behind the four
  # pins below is argued once on that case rather than twice here: why the
  # scope is load-bearing, why the carve-out frame needs no guard, why the
  # ordering is pinned in the token this copy already carries instead of being
  # rewritten to match the definitions, and what the two `.draft/` residuals
  # cost. MEASURED ON THIS SECTION rather than inherited from the twin, which
  # is the rule 3.2, 4.1 and 4.3 all took when a pair moved together — this
  # scope is 69 lines to the Validator's 49 and holds prose the Validator's
  # does not, so a divergence could open here and nowhere else.
  #
  # Per-scope numbers, measured here: `is a protocol violation` 1 span,
  # the ordering window 1 span, `creat` 1 occurrence, and 0 hits for either
  # negation guard on unmutated prose. Section boundary: `^## `, `^##` and
  # `^#` capture the identical 69 lines, so the trailing space decides nothing
  # here either. Mutations, one at a time, each restored before the next: the
  # carve-out reversed alone — RED; the ordering reversed alone — RED; each
  # deleted outright — RED; the `.draft/` allowance reversed alone — RED; the
  # surrounding template text reworded with all three rules standing — GREEN.
  sec="$(md_section "$VALIDATE_MODE" '^## Auditor Sub-agent' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  printf '%s\n' "$flatsec" | command grep -q 'audit-report\.yaml'
  printf '%s\n' "$flatsec" | command grep -qiE 'is a protocol violation'
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-summary ordering is stated with a negation on it — the template reverses the rule its definition states"
    return 1
  fi
  printf '%s\n' "$flatsec" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?creat'
  then
    echo "the template's .draft/ allowance is stated with a negation on the verb — the permission is reversed"
    return 1
  fi

  # ...AND THE RESIDUAL THAT LEFT — D6 (R1.1), the Auditor's copy of it. The
  # argument is the Validator case's, one screen up, and so is the prose
  # repair: `is part of that step` is a frame a negation must SPLIT, where the
  # guard above reaches only a negation parked in FRONT of `creat`. Both
  # templates took the identical edit, which is what keeps one key across the
  # four sites this pattern now reads.
  #
  # Measured here too rather than inherited, one mutation at a time on this
  # section: `though creating `.draft/` on demand is forbidden` — 0, RED; `is
  # NOT part of that step` — 0, RED; `never creating` — 0, RED; the clause
  # deleted — 0, RED. GREEN on the rule-preserving rewording.
  allowed=$(printf '%s\n' "$flatsec" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 1 ]
}

@test "1.2: the Auditor template's carve-out keeps the memory clause, and the Validator's stays memory-free" {
  # R3.4, both halves. auditor.md's carve-out names the memory directory as the
  # agent's OWN store so that 'one writable path' does not forbid the after-audit
  # append the same file mandates. A restatement that drops the clause tells a
  # template-spawned Auditor to violate its own system prompt — and it did:
  # story 011's audit withheld its mandated append rather than risk it.
  aud="$(md_section "$VALIDATE_MODE" '^## Auditor Sub-agent' '^## ')"
  # `is your own store`, not a bare `own store`: the clause is what LICENSES the
  # append, so "it is not your own store" must red rather than satisfy it.
  printf '%s\n' "$aud" | tr '\n' ' ' \
    | command grep -qiE 'memory director[a-z]*[^.]{0,160}is your own store'

  # The NEGATIVE half, and it is the load-bearing one. `memory: project` is
  # carried by analyst and auditor alone, so a memory clause in the Validator's
  # prompt would name a store that agent does not have. Deliberately broad — any
  # mention of memory here reddens, because the failure mode is a well-meaning
  # sweep copying the clause into every carve-out it can find.
  val="$(md_section "$VALIDATE_MODE" '^## Validator Sub-agent' '^## ')"
  if printf '%s\n' "$val" | command grep -qi 'memory'; then
    return 1
  fi
}

# --- 2.1: orchestrator consumes the files ------------------------------------

@test "2.1: validate-mode removes the stale report file before spawning" {
  # R2.2: a leftover from a prior run must never read as a fresh verdict.
  #
  # THE PREDECESSOR PINNED NEITHER HALF OF ITS OWN NAME. It asked only that
  # some line mentioning `stale` also name a report file — line-based on
  # purpose, because `## Index Refresh` calls a stale INDEX "a stale
  # rendering" and that line has nothing to do with reports. Measured on this
  # tree rather than inherited: the deletion verb reversed at all three sites
  # (`Delete`/`delete`/`delete that agent's` -> `Keep`/`keep`/`never delete
  # that agent's`) together with `Before each spawn` -> `After each spawn`
  # left it GREEN, on prose that then stated the opposite rule twice over.
  #
  # SCOPED RATHER THAN WIDENED, AND NO PROSE WAS TOUCHED (R3.1). All three
  # sites sit inside `## Validate Mode Procedure` — steps 3 and 4 and the
  # R2.2 subsection heading — and the decoy sits in `## Index Refresh`, so the
  # section boundary excludes it by construction rather than by the
  # co-location trick the predecessor needed. Measured in the other direction
  # too: the decoy reworded with the rule untouched stays GREEN.
  #
  # THE TRAILING SPACE IN `^## ` IS LOAD-BEARING HERE, measured rather than
  # copied from a neighbour: `^## ` runs past the three `###` subsections to
  # `## Status Transition` and captures 42 lines, the R2.2 heading among them,
  # while `^##` stops at the first `###` and captures 10 — dropping the third
  # site entirely and Redding on unmutated prose.
  sec="$(md_section "$VALIDATE_MODE" '^## Validate Mode Procedure' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # HALF ONE, THE VERB, AND IT IS COUNTED. The rule stands at three sites, so
  # asking whether it is stated ANYWHERE is answered by any two survivors —
  # the partial-removal defect this story is named for. Measured one site at a
  # time: the verb reversed at step 3 alone, at step 4 alone and at the R2.2
  # heading alone each take the count to 2 and Red, where the predecessor
  # stayed GREEN on all three. Why the count is taken over flattened text with
  # `grep -o | wc -l` rather than `grep -c`, why `-eq` rather than `-ge`, and
  # why it is captured before it is compared are argued once on the 1.1
  # carve-out twin above — one decision, not two.
  #
  # `remov` RIDES BESIDE `delet` because this document calls the act by both
  # names — the R2.2 paragraph writes "Step 3 removes … and step 4 removes …"
  # of the very deletes the heading above it mandates, and this case's own
  # name says `removes`. A pin that Redded when the prose adopted the case's
  # own word would be the rewritten-for-the-grep failure this task group is
  # warned about. The widening is measured free: 3 spans either way, and the
  # section holds exactly three `stale` tokens, so no verb elsewhere can raise
  # the count. The 40-character leash is rewording slack, not reach — the
  # widest real gap is 14 (`delete that agent's stale`) and the count is 3 at
  # every width from 20 to 120.
  deletes=$(printf '%s\n' "$flatsec" | command grep -oiE '(delet|remov)[a-z]*[^.]{0,40}stale' | wc -l)
  [ "$deletes" -eq 3 ]

  # ...AND A COUNT CANNOT CARRY THE DIRECTION. `never delete that agent's
  # stale report file` is the rule reversed and still counts three, because
  # the negation PREFIXES the anchor — the same shape that leaves the
  # `.draft/` carve-out open two cases above. Refused here instead, and
  # ADJACENT so that a negation reaching the verb Reds while prose that merely
  # contains one does not: the R2.2 subsection's own "Deleting what is not
  # there is a no-op, never an error" is silent here, measured, as is
  # "**Never respawn silently.**" further down the same section.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?(delet|remov)'
  then
    echo "the stale report file's deletion is stated with a negation on the verb — the rule is reversed"
    return 1
  fi

  # HALF TWO, THE ORDERING, pinned separately so a future reader sees which
  # half broke: `Before each spawn` -> `After each spawn` keeps every word the
  # count above reads and reverses the rule's other half. What is pinned is
  # the ordering word sharing a sentence with BOTH the spawn and the delete —
  # one span in the section, measured, the R2.2 heading itself. A bare
  # `before … spawn` would not reach it: the paragraph under that heading says
  # "immediately before spawning" too, so the heading could be inverted alone
  # and stay green.
  #
  # BOTH ORDERS, for the reason the evidence-pair case below takes them: the
  # rule reworded as `delete that agent's stale report file before each spawn`
  # states the same ordering the other way round, and this task group's risk
  # is a pin so tight a faithful rewording false-Reds. Neither branch matches
  # anything else in the section, measured, before the mutation and under it.
  #
  # Residual, named rather than left to be found: the paragraph's own
  # restatement inverted ALONE — "each immediately after spawning", the
  # heading intact — stays GREEN, measured. Reaching it costs a second count
  # over `before … spawn`, whose price is a false Red the day that paragraph
  # legitimately stops restating the heading above it.
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(before[^.]{0,20}spawn[a-z]*[^.]{0,30}(delet|remov)|(delet|remov)[a-z]*[^.]{0,60}before[^.]{0,20}spawn)'
}

@test "2.1: the procedure reads both verdicts from the report files" {
  # R2.1: steps 3-5 conclude from disk; the message is courtesy.
  #
  # THAT COMMENT WAS THE ONLY PLACE THE DIRECTION WAS STATED. The assertion
  # under it asked whether `validation-report` and `audit-report` OCCURRED
  # anywhere in the section — a filename, which an inversion of this rule has
  # no reason to delete. Measured: steps 3 and 4 rewritten to "Take the verdict
  # from the final message" and "take its verdict from its final message the
  # same way" left it GREEN, because both steps still DELETE their report file
  # and the R2.2 subsection names both files again.
  #
  # Both halves of the comment are asserted now, and both are needed: the
  # inversion of the steps leaves the R2.1 subsection intact, the inversion of
  # that subsection leaves the steps intact, and each was run on its own.
  proc="$(md_section "$VALIDATE_MODE" '^## Validate Mode Procedure' '^## ')"

  # CONCLUDE FROM DISK. Line-based co-location, as at the stale-report case
  # above: this file writes one paragraph per source line, so the report file
  # and the direction have to be stated in the SAME paragraph — the filename
  # cannot be answered by the delete in step 3 while the direction is answered
  # by some unrelated step. What is pinned is the SOURCE of the verdict, not a
  # wording: `read off that report file` and `comes from disk` are the same
  # rule and stay green; `from the final message` is another rule and Reds.
  printf '%s\n' "$proc" | command grep -E 'validation-report' \
    | command grep -qiE 'verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)'
  printf '%s\n' "$proc" | command grep -E 'audit-report' \
    | command grep -qiE 'verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)'

  # THE MESSAGE IS COURTESY — the half no filename can carry: the reply is the
  # source of NO verdict. The negation has to GOVERN the reply, which is what
  # the reversal cannot keep; moving it onto the file ("The report file is a
  # convenience … and the source of no pass/fail decision") Reds here.
  #
  # NOT co-located with a filename, unlike the pass point below, and that is
  # measured rather than preferred: no line of this section states both halves,
  # and the co-located form is answered by R2.3's table row 2 on its own — "or
  # **not** parseable as YAML | **one** `SendMessage`" — a line the inversion
  # of steps 3-4 never touches.
  #
  # `(no|not|never)` carries a boundary on each side so `now`, `know` and
  # `cannot` are not read as negations — that same row 2 ends "asking it to
  # write its report file now", and it is what made the boundaries necessary.
  printf '%s\n' "$proc" \
    | command grep -qiE '(message|repl(y|ies))[^.]{0,120}[^A-Za-z](no|not|never)[^A-Za-z][^.]{0,40}(pass/fail|verdict|decision)'

  # AND THE PREMISE UNDER BOTH HALVES: the files are readable at step 3 only
  # because each agent writes its report as the LAST step, BEFORE any prose.
  # That is the first clause of this section's own R2.1 paragraph (:147), and
  # it is the THIRD unguarded copy of the ordering 4.1 pinned in the two agent
  # definitions — the two prompt templates are the other two, pinned in the
  # `1.1:`/`1.2:` mirror cases with this identical pattern and this identical
  # guard. It lands in THIS case rather than in a case of its own because this
  # scope is the only one that reaches :147 and because the sentence states
  # this case's own rule from the writing side. Measured on this tree before
  # the repair: the ordering reversed at all three copies at once left the
  # whole suite at `1..498`, 498 ok, 0 not ok.
  #
  # ONE SPAN IN THIS SCOPE, measured, out of three `last` tokens — the other
  # two are step 3's `writes that file as its last step` and R2.2's `reads last
  # week's `pass``, neither of which has `before ... compos` behind it. The
  # 40-character leashes carry this copy's own gap of 27 (`** step of their
  # protocol, `), which is why the same pattern reads all three copies. RED
  # measured here, one mutation at a time: `**first** step ... after composing
  # any prose`, `**last** step ... after composing any prose`, and the clause
  # deleted outright. GREEN on `as the **last** thing they do, before composing
  # any prose`. Why the guard below is needed, what its hop admits and what the
  # pin costs are argued once on the `1.1:` mirror case above.
  #
  # FLATTENED, unlike the three assertions above it, and the difference is the
  # claim rather than taste: those pin a fact to the LINE that names a report
  # file, so flattening would let the filename and the direction come from
  # different paragraphs; this one needs no co-location and takes the reflow
  # tolerance instead. Measured on the flattened section, not assumed — one
  # span for the pin, zero hits for the guard, the same two numbers the raw
  # section gives, so the widening admits nothing new.
  flatproc="$(printf '%s\n' "$proc" | tr '\n' ' ')"
  printf '%s\n' "$flatproc" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'
  if printf '%s\n' "$flatproc" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-prose ordering is stated with a negation on it — the premise this section reads its verdicts under is reversed"
    return 1
  fi
}

@test "2.1: an absent or unparseable report is re-requested once via SendMessage, then the run is failed" {
  # R2.3: the recovery path is one SendMessage, never a silent respawn and
  # never a verdict inferred from prose.
  #
  # Scoped to the recovery subsection. The unscoped predecessor asked only
  # whether `SendMessage` and `unparseable` appeared ANYWHERE in the mode file
  # — and both do, in the R2.1 prose above — so deleting any of the three rows
  # this case is named for left it green. Measured: three deletions, three
  # false passes.
  #
  # End pattern is '^#', NOT the '^## ' the neighbouring cases use: that one
  # carries a trailing space and so runs straight past a '###' subsection,
  # swallowing the rest of the file and putting the scope back where it was.
  # '#' anchored at line start cannot match the table's '| # |' header.
  sec="$(md_section "$VALIDATE_MODE" '^### Absent or unparseable' '^#')"
  # Flattened inline rather than via `flat`, which reads a file and cannot take
  # a captured section on a pipe. A soft wrap must not hide a phrase.
  sec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # ONE REQUEST, BY SendMessage — AND NEVER A SECOND, which is the half the
  # predecessor could not carry. That one was
  # `(^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage`, and no pattern could
  # repair it: `one` is a SUBSTRING of every phrase that reverses it (`more
  # than one`, `one per attempt`), so a reversal never has to come near the
  # anchors. Measured, 1.5 and again here on this tree — row 2 rewritten to
  # `**one** `SendMessage` … per attempt … — repeat the row as often as it
  # takes`, the paragraph to `**One request per attempt, …**` and row 3 to
  # `after the last of those requests` left this case GREEN under a rule that
  # now licenses unbounded re-requests. No scope and no count reaches that;
  # only different prose does (R1.4), and 4.3's is the smallest edit that
  # carries the bound: `and **never a second**` inserted into row 2 and `and
  # never a second` into the paragraph — a token inside each existing
  # sentence, no word moved and no paragraph restructured.
  #
  # THE TOKEN IS ONE THE REVERSAL BREAKS RATHER THAN CONTAINS, which is the
  # whole difference from `one`: prose that licenses repeats cannot keep
  # `never a second` and stay coherent. So the mutation that defeated the
  # predecessor Reds here, as do `never` dropped, the token dropped, and the
  # rule inverted to `always a second` — four vectors, one at a time.
  #
  # MECHANISM AND BOUND IN ONE MATCH, because the case is named for both.
  # `SendMessage` occurs exactly once in this section — row 2, measured — and
  # the token sits 30 characters from it. BOTH ORDERS, for the reason the
  # ordering pin two cases above takes them: a rewording that states the bound
  # first states the same rule, and this task group's risk is a pin so tight a
  # faithful rewording false-Reds. Neither branch matches anything else in the
  # section, measured — the paragraph's own `never a second` has no
  # `SendMessage` within 60 characters, before the mutations or under them.
  printf '%s\n' "$sec" \
    | command grep -qiE '(SendMessage[^.]{0,60}never +a +second|never +a +second[^.]{0,60}SendMessage)'

  # ...AND AT BOTH SITES THAT STATE IT, counted, because a `-q` is answered by
  # either one and the partial removal is the defect this story is named for:
  # row 2 is the instruction the flow executes, the paragraph is the argument
  # for it. Measured one site at a time — the bound reversed at row 2 alone and
  # at the paragraph alone each take the count to 1 and Red, where the
  # predecessor stayed GREEN on both. `-eq` rather than `-ge`, over flattened
  # text, captured before it is compared: three decisions argued once at the
  # 1.1 carve-out twin above, at the same measured cost — a legitimate THIRD
  # statement of the bound would false-Red. The ` +` is 4.1's measured reflow
  # slack; the leading boundary is not decoration either, because `whenever a
  # second` ends in `never a second`.
  #
  # ROW 3 STATES THE BOUND TOO, in its own words rather than in this token's
  # (`after that one request`), and it is pinned at the TAIL of this case
  # instead of counted here: it is the same rule read from the failure side and
  # it shares no anchor with `never a second`. Reversing that row alone leaves
  # this count at 2 and Reds the pairing below — measured, one mutation at a
  # time, which is how all three sites end up held.
  bounds=$(printf '%s\n' "$sec" | command grep -oiE '(^|[^A-Za-z])never +a +second' | wc -l)
  [ "$bounds" -eq 2 ]

  # ...AND NOT MORE THAN ONE, for the five phrasings this guard names and no
  # others. That limit is measured, not suspected: 1.5 reddened it with `**more
  # than one** `SendMessage`` and left it GREEN with the `per attempt` form,
  # which is why the bound is now in the PROSE and pinned above rather than
  # enumerated here. Extending the list is the mechanism this story replaces,
  # so the list is untouched.
  #
  # KEPT, AND NOT REDUNDANT — measured rather than assumed, because an
  # assertion that cannot fail while its neighbour passes is one this file
  # deletes (see the carve-out count above). The vector it alone catches is the
  # MINIMAL widening: row 2's `**one**` swapped for `**more than one**` with
  # the token left standing. The prose then contradicts itself, the pin and the
  # count both stay GREEN, and this guard Reds.
  #
  # NOT a bare `!`, and that is not a style choice: bash exempts a `!`-inverted
  # command from errexit, so its status is discarded anywhere but the LAST
  # statement of the @test — and two assertions follow this one. Measured: as a
  # `!` here, this reddened none of the three inversions. No site in tests/ uses
  # that shape any more — sub-task 1.2 converted the last six, and `1.1: no
  # .bats file in tests/ inverts a command as an assertion` keeps them gone.
  #
  # NOT the generic helper the header forbids: that one rejects any negation in
  # the window before any match and false-Reds on auditor.md's memory clause by
  # construction. This names the modifiers of ONE quantifier, stays inline in
  # the case that owns it, and is silent on the unmutated section — which holds
  # four `one`s, measured: row 2's "**one** `SendMessage`", row 3's "after that
  # one request", the paragraph's "One request and never a second" and the
  # respawn paragraph's "looping over one failure".
  #
  # One red-on-correct vector, measured and accepted rather than discovered
  # later: "never more than one `SendMessage`" Reds here, and that is accepted
  # because row 2 is an imperative action cell whose prohibition is already
  # stated, adjacent, as `**never a second**`.
  if printf '%s\n' "$sec" \
    | command grep -qiE '((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)'
  then
    return 1
  fi
  # NEVER a silent respawn — the whole cost the report file exists to avoid,
  # and `never` has to GOVERN `respawn` rather than merely share a sentence
  # with it. The predecessor `never[^.]{0,80}respawn` passed `**Never conclude
  # without a respawn.**` — a rule that MANDATES the respawn — because that
  # reversal moves the negation's OBJECT and leaves both anchors standing
  # (measured, 1.5). Pinned ADJACENT instead: the phrase the rule's own name
  # already uses, one span in this section before and after.
  #
  # The optional `-ly` adverb is the one thing English puts between a
  # prohibition and its verb without changing what is prohibited: `**Never
  # silently respawn the agent.**` stays GREEN, measured. Every reversal needs
  # a verb and a preposition in that slot — `conclude without a`, `fail to`,
  # `skip a` — or a bare `not`, and none of those is an adverb: RED, measured,
  # including the `**Always respawn silently.**` control and the deletion.
  # Two residuals, measured and named rather than hidden: an adverb that
  # WEAKENS instead of reversing (`never unnecessarily respawn`) passes, and
  # the prohibition restated with its negation AFTER the verb (`a silent
  # respawn is never the answer`) false-reds — what is pinned is the order the
  # rule's own name states. Closing the adverb slot to buy the first one back
  # would false-red a plain word-order rewording, the costlier of the two.
  printf '%s\n' "$sec" \
    | command grep -qiE '(^|[^A-Za-z])never[^A-Za-z]+([a-z]+ly[^A-Za-z]+)?respawn'
  # THEN THE RUN IS FAILED — story 011's sub-task 2.1 ToDo, verbatim: "still
  # absent → the run is failed, stated in exactly those terms (R2.3)". The
  # copula and the participle are required ADJACENT, not merely co-occurring
  # within a window: an inversion writes `not` between them, and
  # `the run[^.]{0,40}fail` matched "the run is **not** failed" exactly as it
  # matched the real row. Safe to tighten because it is measured, not hoped:
  # this section holds exactly one `the run … fail` span and it reads `the run
  # is failed` — the same phrase row 3, that ToDo and this case's own name all
  # use, so prose that breaks it is a rewrite of the contract, not a rewording
  # of it. NOT task group 2's Risk field, which an earlier draft of this comment
  # credited: that field reads "recovery path wording must not permit silent
  # respawn" and never carries the phrase — the grep on the line above is what
  # answers for it.
  #
  # ...AFTER *ONE* REQUEST, WHICH IS ROW 3'S HALF OF THE BOUND, and the third
  # site the token above does not reach. A bare `the run is failed` cannot
  # carry it, and that gap is measured rather than argued: with the bound
  # WIDENED but KEPT — `never a second per attempt` at both token sites, row 3
  # rewritten to `after the last of those requests` and `repeat the row as
  # often as it takes` appended — every other assertion in this case stayed
  # GREEN on a section that now licenses unbounded re-requests. Pairing the
  # count with the failure Reds it, because a rule that repeats cannot also say
  # the run is failed after ONE request.
  #
  # THE COUNT SITS ADJACENT TO THE NOUN IT COUNTS, which is what makes `one`
  # usable here after 1.5 proved it unpinnable on its own. The two directions
  # split: a reversal that licenses repeats must change the noun (`the last of
  # those requests`, `each of those requests`) and so loses the phrase, while a
  # reversal that KEEPS `one` needs a modifier in front of it — `more than one
  # request` — which the guard above refuses. Neither assertion covers the
  # other, measured both ways. `single` rides beside `one` because it is this
  # document's other word for the same count, and the widening is measured free
  # — one span either way, and the section's other `one`s are all further than
  # 60 characters from the failure phrase or behind a full stop. Residual,
  # named rather than left to be found: row 3 reworded to drop the count
  # altogether (`after that request`) false-Reds, which is R1.4's trade — the
  # same one 4.1 took at the ordering clause.
  printf '%s\n' "$sec" \
    | command grep -qiE '(^|[^A-Za-z])(one|single) +request[^.]{0,60}the run is failed'
}

@test "2.1: the pass point keys off the report file's verdict" {
  # R2.4: stamping `validated` reads the file, not the message. Scoped to the
  # Status Transition section — "reported" elsewhere must not satisfy it.
  #
  # THE FILENAME WAS NOT THE RULE. Asking only that the section mention a
  # report file left this case green through the rule's own reversal:
  # measured, `Rules 1-3 turn on what an agent said in chat — never on the
  # `verdict` field of `.draft/validation-report.yaml` and
  # `.draft/audit-report.yaml`` keeps every filename, and the case named for
  # the direction passed a section that now states its opposite.
  #
  # The polarity was already in the prose — "never on what an agent said in
  # chat" — so the match carries it: a negation GOVERNING the reply, on the
  # line that names the report file. Exactly one line of this section names
  # one (the rule itself), so the rejection cannot be borrowed from a
  # neighbouring paragraph.
  #
  # The reversal cannot keep that shape. It moves the negation onto the file
  # half, where the full stops in `.draft/…yaml` close the window before any
  # word for the reply — RED, measured. "The verdict is read from the report
  # files … rather than from the agents' replies" stays GREEN, which is the
  # distinction the pin exists to draw: the direction survives a rewording,
  # the reversal does not.
  md_section "$VALIDATE_MODE" '^## Status Transition' '^## ' \
    | command grep -iE 'validation-report|audit-report|report file' \
    | command grep -qiE '((^|[^A-Za-z])(never|not)[^A-Za-z]|rather than|instead of)[^.]{0,80}(chat|message|repl(y|ies)|said|prose)'
}

# --- 3.1: Tech Reviewer measures ---------------------------------------------

@test "3.1: tech-reviewer frontmatter grants Bash" {
  grants "$TECH_REVIEWER" "Bash"
}

@test "3.1: tech-reviewer's Bash is measurement-only and never mutates" {
  # R3.1 + R3.3: the grant arrives WITH its restriction, and the no-modify
  # rule survives reworded — both facts, not either one.
  #
  # `measurement` ALONE IS THE TOPIC, NOT THE RULE. The case is named for a
  # restriction and asserted a subject heading: measured, rewriting the grant
  # to "`Bash` is not limited to measurement — never mutate files or git
  # state" left it GREEN, because the topic word survives every widening of
  # the scope it exists to close. What is pinned instead is the RESTRICTION
  # both files already write — `for measurement only` — which occurs once per
  # file, so no heading and no cross-reference can answer for it.
  flat "$TECH_REVIEWER" | command grep -qiE '(^|[^A-Za-z])for measurement only'

  # THE PHRASE ALONE IS NOT THE RULE EITHER: the reversal keeps it and negates
  # it. "`Bash` is not for measurement only" is the inversion 1.5 measured
  # GREEN against the predecessor, and it contains `for measurement only`
  # verbatim. So the negation is refused where it can reach the phrase —
  # adjacent, or across one hedge ("no longer", "not merely", "must not be").
  # Adjacency rather than a sentence-wide window is the point: a window here
  # would red on "This is a rule, not advice: `Bash` is for measurement only",
  # which states the rule rather than reversing it.
  if flat "$TECH_REVIEWER" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?for measurement only'
  then
    echo "the restriction phrase survives, negated: the grant no longer stops at measurement"
    return 1
  fi

  # THE NO-MUTATION HALF WAS UNGUARDED TOO — the story recorded only the scope
  # half as open, and the sweep in 1.5 recorded this sibling DIRECTION-BLIND.
  # Both are right about a different mutation, and the pair is why the window
  # went: `(never|not)[^.]{0,80}mutat` reads 80 characters and cannot say which
  # clause the negation governs. Measured on this file, one change at a time —
  # dropping the negation ("— mutate files or git state when the fix is
  # trivial") went RED, but moving its OBJECT ("— never refuse to mutate files
  # or git state when the fix is trivial"), a rule that now licenses the
  # mutation, stayed GREEN.
  #
  # The negation sits on the mutation word, at most one `for` apart: `no-modif`
  # is excluded on purpose, because this paragraph names the rule as "The
  # no-modification rule" and that noun would answer the assertion by itself
  # while the clause above it said the opposite. Grepping the lines that name
  # the tool first is the co-location this case is named for — the grant
  # arrives WITH its restriction, not somewhere else in the file: the closing
  # "**Do NOT modify files or git state. Only report.**" is a second span of
  # the prohibition and must not be able to stand in for this one.
  #
  # ONE `for` IS THE WHOLE WIDENING, and strict adjacency was too tight
  # without it: rewriting the half to "— never for mutation." preserves the
  # rule exactly and went RED — this task group's own risk, a pin so tight a
  # faithful rewording false-Reds. It keeps the sentence's own frame ("is for
  # measurement only") and negates it for mutation, so what is admitted is
  # that clause nominalised, not a gap: a VERB between the two is what
  # re-targets the negation, and "never refuse to mutate" is still RED.
  command grep -E '(^|[^A-Za-z])Bash([^A-Za-z]|$)' "$TECH_REVIEWER" \
    | command grep -qiE '(never|not|no) {1,3}(for {1,3})?(mutat|modif)'
}

@test "3.1: a tech-reviewer finding resting on a runnable check cites command and output" {
  # R3.2: measured, not argued — the finding carries the evidence pair.
  #
  # NO PIN COULD HAVE CLOSED THIS ONE ALONE: the predecessor read the WHOLE
  # file, and `command[^.]{0,120}output` was answered TWICE — by the rule at
  # agents/tech-reviewer.md:44 and by the report-format bullet at :55 ("… the
  # command and its output"). Measured, and it is why the scope comes before
  # the polarity: DELETING the rule outright left the predecessor GREEN, so
  # the obligation could vanish from that file without a Red.
  #
  # SCOPED TO THE SECTION THAT STATES THE RULE. `## Measurement, Not Argument`
  # ends where `## Protocol` begins, which puts the checklist bullet out of
  # scope by construction. The end pattern is `^## ` WITH the trailing space,
  # the idiom the `##`-level captures above use; here it is not load-bearing
  # and that is measured, not assumed — the section holds no heading of any
  # depth, so `^##` captures the same seven lines. Where a `###` subsection
  # DOES sit inside, the space decides the boundary, which is why the run-mode
  # case below drops it and says so. Inside the section the pair has exactly
  # one span and `output` occurs exactly once, so the deletion Reds now.
  # The exclusion is measured in the other direction too: the :55 bullet
  # rewritten to `— a paraphrase of what you ran`, the rule untouched, stays
  # GREEN. A span this case does not own must not decide it.
  sec="$(md_section "$TECH_REVIEWER" '^## Measurement, Not Argument' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # THEN THE POLARITY, because a scope alone still passes a section stating
  # the opposite. `carries` is the obligation, and English reverses a rule of
  # this shape with a modal plus a bare infinitive — `need not carry`, `does
  # not carry`, `is not required to carry` — every one of which loses the
  # inflection: RED, measured, all three.
  #
  # The 60-character leash and the two orders are costs, measured rather than
  # preferred. Reworderings that park a parenthetical between the verb and its
  # object cluster at 40-44 characters (`carries, quoted rather than
  # paraphrased, the exact command …`), and `carries the observed output and
  # the exact command that produced it` states the same pair the other way
  # round; a 40-character single-order pattern false-Reds both. Tightening the
  # leash buys nothing back: a sentence where `carries` governs some OTHER
  # noun while the pair sits in a later clause measures 39 characters, inside
  # even a 40-character window. That shape is the residual, named rather than
  # discovered later — the leash proves `carries` shares the sentence, and the
  # guard below is what proves it is not negated.
  printf '%s\n' "$flatsec" \
    | command grep -qiE 'carries[^.]{0,60}(command[^.]{0,120}output|output[^.]{0,120}command)'

  # THE INFLECTION IS NOT THE WHOLE RULE. Three reversals keep it and park the
  # negation beside it — `carries neither the command nor its output`, `never
  # carries`, `no longer carries` — and all three pass the match above,
  # measured. Refused here rather than by narrowing that match, because a
  # negation beside `carries` only reverses the rule when it REACHES the pair:
  # `carries no command it did not actually run` restates the rule and stays
  # GREEN, which is what the `output` leash on the second branch is for.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '((never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?carries|carries[^A-Za-z]{1,3}(no|neither|nothing)[^.]{0,80}output)'
  then
    echo "the evidence pair is stated with a negation beside it — the finding is no longer obliged to carry it"
    return 1
  fi
}

@test "3.1: run-mode Tech Reviewer prompt template mirrors the measurement rule" {
  # R3.4: the duplicated template in references/run-mode.md moves in the same
  # story as the agent definition.
  #
  # THE SECTION SAYS `measurement` THREE TIMES and only one of them is the
  # rule: the heading "Measurement, Not Argument", step 3's "per Measurement
  # above", and the grant itself. Measured — deleting the grant's whole
  # paragraph from the template left this case GREEN, answered by the other
  # two, so the mirror it exists to keep could go missing silently. The phrase
  # `for measurement only` occurs once in the section, which is what makes
  # this assertion load-bearing.
  #
  # The end pattern is `^##` WITHOUT the trailing space on purpose, unlike the
  # `^## ` used elsewhere: it stops at the next heading of any depth, which
  # here is `### Orchestrator Handling of Tech Review`. `^## ` would run past
  # that subsection to `## Context Passing Between Tasks` and let prose the
  # template does not own answer for it. The blockquote markers make no
  # difference — `> ## Protocol` starts with `>`, so no inner heading of the
  # quoted prompt closes the section early.
  sec="$(md_section "$TECH_REVIEW" '^### Tech Reviewer Prompt Template' '^##')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"
  printf '%s\n' "$flatsec" | command grep -qiE '(^|[^A-Za-z])for measurement only'

  # Same guard as the agent definition's case, for the same measured reason:
  # "is not for measurement only" keeps the phrase and reverses the rule.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?for measurement only'
  then
    echo "the template mirrors the restriction phrase, negated — the mirror states the opposite rule"
    return 1
  fi
}

# --- 2.2: least-privilege grant sets -----------------------------------------

@test "2.2: Write is granted to exactly auditor, executor, test-advisor and validator" {
  # Constraint: Validator/Auditor grow by exactly Write. executor and
  # test-advisor already held it; nobody else joins. An exact-set compare
  # reddens on an agent ADDED as loudly as on one removed.
  expected="auditor
executor
test-advisor
validator"
  [ "$(agents_granting Write)" = "$expected" ]
}

@test "2.2: Bash is granted to exactly auditor, executor, tech-reviewer, test-advisor and validator" {
  # Constraint: Tech Reviewer grows by exactly Bash; the four existing holders
  # keep theirs.
  expected="auditor
executor
tech-reviewer
test-advisor
validator"
  [ "$(agents_granting Bash)" = "$expected" ]
}

@test "2.2: PIN Edit stays the executor's alone" {
  # GREEN PIN — true before this story and required to stay true through it:
  # both new grants are Write or Bash, never Edit. A reddening here means a
  # grant came along for the ride.
  [ "$(agents_granting Edit)" = "executor" ]
}

# --- agent-definition conventions --------------------------------------------
#
# NO 011 SUB-TASK OWNS THE CASE BELOW, so it carries no `N.N:` prefix — the
# per-sub-task filter (`bats --filter '^1\.1:'`) must keep answering for exactly
# the sub-task it names, and a general convention borrowing a number would make
# it answer for one more. It is parked in this file because a single case does
# not earn a file of its own; move this block out when a second
# agent-definition convention joins it. Its helper travels with it, which is why
# that helper sits here rather than with the shared ones at the top.

# The memory: line inside the frontmatter block only — the same shape as
# frontmatter_tools, so prose about memory can never enrol an agent.
frontmatter_memory() {
  awk 'NR==1 && $0=="---" {inb=1; next}
       inb && $0=="---" {exit}
       inb && $0 ~ /^memory:/ {print; exit}' "$1"
}

@test "convention: an agent granted memory: project heads its Memory section with the epic- prefixed directory" {
  # `.claude/agent-memory/epic-<name>/` is the runtime's path for a
  # plugin-namespaced agent. Measured, not assumed: epic-analyst/ and
  # epic-auditor/ exist and carry notes from prior runs, while the unprefixed
  # pair these headings once named never existed at all — so the declaration
  # sent an agent to consult and append to nothing.
  #
  # DERIVED FROM THE FRONTMATTER, never from a hardcoded pair, so a third
  # memory-carrying agent joins this pin by existing rather than by someone
  # remembering to come back here.
  checked=0
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    frontmatter_memory "$f" | command grep -q 'project' || continue
    name="$(basename "$f" .md)"
    heading="$(awk '/^## Memory/ {print; exit}' "$f")"
    printf '%s\n' "$heading" | command grep -q "agent-memory/epic-${name}/"
    checked=$(( checked + 1 ))
  done
  # Without this the loop is a vacuous pass: a frontmatter shape the helper
  # stopped parsing would enrol nobody and the case would go green having
  # pinned nothing — the exact defect this story exists to close.
  [ "$checked" -ge 1 ]
}
