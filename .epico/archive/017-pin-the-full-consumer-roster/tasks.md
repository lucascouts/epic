---
story: pin-the-full-consumer-roster
type: feature
scale: standard
version: 1
created: 2026-08-16
status: archived
---

# Implementation Plan - Pin the Full Consumer Roster

## Overview

Task 1 turns the roster into data — one sourced library holding the declared
list, the detection predicate and a diff that names discrepancies — and retires
the prose counts it replaces. Task 2 compares the three consumers that were
never pinned, then closes the loop so a name in the list without a comparison
case is itself a failure. Task 3 repairs story 016's plan, and depends on
neither.

Two honest notes about the shape of this plan.

**Sub-tasks 2.1-2.3 are characterization pins, not test-first work.** The Test
Advisor measured all three consumers against the mixed fixture and found no
drift — they already agree. A test over correct existing behaviour cannot be
made Red without first breaking the code, which this story puts out of scope, so
those three carry no `red-evidence.yaml` entry and their authored cases pass on
arrival. That is recorded, not hidden: their value is preventing the next drift,
not repairing a current one. Sub-tasks 1.1, 1.2, 1.3 and 2.4 are genuinely Red
and their evidence is on file.

**Task 3 has no Commit field.** The only file it touches is under `.epic/`,
which is gitignored, so the group produces nothing committable. This is the
same reason it carries no test: a committed suite cannot pin an uncommitted
artifact.

## Task List

