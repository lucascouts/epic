---
story: close-the-polarity-census
type: feature
scale: standard
version: 3
created: 2026-08-18
last-refined: 2026-08-19
history:
  - v1: Initial story
  - v2: Group 6 records the four commits that landed after 5.3 — the `.draft/` frame (D6), R5.3's roster and body checks, two rules pinned by refusal instead of by phrasing, and the bats-collection defect that ran the whole suite dark on CI
status: archived
---

# Implementation Plan - Close the Polarity Census

## Overview

Story 019 closed ten assertions and wrote a census of what it left open. Its
validate pass measured that census and found four sites it had missed, then a
repo-wide sweep found two more in a file 019 never looked at. Four censuses
across three story versions, each wrong, and every error in an entry that was
argued instead of measured.

So this story does not write a fifth census. It writes the census as a test.
Two lints — one for negation shape, one for window patterns over prose — turn
"nothing else is unpinned" from a claim an author remembers to check into a
condition the suite enforces. Task 1 builds them before anything is fixed, so
every site closed afterwards is closed against a guard that already works.

The sites themselves fall into three repair shapes, and which shape applies is
settled here rather than discovered by the executor:

- **Pin the token in place** where the claim's polarity already lives in a short
  phrase the rule's own name uses (`is authoritative`, `measurement only`).
- **Scope or count** where pinning is defeated by the file rather than by the
  phrase — a second span satisfying the pattern (`:341`), or a rule stated at
  two sites where dropping one leaves the assertion green (`:181`).
- **Rewrite the rule's prose** where the polarity lives in a trailing clause and
  pinning it would pin most of a sentence, which this suite forbids. The rewrite
  moves a polarity token into the sentence; it never restructures the paragraph,
  and it is measured against every other assertion reading that span.

Standard scale: the requirements are worth carrying because the failure this
story closes is a *completeness* failure, and a requirement left uncovered is
visible in a traceability table while a site left unnamed in a comment is not.

**The evidence bar, unchanged from 018 and 019 and raised once.** Every closed
site is proven red against the inversion of its own rule, green against at least
one rule-preserving rewording, and — where an assertion is strengthened rather
than added — still red against the deletion the old pattern caught. Raised: the
two lints must each be proven red against a planted offender before any site is
converted, because a guard that has never failed is the exact thing this story
exists to stop shipping.

**Deliberately not closed here**, and named so the next reader knows they were
weighed: the window-pattern candidates in `tests/anchor-lint.bats:305-308`
(`grep -q 'wins'`, `grep -q 'only when'`) are unmeasured as of writing — task 1.5
sweeps them, and whatever it measures is closed under task 2 or recorded in the
allowlist with its measurement. Nothing is deferred on argument.

## Task List

