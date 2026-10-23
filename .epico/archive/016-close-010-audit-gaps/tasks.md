---
story: close-010-audit-gaps
type: feature
scale: fast
status: archived
version: 1
created: 2026-08-16
---

# Implementation Plan - Close the 010 Audit Gaps

## Overview

Story 010's validate pass came back clean, with three follow-ups the auditor
booked rather than fixed: one stale key-set enumeration, one consumer missing
from the cross-regression harness, and two transition arms with no bats pin.
All three are the same failure mode — **a fact stated in prose cannot fail, so
it is never corrected** — which the codebase already documents twice
(`close-subtask.sh`'s BOX_RE block, `checkbox-grammar.bats`' header). Each
sub-task therefore pins its fix with a test, so the next drift is a red, not a
finding.

Fast scale: three mechanical fixes, each isolated, no architectural decision and
no requirement traceability to carry. The one judgement call — how a *writer*
joins a harness built for *readers* — is settled in 1.2's ToDo so the executor
does not have to make it.

## Task List

- [x] 1 - Close the three follow-ups story 010's audit left open
  - _Complexity: Simple | Tests: Unit | Risks: 1.2 writes to a copy of the shared fixture — never to the fixture itself | Dependencies: None_
  - Objective: Every fact the audit found stated-but-unpinned is now measured by the suite.
  - Follow-up commit, planned by no sub-task: `eff96c2` "docs(016): cite the moved paragraphs by name, not by line", landed after this story closed. Sub-task 1.2 renumbered `checkbox-grammar.bats`' consumer roster from six to seven and shifted the paragraph two other comments cited by line — the same failure mode this story exists to close, shipped by the story itself. It is named here because `story-git-status.sh` reports `anchored_commits: 2` for this story and both anchors must be findable in the plan: `a01503e` (the commit 1.4 planned) and this one.

  - [x] 1.1 - list-mode.md: the key set gains `anchored_commits`
    - Context:
      - Files: `references/list-mode.md:167` (the stale enumeration), `references/validate-mode.md:131` (the same sentence, already correct — copy its shape), `tests/anchor-lint.bats` (already holds the doc-contract cases for this field)
    - Objective: The two places that enumerate `story-git-status.sh`'s output agree with the script.
    - ToDo: in `references/list-mode.md:167`, extend `{story, main_branch, integrated, evidence, checked_at}` to carry `anchored_commits` in the same position `validate-mode.md:131` puts it (between `evidence` and `checked_at`, matching the emission order at `scripts/story-git-status.sh:988`). Change the key list only — the surrounding argument about the rendering living in one script is unaffected and must not be reworded.
    - Tests: Unit · `tests/anchor-lint.bats` — a doc-contract case over flattened `references/list-mode.md` text asserting the enumeration names `anchored_commits`, mirroring the existing `validate-mode.md` doc-contract cases so both copies are pinned by the same mechanism
    - Validation: `command grep -n 'anchored_commits' references/list-mode.md` hits line 167; `bats tests/anchor-lint.bats` green

  - [x] 1.2 - close-subtask.sh joins the cross-regression harness as its seventh consumer
    - Context:
      - Files: the header block of `tests/checkbox-grammar.bats` (the header naming SIX consumers and the "if a seventh appears, it belongs here" rule), the `Mixed fixture totals` block of `tests/checkbox-grammar.bats` (the mixed fixture's shared totals), the `census_boxes` function of `scripts/close-subtask.sh` (`census_boxes` — the reading this harness must compare)
    - Objective: The first *writer* of the checkbox grammar is pinned against the same mixed fixture as the six readers, so a drifted copy is a red.
    - ToDo: settle the writer-in-a-reader-harness question this way — `close-subtask.sh` reports its reading of the grammar in the `census` object of its stdout JSON, so that object is what the harness compares. Copy the mixed fixture story to a `mktemp -d` (the shared fixture is never written to), close its one open box (`1.5`) there, and assert the returned `census` equals the shared truth as it stands after that close: `total 5 · closed 4 · deferred 1 · open 0`. Update the file header: SIX consumers becomes SEVEN, name `close-subtask.sh` in the list, and note that it is the only one that writes. Expect a non-empty embedded `validate` verdict on the bare fixture — assert on `census` only; the verdict is not this harness's subject, and `close-subtask.sh` never rolls a marking back on it.
    - Tests: Unit · `tests/checkbox-grammar.bats` — the seventh-consumer case above (census agrees with the six readers on the copied fixture); the six existing consumer cases and both R5.1 byte-identical goldens still green and unmodified
    - Validation: `bats tests/checkbox-grammar.bats` green with one case more than before; `git diff --stat tests/checkbox-grammar.bats` shows additions plus the header edit only — no existing assertion changed

  - [x] 1.3 - Pin transition rule 2 and the out-of-enum status guard
    - Context:
      - Files: the `reopen edge` arm of `scripts/close-subtask.sh` (rule 2 — open boxes under `done`/`validated` reopen to `in-progress`), the `case "$STATUS_FROM"` block of `scripts/close-subtask.sh` (the `case` whose `*)` arm leaves any status outside the six-value enum alone), `tests/close-subtask-transaction.bats` (fixture conventions and the existing transition cases)
    - Objective: The two transition arms the audit found unprotected fail the suite when they drift.
    - ToDo: add two cases to `tests/close-subtask-transaction.bats`. Rule 2: a fixture stamped `status: done` that still carries open boxes — closing one of the others must report `status_written` as `{from: done, to: in-progress}` and stamp `in-progress` in every artifact, because a story with work still owed is not done. Enum guard: a fixture stamped `status: superseded` whose last open box is closed — `status_written` must be `null` and the frontmatter must read `superseded` afterwards, since `done` would erase a supersede the first time a Quality Gate was settled. Assert the stamp in the file, not only the JSON.
    - Tests: Unit · `tests/close-subtask-transaction.bats` — rule-2 reopen (`done` + open boxes → `in-progress`, reported and stamped); out-of-enum guard (`superseded` + last box closed → `status_written: null`, frontmatter unchanged)
    - Validation: `bats tests/close-subtask-transaction.bats` green with two cases more than before; both new cases verified red against a mutated copy of the `case` block before being accepted

  - [x] 1.4 - Commit
    - Validation: `bats tests/` fully green (450 cases: 446 + 4 — 1 in anchor-lint, 1 in checkbox-grammar, 2 in close-subtask-transaction); `shellcheck -S warning scripts/*.sh` clean
    - Commit: "test(016): pin the three facts story 010's audit found stated but unmeasured"

## Quality Gates

- [x] All acceptance criteria validated (each of the three follow-ups has a passing test, not a prose claim)
- [x] All task validations pass
- [x] All tests written and passing (full bats suite green; the six existing consumer cases and both R5.1 goldens untouched)
- [x] Code integrated (`references/list-mode.md` and `references/validate-mode.md` enumerate the same key set as the script emits)
- [~] Error handling implemented (n/a — no new runtime code; the two new transition cases cover the arms that decide what is *not* written) (n-a: no new runtime code; the two new transition cases cover the arms that decide what is not written)