- [x] 1 - The roster becomes data
  - _Complexity: Moderate | Tests: Unit | Risks: a detection predicate too broad reds on scripts that only mention the grammar in prose; too narrow goes green by finding nothing | Dependencies: None_
  - Objective: The set of checkbox-grammar consumers is derived from the tree and compared against a declared list, so no human writes the count again.

  - [x] 1.1 - The roster library: declare it, derive it, name the discrepancy
    - Context:
      - Files: `tests/checkbox-grammar.bats:1-32` (the header the roster is leaving), `scripts/` (the scan surface — 24 scripts, of which 10 read the grammar), `.epic/stories/017-pin-the-full-consumer-roster/.draft/authored-tests/tests/consumer-roster.bats` (the authored contract this must satisfy)
    - Objective: The harness carries the consumer roster as data and fails when a scan of `scripts/` disagrees with it, naming the unregistered script.
    - ToDo: create `tests/lib/checkbox-consumers.sh` defining exactly the four names the authored suite sources — `CHECKBOX_CONSUMERS` (array of the ten basenames: archive-story.sh, close-subtask.sh, cross-reference.sh, epic-index.sh, hook-post-tool-failure.sh, hook-precompact.sh, hook-task-completed.sh, monitor-stale.sh, supersede-story.sh, validate-story.sh), `CHECKBOX_CONSUMER_EXEMPT` (empty; each future entry is `"name.sh: reason"`, and an entry with no reason is rejected rather than silently accepted), `detect_checkbox_consumers <dir>` (prints one detected basename per line) and `checkbox_roster_diff <dir>` (exit 0 on agreement, non-zero otherwise, **naming** each discrepancy — a bare exit code tells the next reader nothing, which is the failure mode this whole story is about). Read both arrays at call time, never snapshot them into locals: the authored cases reassign them to build the hostile halves. Strip whole-line comments (`sed 's/^[[:space:]]*#.*//'`) before matching — three scripts discuss the grammar in prose without reading it there. A predicate measured to resolve to exactly the ten and none of the other fourteen is `\[\(?\[?[ x~]{1,4}\]?\)?\]` over the escaped-bracket form; any predicate that satisfies 1.2 is acceptable. Source the library from both `tests/consumer-roster.bats` and `tests/checkbox-grammar.bats` (2.4 needs it too) — one definition, two consumers. Every file read must handle its own failure: a `[[ -f ]]` says the file exists, not that it opens, so follow the `{ …; } 2>/dev/null < "$f" || rc=1` shape the existing censuses use.
    - Tests: Unit · `tests/consumer-roster.bats` — declared roster and a scan of `scripts/` agree (both sides non-empty), an unregistered consumer reddens and the red names it, an exemption silences a detected script only when it carries a written reason
    - Validation: `bats tests/consumer-roster.bats` green; `shellcheck -S warning tests/lib/checkbox-consumers.sh` clean; the library sources cleanly under `set -euo pipefail`
    - Requirements: R1.1, R1.2, R1.4

  - [x] 1.2 - Pin the predicate against the declared roster
    - Context:
      - Files: `scripts/monitor-stale.sh:205-215` (the DELIBERATE EXCEPTION comment block and the `- [ ]` it narrows to), `scripts/hook-task-completed.sh:44` (the inline `\s*` spelling)
    - Objective: A narrowed predicate cannot turn the derivation green by finding nothing — the predicate must still find every declared consumer individually.
    - ToDo: no new implementation is needed if 1.1's predicate already finds every declared consumer in isolation; this sub-task is the verification point that proves it. Run the authored anti-narrowing cases and, if any declared consumer is not found alone, widen the predicate in `tests/lib/checkbox-consumers.sh` until it is. The two spellings that defeat a naive scan of the `[ x~]` class are `monitor-stale.sh`, which narrows to `- [ ]` on purpose — its comment block calls this the DELIBERATE EXCEPTION, so widen the predicate, never the script — and `hook-task-completed.sh`, which writes the box inline with `\s*` instead of `[[:space:]]*`. Any widening must not pull in one of the fourteen non-consumers: re-run the full scan after every change and confirm the set is still exactly ten.
    - Tests: Unit · `tests/consumer-roster.bats` — every declared consumer is found ALONE by the predicate (anti-narrowing pin), a declared consumer the predicate cannot find fails named, a script that only discusses the grammar in comments is not detected
    - Validation: `bats tests/consumer-roster.bats` green; the anti-narrowing case verified red against a copy of the library whose predicate is narrowed to `[ x~]` alone — which drops `monitor-stale.sh` — mutated under `mktemp -d`, never in the tree
    - Requirements: R1.3

  - [x] 1.3 - Retire the prose counts from the harness header
    - Context:
      - Files: `tests/checkbox-grammar.bats:1-32` (header), `:70` (a count inside the fixture body)
    - Objective: The roster is asserted in exactly one place — the library — and prose stops stating how many consumers there are, while the record of the wrong counts survives.
    - ToDo: rewrite the header so it carries no present-tense count and no inline consumer list; point at `tests/lib/checkbox-consumers.sh` by name as the roster's home. There are three offenders and the authored test catches only two — **line 12, `SIX OF THE SEVEN READ THE GRAMMAR`, is a present-tense count in a shape the predicate does not match and must be removed by hand**; keep what it actually says (one consumer writes, the rest read, and the writer belongs further inside the roster rather than outside it) without the arithmetic. Line 5 (`the SEVEN checkbox consumers` plus the inline list) is caught by the test. Line 70 is fixture body — `Shared mixed-grammar fixture for the four checkbox consumers.` — drop the count word rather than updating it to ten, or the fixture becomes the next thing to go stale. Keep lines 20-27, the history of the four earlier wrong counts, intact: it is the argument for the derivation, not an instance of the defect — and add one sentence saying the count is now derived and the history is preserved deliberately. Keep the mixed-fixture totals block: those are fixture truth, not a roster count.
    - Tests: Unit · `tests/consumer-roster.bats` — no file under `tests/` or `scripts/` states a cardinal count of grammar consumers in prose, and the record of the earlier wrong enumerations survives the edit
    - Validation: `bats tests/consumer-roster.bats` green; `command grep -niE '\b(four|five|six|seven|eight|nine|ten)\b[^.]*consumer' tests/*.bats scripts/*.sh` returns only lines inside the preserved history block
    - Requirements: R1.4

  - [x] 1.4 - Commit
    - Validation: `bats tests/consumer-roster.bats` and `bats tests/checkbox-grammar.bats` both green; `shellcheck -S warning tests/lib/*.sh scripts/*.sh` clean
    - Commit: "test(017): the consumer roster becomes data the suite derives"

