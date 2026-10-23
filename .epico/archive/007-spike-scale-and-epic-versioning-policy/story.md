---
story: spike-scale-and-epic-versioning-policy
type: feature
scale: full
status: archived
version: 2
created: 2026-08-02
last-refined: 2026-08-09
history:
  - v1: Initial story
  - v2: Task 5 — close the validate-007 findings (spike exemption in Run, four unpinned branches, honest gates and complete registers). No requirement changed.
---

# Story - Spike Scale & .epic Versioning Policy

## Introduction

Two capabilities that legalize proven field behavior. A `spike` scale gives exploratory, tasks-only work a sanctioned shape with a mandatory Verdict — the corpus's heaviest user ran 15+ off-contract probe dirs, and seeds died waiting for refines that never came. And an explicit `.epic` versioning policy ends the gitignore war that destroyed 54 stories in one project: the init wizard asks a first-class question (recommended: version the `.md` artifacts, ignore `.draft/`), records the choice, and a lint surfaces contradictions between the declared policy and what git actually tracks. Validation also becomes scale-aware, closing the hole that let `scale: medium` ship unnoticed.

## Related Stories

- Related: `.epic/stories/004-story-state-machine-checkbox-grammar/story.md` — engine status transitions apply to spikes
- Related: `.epic/stories/005-archive-in-the-flow/story.md` — terminal spikes are archivable; the index renders verdicts

## Requirements

### R1. Spike Scale

**User Story:** As an Epic user, I want a sanctioned scale for exploration, so that probes get a home, a conclusion and a deadline instead of polluting the story funnel.

#### Acceptance Criteria

- R1.1: WHEN a story is created with scale `spike` THE SYSTEM SHALL produce only a tasks.md containing a `## Verdict` section with status `open`
- R1.2: WHEN validation runs on a spike without a `## Verdict` section THE SYSTEM SHALL report an error
- R1.3: WHEN a spike's Verdict status is `promote` without a `promoted-to:` reference THE SYSTEM SHALL report an error
- R1.4: WHEN a spike's tasks.md contains a `Requirements:` field or R-number token THE SYSTEM SHALL report an error stating spikes have no requirements chain
- R1.5: WHILE a spike's Verdict remains `open` and its tasks.md has not been modified for 14 days THE SYSTEM SHALL flag it as stale in the story list
- R1.6: WHEN a spike's Verdict is set to `promote` in an interactive session THE SYSTEM SHALL offer to create the follow-up story pre-filled with the spike's conclusion
- R1.7: WHEN a spike's Verdict is `wont-do` or `promote` with its target recorded THE SYSTEM SHALL treat the spike as complete for archive purposes

### R2. Scale-Aware Validation

**User Story:** As an Epic user, I want the validator to read the declared scale, so that invalid scales are caught and each scale is validated by its own contract.

#### Acceptance Criteria

- R2.1: WHEN validation runs on a story whose `scale` value is outside `fast`, `standard`, `full`, `spike` THE SYSTEM SHALL report an error naming the invalid value and the valid set
- R2.2: WHERE a story has no `scale:` field THE SYSTEM SHALL validate using the current file-presence inference with output identical to the pre-change behavior
- R2.3: IF the declared scale contradicts the files present (e.g. `spike` with a story.md) THEN THE SYSTEM SHALL report a warning naming both

### R3. Versioning Policy Wizard

**User Story:** As an Epic user, I want the versioning decision made explicitly at init, so that history-destroying gitignore flip-flops are replaced by a recorded choice.

#### Acceptance Criteria

- R3.1: WHEN init runs interactively THE SYSTEM SHALL ask the versioning-policy question offering exactly two options, with versioned-artifacts as the recommended default
- R3.2: WHEN the versioned option is chosen THE SYSTEM SHALL write `.epic/.gitignore` ignoring `.draft/` and `*.wip`, offer to remove any root-gitignore rule that ignores `.epic/`, and record `tracked-md` in `.epic/.gitpolicy`
- R3.3: WHEN the local-only option is chosen THE SYSTEM SHALL ensure the root gitignore ignores `.epic/` and record `local-only` in `.epic/.gitpolicy`
- R3.4: WHERE init runs non-interactively THE SYSTEM SHALL apply the local-only policy without prompting

### R4. Policy Contradiction Lint

**User Story:** As an Epic user, I want to see when git's reality contradicts the declared policy, so that partial tracking is caught before it destroys history.

#### Acceptance Criteria

- R4.1: WHEN the policy lint runs THE SYSTEM SHALL report a verdict of `consistent`, `contradiction` or `partial` derived from the declared policy, the gitignore state and the tracked-file counts
- R4.2: WHEN the story list is rendered and the lint verdict is not `consistent` THE SYSTEM SHALL show a one-line notice naming the contradiction
- R4.3: WHERE the workspace is not a git repository THE SYSTEM SHALL report `consistent` and show nothing

## Success Metrics

- A kpranois-shaped fixture (tracked `.epic` files under an ignoring gitignore) reports `contradiction`
- `scale: medium` fixture fails validation with the enum named
- A 15-day-old open spike is flagged; a 13-day-old one is not

## Constraints

- Non-interactive init never silently starts committing `.epic` (conservative default: local-only)
- The recommended policy tracks only `story.md`, `design.md`, `tasks.md`, `archive/manifest.yaml`, `EPIC.md` — never `.draft/`
- Spike staleness reuses the existing mtime logic (no duplicated stat code); threshold 14 days
- Legacy stories without `scale:` keep byte-identical validation behavior (R2.2)

## Out of Scope

- Migrating existing projects' gitignore state outside init
- Spike auto-promotion or auto-closing (offers only)
- Program-level roadmap constructs (waves, GO/NO-GO gates)
- Changing the user's global CLAUDE.md rule (documented pointer only — the choice is per-project at init)