- [x] 1 - The census is a test before it is a claim
  - _Complexity: Moderate | Tests: Unit | Risks: a lint that has never failed is indistinguishable from a lint that cannot fail — this story's whole subject | Dependencies: None_
  - Objective: The suite rejects an inert negation and an unlisted window pattern without any human reviewing them.

  - [x] 1.1 - The negation lint fails on a planted offender
    - Context:
      - Files: new `tests/assertion-hygiene.bats` (a new file, not the wave-011 policy file, whose subject is the 011 contract and not suite-wide hygiene), the six negation sites the lint must eventually accept, the `setup()` shape used across the suite (`PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"`)
    - Objective: A `!`-inverted command used as an assertion anywhere in `tests/` fails the suite, naming file and line.
    - ToDo: scan every `tests/*.bats` for a command whose status is inverted with the reserved word `!` — the shape is `!` followed by whitespace at the start of a statement, including after `&&`, `||`, `;`, `{` and `then`. Settle the three discriminations rather than discovering them. (1) `[ ! -f x ]` and `[[ ! "$a" =~ b ]]` are CONFORMING and must not be flagged: the `!` there is a conditional operator, the `[`/`[[` returns non-zero itself, and `errexit` is not exempt — measured. (2) `if ! grep …; then` is CONFORMING: the negation sits in an `if` condition, whose status the `if` consumes. (3) A `!` inside a single- or double-quoted string, inside a comment, or inside an `awk` program (`!inb && …` appears twice in this suite) is not a shell negation — strip comments and skip quoted regions before matching, or the lint reds on text it should ignore. Emit one line per offender as `file:line: <the line>` and `return 1`; do not abort on the first, because an author converting a batch wants the whole list. Write the lint as a single case, not a helper shared with 1.4 — the two lints answer different questions and a shared walker couples them for no gain.
    - Tests: Unit · `tests/assertion-hygiene.bats` — a planted `! true` outside last position is flagged, one in last position is flagged, `[ ! -f x ]` and `if ! …; then` are not
    - Validation: the lint verified red against a planted `! true` inserted as a non-final assertion in a scratchpad copy of an existing case, with the offender's file and line named in the output, then removed; verified red a second time against a planted `! true` in FINAL position, since R4.1 admits no position exemption; verified GREEN against a planted `[ ! -f /nonexistent ]` and a planted `if ! true; then return 1; fi` in the same slot, so the discriminations hold and the lint does not red on conforming shapes; the six known negation sites are expected to make it red at this point — record that list as the input to 1.2 rather than weakening the lint
    - Requirements: R4.1, R4.2, R4.3

  - [x] 1.2 - The six negations are converted, and the lint goes green
    - Context:
      - Files: `tests/validate-story.bats:238`, `tests/spike-stale.bats:85` and `:91`, `tests/secrets-allowlist.bats:344`, `tests/reports-by-artifact-policy.bats:231`, `tests/supersede-story.bats:495`, and the `if … then return 1; fi` shape story 019 established
    - Objective: Every one of the six reddens when the fact it denies becomes true, and the lint from 1.1 passes.
    - ToDo: convert each to `if … then return 1; fi`, changing the SHAPE ONLY — every pattern, path, variable and pipe stage stays byte-identical, so the conversion cannot alter what is asserted, only whether the assertion can report it. Two carry a wrinkle worth stating. `tests/supersede-story.bats:495` is `[ -z "$output" ] || ! echo "$output" | jq -e . > /dev/null 2>&1`, a disjunction: preserve the short-circuit by converting to `if [ -n "$output" ] && echo "$output" | jq -e . > /dev/null 2>&1; then return 1; fi`, which is the same claim — an empty output passes, a parseable one fails. `tests/reports-by-artifact-policy.bats:231` sits in a file whose header documents it as a last-position negation; that header text is task 5.2's to correct, not this sub-task's, so leave it and let 5.2 find it. Story 019's convention says to convert a working last-position negation only when its case is touched — this story touches all six deliberately, and R4.1 supersedes the convention. If a converted assertion reds on the UNMUTATED tree, that is a real defect the inert shape was hiding: **STOP and escalate**, because silently adjusting it to keep the suite green re-creates the exact defect being closed.
    - Tests: Covered by Task 1.1 — the lint is the test for the conversion; each site's own before/after mutation is in Validation
    - Validation: each of the six verified red under a must-fail mutation of its own pattern in a scratchpad copy — one at a time, restored between — where the same mutation is first confirmed to leave the case GREEN before conversion, so the before/after pair carries the claim rather than the after alone; the unmutated pre-conversion case confirmed passing first, so a green-before is inertness and not a case already broken; 1.1's lint green afterwards; full `bats tests/` green with no case renamed
    - Requirements: R4.1

  - Commit: "test(020): the suite rejects a negation that cannot fail"

  - [x] 1.4 - The window-pattern lint fails on an unlisted pattern
    - Context:
      - Files: `tests/assertion-hygiene.bats` (extended), a new allowlist the lint reads, the eleven known window patterns in `tests/reports-by-artifact-policy.bats` and `tests/scale-resolution.bats`
    - Objective: A prose assertion using a window pattern that is not on the allowlist fails the suite, naming file and line.
    - ToDo: match the window signature `[^.]{0,N}` in any `tests/*.bats` assertion, and require each occurrence to appear in an allowlist keyed by `file:pattern`. Settle the allowlist's location and shape: keep it in the lint file itself as a heredoc table, NOT a separate data file — a separate file drifts from the suite and gives a future author somewhere to add an entry without reading why the others are there. Each row carries the file, the pattern, the verdict (`PINNED` or `ALLOWED`), and the measurement that justifies it in one sentence (the mutation applied and the observed result). Key the row on the pattern text rather than the line number, because every insertion above it would otherwise invalidate the table — this is the failure mode 019's header hit when 1.4 shifted sixty lines. An `ALLOWED` row is for a pattern that makes no directional claim (a filename, a field name); it is not an escape hatch for a directional one, and the lint cannot tell the difference, so the row's sentence is what a reviewer reads. State plainly in the file header that the lint checks the row EXISTS, not that its sentence is true — implying otherwise is the unearned confidence 018 refused to buy.
    - Tests: Unit · `tests/assertion-hygiene.bats` — an unlisted window pattern is flagged, a deleted allowlist row whose pattern survives is flagged, a fully listed tree passes
    - Validation: the lint verified red against a planted window pattern absent from the allowlist, with file and line named, then removed; verified red against deleting a row from the allowlist while its pattern remains in the suite, so the table cannot silently shrink; verified GREEN on the unmutated tree once every known pattern has a row; `bats tests/` green afterwards
    - Requirements: R5.1, R5.2, R5.3

  - [x] 1.5 - The allowlist is populated by a measured sweep, not an enumeration
    - Context:
      - Files: the allowlist from 1.4, every `tests/*.bats` carrying a window pattern, the prose files they read (`agents/*.md`, `references/*.md`), and the unmeasured candidates at `tests/anchor-lint.bats:305-308`
    - Objective: Every window pattern in the suite has a row whose verdict was measured, and the sites needing repair are the output of that sweep rather than of a reading.
    - ToDo: for each window pattern the lint finds, invert the rule it guards in a scratchpad copy of the prose file and record whether the owning case reds. A pattern that stays green is DIRECTION-BLIND and becomes an input to task 2, 3 or 4 by the repair shape the Overview defines; a pattern that reds is `PINNED`; a pattern making no directional claim is `ALLOWED` with the reason. **Use `command grep`, never bare `grep`, for any repo-wide sweep whose result is used as evidence** — the harness routes bare `grep` through a shim honouring `.gitignore`, which returns a false clean on `.epic/` and has been observed to do so in this repo. Report the sweep's own coverage: how many `.bats` files were read, how many patterns found, how many measured. A sweep that cannot state its denominator is the enumeration this story is replacing. Where the sweep finds a site not named in this story, add it to the appropriate task rather than to a comment.
    - Tests: None — the sweep produces the allowlist's data, and 1.4's lint is what enforces it; the sweep's own correctness is measured in Validation by reconciling its counts against an independent command
    - Validation: the sweep's file and pattern counts reported and reconciled against an independent count taken with a different command; every row's verdict reproduced by re-running one mutation chosen at random from each verdict class; `tests/anchor-lint.bats:305-308` measured and its verdict recorded either way
    - Requirements: R5.2

  - Commit: "test(020): the census is a lint with a measured allowlist"