- [x] 2 - Every consumer is compared, including the three now unpinned
  - _Complexity: Moderate | Tests: Unit | Risks: two of the three write to disk — every run is against a mktemp copy, and the shared fixture is asserted byte-identical afterwards | Dependencies: Task 1_
  - Objective: Each declared consumer is compared against the same mixed fixture on its own output surface, and registration alone cannot substitute for comparison.

  - [x] 2.1 - `archive-story.sh` agrees with the fixture
    - Context:
      - Files: `scripts/archive-story.sh:433-455` (`census_tasks` — the flat box-character split), `:248` (the emitted `tasks` object)
    - Objective: archive-story's reading of the mixed fixture matches the shared truth on the fields where the two aggregations coincide.
    - ToDo: run `archive-story.sh` against a `mktemp -d` copy of the mixed fixture and assert on the emitted JSON `.tasks` object — `total == 5` and `open == 1`, identical to the shared truth, and `closed + deferred == 4`, the settled count. Do **not** assert `closed == 3`: `census_tasks` splits on the box character alone and never reads the qualifier, so terminal `[~] 1.3` is counted deferred by design and the script reports `closed 2, deferred 2`. State that mapping inside the case, so the next reader does not "correct" it into an equality and demand a change to an aggregation archive-story documents on purpose. archive refuses to move a story that still holds an open box; the refusal path emits the same JSON (`moved: false` plus a `reason`), so assert `.tasks` only and never `moved` — the refusal is not this harness's subject. Assert the shared fixture is byte-identical after the run.
    - Tests: Unit · `tests/checkbox-grammar.bats` — archive-story's `tasks` object on the mixed fixture: total 5 and open 1 identical to the shared truth, closed/deferred/open disjoint and summing to total, settled boxes = 4; run against a copy, shared fixture byte-identical after
    - Validation: `bats tests/checkbox-grammar.bats` green with one case more than before; the shared fixture unmodified after the run
    - Requirements: R2.1, R2.4

  - [x] 2.2 - `epic-index.sh` agrees with the fixture
    - Context:
      - Files: `scripts/epic-index.sh:388-416` (the census and its deferred/terminal split), `:369` (the aggregation described from the outside)
    - Objective: epic-index's census maps onto the shared truth, given that it emits no `open` field and folds a terminal `[~]` into `done`.
    - ToDo: run `epic-index.sh` — read-only, takes `--epic-dir`, so no copy is required for safety, though the fixture must still be byte-identical afterwards — and parse its rendered progress cell back to numbers; assert total 5, done 3 and deferred 1, and that `total − done − deferred` equals the shared open count of 1. epic-index folds a terminal `[~]` into `done`, the opposite fold from archive-story's, so state both mappings side by side in the case: one fixture, three consumers, three different-but-consistent aggregations. That comment is the point of the case as much as the assertion is — it is what stops the next reader from flattening three deliberate aggregations into one.
    - Tests: Unit · `tests/checkbox-grammar.bats` — epic-index's rendered progress cell parsed back to total 5, done 3, deferred 1, with `total − done − deferred` = the shared open count of 1; run against a copy, shared fixture byte-identical after
    - Validation: `bats tests/checkbox-grammar.bats` green with one case more than 2.1 left it; the shared fixture unmodified
    - Requirements: R2.2

  - [x] 2.3 - `supersede-story.sh` agrees with the fixture
    - Context:
      - Files: `scripts/supersede-story.sh:386-430` (`SUBTASK_RE`, `DEFERRED_RE`, and the open-or-deferred collection), `tests/supersede-story.bats` (conventions for driving it — it needs `--by` and `--rationale`)
    - Objective: The set of boxes supersede carries into the successor story equals the shared open-or-deferred set, and no others.
    - ToDo: run `supersede-story.sh` against a `mktemp -d` copy with the required `--by` and `--rationale`, and assert on both surfaces — the banner remap rows and the boxes closed as `superseded-by` — that the carried set is exactly `{1.4, 1.5}`: the open box and the deferred one. `[x]` 1.1 and 1.2 and terminal `[~]` 1.3 must be absent from both surfaces. Assert as a **set**, not as a count: a count would pass if the wrong two boxes were carried, which is precisely the drift this case exists to catch. Assert the shared fixture is byte-identical after the run.
    - Tests: Unit · `tests/checkbox-grammar.bats` — supersede carries the SET {1.4, 1.5} on both surfaces (banner remap rows and the boxes closed as superseded-by), settled boxes 1.1/1.2/1.3 untouched; run against a copy, shared fixture byte-identical after
    - Validation: `bats tests/checkbox-grammar.bats` green with one case more than 2.2 left it; the shared fixture unmodified
    - Requirements: R2.3, R2.4

  - [x] 2.4 - Close the loop: a declared consumer with no comparison is a failure
    - Context:
      - Files: `tests/checkbox-grammar.bats` (the `@test` titles that name each compared consumer), `tests/lib/checkbox-consumers.sh` (the declared roster, from 1.1)
    - Objective: Every name in the declared roster is compared by at least one case in the harness, so adding a name cannot silence the derivation without pinning the script.
    - ToDo: source `tests/lib/checkbox-consumers.sh` from `tests/checkbox-grammar.bats` and add the closure case — every name in `CHECKBOX_CONSUMERS` is named by at least one `@test` title in this file, and the failure lists the uncompared names rather than reporting a bare count. Match on the basename with `.sh` stripped: titles read `archive-story`, not `archive-story.sh`. Measured today the seven already-pinned consumers each appear in a title and the three from 2.1-2.3 appear in none, so this case is red until those three land — that ordering is deliberate, and it is why this sub-task sits at the end of the group rather than in Task 1 with the rest of the roster work.
    - Tests: Unit · `tests/checkbox-grammar.bats` — every name in the declared roster is named by at least one `@test` title in the harness; missing consumers are listed by name
    - Validation: `bats tests/checkbox-grammar.bats` green; the case verified red by removing one of the three new comparison cases from a `mktemp -d` copy of the file
    - Requirements: R1.5, R2.5

  - [x] 2.5 - Commit
    - Validation: `bats tests/` fully green; `git diff` on `tests/checkbox-grammar.bats` shows the four new cases plus the library source line and nothing else — no existing assertion changed, both R5.1 byte-identical goldens untouched
    - Commit: "test(017): the three unpinned consumers join the harness, and the roster closes its loop"

