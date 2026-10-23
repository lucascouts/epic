---
story: executor-owns-marking
type: feature
scale: full
status: archived
version: 1
created: 2026-08-16
---

# Story - Executor-Owns-Marking (Script-Mediated Sub-task Closing)

## Introduction

Closing a finished sub-task today costs model output in the most expensive
context there is: the orchestrator hand-edits `tasks.md`, re-reads it for the
census, and hand-runs the status transition — 100% of the corpus's 1,316 box
markings were written this way (2026-07-23 analysis). This story gives the
plugin one deterministic writer for that whole tail (`close-subtask.sh`) and
closes the enforcement gap on the commit anchor that the git-aware lifecycle
(story 006) reads integration from. Derived from `design.md` (design-first).

## Requirements

### R1. One sanctioned writer for closing boxes

#### Acceptance Criteria

- R1.1: WHEN the orchestrator records a completed sub-task THE SYSTEM SHALL
  write the `[x]` box through `close-subtask.sh`, replacing the model-authored
  edit with one script invocation
- R1.2: WHEN a box is closed without the work being done THE SYSTEM SHALL
  accept exactly the four-qualifier grammar (`deferred:` / `waived:` / `n-a:` /
  `superseded-by:NNN`) and write the qualifier on the same line as the box
- R1.3: WHEN the requested box does not exist, or is already closed, THE SYSTEM
  SHALL refuse with exit 1, name the reason, and write nothing
- R1.4: WHEN the target story lives under `.epic/archive/` THE SYSTEM SHALL
  refuse without writing
- R1.5: WHEN a close succeeds THE SYSTEM SHALL emit exactly one JSON object on
  stdout carrying the box written, the census, the status transition applied,
  and the embedded validation verdict
- R1.6: WHEN rewriting `tasks.md` THE SYSTEM SHALL preserve the file's line
  endings and leave the file unchanged on any mid-write failure
- R1.7: WHEN a close leaves a task group with no open children THE SYSTEM SHALL
  close the parent group header in the same atomic write — header and children
  are never inconsistent between invocations

### R2. Marking and status are one transaction

#### Acceptance Criteria

- R2.1: WHEN a close changes the completion census THE SYSTEM SHALL apply the
  status transition rules and stamp `status:` in every story artifact carrying
  frontmatter, in the same invocation
- R2.2: WHEN a close writes `done` THE SYSTEM SHALL report that transition in
  its output so Run mode can make the archive offer on its existing trigger
- R2.3: WHEN a close succeeds THE SYSTEM SHALL invoke story validation itself
  and embed the verdict — a Bash write fires no PostToolUse hook, so the
  per-marking validation must not depend on one
- R2.4: IF the embedded validation reports errors THEN THE SYSTEM SHALL keep
  the marking as written and surface the errors — the box state records what
  happened; correction is a follow-up action, not a rollback

### R3. The orchestrator/executor contract moves, the prohibitions stay

#### Acceptance Criteria

- R3.1: WHEN an executor finishes a sub-task THE SYSTEM SHALL include in its
  report a machine-liftable closing block: sub-task id, outcome (`done`,
  `close-tilde` with qualifier and reason, or `failed`), and the pre-authored
  commit message it validated against
- R3.2: THE SYSTEM SHALL retain the executor prohibitions on marking boxes and
  running `git commit`, restated with the script-mediated rationale in the
  executor definition AND every duplicated documentation surface (the run-mode
  Executor prompt template, the SKILL persona tables, ARCHITECTURE.md,
  README.md, the SKILL lifecycle-status writers list)
- R3.3: WHILE a parallel batch run is active THE SYSTEM SHALL close boxes only
  in the main tree, sequentially, after each worktree merge — never inside a
  worktree copy of `tasks.md`
- R3.4: WHEN a task group's work is committed THE SYSTEM SHALL execute the
  commit orchestrator-side, post-merge, using the group's pre-authored Commit
  message verbatim

### R4. The commit anchor is checked, not just recommended

#### Acceptance Criteria

- R4.1: WHEN validation reads a `Commit` field whose message does not carry the
  story anchor (`type(NNN):` with this story's number) THE SYSTEM SHALL warn,
  naming the expected shape and the field's current text
- R4.2: WHEN a story in state `done` or `validated` has zero anchored commits
  reachable from HEAD THE SYSTEM SHALL warn that integration detection cannot
  see the story's work
- R4.3: WHEN counting anchored commits THE SYSTEM SHALL match the anchor only
  as a delimited token, reusing story 006's rules — a bare story number in a
  subject SHALL NOT count
- R4.4: WHEN `story-git-status.sh` gains the anchored-commit count THE SYSTEM
  SHALL keep every existing output field byte-compatible on an unchanged
  repository — the addition is additive only

## Success Metrics

- A dogfood run of one story completes with zero model-authored box edits in
  the orchestrator transcript (every marking is a `close-subtask.sh` call)
- The anchor lint fires on a fixture Commit field lacking `(NNN)` and stays
  quiet on a conforming one; the reverse check counts 006's fixture shapes
  correctly
- Marking cost per sub-task drops from a model-authored Edit + re-read to one
  tool call returning the census

## Constraints

- House script contract: one JSON object on stdout, diagnostics on stderr,
  exit 0/1/2; standalone script (no shared lib) per the "readers move together"
  convention
- All new checks are warnings — the lifecycle's non-blocking decision (story
  006) governs here too
- Test harness is `bats` (local checkout); no new runtime dependencies beyond
  `bash`, `git`, `jq`

## Out of Scope

- Executors marking boxes inside worktrees (rejected at clarify — merge
  conflicts on tasks.md)
- Changing the Commit field's shape from sub-task to group field (story 015 of
  this wave; the R4.1 lint reads either shape)
- Making any anchor check an error or an archive blocker
- Mirroring sub-tasks into the session task list (separate maintenance story)