- [x] 2 - Sites whose polarity token already exists
  - _Complexity: Simple | Tests: Unit | Risks: a token pinned too tightly turns a future rewording into a false red, which is the opposite defect and equally out of bounds | Dependencies: Task 1_
  - Objective: Each site reddens on its own inversion and stays green on a rule-preserving rewording.

  - [x] 2.1 - The two report-file assertions pin direction, not filenames
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:323` (case `2.1: the pass point keys off the report file's verdict`) and `:247-248` (case `2.1: the procedure reads both verdicts from the report files`), the prose at `references/validate-mode.md:183` and the `## Validate Mode Procedure` steps 3-4
    - Objective: Rewriting either rule to conclude from the agent's message instead of the file turns the suite red.
    - ToDo: both cases state a direction in their own comment — "reads the file, not the message" and "conclude from disk; the message is courtesy" — while asserting only that a report filename occurs in the section. Measured: inverting the prose to "turn on what an agent said in chat — never on the `verdict` field of `.draft/validation-report.yaml`" leaves `:323` green, because the filename survives the inversion; the same holds for `:247-248` with steps 3-4 rewritten to take the verdict from the final message. The polarity carrier is already in the prose at `references/validate-mode.md:183` — "**never on what an agent said in chat**" — so pin the direction, not the filename: require the report file and the rejection of the message in one match. Do not pin the whole clause; anchor on the short span the rule's own sentence uses. Keep both case names and both `# R2.x:` comments — they were already right, only the bodies were not, which is exactly 018's 1.1 again.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same two `2.1:` cases, unchanged in name and count
    - Validation: each of the two verified red against the inversion of its own rule in a scratchpad copy — one mutation at a time, restored between, two separate reds; each verified GREEN against a rule-preserving rewording that keeps the direction (e.g. "the verdict is read from the report file rather than from the reply"), so no false red was bought; `bats tests/` green afterwards
    - Requirements: R1.1, R1.2

  - [x] 2.2 - The measurement-only assertions pin the "only"
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:335` (case `3.1: tech-reviewer's Bash is measurement-only and never mutates`) and `:348` (case `3.1: run-mode Tech Reviewer prompt template mirrors the measurement rule`), the prose at `agents/tech-reviewer.md:46` and its mirror in `references/run-mode.md:581`
    - Objective: Widening the Bash grant from measurement to anything turns the suite red.
    - ToDo: both cases name a restriction — "measurement-**only**", "mirrors the measurement rule" — and pin only the topic word `measurement`. Measured: rewriting "`Bash` is for measurement only" to "`Bash` is not limited to measurement" leaves both green. Note the asymmetry and treat the two differently: `:335` has a sibling at `:336` pinning the "never mutate" half, so only the scope half is unguarded there; `:348` has no sibling at all and the whole rule rests on one topic word. Pin the restriction phrase both files already use — `for measurement only` — rather than inventing one. The header's closing paragraph currently cites `measurement` as an example of a topic word with no polarity to pin; that claim is refuted by this measurement and its correction belongs to 5.2.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same two `3.1:` cases, unchanged in name and count
    - Validation: each verified red against `for measurement only` → `not limited to measurement` in its own file, one at a time, restored between; `:335` additionally verified to still red when only the "never mutate" half is inverted, confirming the sibling assertion was not weakened; both verified GREEN against a rewording that preserves the restriction (e.g. "`Bash` is for measurement only — never for mutation"); `bats tests/` green afterwards
    - Requirements: R1.1, R1.2

  - [x] 2.3 - The scale-authority assertions pin which artifact wins
    - Context:
      - Files: `tests/scale-resolution.bats:779` and `:783` (case `3.2: references/tasks.md states that tasks.md is authoritative for the declared scale`), the prose at `references/tasks.md:68` and `:70`
    - Objective: Reversing which artifact is authoritative for `scale` turns the suite red.
    - ToDo: this is the site no census ever named, and it is in a file story 019 never opened. `:779` matches `tasks\.md[^.]{0,160}authoritative`, which is satisfied by "`tasks.md` is **not** authoritative" — measured green. `:783` matches `story\.md[^.]{0,200}(reported|not honoured|not honored)`, and the realistic inversion "**honoured**, not reported" keeps the word `reported` in the span — also measured green. For `:779` pin `is authoritative` adjacent, the phrase the case's own name and the prose heading both use. For `:783` the polarity lives in the pairing, so pin the ordering the rule states — `reported`, and NOT honoured — rather than either word alone; take the measurement before tightening, and if the section carries a second span satisfying the tightened pattern, scope with the file's existing flatten rather than widening. Do not touch the second `@test` in this file (`3.2: no comment in validate-story.sh still claims story.md wins for scale`): it already uses the `if … then return 1; fi` shape and is out of this sub-task's scope.
    - Tests: Unit · `tests/scale-resolution.bats` — the same `3.2:` case, unchanged in name and count
    - Validation: `:779` verified red against `is authoritative` → `is not authoritative` at `references/tasks.md:68`, restored; `:783` verified red against "reported, not honoured" → "honoured, not reported" at `:70`, restored; both verified GREEN against a rewording preserving the rule (e.g. "`tasks.md` is authoritative for the declared `scale`" reflowed across lines, since the assertion reads flattened text); `bats tests/` green afterwards
    - Requirements: R1.1, R1.2

  - [x] 2.4 - The respawn prohibition and the anchor precedence pin their own direction
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats` (the `never[^.]{0,80}respawn` assertion), the rule in `agents/validator.md` / `agents/auditor.md`, and `tests/anchor-lint.bats:306` (`grep -q 'wins'`) with the precedence rule it reads
    - Objective: Reversing the respawn prohibition, or the anchor precedence, turns the suite red.
    - ToDo: **added by 1.5's sweep — neither site was named by any census.** Measured: `**Never respawn silently.**` rewritten to `**Never conclude without a respawn.**` leaves the case GREEN, because the pattern holds `never` and `respawn` in one window and cannot tell which one the `never` governs; the control (`**Always respawn silently.**`) reds, so the case is not simply broken. Pin the prohibition the prose already states — `never respawn` adjacent — rather than the pair at a distance. For `tests/anchor-lint.bats:306` the assertion is the bare literal `grep -q 'wins'`, which survives reversing which side wins: measured GREEN under `anchored_commits == 0 wins over rule 3` becoming `Rule 3 wins over anchored_commits == 0`, and RED only when the rule is deleted. Pin which side wins, not the word. That site is NOT a window pattern, so 1.4's lint cannot see it and no allowlist row can exist for it — its evidence lives in this sub-task or nowhere.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` and `tests/anchor-lint.bats` — the existing cases, unchanged in name and count
    - Validation: `never respawn` verified red against `Never conclude without a respawn`, restored; verified GREEN against a rewording preserving the prohibition; `anchor-lint.bats:306` verified red against the precedence reversed, restored, and GREEN against a rewording that keeps the same side winning; `bats tests/` green afterwards
    - Requirements: R1.1, R1.2

  - Commit: "test(020): seven directional assertions pin their own direction"