- [x] 3 - Story 016's plan states only facts that hold
  - _Complexity: Simple | Tests: None | Risks: the target lives under `.epic/`, which is gitignored — `grep -r` skips it in silence, and no committed test can pin it | Dependencies: None_
  - Objective: The two stale citations and the unrecorded follow-up commit in story 016's plan are repaired where they are stated. This group produces nothing committable — its only file is gitignored — so it carries no Commit field.

  - [x] 3.1 - Cite by name and record the follow-up commit
    - Context:
      - Files: `.epic/stories/016-close-010-audit-gaps/tasks.md:44` (the two stale citations), `tests/checkbox-grammar.bats` (where the cited content now lives — the rule moved to line 24, the totals to 29-31)
    - Objective: Story 016's plan carries no citation to a line range that no longer holds the cited content, and names every commit anchored to it.
    - ToDo: in story 016's plan at line 44, replace `tests/checkbox-grammar.bats:1-20` and `tests/checkbox-grammar.bats:17-19` with name-based citations — the header block, and the mixed-fixture totals block — since 016's own header edit is what moved them. Change the citations only; every other clause of that line stays verbatim. Then record the follow-up commit: add a group-level line naming `eff96c2` as a post-close correction that no sub-task planned, so `anchored_commits: 2` has a counterpart in the artifact. Do **not** add a checkbox for it — a new box would change the census of a story already stamped `done`, and `close-subtask.sh` would then have a story with open work marked complete. Do not renumber anything. Use `command grep` for every check against this file: plain `grep` honours `.gitignore` and returns nothing for `.epic/` without erroring, so a verification run with plain `grep` would look clean whether or not the edit landed.
    - Tests: None — the target artifact lives under `.epic/`, which is gitignored, so no committed test can pin a one-time repair of an uncommitted file; it is verified by validation command instead
    - Validation: `bash scripts/validate-story.sh .epic/stories/016-close-010-audit-gaps` reports `status: pass` with 0 errors; `command grep -n 'checkbox-grammar.bats:1-20\|checkbox-grammar.bats:17-19' .epic/stories/016-close-010-audit-gaps/tasks.md` returns nothing; `command grep -c 'eff96c2' .epic/stories/016-close-010-audit-gaps/tasks.md` returns at least 1
    - Requirements: R3.1, R3.2, R3.3, R3.4

## Quality Gates

- [x] All acceptance criteria validated (every requirement traced to a sub-task, and every sub-task's claim measured by a command or a case)
- [x] All task validations pass
- [x] All tests written and passing (`bats tests/` green; the seven existing consumer comparisons and both R5.1 byte-identical goldens untouched)
- [x] Code integrated (`tests/lib/checkbox-consumers.sh` is sourced by both suites — the roster has one definition and no orphan copy)
- [x] Error handling implemented (every file read in the library handles a file that exists but does not open; `checkbox_roster_diff` names each discrepancy rather than returning a bare exit code)
