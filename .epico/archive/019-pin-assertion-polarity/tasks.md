---
story: pin-assertion-polarity
type: feature
scale: fast
version: 4
created: 2026-08-17
last-refined: 2026-08-17
status: archived
history:
  - v1: Initial story
  - v2: Pin the one-request assertion's polarity; correct the census, the `.draft/` claim and the R2.3 citation
  - v3: A negated assertion outside last position is inert — measured mid-run; 1.4 changes shape, 1.7 converts the five inert assertions the finding exposed
---

# Implementation Plan - Assertions Pin Polarity, Not Co-occurrence

## Overview

Story 018 proved its three recovery assertions red against **deletion**: remove
the sentence, the suite reddens. Its own audit then named the gap that proof
leaves open. `the run[^.]{0,40}fail` matches co-occurrence, not polarity, so the
sentence *"the run is **not** failed"* satisfies it exactly as the real one does
— and the rule it guards would be inverted with the suite still green.

That is 018's own stated failure mode, one turn later: a test that **looks** like
it measures the declared risk and does not. 018 closed it for absence; this story
closes it for inversion.

The class is wider than the line the audit named — and wider than v1 of this
story saw. Measured across `tests/reports-by-artifact-policy.bats`, five
assertions state a directional claim through a bare co-occurrence grep and are
closed here: `:93` and `:117` (`protocol violation`), `:134` (`own store`),
`:183` (`one … SendMessage`) and `:187` (`the run … fail`). Two others are
already polarity-pinned and stay untouched — `never[^.]{0,80}respawn` (`:185`)
and `(never|not)[^.]{0,80}mutat` (`:207`). They are the shape this story copies
rather than invents, and both live in the same file, so the convention is
already local.

`:183` arrived in v2, put there by this story's own audit: it is the **first**
assertion of the very case whose **third** assertion 1.1 had just fixed, and it
was measured green under both "more than one `SendMessage`" and "not just one
`SendMessage`" — 019's defect definition, verbatim, inside the case 019 edited.
The census below is written as an enumerated partition rather than a count for
that reason: a number invites the reader to trust it, a list invites them to
check it.

The evidence bar rises with the defect. 018's mutations **deleted** a sentence;
this story's **invert** one — a `not` inserted where the claim turns — because a
deletion red proves only that the assertion reads the right span, never that it
reads the right direction. Each strengthened assertion must stay red against the
old deletion too, so the new pattern is provably stronger and not merely
different.

**A negated assertion outside last position is inert.** Found in v3 by running
1.4 as v2 wrote it: the ToDo said to copy the `! printf … | command grep` shape
from `:169`, and the resulting assertion measured GREEN under all three
inversions it exists to red. Bash exempts a `!`-inverted command from `errexit`,
so its non-zero status is discarded unless it is the last command in the
`@test` — `:169` works only by accident of layout. Isolated to one variable:
the same negation reds in last position, passes in any other, a bare `! true`
passes too (so it is not the pipe), and a plain failing `grep` reds (so
`errexit` is active). Every negated assertion in the suite was then mutated to
must-fail: five of them stayed green — `tests/supersede-story.bats:383`, `:384`,
`:407`, `:410` and `tests/spike-validation.bats:182`. They cannot report a
defect and never could. 1.7 converts them; 1.4 adopts the position-independent
shape `if … then return 1; fi`, chosen over a subshell because bats reports the
failing line rather than the case.

This is 019's own thesis at its limit. The story exists because an assertion
satisfied by a rule AND its negation proves nothing; an assertion satisfied by
everything is the same defect with the window opened all the way. That it
reached this story through this story's own ToDo is the argument for measuring
rather than reasoning, made at the story's expense.

The five remaining negations — `tests/reports-by-artifact-policy.bats:169`,
`tests/secrets-allowlist.bats:344`, `tests/spike-stale.bats:85` and `:91`,
`tests/validate-story.bats:238` — sit in last position and were measured red
under the same mutation, so they work today. They are named in the convention
block by 1.5 as fragile rather than converted by 1.7: one appended assertion
disables any of them silently. Fix what is broken, document what is load-bearing
by accident.

Fast scale: one file for the polarity work, two more for 1.7's conversions, no
new case, no requirement traceability to carry. Three judgement calls the
executor should not have to make — whether to factor this into a shared helper,
which token carries each claim's polarity, and which negation shape survives
being moved — are settled in the ToDos below.

