---
story: close-the-polarity-census
type: feature
scale: standard
version: 2
created: 2026-08-18
last-refined: 2026-08-19
history:
  - v1: Initial story
  - v2: Group 6 records the four commits that landed after 5.3 — the `.draft/` frame (D6), R5.3's roster and body checks, two rules pinned by refusal instead of by phrasing, and the bats-collection defect that ran the whole suite dark on CI
status: archived
---

# Story - Close the Polarity Census

## Introduction

This repository's policy tests assert that a rule is *stated* in the prose the
plugin executes from — agent definitions and mode references. Stories 018 and
019 established that such an assertion can be satisfied by a rule and its
negation alike, and that a `!`-inverted assertion outside an `@test`'s last
statement cannot fail at all. Story 019 closed ten sites and then claimed, in a
comment block, a complete census of what remained.

That census was measured during 019's validate pass and found incomplete — for
the fourth time across three versions of the same story, and every time in the
entries that were argued rather than measured. This story closes the remaining
sites and replaces the comment block with a test, so the completeness claim
stops depending on an author remembering to look.

The scope is the repository, not one file. A site in
`tests/scale-resolution.bats` — a case named *"states that `tasks.md` **is**
authoritative"* — was measured green with its rule inverted to *"is **not**
authoritative"*, and no census had ever named it. The class was never confined
to the file 019 audited; only the searching was.

## Related Stories

- Source: `.epic/stories/019-pin-assertion-polarity/tasks.md` — closes 019's
  named backlog plus the four sites its validate pass measured
- Source: `.epic/stories/018-close-011-audit-gaps/tasks.md` — established
  proof-by-mutation as the evidence bar for a strengthened assertion

## Requirements

### R1. A Directional Assertion Reddens On Its Own Inversion

**User Story:** As a maintainer changing a rule in an agent definition, I want
the suite to fail when I reverse the rule's meaning, so that a policy test
cannot certify a contract it no longer guards.

#### Acceptance Criteria

- R1.1: WHEN the prose rule guarded by a policy assertion is inverted at every
  site the assertion reads THE SYSTEM SHALL fail the test suite
- R1.2: WHEN that same prose rule is reworded without changing its meaning THE
  SYSTEM SHALL leave the test suite green
- R1.3: WHEN an assertion is strengthened THE SYSTEM SHALL still fail on the
  deletion of the rule it guards, so that the new pattern is provably stronger
  than the one it replaces and not merely different
- R1.4: WHERE a claim's polarity cannot be matched without matching most of a
  sentence THE SYSTEM SHALL state the rule in prose carrying a polarity token of
  at most four words, and pin that token

### R2. A Prose Rewrite Costs Nothing It Does Not Announce

**User Story:** As a reader of the agent definitions, I want a rule rewritten
for testability to still read as guidance written for me, so that the test
suite's needs do not degrade the product.

#### Acceptance Criteria

- R2.1: WHEN a prose rule is rewritten to carry a pinnable polarity token THE
  SYSTEM SHALL leave every other assertion that reads the same span green
- R2.2: WHEN a prose rule is rewritten THE SYSTEM SHALL confine the edit to
  inserting or moving a polarity token within the existing sentence, never
  restructuring the surrounding paragraph
- R2.3: WHEN a prose rewrite is proposed THE SYSTEM SHALL name every assertion
  in the suite that reads the rewritten span, measured rather than assumed

### R3. An Assertion Reads Exactly The Span That Owns Its Rule

**User Story:** As an author strengthening an assertion, I want the match scoped
to the rule's own section, so that pinning the polarity is not defeated by an
unrelated sentence elsewhere in the file.

#### Acceptance Criteria

- R3.1: WHERE more than one span in the file under test satisfies an assertion's
  pattern THE SYSTEM SHALL scope that assertion to the section stating the rule
- R3.2: WHERE a rule must hold at two or more sites for the contract to stand
  THE SYSTEM SHALL assert the count of conforming sites, so that removing the
  rule from one site fails the suite

### R4. No Assertion In The Suite Is Incapable Of Failing

**User Story:** As an author appending an assertion to an existing case, I want
the suite to reject a shape that silently stops asserting, so that test
ordering cannot turn a guard into a no-op.

#### Acceptance Criteria

- R4.1: THE SYSTEM SHALL express every negated assertion in `tests/` as a
  conditional that returns non-zero, never as a `!`-inverted command
- R4.2: WHEN a `!`-inverted command is used as an assertion in any `.bats` file
  THE SYSTEM SHALL fail the test suite, naming the file and line
- R4.3: WHERE a `!` appears inside `[ ]` or `[[ ]]` THE SYSTEM SHALL treat it as
  conforming, because a conditional operator's status is not exempt from
  `errexit`

### R5. The Census Is A Test, Not A Comment

**User Story:** As the next author adding a prose assertion, I want the suite to
tell me my pattern is direction-blind, so that completeness stops depending on
someone re-reading a comment block.

#### Acceptance Criteria

- R5.1: WHEN a prose assertion in `tests/` uses a window pattern and is absent
  from the polarity allowlist THE SYSTEM SHALL fail the test suite, naming the
  file and line
- R5.2: THE SYSTEM SHALL require each allowlist entry to carry the measurement
  that justifies it — the mutation applied and the observed result
- R5.3: WHEN the census test itself is disabled or emptied THE SYSTEM SHALL fail,
  so that the guard cannot be silently removed

## Success Metrics

- Every site named in this story fails the suite under the inversion of its own
  rule, measured one mutation at a time and restored between
- Every site named in this story stays green under at least one rule-preserving
  rewording, so no polarity was bought with a false red
- Zero `!`-inverted command assertions remain in `tests/`
- A newly added direction-blind prose assertion fails the suite without any
  human having reviewed it
- Case count changes only by the cases this story adds, and no existing case is
  renamed

## Constraints

- The prose under test is the product. A rewrite may insert or move a polarity
  token inside an existing sentence; it may not restructure the paragraph, and
  it may not introduce phrasing written for the grep rather than the reader
- Assertions stay behavior-level. Pinning an exact sentence is the opposite
  defect and is out of bounds — `tests/reports-by-artifact-policy.bats`'s own
  header forbids it
- No generic polarity helper. A guard rejecting a negation in the window before
  a match false-reds on `agents/auditor.md`'s memory clause by construction —
  measured in story 019
- No E2E tooling applies: the suite is bats over shell and markdown, with no UI
  and no running service. Recorded as `none — no E2E tooling applicable`
- Every claim of completeness in this story must be produced by a measured sweep,
  never by an author's enumeration — that mechanism has failed four times

## Out of Scope

- Converting the assertion style of tests that make no prose claim (fixture-based
  tests in `archive-story.bats`, `epic-index.bats` and their peers)
- Rewriting any rule's meaning. This story changes how a rule is *stated* and how
  it is *guarded*, never what it requires
- Pinning prose in `skills/`, `hooks/` or `monitors/` — no policy test reads them
  today, and adding that coverage is a story of its own
- Retro-fitting the census test to non-`.bats` assertion sites (shell scripts
  under `scripts/` that grep their own docs)
