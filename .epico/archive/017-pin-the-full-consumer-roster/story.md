---
story: pin-the-full-consumer-roster
type: feature
scale: standard
version: 1
created: 2026-08-16
status: archived
---

# Story - Pin the Full Consumer Roster

## Introduction

The checkbox grammar — the regex that decides whether a line is a task box and
whether that box is open, closed, deferred or terminal — is duplicated across
**ten** scripts. `tests/checkbox-grammar.bats` exists to stop those copies from
drifting apart, and it works: it passes one mixed fixture through every consumer
and asserts they agree.

What does not work is the roster. Five consecutive enumerations of *which*
scripts are consumers have been wrong — "6 regex places across 4 scripts" → 5 →
6 → 7 → 10 — and the header of that file records the first four itself, each
time concluding that the lesson is the harness. The fifth was written by story
016, sub-task 1.2, into that same header: it says SEVEN, and a measured scan of
`scripts/` finds TEN. `archive-story.sh`, `epic-index.sh` and
`supersede-story.sh` each keep their own copy of both the box regex and the
deferred/terminal split, and none is compared against the fixture.

This story stops writing the number. The roster becomes data the suite derives
from the tree and compares against a declared list, so an eleventh consumer
reddens until someone registers it — no human writes a count again. It also
pins the three consumers currently outside the harness, and repairs the two
facts story 016 stated in a place where they could not fail.

## Related Stories

- Related: `.epic/stories/016-close-010-audit-gaps/tasks.md` — this story closes
  the three gaps 016's validate pass found: the roster it left wrong, the two
  citations its own header edit invalidated, and the commit it left unanchored.
- Related: `.epic/stories/004-story-state-machine-checkbox-grammar/` (archived) —
  origin of the cross-regression harness and of the mixed fixture this story
  extends.

## Requirements

### R1. The roster is derived from the tree, never declared in prose

The recurring defect is not any single wrong number. It is that the number is
prose: a sentence cannot fail, so nobody is told when it goes stale.

#### Acceptance Criteria

- R1.1: WHEN the cross-regression suite runs THE SYSTEM SHALL scan every script
  under `scripts/` for a checkbox-grammar reading and SHALL fail when the set of
  scripts found differs from the declared consumer list
- R1.2: WHERE a script matches the detection predicate but does not read the
  grammar THE SYSTEM SHALL require an explicit exemption entry carrying a
  written reason, and SHALL fail when such a script is neither a declared
  consumer nor exempt
- R1.3: THE SYSTEM SHALL pin the detection predicate against the declared
  consumer list, failing when the predicate stops finding a script that is
  declared a consumer — so narrowing the predicate cannot turn the derivation
  green by finding nothing
- R1.4: THE SYSTEM SHALL carry the consumer roster in exactly one place — the
  declared list the derivation compares against — and no file under `tests/` or
  `scripts/` SHALL assert a present-tense count of consumers in prose; the
  record of the counts that were wrong is history, not an assertion, and
  remains, because it is the argument for the derivation
- R1.5: IF a script is a declared consumer but no case in the cross-regression
  harness compares it against the shared fixture THEN THE SYSTEM SHALL fail —
  registering a name is not sufficient to turn the derivation green

### R2. Every consumer agrees with the shared fixture, including the three now unpinned

A script can be on the roster and still hold a drifted copy. Membership answers
"is it registered?"; only a comparison answers "does it read the same truth?".

#### Acceptance Criteria

- R2.1: WHEN the mixed fixture is read by `archive-story.sh` THE SYSTEM SHALL
  assert its emitted `tasks` object reports total 5 and open 1 identical to the
  shared truth, and that `closed + deferred` equals the shared settled count of
  4 — `census_tasks` splits on the box character alone and never reads the
  qualifier, so a terminal `[~]` is folded into `deferred` by design and it
  reports closed 2, deferred 2; agreement here is a mapping, not an equality
- R2.2: WHEN the mixed fixture is read by `epic-index.sh` THE SYSTEM SHALL
  assert its census reports total 5, done 3 and deferred 1, and that `total −
  done − deferred` equals the shared open count of 1 — `epic-index.sh` emits no
  `open` field and folds a terminal `[~]` into `done`, the opposite fold from
  archive-story's, so agreement here is a mapping, not an equality