**Deliberately not closed here**, all four from the same measurement:

- The `.draft/`-creation pair, `creat[a-zA-Z]*[^.]{0,80}\.draft` at `:95` and
  `:118`. Its claim's polarity lives in a trailing clause — "creating `.draft/`
  on demand **is part of this step** rather than a precondition for it"
  (`agents/validator.md:36`, `agents/auditor.md:74`) — so pinning the direction
  means pinning most of a sentence, which this file's own header forbids in as
  many words. The realistic drift is removal of the on-demand allowance, and the
  assertion catches that only when the allowance goes from **both** sites: each
  file states it twice (`agents/validator.md:36` and its `One writable path`
  bullet), and dropping it from the bullet alone passes green. Measured in v2 —
  v1 asserted the broader claim without taking that measurement.
- ~~The ordering pair, `before[^.]{0,160}summar` at `:88` and `:113`.~~
  **Withdrawn in v3 — this exclusion was argued, not measured, and the
  measurement refuted it.** v2 claimed `before` **is** the polarity carrier,
  since the realistic inversion writes "after composing", which does not match;
  the only slip-through was said to be "not before composing any textual
  summary — prose nobody writes". Measured during 1.5: `never before composing`
  leaves the case green, and that is one word inserted, not exotic prose. The
  pair is now named in the header as NEGATION-PERMEABLE and joins the backlog
  below. An exclusion whose sole support is a prediction about what nobody would
  write is the same currency this story keeps refusing.
- The stale-report assertion at `:151`, `stale` co-located with
  `validation-report|audit-report|report file`. It pins neither the deletion verb
  nor the ordering: rewriting `Delete`/`delete`/`delete that` to
  `Keep`/`keep`/`never delete` at all three prose sites leaves it green. The
  weakest assertion in the file.
- The evidence-pair assertion at `:212`, `command[^.]{0,120}output`. An
  obligation rather than a direction, so a softer member of the class, but it
  fails the same way: `carries the exact command and its observed output`
  rewritten to `need not carry …` leaves it green.

**In v2 the first two were called exclusions on merit and only the last two
backlog. v3 collapses that distinction: all four are backlog.** One exclusion was
withdrawn above under measurement, and the other — the `.draft/` pair — was
re-measured during 1.5 and stays green with `creating .draft/ on demand` negated
at both sites, so its "pinning the direction means pinning most of a sentence"
argument describes a real cost without establishing that the assertion works.
None predates the wave-011 file; none is scoped by a task here; all belong to a
story of their own, together with the unpinned `is a protocol violation` copies
in the prompt templates at `references/validate-mode.md:62` and `:132` — R3.4's
own stated concern, pinned by nothing, and measured green with both copies
inverted.

Named so the next reader knows what was weighed and left. **Every census this
story wrote has been wrong.** v1 missed three members of the class; v2 found two
of them and graded two others on argument alone; v3's 1.5 measured the file
whole and found four unpinned assertions where the ToDo expected two. A
partition claiming to be complete is worth exactly what its worst entry is
worth, and the pattern across three versions is that the entries which went
unmeasured are the ones that were wrong — not some of them, all of them.

## Task List

