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
#   DIRECTION-BLIND — a straight inversion leaves them green. `:241` asks only
#   that some line mentioning `stale` also names a report file, so rewriting
#   `Delete`/`delete`/`delete that agent's` to `Keep`/`keep`/`never delete that
#   agent's` at all three prose sites in references/validate-mode.md — and
#   `Before each spawn` to `After` on top of that — leaves it green: it pins
#   neither the deletion verb nor the ordering. `:341`
#   (`command[^.]{0,120}output`) states an obligation rather than a direction
#   and fails the same way, staying green with tech-reviewer.md's `carries the
#   exact command and its observed output` rewritten to `need not carry …`. A
#   second span in that file satisfies the pattern too, so even deleting the
#   rule outright would not Red it.
#
#   NEGATION-PERMEABLE — they catch a rewrite but not a negation parked in
#   front of the match, which is the `the run[^.]{0,40}fail` defect again.
#   `:172` and its 1.2 twin Red when `before composing any textual summary`
#   becomes `after composing …`, and stay green when it becomes `never before
#   …`. `:181` and its twin stay green when both `creating .draft/ on demand`
#   sites become `never creating .draft/`.
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
  flat "$VALIDATOR" | command grep -qiE 'before[^.]{0,160}summar'
}

@test "1.1: validator carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # R1.5: the no-modify rule narrows to a carve-out, it does not disappear.
  # The assertive frame `is a` is part of the match: the definition writes "Any
  # other write is a protocol violation" verbatim, and the inversion breaks it.
  flat "$VALIDATOR" | command grep -qiE 'is a protocol violation'
  # R1.3: fast/spike stories have no .draft/ until someone makes one.
  flat "$VALIDATOR" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'
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
  flat "$AUDITOR" | command grep -qiE 'before[^.]{0,160}summar'
}

@test "1.2: auditor carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # Same assertive frame as the Validator's, and for the same reason.
  flat "$AUDITOR" | command grep -qiE 'is a protocol violation'
  flat "$AUDITOR" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'
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
  # Line-based co-location on purpose: 'stale' alone matches the Index Refresh
  # section's "a stale rendering", which has nothing to do with reports.
  command grep -i 'stale' "$VALIDATE_MODE" \
    | command grep -qiE 'validation-report|audit-report|report file'
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

  # ONE request, and by SendMessage — not a loop, not a respawn.
  printf '%s\n' "$sec" \
    | command grep -qiE '(^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage'
  # ...AND NOT MORE THAN ONE. The positive pattern above cannot carry this:
  # `one` is a substring of every phrase that negates it (`more than one`,
  # `not just one`, `one or more`), so there is no polarity token to move
  # inside the match the way `is failed` does below. Hence a second, negated
  # grep — measured green under all three inversions without it.
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
  # two further `one`s ("One request, to the agent…", "after that one request").
  #
  # Two red-on-correct vectors, both measured and accepted rather than
  # discovered later: "a single `SendMessage`" is PRE-EXISTING — the positive
  # pattern above reds it too, so this line adds nothing there; "never more than
  # one `SendMessage`" is ADDED, and accepted because row 2 is an imperative
  # action cell and a prohibition does not fit that column.
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
  printf '%s\n' "$sec" | command grep -qiE 'the run is failed'
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
  flat "$TECH_REVIEWER" | command grep -qiE 'command[^.]{0,120}output'
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