- R2.3: WHEN the mixed fixture is read by `supersede-story.sh` THE SYSTEM SHALL
  assert that the set of boxes it carries into the successor story equals the
  shared open-or-deferred set — sub-tasks 1.4 and 1.5, and no others
- R2.4: WHERE a consumer under comparison writes to disk THE SYSTEM SHALL run it
  against a copy of the fixture and SHALL leave the shared fixture byte-identical
- R2.5: THE SYSTEM SHALL keep the seven existing consumer comparisons and both
  byte-identical legacy goldens passing and unmodified

### R3. Story 016's stated facts are repaired where they are stated

#### Acceptance Criteria

- R3.1: THE SYSTEM SHALL leave no citation in story 016's plan pointing at a
  line range that no longer holds the content the citation claims
- R3.2: WHERE a story plan cites a location inside another file THE SYSTEM SHALL
  cite it by the name of the thing cited rather than by a line range
- R3.3: THE SYSTEM SHALL name every commit anchored to story 016 in story 016's
  own plan, so `anchored_commits` has a counterpart in the artifact
- R3.4: WHEN `validate-story.sh` runs against story 016 after the repair THE
  SYSTEM SHALL report `status: pass` with zero errors

## Success Metrics

- The word "seven" — or any other consumer count — appears in zero prose
  sentences across `tests/` and `scripts/`; the roster exists only as data.
- Adding an eleventh consumer to `scripts/` reddens `bats tests/` without anyone
  editing a number, and the red names the unregistered script.
- The detection predicate resolves to exactly the ten declared consumers on the
  tree as it stands, with zero exemptions required.
- `bats tests/` fully green with four cases more than the 450 at HEAD.
- Every citation in story 016's plan resolves to the content it claims.

## Constraints

- Shell and bats only. No new runtime dependency: `jq` is already declared in CI
  and used by sixteen suites.
- The shared mixed fixture is never written to. A consumer that writes runs
  against a `mktemp -d` copy — the convention story 016's sub-task 1.2
  established.
- The detection predicate must tolerate every spelling present in the tree,
  including two that a naive scan of the `[ x~]` class would miss:
  `monitor-stale.sh` deliberately narrows to `- [ ]` (documented as the
  DELIBERATE EXCEPTION in its own comment block) and `hook-task-completed.sh`
  writes the box inline with `\s*` rather than `[[:space:]]*`.
- Comment lines are excluded from detection: three scripts discuss the grammar
  in prose without reading it there.
- The Commit anchor uses the checkbox sub-task shape, current at HEAD. Story 015
  (`migrate-commit-field`) converts it to a group-level `Commit:` field but is
  unimplemented, so the field shape is not yet valid.
- `.epic/` is gitignored, so repairing story 016's plan carries no git history
  cost and leaves the delivered code untouched.
- Tooling: n/a — no browser or E2E surface in this story. No E2E tool is
  selected and none is needed.

## Out of Scope

- **The reverse anchor check** — making an anchored commit with no counterpart in
  the plan fail. It needs a rule for the legitimate case (a later story fixing an
  earlier one, which is exactly what `eff96c2` is), and that is a design
  decision. Goes to story 018.
- **The duplicated `(n-a: …)` qualifier defect** in `close-subtask.sh` — `set_box()`
  appends its qualifier without inspecting the line it is about to write. Story 018.
- **`cross-reference.sh` exiting 2 on a Fast story** instead of the documented
  exit 0 with `status: no-requirements-chain`. Story 018.
- **Collapsing the ten regex copies into one shared source.** This story measures
  that the copies agree; de-duplicating them is a larger change with its own
  blast radius, and the harness is what makes it safe to attempt later.
- **Any change to what a consumer does.** Every script here is read for
  comparison only; none of their behaviour changes.
- Re-verifying story 016's unmeasured Red claim. Fast mode persists no Red
  evidence by contract, and re-measuring it would require mutating shipped code.