- [x] 1 - Every directional assertion reddens when its rule is inverted
  - _Complexity: Simple | Tests: Unit | Risks: an assertion tightened until it pins a sentence turns every future rewording into a false red — the opposite defect, and this file's header forbids it in as many words | Dependencies: None_
  - Objective: No assertion in the suite is satisfied by both a rule and its negation.

  - [x] 1.1 - The recovery case's third assertion pins "is failed"
    - Context:
      - Files: the third assertion of the `2.1: an absent or unparseable report is re-requested once via SendMessage, then the run is failed` case in `tests/reports-by-artifact-policy.bats` (line 187, `the run[^.]{0,40}fail`), row 3 of the `### Absent or unparseable` table in `references/validate-mode.md` (the sentence it measures), the neighbouring assertion two lines up (`never[^.]{0,80}respawn` — the polarity-pinned shape to copy)
    - Objective: Rewriting row 3 to say the run is **not** failed turns the suite red.
    - ToDo: the claim's polarity lives in the copula and the participle together, and an inversion writes `not` between them — so require `is failed` adjacent rather than `fail` anywhere within forty characters of `the run`. Measured, so the tightening is safe: the scoped section is `references/validate-mode.md` lines 160-176, it carries the literal `**the run is failed**` in row 3, and it contains exactly one `the run … fail` span, so the pattern has no neighbour that could satisfy it by accident. Do not widen the window for a hypothetical rewording: `the run is failed` is the phrase row 3, story 011's sub-task 2.1 ToDo ("the run is failed, **stated in exactly those terms**", R2.3) and this case's own name all already use, so a rewording that breaks it is a rewording of the rule itself. (v2 corrected this citation: v1 credited task group 2's Risk field, which does not carry the phrase. The 2.1 ToDo is the stronger source anyway — it makes `the run fails` a change to the contract rather than a rewording of it.) Keep the case name, the `# R2.3:` comment, the section scoping and the inline flatten exactly as 018 left them — only the third grep changes.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same `2.1:` recovery case, same name, same count
    - Validation: the assertion verified red against a copy of `references/validate-mode.md` whose row 3 reads "the run is **not** failed" — an inversion, not a deletion — then restored; verified still red against 018's deletion mutation, proving the new pattern strictly stronger and not merely different; `bats tests/` green afterwards with the count unchanged at 482

  - [x] 1.2 - The protocol-violation and own-store assertions join it
    - Context:
      - Files: the `protocol violation` assertions at `tests/reports-by-artifact-policy.bats:93` and `:117`, the `memory director[a-z]*[^.]{0,160}own store` assertion at `:134`, the sentences they measure (`agents/validator.md:74`, `agents/auditor.md:125`, `references/validate-mode.md:132`), the file header's stated convention at lines 16-20
    - Objective: The three remaining directional assertions redden on their own inversions, by the same rule 1.1 applies.
    - ToDo: for the two `protocol violation` assertions, require the assertive frame `is a protocol violation` — both definitions write "Any other write is a protocol violation" verbatim, and the inversion "is **not** a protocol violation" breaks `is a`. For the `own store` assertion, keep the section scoping and require `is your own store`. Then settle the factoring call rather than discovering it: **do not introduce a generic polarity helper.** A helper that guards polarity by rejecting a negation word in the window before the match reds on correct prose right here — the sentence at `agents/auditor.md:125` reads "your memory directory **is not** a second path in the code under audit — it is your own store", so a negation sits one clause ahead of the match by design, and the guard would fire on the very text it exists to protect. Four explicit patterns are reviewable; one helper with a false red is the defect this story is closing, wearing a different hat. Finally, extend the header's convention (lines 16-20) with the polarity rule so the next assertion is written this way instead of audited into it — and note plainly that the header is a comment, not a claim under test: this suite has no case that pins its own conventions, and implying one is exactly the confidence 018 refused to buy.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the two report-file cases and the memory-clause case, all three unchanged in name and count
    - Validation: each assertion verified red against its own inversion in a scratchpad copy — "is **not** a protocol violation" in `agents/validator.md`, the same in `agents/auditor.md`, "is **not** your own store" in `references/validate-mode.md` — one mutation at a time, restored between, three separate reds; `bats tests/` green afterwards at 482 cases

  - Commit: "test(019): assertions pin polarity, not co-occurrence"

  - [x] 1.4 - The recovery case's first assertion pins one request, not any count
    - Context:
      - Files: the first assertion of the same `2.1:` case in `tests/reports-by-artifact-policy.bats` (line 210, `(^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage`), row 2 of the `### Absent or unparseable` table in `references/validate-mode.md` (line 166, the sentence it measures), the negated assertion at `:169` (`! command grep -qi 'memory'` — this file's local precedent for a negated grep)
    - Objective: Rewriting row 2 to permit more than one `SendMessage` turns the suite red.
    - ToDo: this claim does not behave like the four 1.1 and 1.2 closed, and that difference is why v1's census walked past it. There the negation inserts `not` between two adjacent anchors, so moving the polarity token inside the match closes the gap; here the negation is a modifier PREFIXED to the quantifier — `more than one`, `not just one`, `one or more`, an open set — and `one` is a substring of every phrase that negates it, so there is no token to move inside. The convention as 1.2 wrote it does not reach this assertion; saying so in the header is 1.5's job. Two candidates were measured against three inversions and four rule-preserving reworderings, not argued. A bold frame (`\*\*one\*\*[^.]{0,80}SendMessage`) reds all three inversions but also reds `**exactly one**` and a correct row that merely lost its asterisks — it pins markdown emphasis, the most volatile thing in a prose file, which is the sentence-pinning this file's header forbids in as many words. A targeted negative reds all three inversions and the deletion while staying green on both reworderings. Take the targeted negative: keep the positive pattern exactly as it stands and add one inline negated grep naming the modifiers — `((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)`. **Not with a bare `!` — that was v2's instruction and it produced an inert assertion.** The negation goes in an `if … then return 1; fi`, because bash exempts a `!`-inverted command from `errexit` and this grep has two assertions after it, so its failure would be discarded (see the Overview; measured, and the reason `:169`'s identical shape works is that nothing follows it). A subshell `( ! … )` also survives the move, and is rejected only on diagnostics: bats reports the failing line for the `if`, the `@test` line for the subshell, and this case holds three assertions. The regex above is unchanged by the shape — it was measured correct on all six variants before the shape defect was found, so do not re-derive it. This is not the helper 1.2 forbade: that was a GENERIC guard rejecting any negation in the window before any match, which false-reds on `agents/auditor.md:125` by construction, whereas this names the modifiers of one quantifier, stays inline in the case that owns it, and was measured silent on the unmutated section. Two red-on-correct vectors remain, stated rather than left to be discovered: `a single \`SendMessage\`` is PRE-EXISTING (today's pattern reds it too, so this change adds nothing there), and `never more than one \`SendMessage\`` is ADDED and accepted, because row 2 is an imperative action cell and a prohibition does not fit the grammar of that column.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same `2.1:` recovery case, same name, same count
    - Validation: the assertion verified red against each of the three inversions of row 2 in a scratchpad copy — `**more than one**`, `**not just one**`, `**one or more**` — one mutation at a time, restored between; verified still red against deletion of the row, with the reddening line ATTRIBUTED rather than assumed — v2 accepted this measurement without asking which assertion fired, and the answer is the retained positive pattern, not the new negative one. That attribution is the point, not a shortfall: the negative is a prohibition, so on a deleted row it is correctly SILENT, and "strictly stronger" is carried by construction — the positive is kept byte-identical and the negative is added on top, so the pair reds a superset of what the positive alone redded. The deletion measurement confirms the old guarantee survived the edit; the three inversion reds are what the new pattern buys. Do not attempt to make the negative red on deletion: a prohibition that fires on absent text would red every unrelated file; and verified GREEN against both `**exactly one**` and an unbolded `one`, so the polarity was not bought with a false red; the three inversion reds are themselves the position proof, since the new assertion is not the last statement in its case; `bats tests/` green afterwards with the count unchanged at 482

  - [x] 1.5 - The header and the citation describe what the file actually does
    - Context:
      - Files: the convention block at `tests/reports-by-artifact-policy.bats:22-42`, the comment at `:219`, and the two assertions the file still leaves polarity-blind (`:179`, `:246`)
    - Objective: A reader of the header can predict which assertions are pinned and which are not, and no comment cites a source for a phrase that source does not carry.
    - ToDo: four edits, all comment-level, none touching an assertion. Locate each by content, not by the line numbers above — 1.4 inserts lines ahead of them. (1) At **both** sites carrying the "task group 2's Risk" credit (`:213` and `:219` pre-1.4 — v2's ToDo named only one and the Acceptance covers both), replace it with the real source — story 011's sub-task 2.1 ToDo, "the run is failed, stated in exactly those terms (R2.3)" — which is the stronger citation anyway, since it makes `the run fails` a change to the contract rather than a rewording of it. (2) Extend the convention block with the modifier-prefix case: when the negation prefixes a quantifier instead of splitting two anchors, there is no token to move inside the match, and the sanctioned form is an inline negated grep naming that claim's modifiers — never a generic one, for the reason the block already gives two paragraphs down. (3) Name the two assertions the convention does not hold for — `:179` (neither the deletion verb nor the ordering is pinned; the rule inverted at all three prose sites stays green) and `:246` (`command … output`, where negating the obligation stays green) — with the measurement and the note that both predate this story and belong to their own. (4) Add the negation rule the v3 finding bought: a negated assertion MUST NOT rely on being the last statement in its `@test`, because bash exempts a `!`-inverted command from `errexit` and discards its status anywhere else — state the sanctioned shape (`if … then return 1; fi`), state that the subshell form also works and was rejected on diagnostics alone, and name `:169` as this file's own last-position negation: measured red today, silently inert the moment an assertion is appended after it. Name the four other last-position negations in the suite the same way — `tests/secrets-allowlist.bats:344`, `tests/spike-stale.bats:85` and `:91`, `tests/validate-story.bats:238` — so the next author converting one is not doing archaeology. A convention block the file silently contradicts is worse than none: the next author reads it as an invariant, which is the same unearned confidence 018 refused to buy.
    - Acceptance: the header names every assertion in the file that is not polarity-pinned; the header states the negation-position rule and names every last-position negation in the suite; no comment cites story 011's task group 2 Risk field for a phrase that field does not contain; the case count is unchanged at 482 and no case name changes
    - Validation: `bats tests/` green at 482 with every case name byte-identical to the pre-edit run

  - Commit: "test(019): pin the one-request assertion, name what stays unpinned"

  - [x] 1.7 - The five inert assertions are made capable of failing
    - Context:
      - Files: `tests/supersede-story.bats:383`, `:384` (the R3.2 banner case), `:407`, `:410` (the R3.3 superseded-by case), `tests/spike-validation.bats:182` (the verdict-enum case), and the shape 1.4 established in `tests/reports-by-artifact-policy.bats`
    - Objective: Each of the five assertions reddens when the fact it denies becomes true.
    - ToDo: convert each to `if … then return 1; fi`, changing the shape ONLY — every pattern, path and variable stays byte-identical, so the conversion cannot alter what is asserted, only whether the assertion can report it. Take them one file at a time. Do not touch the five last-position negations named in 1.5's convention edit: they are measured working, and converting them is churn this story did not scope. Do not add, rename or reorder a case. If a converted assertion turns out to red on the UNMUTATED tree, that is a real defect the inert shape was hiding — **STOP and escalate**, because fixing it is a different story and silently adjusting the assertion to keep the suite green would re-create the exact defect being closed.
    - Tests: Unit · `tests/supersede-story.bats` and `tests/spike-validation.bats` — the three affected cases, all unchanged in name and count
    - Validation: each of the five verified red under a must-fail mutation of its own pattern in a scratchpad copy — one at a time, restored between — where all five were measured GREEN under that same mutation before the conversion, so the before/after pair is what carries the claim rather than the after alone; `bats tests/` green afterwards at 482 with no case renamed

  - Commit: "test(019): a negated assertion outside last position asserted nothing"

## Quality Gates

- [x] All acceptance criteria validated (each strengthened assertion proven red against the inversion of its own rule, not merely against a deletion) — reopened in v2, reopened again in v3 with the criterion raised: an assertion must first be proven CAPABLE of reddening, since the v2 attempt at 1.4 met every polarity requirement while being unable to fail at all. Met: 1.1/1.2's three inversion reds, 1.4's eight-measurement table, 1.7's five before/after pairs, each re-measured independently by the orchestrator
- [x] All task validations pass — 1.1 through 1.8 closed; every Validation field executed and its output reported, none summarised as "it passed"
- [x] All tests written and passing (full bats suite green at 482 cases, count unchanged) — **reopened in v3, and this is the gate the finding cost.** It was ticked at v2 against a green suite that contained five assertions incapable of failing. The count and the colour were both accurate; what they measured was not what the gate claims. Re-ticked on the 1.7 before/after pair: all five GREEN under a match-everything mutation before conversion, all five RED after
- [x] Code integrated (no assertion in the suite is satisfied by every input, and none in this file matches both a rule and its negation except those the header names with their measurement) — v1 left three members of the class named nowhere; v2 named two and graded two on argument; v3 measured the file whole. Four unpinned assertions plus two prompt-template copies remain, each named in the header with the mutation that exposed it and deferred to a story of its own
- [~] Error handling implemented (n-a: no new runtime code — the story changes five regexes and five assertion shapes across three test files, and the arm each one pins is covered by 1.1's, 1.2's and 1.7's reds)
