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
# is satisfied by its own negation. The sanctioned form is a SECOND, inline
# negated grep naming that claim's own modifiers (`:296`) — never a generic
# one, for the reason the paragraph above gives. Naming the modifiers is also
# what keeps it behavior-level: it rejects the handful of phrases that reverse
# the count, not the sentence that states it.
#
# A NEGATED ASSERTION MUST NOT REST ON BEING LAST. Bash exempts a `!`-inverted
# command from errexit, so anywhere but the final statement of an @test its
# non-zero status is discarded and the assertion is inert — green whatever the
# file under test says. Probed, not reasoned: `! true` followed by one more
# assertion passes, while `if true; then return 1; fi` in that same slot fails.
# The sanctioned shape is therefore `if … then return 1; fi` (`:296`). The
# subshell `( ! … )` also survives being moved and was rejected on diagnostics
# alone — bats named the `return 1` line for the `if` and only the `@test` line
# for the subshell, pointing at the case instead of the assertion.
#
# Five negations in this suite are correct TODAY only because nothing follows
# them, each one appended assertion away from silently becoming a no-op: `:231`
# here, `tests/secrets-allowlist.bats:344`, `tests/spike-stale.bats:85` and
# `:91`, and `tests/validate-story.bats:238`. Measured, not assumed — each
# pattern was widened to match everything and each owning case went Red.
# Convert one when you touch its case, not in a sweep.
# Five OTHERS were already inert by this rule and sub-task 1.7 converted them:
# `tests/supersede-story.bats:387`, `:390`, `:419`, `:424` and
# `tests/spike-validation.bats:187`.
#
# WHERE THE POLARITY RULE DOES NOT HOLD IN THIS FILE, named rather than quietly
# excepted: a convention the file contradicts gets read as an invariant, which
# is worse than no convention. Every site below predates this story, and closing
# them is a story of its own rather than a sweep bolted on here. Two grades,
# both measured:
#
#   DIRECTION-BLIND — a straight inversion leaves them green. BOTH ENTRIES OF
#   THIS GRADE ARE NOW CLOSED, and the record stays because what each cost to
#   close is the argument for the next pin, not because either is still open.
#   The stale-report case ("2.1: validate-mode removes the stale report file
#   before spawning") asked only that some line mentioning `stale` also name a
#   report file, so rewriting `Delete`/`delete`/`delete that agent's` to
#   `Keep`/`keep`/`never delete that agent's` at all three prose sites in
#   references/validate-mode.md — and `Before each spawn` to `After` on top of
#   that — left it green: it pinned neither half of its own name. Sub-task 4.2
#   SCOPED it to `## Validate Mode Procedure`, which is where all three sites
#   sit and where the Index Refresh decoy does not, then counted the three
#   deletion sites, refused a negation on the verb, and pinned the ordering as
#   an assertion of its own. No prose was touched. The evidence-pair case
#   below ("a tech-reviewer finding resting on a runnable check cites command
#   and output") was the second entry and is CLOSED the same way: it read the
#   whole file for `command[^.]{0,120}output`, which two spans answered, so
#   deleting the rule left it green. It now scopes to the section stating the
#   rule and pins the obligation's own inflection — each measurement is in its
#   own case's comment.
#
#   NEGATION-PERMEABLE — they catch a rewrite but not a negation parked in
#   front of the match, which is the `the run[^.]{0,40}fail` defect again.
#   `:172` and its 1.2 twin Red when `before composing any textual summary`
#   becomes `after composing …`, and stay green when it becomes `never before
#   …`. The `.draft/` carve-out pair is HALF repaired: sub-task 3.2 replaced
#   its occurrence check with a count of the two spans each file states the
#   allowance at, so dropping it from either site Reds now — but both sites
#   rewritten to `never creating .draft/` keep the count at two and stay green,
#   because the negation prefixes the anchor `creat`. No count reaches that;
#   sub-task 4.3 owns it.
#
# A pattern naming only a file, a field or a topic (`audit-report.yaml`,
# `verdict`, `measurement`) makes no directional claim and so has no polarity to
# pin — the first paragraph governs those. Outside the class but owed to the
# same follow-up: `is a protocol violation` is pinned in the agent files above
# and nowhere for the prompt-template copies at references/validate-mode.md:62
# and :132, and inverting both leaves the whole 482-case suite green.
#
# THIS HEADER IS A COMMENT, NOT A CLAIM UNDER TEST. No case in this suite pins
# its own conventions. The rules above hold because the next author reads them,
# not because dropping one would turn anything Red — and implying otherwise is
# exactly the unearned confidence story 018 refused to buy.
#
# CASE NAMES CARRY THE SUB-TASK THAT OWNS THE PROSE (`1.1:` … `3.1:`), so
# `bats --filter '^1\.1:'` answers for exactly that sub-task's contract. The
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
  md_section "$VALIDATE_MODE" '^## Validator Sub-agent' '^## ' \
    | command grep -q 'validation-report\.yaml'
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
  md_section "$VALIDATE_MODE" '^## Auditor Sub-agent' '^## ' \
    | command grep -q 'audit-report\.yaml'
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
  # `!` here, this reddened none of the three inversions. `:231` uses that shape
  # and is load-bearing only because nothing follows it there.
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
  sec="$(md_section "$RUN_MODE" '^### Tech Reviewer Prompt Template' '^##')"
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
