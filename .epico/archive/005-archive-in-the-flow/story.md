---
story: archive-in-the-flow
type: feature
scale: full
version: 1
created: 2026-08-02
status: archived
---

# Story - Archive in the Flow

## Introduction

Archive is the broken step of Epic's lifecycle: absent in 20 of 26 real projects, and where used, a manual end-of-era sweep with hand-declared manifests that lie, no pruning (55 MB of test logs and a 2.3 GB binary were archived wholesale) and no protection. This story turns archive into a scripted, guarded, in-flow operation: a single CLI performs preflight, weight/binary and secrets guards, `.draft` pruning, a checkbox-derived manifest entry and the move — and the orchestrator offers it at the exact moment the corpus proved archives happen organically (right after a passing validate). A managed index block in `.epic/EPIC.md` is regenerated so archive never breaks links again.

## Related Stories

- Related: `.epic/stories/004-story-state-machine-checkbox-grammar/story.md` — completion semantics and the `archived` status transition
- Related: `.epic/stories/006-git-aware-lifecycle/story.md` — supersede's immediate-archive offer delegates here

## Requirements

### R1. Guarded Archive Operation

**User Story:** As an Epic user, I want archiving to be one safe command, so that moving a story cannot silently preserve junk, secrets or lies.

#### Acceptance Criteria

- R1.1: WHEN archive is requested for a complete story with no guard violations THE SYSTEM SHALL move the story directory to `.epic/archive/` and report the move in structured output
- R1.2: IF the story contains a file larger than 10 MB or a non-text file THEN THE SYSTEM SHALL block the archive, list every offending file with its size and reason, and move nothing
- R1.3: WHERE a secrets scanner is installed THE SYSTEM SHALL scan the story before moving and, on findings, block the archive reporting the findings count
- R1.4: WHEN a guard is overridden by its flag (`--allow-heavy`, `--skip-secrets`) THE SYSTEM SHALL complete the archive and record the override in the manifest entry
- R1.5: WHEN archive is requested for an incomplete story without `--force` THE SYSTEM SHALL refuse and report the open items count
- R1.6: WHEN `--force <reason>` is used on an incomplete story THE SYSTEM SHALL complete the archive and record the reason in the manifest entry
- R1.7: WHEN archive is requested for an already-archived story THE SYSTEM SHALL refuse without modifying anything
- R1.8: WHERE no secrets scanner is installed THE SYSTEM SHALL proceed and note the skipped scan in its output

### R2. Evidence Pruning

**User Story:** As an Epic user, I want bulky execution evidence pruned at archive time, so that the archive holds decisions, not gigabytes.

#### Acceptance Criteria

- R2.1: WHEN a story with `.draft/logs/` is archived THE SYSTEM SHALL replace the log files with a single summary file recording each log's name, size, last-modified time and the tail of the most recent log
- R2.2: WHEN a `.draft/` file is byte-identical to its promoted sibling artifact THE SYSTEM SHALL remove the `.draft` copy during archive
- R2.3: WHEN `--keep-logs` or `--keep-copies` is passed THE SYSTEM SHALL preserve the corresponding files and record the override

### R3. Derived Manifest

**User Story:** As an Epic user, I want the archive manifest computed from the artifacts, so that a manifest entry can never claim a completion the checkboxes contradict.

#### Acceptance Criteria

- R3.1: WHEN a story is archived THE SYSTEM SHALL append a manifest entry whose task totals (total, closed, deferred) are computed from the story's checkboxes at move time
- R3.2: WHEN a forced archive moves a story with open checkboxes THE SYSTEM SHALL record the true open count in the manifest entry
- R3.3: WHEN the manifest file does not exist THE SYSTEM SHALL create it with a header stating the numbers-are-never-recycled policy
- R3.4: WHEN an archive operation is interrupted THE SYSTEM SHALL never leave a moved story without its manifest entry

### R4. In-Flow Offer

**User Story:** As an Epic user, I want to be offered the archive at the moment a story finishes, so that archiving stops depending on my memory.

#### Acceptance Criteria

- R4.1: WHEN Validate mode ends with a passing verdict on a story that is `done` or `validated` THE SYSTEM SHALL offer to archive it with a yes/no prompt
- R4.2: WHEN Run mode ends with the story transitioned to `done` THE SYSTEM SHALL offer to archive it with a yes/no prompt
- R4.3: WHERE the session is headless THE SYSTEM SHALL log the archive suggestion and proceed without pausing
- R4.4: WHEN the story's condition is `done-except-external` THE SYSTEM SHALL include the deferred items in the offer text and, on acceptance, record them in the manifest entry

### R5. Managed Index

**User Story:** As an Epic user, I want a generated story index whose links survive archiving, so that a hand-maintained index never again becomes the reason archives don't happen.

#### Acceptance Criteria

- R5.1: WHEN the index is regenerated THE SYSTEM SHALL list every story with its number, state, progress and a link resolving to its current location (stories/ or archive/)
- R5.2: WHEN a story is archived THE SYSTEM SHALL regenerate the index so its link points into `.epic/archive/`
- R5.3: WHEN the index file contains content outside the generated-block markers THE SYSTEM SHALL preserve that content unchanged
- R5.4: WHEN the index is regenerated twice with no state change THE SYSTEM SHALL produce no difference in the file

### R6. History Preservation

**User Story:** As an Epic user versioning `.epic` artifacts, I want archive moves to preserve git history, so that a story's evolution stays auditable after archiving.

#### Acceptance Criteria

- R6.1: WHEN the story's files are git-tracked THE SYSTEM SHALL perform the move so that the files' git history remains reachable (rename tracked by git)
- R6.2: WHEN the story's files are not git-tracked THE SYSTEM SHALL perform a plain filesystem move

## Success Metrics

- A zeo-002-shaped fixture (2 GB-class binary) is blocked with the offender listed
- A pmg-072-shaped fixture (log directory) archives at a fraction of its original size with a summary present
- Manifest counts always equal recomputed checkbox counts on fixtures (derived-not-declared test green)

## Constraints

- All file operations inside `.epic/archive/` are performed by the script via Bash — `hook-archive-guard.sh` (PreToolUse on Edit|Write) keeps blocking interactive edits and its message points to the script
- Structured JSON output with `json_escape()` on every string; fail-closed (guard violation → exit 1, nothing moved; exit 2 invalid input)
- Guard thresholds: >10 MB per file, or non-text content (NUL heuristic); secrets scanner: gitleaks when on PATH
- Step order fixed: nothing destructive before all guards pass; manifest append before move; index regeneration last (failure warns, never rolls back)

## Out of Scope

- Retroactive pruning or manifest repair of pre-existing archives (a future `epic migrate` concern)
- Auto-archiving without an accepted offer or explicit command
- Un-archive/restore operation
- Program-level roadmap features beyond the generated index block (waves/gates GO-NO-GO)