- [x] 3 - Sites defeated by the file rather than by the phrase
  - _Complexity: Simple | Tests: Unit | Risks: scoping too narrowly makes a legitimate move of the rule to a neighbouring section a false red | Dependencies: Task 1_
  - Objective: Each assertion reads exactly the span that owns its rule.

  - [x] 3.1 - The evidence-pair assertion reads only the section that states it
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:341` (case `3.1: a tech-reviewer finding resting on a runnable check cites command and output`), the rule at `agents/tech-reviewer.md:44` inside `## Measurement, Not Argument`, and the second satisfying span at `:55` inside `## Protocol`
    - Objective: Removing or reversing the evidence obligation turns the suite red.
    - ToDo: this site cannot be closed by pinning alone, and the reason is measured: `flat "$TECH_REVIEWER"` reads the whole file, and `command[^.]{0,120}output` is satisfied twice — by the rule at `:44` and by the report-format bullet at `:55` — so even DELETING the rule leaves the case green. Scope first, then pin. The file's headings are `## When You Are Activated` (14), `## Focus Areas` (18), `## Measurement, Not Argument` (40) and `## Protocol` (48), so `md_section "$TECH_REVIEWER" '^## Measurement, Not Argument' '^## '` isolates the rule and excludes the bullet — note `md_section`'s end pattern must be `'^## '` WITH the trailing space to stop at the next `##`, and that `flat` reads a file and cannot take a captured section on a pipe, so flatten inline with `printf '%s\n' "$sec" | tr '\n' ' '`. Both gotchas are recorded in story 018's 1.1 and cost a debugging cycle there. Then pin the obligation's polarity within that section: the rule reads "carries the exact command and its observed output", and the realistic weakening is "need not carry", so require `carries` adjacent to the pair.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same `3.1:` evidence-pair case, unchanged in name and count
    - Validation: verified red against DELETING the rule at `agents/tech-reviewer.md:44` — the measurement that proves the scoping worked, since this deletion left the case green before; verified red against `carries` → `need not carry`; verified GREEN against the report-format bullet at `:55` being reworded, since that span is no longer in scope and must not affect this case; `bats tests/` green afterwards
    - Requirements: R3.1, R1.1, R1.3

  - [x] 3.2 - The .draft/ assertions require the rule at both sites
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:181` and `:205`, the rule stated twice per file — `agents/validator.md:36` and its `One writable path` bullet at `:74`, `agents/auditor.md:74` and its bullet at `:125`
    - Objective: Dropping the on-demand allowance from either site turns the suite red.
    - ToDo: story 019 deferred this pair with a correct diagnosis and no fix: the polarity lives in a trailing clause ("creating `.draft/` on demand **is part of this step rather than a precondition for it**"), so pinning direction means pinning most of a sentence — which this file's header forbids. But the measured failure is narrower than that diagnosis: each file states the allowance TWICE, and dropping it from the bullet alone leaves the case green because the other span still satisfies the pattern. Close that half here with a count rather than a rewrite: assert that the allowance appears at exactly the two sites per file, using the `[ "$(command grep -c …)" -eq 2 ]` shape `tests/supersede-story.bats:482` already uses. The polarity half stays open and is 4.1's, whose prose rewrite gives this assertion a token to pin; sequence 3.2 before 4.1 so the count is in place when the prose changes, and re-run this case as part of 4.1's validation. **Corrected by 1.5's measurement:** 4.1 rewrites the ORDERING clause in that sentence and does not give this assertion a polarity token, so the polarity half is **4.3's**, not 4.1's — the row was measured green with the carve-out reversed at both spans in both files.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same `1.1:`/`1.2:` carve-out cases, unchanged in name and count
    - Validation: verified red against removing the allowance from the `One writable path` bullet only, in each file separately — two mutations, two reds, which is the measurement 019 recorded as failing; verified red against removing it from the first site only; verified GREEN when the allowance is reworded at both sites without being removed; `bats tests/` green afterwards
    - Requirements: R3.2, R1.1

  - [x] 3.3 - The comment-census assertions require the rule at every site
    - Context:
      - Files: `tests/scale-resolution.bats:794`, the THREE comment spans in `scripts/validate-story.sh` it reads, and `tests/anchor-lint.bats:307` (`grep -q 'only when'`) with the two unrelated spans at `references/validate-mode.md:195` and `:263` that satisfy it
    - Objective: Dropping the rule from any one comment span, or reversing the "only when" rule, turns the suite red.
    - ToDo: **added by 1.5's sweep — neither site was named by any census.** `:794` reads three comment spans in `validate-story.sh` and is satisfied by any one of them; measured GREEN with a `not` inserted into ALL THREE, which is worse than the `:181` defect it resembles. Assert the count of conforming spans, using the `[ "$(command grep -c …)" -eq N ]` shape `tests/supersede-story.bats` already uses, then pin the polarity within each. `tests/anchor-lint.bats:307` is the file-defeats-the-phrase shape in its purest form: `only when` occurs at `references/validate-mode.md:195` and `:263` for reasons unrelated to the rule, so DELETING the rule outright leaves the case GREEN — measured. Scope to the section that owns the rule before pinning anything, the same repair 3.1 applies to `agents/tech-reviewer.md`.
    - Tests: Unit · `tests/scale-resolution.bats` and `tests/anchor-lint.bats` — the existing cases, unchanged in name and count
    - Validation: `:794` verified red against a `not` in all three comment spans, and red again against a `not` in ONE span only, restored between; `anchor-lint.bats:307` verified red against DELETING the rule — the measurement that proves the scoping worked, since that deletion left the case green before — and GREEN against `validate-mode.md:195` and `:263` being reworded, since those spans are no longer in scope; `bats tests/` green afterwards
    - Requirements: R3.1, R3.2, R1.1, R1.3

  - Commit: "test(020): four assertions read the span that owns their rule"

- [x] 4 - Sites that need the rule restated before it can be pinned
  - _Complexity: Moderate | Tests: Unit | Risks: a sentence rewritten for the grep rather than the reader degrades the product this repo ships — the prose IS the plugin | Dependencies: Task 3_
  - Objective: Each rule states its polarity in a token a reader parses and a pattern can hold.

  - [x] 4.1 - The ordering rule states what must not happen
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:172` and `:199` (`before[^.]{0,160}summar`), the rule at `agents/validator.md:36` and `agents/auditor.md:74`, and `:181`/`:205` from 3.2 which read the SAME sentence
    - Objective: Reversing the write-before-summary ordering turns the suite red, and no other assertion reading that sentence changes colour.
    - ToDo: story 019 withdrew its own exclusion here under measurement — `before` was argued to be the polarity carrier, then `never before composing` was measured green, which is one word inserted rather than exotic prose. The token to pin does not exist yet, so make it exist. Rewrite the clause so the ordering states its own prohibition inline — the rule is "write the file, THEN compose the reply", and the sentence should say the reply is never composed first, in four words or fewer. **The constraint from R2.2 is binding: insert or move a token inside the existing sentence; do not restructure the paragraph, and do not write a phrase that reads as test scaffolding.** Before editing, list every assertion that reads this span — `:172`, `:181`, `:199`, `:205` at minimum, and whatever 1.5's sweep adds — and after editing, re-run each and report its colour; R2.3 makes that list a deliverable, not a precaution. Apply the identical rewrite to both agent files: they state the rule in the same words today and a divergence here would be a new defect.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the `1.1:`/`1.2:` ordering cases, plus 3.2's count cases re-run as regression
    - Validation: verified red against the rewritten rule inverted (`never composed first` → `composed first`), one file at a time, restored between; verified red against `never before composing` — the exact mutation that defeated the old pattern; verified GREEN against a rewording preserving the ordering; every assertion identified as reading this span re-run and its colour reported individually, with 3.2's count case explicitly confirmed still red on a single-site removal; `bats tests/` green afterwards
    - Requirements: R1.4, R2.1, R2.2, R2.3

  - [x] 4.2 - The stale-report rule states the verb and the ordering
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats:241` (case `2.1: validate-mode removes the stale report file before spawning`), the three prose sites at `references/validate-mode.md:138`, `:139` and `:151`, and the `stale rendering` decoy at `:363`
    - Objective: Reversing either the deletion verb or the before-spawn ordering turns the suite red.
    - ToDo: the weakest assertion in the file, and measured as such — rewriting `Delete`/`delete`/`delete that agent's` to `Keep`/`keep`/`never delete that agent's` at all three sites AND `Before each spawn` to `After` leaves it green, because the pattern only asks that some line mentioning `stale` also names a report file. It pins neither half of its own case name. Two facts to carry: the rule is stated at three sites, and the file contains a `stale rendering` line in the Index Refresh section that has nothing to do with reports — which is why the current assertion is line-based rather than section-scoped. Prefer scoping to the section that owns the rule over widening the pattern, then pin the verb and the ordering as separate assertions, so a future reader can see which half broke. If the rule's three sites do not share a scopeable section, restate the rule once in the section that owns it and let the other two sites reference it — a rule stated three times is three chances to drift, and consolidating is the smaller change than pinning three spans.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the same `2.1:` stale-report case, unchanged in name and count
    - Validation: verified red against the deletion verb inverted at all three sites; verified red against the verb inverted at ONE site only, since a rule that survives partial removal is the `:181` defect again; verified red against `Before each spawn` → `After each spawn`; verified GREEN against the `stale rendering` decoy at `:363` being reworded, proving the scoping excluded it; `bats tests/` green afterwards
    - Requirements: R1.4, R2.1, R2.2, R3.1

  - [x] 4.3 - The one-request rule and the on-demand carve-out state their own polarity
    - Context:
      - Files: `tests/reports-by-artifact-policy.bats` (the `one[^A-Za-z][^.]{0,80}SendMessage` assertion and its negated companion), the `creat[a-zA-Z]*[^.]{0,80}\.draft` assertions from 3.2, and the rules in `agents/validator.md` / `agents/auditor.md`
    - Objective: Widening the one-request recovery, or reversing the on-demand carve-out, turns the suite red.
    - ToDo: **added by 1.5's sweep — three rows no task covered.** The first is the pair this file's own header holds up as the SANCTIONED shape: a positive assertion guarded by a negated companion. Measured: rewriting the rule to `one SendMessage per attempt … repeat the row as often as it takes` leaves BOTH green, because the companion only reds on the five modifiers it enumerates and `per attempt` is not among them. **Do not extend the enumeration** — an enumeration of the ways to say "more than one" is the mechanism this story is replacing. Rewrite the rule so the single-request bound states itself inline, per R2.2: insert or move a token inside the existing sentence, never restructure the paragraph. The second is `creat…\.draft`: 3.2 closes its COUNT half and 4.1 rewrites the ordering clause in the same sentence, but neither gives this assertion a polarity token — measured GREEN with `…is part of this step` reversed at both spans in both files. Give the carve-out its own token in the same rewrite pass, and re-run 3.2's count cases as regression.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the existing cases, unchanged in name and count, plus 3.2's count cases re-run as regression
    - Validation: the one-request pair verified red against `per attempt … repeat as often as it takes` — the exact mutation that defeated it — and against the rewritten rule inverted, restored between; the `.draft` carve-out verified red against its reversal at both spans, and red again against reversal at ONE span only; every assertion identified as reading each rewritten span re-run and its colour reported individually, per R2.3; `bats tests/` green afterwards
    - Requirements: R1.4, R2.1, R2.2, R2.3

  - Commit: "test(020): three rules state the polarity their guards could not pin"

- [x] 5 - The unguarded copies, and the header that stops claiming
  - _Complexity: Simple | Tests: Unit | Risks: a header describing a guard the suite does not have is worse than no header — it is read as an invariant | Dependencies: Tasks 1-4_
  - Objective: The prompt templates carry the same guard as the definitions they mirror, and no comment claims a completeness the tests do not enforce.

  - [x] 5.1 - The prompt-template copies are pinned like the definitions
    - Context:
      - Files: `references/validate-mode.md:62` and `:132` (the Validator and Auditor prompt templates), the pinned originals at `agents/validator.md:74` and `agents/auditor.md:125`, and the `1.1:`/`1.2:` template-mirror cases already in the policy file
    - Objective: Inverting the carve-out in either prompt template turns the suite red.
    - ToDo: story 019 pinned `is a protocol violation` in the two agent definitions and left the two prompt-template copies guarded by nothing — measured: inverting BOTH copies leaves the whole suite green at 482. This is a concern story 011 stated for itself and never guarded. The file already has cases whose job is exactly this shape (`1.1: validate-mode Validator prompt template mirrors the report file`), so extend those rather than adding new cases — a mirror case that checks the filename but not the carve-out is the same half-guard defect one level down. Pin the same assertive frame the definitions use, `is a protocol violation`, scoped to each template block. **Added by 4.1's measurement, and it is a second site of the same shape:** 4.1 rewrote the ordering clause in both agent definitions to `never composing any textual summary first`, and the three template copies at `references/validate-mode.md:33`, `:90` and `:147` still read `before composing any textual summary` / `before composing any prose`. That is NOT a contradiction - `as the LAST step before ...` states the same ordering with its own token - but no assertion pins the ordering in any of the three, so all three are unguarded copies exactly as the carve-out was. Measure each before deciding: pin the token each copy already carries rather than rewriting three sites to match a fourth, unless the measurement says the existing token cannot be pinned.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the two existing template-mirror cases, extended rather than duplicated
    - Validation: verified red against each copy inverted separately — two mutations, two reds, restored between; verified red against both inverted at once, the mutation that was green before this sub-task; verified GREEN against a rewording of the surrounding template text that keeps the carve-out; `bats tests/` green afterwards
    - Requirements: R1.1, R1.2

  - [x] 5.2 - The header points at the guard instead of standing in for it
    - Context:
      - Files: the convention block at `tests/reports-by-artifact-policy.bats:16-115`, the new `tests/assertion-hygiene.bats`, and every claim in the old header that tasks 1-5 have now made false
    - Objective: A reader of the header can tell which claims the suite enforces and which are guidance, and no claim in it is contradicted by the tree.
    - ToDo: five corrections, all comment-level, none touching an assertion, and each traceable to a measurement this story took. (1) The census paragraphs naming five last-position negations and five converted ones are obsolete — 1.2 converted all six and 1.1 enforces the rule, so replace the enumeration with a pointer to the lint. An enumeration that the suite now generates is a copy waiting to go stale, which is how this header got here. (2) The closing paragraph cites `measurement` as a topic word with no polarity to pin; 2.2 measured that refuted, so correct it and say what the measurement was. (3) The DIRECTION-BLIND and NEGATION-PERMEABLE blocks list sites that tasks 2-4 have closed — remove the closed ones, and for anything the sweep left open, point at its allowlist row rather than restating the measurement in two places. (4) The `THIS HEADER IS A COMMENT, NOT A CLAIM UNDER TEST` paragraph is now only half true: the negation rule and the window-pattern rule ARE under test. Say precisely which parts are enforced and which are still guidance — a partial guard described as none is as misleading as none described as a guard. (5) Locate every edit by content, not by the line numbers above, because tasks 1-4 shift them.
    - Tests: None — comment-only edit; the guarantee it used to carry is now carried by 1.1's and 1.4's lints, and Validation re-runs the suite for case-name identity
    - Validation: `bats tests/` green with every case name byte-identical to the pre-edit run; every line reference surviving in the header resolved against the tree and confirmed to point at what it claims; every claim of enforcement in the header traced to a case that enforces it, with the case named
    - Requirements: R5.3

  - Commit: "test(020): the census is enforced, and the header says what it enforces"

- [x] 6 - The four sites this story's own measurements exposed after 5.3
  - _Complexity: Moderate | Tests: Unit | Risks: recorded after its work landed — every box below cites the commit that carries its measurement, and the drift itself is a deviation entry rather than a smoothed-over plan | Dependencies: Tasks 1-5_
  - Objective: The three residuals tasks 5.1 and 5.2 measured and named are closed, and so is the defect that had been running the entire suite dark on CI while five commits reported it green.

  - [x] 6.1 - The `.draft/` permission carries a frame a negation must split
    - Context:
      - Files: `references/validate-mode.md` (the Validator and Auditor prompt templates), `tests/reports-by-artifact-policy.bats` (the `\.draft[^.]{0,40}is +part of` allowlist key, one row over four sites)
    - Objective: A reversal that parks its negation AFTER the verb reddens both template copies, not just the one form the adjacency guard reaches.
    - ToDo: the templates stated the allowance as a dangling participle — `in the story directory, creating .draft/ on demand — fast and spike stories have none` — with no token a negation has to break, while the guard beside it reaches a negation only immediately in FRONT of the verb. Take 4.3's agent-definition edit verbatim into both templates so the direction rests on the `is part of` frame, which splits under `is NOT part of it`. Do NOT widen the negation guard: enumerating the ways English says "no" is the mechanism this story replaced.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the two template cases on the `is part of` key, counted at 1 per template section rather than `-q`, because the file holds two spans and the defect is the copy that contradicts its twin
    - Validation: measured on the pre-repair tree, one mutation at a time, whole file restored between — `though creating .draft/ on demand is forbidden` left BOTH template cases GREEN while the control `never creating` went RED, so one form of the same reversal was caught and the other was not; re-measured per template scope after the edit: `though … is forbidden` RED, `is NOT part of that step` RED, `never creating` RED here and at the adjacency guard beside it, the clause deleted outright RED; GREEN in the other direction on `creating .draft/ when you find none is part of that step` and on the sentence reflowed with not a word changed; `bats tests/` 498 green, exit 0, no case added, renamed or reordered
    - Requirements: R1.1, R1.2, R2.1, R2.2, R3.2

  - Commit: "test(020): the .draft/ permission carries a frame a negation must split"

  - [x] 6.3 - R5.3's roster closes its two open cells, and two rules stop being pinned by phrasing
    - Context:
      - Files: `tests/assertion-hygiene.bats` (roster existence match and body walker), `tests/scale-resolution.bats` (the `tasks.md is authoritative` pair), and this file's Quality Gate 6
    - Objective: No case in the census file can be commented out or gutted and stay green, and no rule-preserving rewording of the two named residuals costs a false Red.
    - ToDo: match roster existence at COLUMN 1 (`index($0, want) == 1`) so a commented-out header is not a header; run the body check per rostered case over that case's own tokens instead of over the census case alone; bound each body by its own closing brace rather than by the next header, since ~1000 lines of helpers sit between the `1.1:` and `1.4:` cases; carry heredoc bodies rather than parsing them, because eleven fixtures close with a `}` in column 1 inside a heredoc; add the six cases that were in no roster at all, including `1.1: no .bats file in tests/ inverts a command as an assertion` — the case that imposes R4.1/R4.2 on the whole suite and appeared exactly once, in no roster, with no body check; assert `real_headers == roster size` so a case added without a row is as loud as a case removed. Separately, replace the two literal verb phrases that wrote direction into the match (`is (the )?authoritative`) with a refusal, and retire Quality Gate 6 to what the story can sustain — the denominator of each sweep and the assertion that changed colour.
    - Tests: Unit · `tests/assertion-hygiene.bats` and `tests/scale-resolution.bats` — the rostered cases and the two authority cases, extended rather than duplicated
    - Validation: 4 mutations × 16 rostered cases, one at a time, each restored before the next — 62 of 64 RED, the two exceptions the census's own and unchanged; on the residuals, rule-preserving prose measured RED before and GREEN after: `is always authoritative`, `is strictly authoritative`, `is and remains authoritative`; `bats tests/` green afterwards
    - Requirements: R1.2, R1.4, R5.3

  - Commit: "test(020): every case in this file carries a roster entry and a body check" — landed as TWO commits, `879469f` (the roster) and `1b5d3e3` (the two rules pinned by refusal), both at the same measurement pass

  - [x] 6.5 - The fixtures no longer plant a case bats will collect
    - Context:
      - Files: `tests/assertion-hygiene.bats` (eleven `@test "planted"` fixtures and the census case), `.github/workflows/` (the runner's bats version), this file's Instrument note
    - Objective: The suite that reports this story green actually runs on the runner.
    - ToDo: bats collects any line beginning `@test`, heredoc body or not, indented or in column 1. On bats 1.10 — the version `apt` ships on `ubuntu-latest` — the eleven fixtures produced `Duplicate test name(s) … test_planted` ×10 and the file refused to LOAD; since `bats tests/` aborts on a load error, the WHOLE suite ran zero cases on the runner, 377 ms to failure. Unique fixture names would trade a load error for eleven phantom cases, and indentation does not help, so the literal token has to go: fixtures write `%%TEST%%` and a `plant` helper restores `@test` on the way to disk, leaving what the lint reads byte-identical. Make it a check, not a comment — the census case asserts that no line in the file starts with `@test` except a real `N.N: ` header. Retire the Instrument note that had explained the 509-vs-498 grep discrepancy as an artefact; it was this defect.
    - Tests: Unit · `tests/assertion-hygiene.bats` — the census case, which subsumes the roster partition it replaces
    - Validation: found by `act -j bats` before pushing, not by a red — the file entered in `53861a3` and had never reached CI; one fixture reverted to a literal `@test` → RED naming the line; verified on both versions — bats 1.14 local `1..498, 0 not ok`; bats 1.10 in the runner image `tests/assertion-hygiene.bats → 1..16, 0 not ok` and `tests/ → 1..498, 14 not ok`, the 14 being the root false-reds the workflow documents for act (same 14 before this change with the file removed, so no regression); `grep -c '^@test'` and `bats` now agree at 498
    - Requirements: R5.3

  - Commit: "test(020): the fixtures no longer plant a case bats will collect"

## Quality Gates

- [x] All acceptance criteria validated — each closed site proven red against the inversion of its own rule, green against at least one rule-preserving rewording, and, where the assertion was strengthened rather than added, still red against the deletion the old pattern caught
- [x] Both lints proven red against a planted offender BEFORE any site was converted — a guard that has never failed is the defect this story exists to close, and shipping one would repeat it at a new level
- [x] All task validations pass — every Validation field executed and its output reported, none summarised as "it passed"
- [x] All tests written and passing — full `bats tests/` green; case count = baseline + the cases tasks 1 and 5.1 add; no existing case renamed
- [x] The census is produced by a measured sweep with a stated denominator — how many files read, how many patterns found, how many measured — and every site it surfaced is closed by a task or carries an allowlist row with its measurement
- [x] Every prose rewrite states the denominator it swept — how many assertions read the rewritten span — and names the assertion(s) whose colour changed, with the mutation applied and the colour observed
- [x] Code integrated — zero `!`-inverted assertions and zero unlisted window patterns, both enforced by the suite rather than asserted by a comment

> **Gate 4, corrected by measurement.** The gate reads `baseline + the cases tasks 1 and 5.1 add`. Measured: 482 pre-story + 16 from task 1 = 498 at HEAD. **5.1 added ZERO cases** — its own ToDo required extending the two mirror cases rather than adding any, and it did. No pre-existing case was removed or renamed (diffed pre-story against HEAD).
>
> **Gate 6, retired and replaced, 6.3.** The gate read: *every prose rewrite names the assertions reading its span and reports each one's post-edit colour*. The story never produced that roster. The sweeps were reported in aggregate — the body of `0141e68` says "the plan named one assertion; the sweep found five … under each inversion exactly one changed colour" — and the five are named nowhere: checked against `tasks.md`, the six commit bodies, and the test-file headers, which are this story's deviation register (there is no `deviations.yaml`). A gate marked `[x]` whose evidence does not exist is the defect this story exists to close, one level up, so it is rewritten to what the story does produce and can sustain: the **denominator** of the sweep, and the assertion(s) that **changed colour**, each with its mutation and observed colour. What is given up is the record of which assertions stayed silent under the mutation; what is kept is that the sweep happened, that its size was counted, and that its result was measured rather than assumed. Re-running the sweeps to produce the nominal roster was the alternative and was weighed: the roster of non-changing assertions is a record, not a guarantee, and the guarantee is already carried by the denominator plus the assertion that moved.
>
> **Instrument note, and the defect it was covering for, 6.5.** The note read: *`command grep -c '^@test'` over the suite answers 509, not 498, because `tests/assertion-hygiene.bats` carries 11 `@test "planted"` fixtures inside heredoc bodies; `bats` is the instrument, the grep is not.* True of the local `bats` 1.14 — and the discrepancy was not a grep artefact, it was the defect. **bats collects any line beginning `@test`, heredoc body or not, indented or in column 1.** Measured on bats 1.10, the version `apt` ships on the runner's `ubuntu-latest`: the eleven fixtures made the file answer `Duplicate test name(s) … test_planted` ×10 and refuse to LOAD, and since `bats tests/` aborts on a load error, the **whole suite** ran zero cases on the runner — 377 ms to failure. Found by running `act -j bats` before pushing; the file entered in `53861a3` and had never reached CI, so no red ever said so. The fixtures now carry `%%TEST%%` and a `plant` helper restores `@test` on the way to disk, so the file on disk is byte-identical for the lint and holds no case for bats. `grep -c '^@test'` and `bats` now agree at 498, and the census case asserts that no line starts with `@test` except a real header — the condition as a check, since a comment saying it is what stood here.
