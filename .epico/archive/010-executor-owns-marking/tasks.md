---
story: executor-owns-marking
type: feature
scale: full
status: archived
version: 1
created: 2026-08-16
---

# Implementation Plan - Executor-Owns-Marking

## Overview

Build the closing script first (it is the contract everything else consumes),
then make marking-and-status one transaction inside it, then the anchor checks,
and only then rewrite the run-mode/executor prose to point at the finished
mechanism. Prose last is deliberate: the references must describe a script that
already exists and passes its suite, never the other way around.

## Task List

- [x] 1 - close-subtask.sh: skeleton, marking, refusals
  - _Complexity: Moderate | Tests: Unit | Risks: regex drift vs the five census readers — copy the shared grammar verbatim | Dependencies: None_
  - Objective: The one sanctioned writer exists, marks exactly one box per call, and refuses everything it must.

  - [x] 1.1 - Script skeleton: args, story resolution, refusal arms
    - Context:
      - Files: `scripts/archive-story.sh` (house contract: state vars + single `emit_report`, exit 0/1/2), `scripts/supersede-story.sh` (story resolution)
    - Objective: `close-subtask.sh <NNN|dir> <N.N> [--tilde "<qualifier>: <reason>"]` parses, resolves the story, and refuses archived targets.
    - ToDo: `set -euo pipefail`; resolve NNN via `.epic/stories/NNN-*` glob; exit 2 on usage errors with the synopsis on stderr; exit 1 + reason when the story is missing or under `.epic/archive/` (R1.4); on refusal write nothing — assert no tmp file remains.
    - Tests: Unit · `tests/close-subtask.bats` — no/partial args and `--help` exit 2 with the synopsis on stderr; missing story exits 1; archived story exits 1 with tasks.md byte-identical; a refusal leaves no file behind, not even a tmp
    - Validation: script refuses an archived story and a missing story with exit 1; `--help`/bad args exit 2
    - Requirements: R1.4

  - [x] 1.2 - Box locate-and-mark with the shared grammar, atomically
    - Context:
      - Files: `scripts/archive-story.sh:433-540` (census grammar + qualifier token regexes), `scripts/supersede-story.sh:464-483` (`rewrite_file` atomic pattern)
    - Objective: `[x]` and `[~](qualifier: reason)` writes land atomically; wrong targets are refusals, not writes.
    - ToDo: locate the box by its `N.N -` (or `N -`, or Quality-Gate text-prefix) label using the shared `^[[:space:]]*- \[([ x~])\]` grammar; mark `[x]`, or `[~]` appending `(qualifier: reason)` same-line after validating the qualifier against the four-form grammar (refuse others, exit 1); refuse a box already `[x]`/`[~]` naming its current state (R1.3); when the close leaves the parent group with no open children, close the group header in the same rewrite — header and children are never inconsistent between invocations (R1.7, the validator errors on that pair); rewrite via the tmp-file+`mv -f` pattern preserving EOL (R1.6); reason text flows through the rewriter only — never into a shell command or pattern.
    - Tests: Unit · `tests/close-subtask.bats` — marks `[x]` by `N.N` and reports `{task, box}`; bare-NNN story resolution from the project root; tilde-marks with each of the four qualifiers same-line; refuses unknown box, already-`[x]` (naming it), already-`[~]`, and a qualifier outside the grammar — all writing nothing; marks a group box by bare `N` without touching `N.N`; marks a Quality-Gate box by `gate:` text-prefix; CRLF fixture round-trips byte-identical outside the marked line; closing the last open child closes the group header in the same write (two-line diff vs snapshot); an open sibling leaves the header open; children closed via terminal `[~]` close the header too (R1.7)
    - Validation: bats: mark, tilde-mark ×4 qualifiers, refuse unknown/closed/bad-qualifier, group-header auto-close on last child, CRLF fixture round-trips byte-identical outside the marked line
    - Requirements: R1.1, R1.2, R1.3, R1.6, R1.7

  - [x] 1.3 - Commit
    - Validation: All tests from 1.1 and 1.2 pass
    - Commit: "feat(010): add close-subtask.sh — sanctioned box writer with refusal arms"

