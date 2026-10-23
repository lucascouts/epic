---
story: story-state-machine-checkbox-grammar
type: feature
scale: full
version: 2
created: 2026-08-02
last-refined: 2026-08-04
status: archived
history:
  - v1: Initial story
  - v2: Reopen transition (R1.7, R1.8), dependency-satisfaction criterion (R3.6), and the R1.2/R1.4 preconditions folded in from the deviation register
---

# Story - Story State Machine & Checkbox Grammar

## Introduction

Epic stories today have no machine-readable lifecycle state (the `status:` field is unspecified, hand-invented in the field, and lies when present) and a binary checkbox grammar that cannot express "resolved without being executed" — the two gaps behind the corpus's #1 false signal (eternally-"partial" stories) and dead status metadata. This story introduces a 6-value `status:` enum written exclusively by the engine at fixed transition points, and a third checkbox state `[~]` with a structured qualifier, updated atomically across every parser that reads checkboxes.

## Related Stories

- Related: `.epic/stories/005-archive-in-the-flow/story.md` — consumes the completion semantics and the `archived` transition
- Related: `.epic/stories/006-git-aware-lifecycle/story.md` — consumes the `superseded` state and `superseded-by:` qualifier

## Requirements

### R1. Engine-Written Status Transitions

**User Story:** As an Epic user, I want the story's lifecycle state recorded by the engine itself, so that the state can never drift from what actually happened.

#### Acceptance Criteria

- R1.1: WHEN Create mode writes a story's final artifacts THE SYSTEM SHALL include `status: draft` in the frontmatter of every artifact written
- R1.2: WHEN a sub-task marking leaves at least one `[ ]` or deferred `[~]` remaining and the story's `status` is absent or `draft` THE SYSTEM SHALL update the story's `status` to `in-progress`
- R1.3: WHEN a sub-task marking leaves the story with no `[ ]` checkbox remaining and no deferred `[~]` THE SYSTEM SHALL update the story's `status` to `done`
- R1.4: WHEN Validate mode completes with a passing verdict and no `[ ]` checkbox remains THE SYSTEM SHALL update the story's `status` to `validated`
- R1.5: WHEN the engine updates `status` THE SYSTEM SHALL write the same value to every artifact of the story that carries frontmatter
- R1.6: WHEN Run mode performs a status transition on a legacy story with no `status:` field THE SYSTEM SHALL add the field with the observed state without inventing any prior state
- R1.7: WHEN a status transition point censuses a story whose `status` is `done` or `validated` and finds at least one `[ ]` checkbox THE SYSTEM SHALL update the story's `status` to `in-progress`
- R1.8: WHEN Refine mode writes a story's tasks.md THE SYSTEM SHALL apply the status transition rules to the resulting checkbox census

### R2. Status Validation

**User Story:** As an Epic user, I want invalid or lying status values surfaced, so that hand-edited state cannot silently corrupt the lifecycle.

#### Acceptance Criteria

- R2.1: WHEN validation runs on a story whose `status` value is outside the enum (`draft`, `in-progress`, `done`, `validated`, `superseded`, `archived`) THE SYSTEM SHALL report an error naming the invalid value and the enum
- R2.2: WHERE a story has no `status:` field THE SYSTEM SHALL complete validation with zero status-related errors or warnings
- R2.3: IF `status` is `done` or `validated` while at least one `[ ]` checkbox remains THEN THE SYSTEM SHALL report a warning that the status is ahead of the checkboxes
- R2.4: IF artifacts of the same story carry different `status` values THEN THE SYSTEM SHALL report a warning naming the divergent files

### R3. Third Checkbox State `[~]`

**User Story:** As an Epic user, I want a sanctioned way to close a box as "resolved without execution", so that waived gates and externally-blocked work stop rendering stories eternally partial.

#### Acceptance Criteria

- R3.1: WHEN a checkbox line uses `[~]` followed by a same-line qualifier among `deferred:`, `waived:`, `n-a:`, `superseded-by:` THE SYSTEM SHALL accept the line as a valid closed-state checkbox
- R3.2: WHEN a `[~]` checkbox has no recognized same-line qualifier THE SYSTEM SHALL report a validation error listing the four valid qualifier forms
- R3.3: WHEN every checkbox of a story is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`) THE SYSTEM SHALL treat the story as complete
- R3.4: WHERE the only non-`[x]` checkboxes are `[~] (deferred: …)` THE SYSTEM SHALL report the story's computed condition as `done-except-external` with the count of deferred items
- R3.5: WHEN progress is rendered for a story containing `[~]` boxes THE SYSTEM SHALL count closed boxes as `[x]` plus terminal `[~]` and report deferred boxes separately
- R3.6: WHERE a task's `Dependencies` field names another task THE SYSTEM SHALL treat that dependency as satisfied only when every one of its checkboxes is `[x]` or terminal `[~]`

### R4. Parser Consistency (Atomic Grammar)

**User Story:** As the plugin maintainer, I want every checkbox-reading tool to agree on the counts, so that the false-clean/false-orphan class fixed in e890d02 cannot reopen through grammar drift.

#### Acceptance Criteria

- R4.1: WHEN the same tasks.md is processed by the validation, cross-reference, task-completion-hook and staleness tools THE SYSTEM SHALL report mutually consistent totals of open, closed and deferred checkboxes
- R4.2: WHEN a `[~]` sub-task heading carries a `Requirements:` field THE SYSTEM SHALL keep attributing those R-numbers to that sub-task in the traceability mapping
- R4.3: WHEN staleness is evaluated THE SYSTEM SHALL treat only `[ ]` checkboxes as pending work

### R5. Legacy Compatibility

**User Story:** As a user with 26 pre-existing projects, I want old stories untouched by the new grammar, so that no legacy session is blocked or renumbered.

#### Acceptance Criteria

- R5.1: WHEN validation and cross-reference run on a legacy story (no `status:`, no `[~]`) THE SYSTEM SHALL produce output identical to the pre-change behavior for that story

## Success Metrics

- The 4 checkbox-consuming scripts agree on counts for a shared mixed fixture (cross-regression test green)
- A story with only waived/n-a gates open reports `complete`, not `partial`
- Legacy fixture byte-compat test green

## Constraints

- Engine status writes use `Edit` (the PostToolUse validate hook matches `Write` only — engine writes must not re-trigger it)
- Deployment order inside the task plan: parsers/validators learn `[~]` and the enum BEFORE any engine path writes them (`hook-task-completed.sh` blocks with exit 2 otherwise)
- Bash 5.3 + `set -u`: any new associative-array counting uses manual counters (`REQ_KEYS` pattern)
- Absence of `status:` is never an error or warning (R2.2) — 340+ legacy stories exist

## Out of Scope

- A computed `blocked` condition (no acceptance criterion here; future story)

- `archived` and `superseded` transition implementations (owned by stories 005 and 006; this story only defines the enum values)
- The computed `integrated` flag (story 006)
- A migration command for legacy stories (`epic migrate`, wave 3)
- Any change to the `Requirements:`-field traceability model itself