- [x] 2 - Marking and status as one transaction
  - _Complexity: High | Tests: Unit | Risks: transition rules must match run-mode's 4-rule census exactly — fixture-pin them | Dependencies: Task 1_
  - Objective: A successful close carries census, status stamp, and embedded validation in one invocation and one JSON object.

  - [x] 2.1 - Census + status transition + frontmatter stamping
    - Context:
      - Files: `references/run-mode.md:126-151` (the 4 transition rules), `scripts/supersede-story.sh:725-790` (`write_status_pair`), `scripts/archive-story.sh:307-326` (frontmatter parsing, CRLF-tolerant)
    - Objective: The status a human never types (story 004's contract) is written by this script at the moment the census changes.
    - ToDo: after the box write, run the census; apply the transition rules; stamp `status:` in every artifact with frontmatter (tasks.md always; story.md/design.md when present) via the `write_status_pair` pattern; record `{from, to}` or `null` when unchanged (R2.1); `done` written must be visible to the caller for the archive offer (R2.2).
    - Tests: Unit · `tests/close-subtask-transaction.bats` — last-box close flips `in-progress`→`done` in all three artifacts reporting `{from, to}`; deferred-only close never writes `done` (rule 1 vs deferred); terminal tilde close of the last box does write `done`; first marking of a `draft` story and of a legacy no-status story writes `in-progress` everywhere; a close leaving open boxes writes no transition (`null`); an open Quality-Gate box blocks `done` — the census spans the gates; census counts in the JSON match the boxes as they now stand
    - Validation: bats on 004-shaped fixtures: closing the last box flips `in-progress`→`done` in all artifacts; a deferred-only close never writes `done`
    - Requirements: R2.1, R2.2

  - [x] 2.2 - Self-validation + the one JSON report
    - Context:
      - Files: `scripts/validate-story.sh` (invocation + JSON verdict shape), `scripts/archive-story.sh:150-170` (`_json_escape_table` — full C0 escape set)
    - Objective: The per-marking validation the Write-hook used to guarantee survives the move to Bash writes, inside the script's own output.
    - ToDo: invoke `validate-story.sh` on the story (guard with `|| rc=$?` — never let set -e eat the verdict: the 02/07 fail-open bug is the anti-pattern); embed `{errors, warnings, status}`; emit the single stdout JSON `{story, task, box, qualifier, census, status_written, validate}` escaping every file-derived string through the full escape table (R1.5); validation errors do not roll back the marking (R2.4).
    - Tests: Unit · `tests/close-subtask-transaction.bats` — one JSON object with the full seven-key set parses under `jq empty` with a hostile reason (quotes + backslash, and a separate embedded-newline case); embedded validate verdict `{errors, warnings, status}` present and clean on a clean story; a calibrated validation error (`Requirements:`-less standard tasks) still exits 0, shows the box marked in the file and `validate.errors >= 1`
    - Validation: bats: JSON parses under `jq empty` with a hostile qualifier reason (quotes, newline); a fixture with a validation error still shows the box marked and `validate.errors > 0`
    - Requirements: R1.5, R2.3, R2.4

  - [x] 2.3 - Commit
    - Validation: All tests from 2.1 and 2.2 pass
    - Commit: "feat(010): close-subtask carries census, status stamp and embedded validation"

- [x] 3 - Anchor enforcement: authoring lint + reverse check
  - _Complexity: Moderate | Tests: Unit | Risks: 015 changes the Commit field's shape — lint reads field text, not checkbox position | Dependencies: None (parallel-safe with Task 1-2)_
  - Objective: The anchor `story-git-status.sh` needs stops being unenforced advice.

  - [x] 3.1 - Commit-field anchor lint in validate-story.sh
    - Context:
      - Files: `scripts/validate-story.sh` (warning emission patterns), `references/tasks.md:206-212` (Commit field, both shapes)
    - Objective: A Commit message that integration detection cannot see draws a warning at authoring time.
    - ToDo: for each `Commit:` field value (sub-task or inline — match the field, not the box), warn unless the subject matches `type(0*NNN):` for this story's number (R4.1); zero-padded and unpadded both accepted; warning text names the expected shape and the offending value; never an error.
    - Tests: Unit · `tests/anchor-lint.bats` — unanchored `feat: …` warns naming `(010)` and the offending value while `errors` stays 0 and exit stays 0; anchored `feat(010):` and unpadded `fix(10):` stay quiet (PIN cases on a calibrated zero-warning fixture); the field on a Commit sub-task is matched too, not the checkbox shape; a group-level `- Commit:` field on the parent task body (story 015's shape) warns when unanchored and stays quiet when anchored (PIN, calibrated group fixture)
    - Validation: bats: fixture with `feat: msg` warns naming `feat(010):`; `feat(010): msg` and `fix(10): msg` stay quiet
    - Requirements: R4.1

  - [x] 3.2 - `anchored_commits` in story-git-status.sh + validate-mode consumption
    - Context:
      - Files: `scripts/story-git-status.sh:774-790` (`MSG_CONV_RE`/`MSG_SLUG_RE` token rules — the single home of the anchor regexes), `references/validate-mode.md` (warning surfacing)
    - Objective: A done story whose commits are invisible to integration detection says so at validate time.
    - ToDo: add `anchored_commits` — count of subjects reachable from HEAD matching the existing token rules (bare number never counts, R4.3); additive field only — existing fields byte-compatible on an unchanged repo (R4.4); validate-mode.md gains the consumption rule: `done|validated` + `anchored_commits == 0` → warning (R4.2), non-blocking — AND the no-double-fire precedence: `anchored_commits == 0` wins over 006's `integrated=false` warning, which fires only when anchored commits exist; `integrated: null` silences both (design §4).
    - Tests: Unit · `tests/anchor-lint.bats` — conventional (padded + unpadded) and slug subjects count 3 while a bare `story 10` and a `1010` substring count nothing; the count reads HEAD, not main (2 on the unmerged story branch, 0 back on main); existing fields keep their values beside the additive field (PIN-verified conjuncts); `references/validate-mode.md` names the `anchored_commits` consumption rule (doc contract) and settles the no-double-fire precedence — `anchored_commits == 0` wins, `integrated=false` fires only when anchored commits exist but none reached main, `integrated: null` silences both (flattened-text doc contract)
    - Validation: bats fixture repo: anchored subject counts, slug subject counts, bare `10` does not; existing story-git-status.bats cases untouched and green
    - Requirements: R4.2, R4.3, R4.4

  - [x] 3.3 - Commit
    - Validation: All tests from 3.1 and 3.2 pass
    - Commit: "feat(010): enforce the commit anchor — authoring lint and reverse check"

- [x] 4 - Contract prose: run-mode and executor point at the mechanism
  - _Complexity: Simple | Tests: None | Risks: stale cross-references — self-review checklist item on citation anchors | Dependencies: Task 1, Task 2_
  - Objective: The references describe the shipped script; the prohibitions stay, now with their reason.

  - [x] 4.1 - run-mode.md: step 7 invokes the script; parallel closes serialize post-merge
    - Context:
      - Files: `references/run-mode.md` (step 7 at :116, transition census :126-151, worktree merge :540-556, archive-offer trigger :583)
    - Objective: The orchestrator's marking step becomes one tool call; worktree copies of tasks.md are never written.
    - ToDo: rewrite step 7 to invoke `close-subtask.sh` with the executor report's closing block; census/status read from the returned JSON (no re-read); a `failed` outcome makes no close call — it routes through the existing step-6 FAIL path; parallel section: closes only in the main tree, sequentially, after each merge (R3.3); commit execution stays orchestrator-side post-merge with the pre-authored message verbatim (R3.4); archive offer keyed on `status_written.to == "done"` — same trigger, new source; Trivial-inline path closes via the same script; state the resume semantics — an "already closed" refusal is benign confirmation on a resumed run; warn against interleaving closes across stories mid-run (the hook-task-completed most-recently-modified gotcha); note that refine-mode keeps orchestrator-side Edits for its own census (design §5).
    - Validation: `command grep -n 'close-subtask' references/run-mode.md` hits step 7, parallel section, and inline path; no remaining instruction for the orchestrator to edit a box by hand
    - Requirements: R1.1, R3.3, R3.4

  - [x] 4.2 - executor.md: machine-liftable closing block; prohibitions restated
    - Context:
      - Files: `agents/executor.md` (report format, prohibitions at :117-118)
    - Objective: The executor's report carries exactly what the orchestrator forwards to the script.
    - ToDo: add the closing block to the step-6 report spec — sub-task id, outcome (`done` | `close-tilde` + qualifier + reason | `failed`), pre-authored commit message validated against (R3.1); restate the no-marking/no-commit prohibitions with the script-mediated rationale (R3.2) — and land the same change in EVERY duplicated surface of the drift set (design §5): the duplicated Executor prompt template inside `references/run-mode.md`, the SKILL persona tables AND the SKILL lifecycle-status writers list (orchestrator → script), `ARCHITECTURE.md`'s Executor protocol, `README.md`'s sub-agent table.
    - Validation: `command grep -n 'closing block\|close-tilde' agents/executor.md references/run-mode.md` shows the spec in both copies; prohibitions still present; `command grep -n 'close-subtask' skills/epic/SKILL.md ARCHITECTURE.md README.md` hits the writers list and both doc tables
    - Requirements: R3.1, R3.2

  - [x] 4.3 - Commit
    - Validation: All tests still green; prose cross-references resolve
    - Commit: "docs(010): run-mode and executor contracts route closing through the script"

- [x] 5 - Interface verification: report → close → verdict round-trip
  - _Complexity: Moderate | Tests: Integration | Risks: None | Dependencies: Task 1, Task 2, Task 4_
  - Objective: The producer→consumer contract (executor closing block → script args → JSON verdict) is verified as one flow before the story closes.

  - [x] 5.1 - Scripted mini-run over a fixture story
    - Context:
      - Files: `tests/` (fixture conventions: mktemp + teardown), `.epic/archive/004-*/tasks.md` (census fixture shapes)
    - Objective: One test drives the whole chain the way run-mode will.
    - ToDo: fixture story with 2 sub-tasks; simulate the executor closing block for each (one `done`, one `close-tilde deferred:`); invoke the script per block; assert together: box states in the diff, `status:` stamped to the expected state, embedded validate verdict, and JSON fields consumed exactly as run-mode's new step 7 describes them.
    - Tests: Integration · `tests/close-subtask-roundtrip.bats` — executor closing blocks (one `done`, one `close-tilde deferred:` with qualifier + reason) are lifted into script arguments exactly as step 7 will lift them; census, `status_written` and embedded verdict read from the returned JSON only; box states and `status:` stamp then verified in the artifacts; a both-done variant flips `done` and fires the `status_written.to == "done"` archive trigger
    - Validation: the new integration bats file passes; full suite green
    - Requirements: R1.5, R2.1, R3.1
    - Commit: "test(010): round-trip integration — executor report to close verdict"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R4.4 each covered by a passing test or a grep-verifiable prose change)
- [x] All task validations pass
- [x] All tests written and passing (full bats suite, existing files untouched and green)
- [x] Code integrated (no orphaned implementations — run-mode step 7 actually points at the shipped script)
- [x] Error handling implemented (every refusal arm exercised; no fail-open path under `set -euo pipefail`)
