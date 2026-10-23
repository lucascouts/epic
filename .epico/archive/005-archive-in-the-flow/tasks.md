---
story: archive-in-the-flow
type: feature
scale: full
version: 1
created: 2026-08-02
status: archived
---

# Implementation Plan - Archive in the Flow

## Overview

Five groups, bottom-up: the core script (preflight → derived manifest → move) first, then the two guards, then pruning, then the index generator, and finally the in-flow wiring (offers + references + guard message). All destructive behavior lives in `scripts/archive-story.sh` and is reached only after every guard passes; the fixed step order (manifest append BEFORE move, index regen last) is itself a requirement (R3.4). Depends on story 004's completion semantics for preflight.

## Task List

- [x] 1 - archive-story.sh core: preflight, derived manifest, move
  - _Complexity: High | Tests: Unit + Integration (archive-story.bats) | Risks: hook-archive-guard collision (bypass is Bash-only by design); interrupted-move consistency | Dependencies: story 004 (completion semantics)_
  - Objective: a single fail-closed CLI that refuses bad input, derives truth from checkboxes and moves with history preserved.

  - [x] 1.1 - Script skeleton, preflight and JSON contract
    - Context:
      - Files: `scripts/validate-story.sh` (json_escape/output conventions), `scripts/cross-reference.sh` (REQ_KEYS counter pattern), `references/list-mode.md` (:52-89 current prose procedure)
    - Objective: `archive-story.sh <NNN|dir> [flags]` resolves the story, enforces preflight, and always emits the structured JSON contract.
    - ToDo:
      - New `scripts/archive-story.sh` with `set -euo pipefail`, `--help`, exit codes 0/1/2 and JSON `{story, status: archived|blocked|refused, moved, pruned{}, guard{violations[]}, secrets{}, manifest_entry{}}` — every string through `json_escape()`.
      - Preflight: story must be in `stories/` (already in `archive/` → `refused`, exit 1, nothing touched — R1.7); completion check = frontmatter `status` in `done|validated|superseded` OR no `[ ]` remaining (the design's OR — count with the `\[[ x~]\]` grammar and manual integer counters — bash 5.3 set -u GOTCHA); `scale: spike` stories are complete when `## Verdict` status is `wont-do`, or `promote` with `promoted-to:` recorded (007 R1.7 — this is code here, not doc); incomplete without `--force` → `refused` reporting the open count (R1.5); `--force <reason>` (reason argument REQUIRED) captured for the manifest (R1.6). Spike-preflight test case added to `tests/archive-story.bats` at execution (test_surface_adjusted — authored suite predates this rule).
      - Parse flags `--allow-heavy --skip-secrets --keep-logs --keep-copies --force`; unknown flag → exit 2 usage. Collect every used override into `overrides_used[]`.
      - Handle all subcommand failures explicitly (`|| rc=$?` pattern from e890d02) — no bare set -e aborts mid-JSON.
    - Tests: Unit · `tests/archive-story.bats` — help exit 0, unknown flag exit 2, refusals (incomplete w/o --force, already archived) with valid JSON and nothing moved
    - Validation: bats: refusal matrix (incomplete, already archived, unknown flag) each with valid JSON (`jq -e`) and nothing moved
    - Requirements: R1.5, R1.6, R1.7

  - [x] 1.2 - Derived manifest entry, append-before-move
    - Context:
      - Files: `.epic/docs/analise-casos-reais-epic.md` (manifest evidence: derived-not-declared rationale)
    - Objective: the manifest can never contradict the checkboxes, and an interrupted run never leaves a moved story without an entry.
    - ToDo:
      - Compute entry fields at move time: story, number, slug, type, scale, status (frontmatter), tasks_total/closed/deferred (same grammar as 1.1), deferred_items[] — one "N.N — title (reason)" per deferred box (R4.4 records the items, not just a count), archived_at (date -Iseconds), pruned{}, overrides_used[], forced_reason when present (R3.1, R3.2).
      - Create `.epic/archive/manifest.yaml` with a header comment `# Numbers are never recycled` when absent (R3.3).
      - Append the entry BEFORE the move; if the append fails, abort with `blocked` and move nothing (R3.4). GOTCHA: all writes inside `.epic/archive/` happen via Bash redirection in this script — `hook-archive-guard.sh` blocks the Edit/Write tools there by design; do not route any of this through orchestrator file tools.
    - Tests: Unit · `tests/archive-story.bats` — counts derived from `[x]`/`[~]` mix, forced archive records true open count + reason, policy header on creation, append-failure aborts before move
    - Validation: bats: entry counts equal recomputed fixture counts (incl. forced-open case); kill-between-append-and-move simulation leaves manifest entry + story still in stories/ (re-run completes idempotently)
    - Requirements: R3.1, R3.2, R3.3, R3.4

  - [x] 1.3 - Move with history preservation + status transition
    - Context:
      - Files: `scripts/story-git-status.sh` design (006 — main detection precedent), `references/list-mode.md` (:87 numbers-never-recycled)
    - Objective: tracked stories keep their git history through the move; the moved artifacts carry `status: archived`.
    - ToDo:
      - Detect trackedness with `git ls-files --error-unmatch` on the story dir (quiet); tracked → `git mv`, untracked → `mv` (R6.1, R6.2); not-a-repo → `mv`.
      - After the move, set `status: archived` in the moved artifacts' frontmatter via `sed -i` (Bash — guard-exempt; story 004 defines the field).
      - Emit `moved: true` and `status: "archived"` in the JSON only after both steps succeed.
    - Tests: Integration · `tests/archive-story.bats` — moved story verified on disk with status archived; tracked story keeps history (`git log --follow`); untracked moved plainly
    - Validation: bats in a temp git repo: tracked fixture → `git log --follow` non-empty post-move; untracked → plain move; frontmatter shows archived
    - Requirements: R1.1, R6.1, R6.2

  - [x] 1.4 - Commit
    - Validation: bats for group 1 green; shellcheck -S warning clean on archive-story.sh
    - Commit: "feat(005): archive-story.sh core — preflight, derived manifest, history-preserving move"

- [x] 2 - Guards: weight/binary and secrets
  - _Complexity: Moderate | Tests: Unit (archive-story.bats) | Risks: false-positive binary detection on UTF-16/BOM files | Dependencies: Task 1_
  - Objective: nothing heavy, binary or secret-bearing crosses into the archive without an explicit, recorded override.

  - [x] 2.1 - Weight/binary guard
    - Objective: any file >10 MB or non-text blocks the move with the offender list.
    - ToDo:
      - Scan every file: size via `stat -c %s || stat -f %z` (portable pair — GNU-ism rule from wave 0); binary heuristic `LC_ALL=C grep -qI .` (NUL-detection; document the UTF-16 false-positive edge in a comment).
      - Violations → `blocked`, exit 1, `guard.violations[] = {file, size, reason}`, nothing moved (R1.2); `--allow-heavy` skips the guard and lands in `overrides_used` (R1.4).
    - Tests: Unit · `tests/archive-story.bats` — 10485761-byte blocks / 10485760 passes (boundary), NUL file blocks, --allow-heavy archives + records override
    - Validation: bats: 10 MB boundary file (10485761 bytes) blocks, 10485760 passes; NUL-file blocks; --allow-heavy archives and records
    - Requirements: R1.2, R1.4

  - [x] 2.2 - Secrets guard (gitleaks when available)
    - Objective: findings block; absence of the scanner degrades loudly-but-gently.
    - ToDo:
      - `command -v gitleaks` → run `gitleaks dir <story> --no-banner --exit-code 1 --max-target-megabytes 15 --report-format json --report-path <tmp>`; findings → `blocked` with `secrets.findings=N` and the report path (R1.3); scan errors (non-0/1 exit) → treat as blocked with reason (fail-closed).
      - No gitleaks on PATH → `secrets: {skipped: "gitleaks not installed"}`, proceed (R1.8); `--skip-secrets` → skipped + recorded (R1.4).
    - Tests: Unit · `tests/archive-story.bats` — gitleaks finding blocks (gated on command -v), --skip-secrets bypasses + records, absent scanner proceeds noting skip
    - Validation: bats gated on `command -v gitleaks` (skip-with-note otherwise): fixture with a fake AWS-style key blocks; --skip-secrets passes and records
    - Requirements: R1.3, R1.4, R1.8

  - [x] 2.3 - Commit
    - Validation: group 2 bats green; full-suite regression green
    - Commit: "feat(005): weight/binary and secrets guards, and an atomic manifest append"

- [x] 3 - Evidence pruning
  - _Complexity: Moderate | Tests: Unit (archive-story.bats) | Risks: destructive step — must run only after all guards pass | Dependencies: Task 2_
  - Objective: logs collapse to a summary and exact duplicates disappear — after guards, before manifest.

  - [x] 3.1 - `.draft/logs` → summary
    - Objective: the archive keeps what the logs proved, not the logs.
    - ToDo:
      - When `.draft/logs/` exists and `--keep-logs` absent: write `.draft/logs-summary.md` (per file: name, size, mtime; plus the tail -40 of the most recently modified log), then delete the log files (R2.1, R2.3). Record `pruned.logs_kb`.
      - Execute strictly after guards pass (sequence assertion in script — pruning never precedes a possible `blocked`).
    - Tests: Unit · `tests/archive-story.bats` — logs collapse to summary (names + newest tail), raw logs deleted, pruned.logs_kb > 0, --keep-logs preserves
    - Validation: bats: log-dir fixture → summary exists with all names + tail; --keep-logs preserves; pruned.logs_kb ≈ freed size
    - Requirements: R2.1, R2.3

  - [x] 3.2 - Byte-identical `.draft` copies
    - Objective: exact duplicates of promoted artifacts are dropped, never near-duplicates.
    - ToDo:
      - For each `.draft/` file with a same-named promoted sibling: `cmp -s` equal → delete draft copy, count in `pruned.copies_removed` (R2.2); differing → keep untouched; `--keep-copies` skips (R2.3).
    - Tests: Unit · `tests/archive-story.bats` — byte-identical copy removed, one-byte-different kept, --keep-copies preserves
    - Validation: bats: identical copy removed; one-byte-different copy kept
    - Requirements: R2.2, R2.3

  - [x] 3.3 - Commit
    - Validation: group 3 bats green
    - Commit: "feat(005): evidence pruning at archive time"

- [x] 4 - epic-index.sh: managed index block
  - _Complexity: Moderate | Tests: Unit + Integration (epic-index.bats) | Risks: clobbering hand-written content outside markers | Dependencies: Task 1 (manifest), story 004 (status/progress semantics)_
  - Objective: a regenerated-from-disk index whose links are correct by construction.

  - [x] 4.1 - Generator
    - Objective: `epic-index.sh` writes the block between markers, preserving everything else.
    - ToDo:
      - New `scripts/epic-index.sh`: scan `stories/` + `archive/`; table row per story: number, slug, status (frontmatter or "—"), progress (closed/total per 004 grammar), link to the current location (R5.1); `superseded` rows read the frontmatter `superseded-by: MMM` companion (written by 006) and render `superseded by MMM` / `(missing)` when unresolvable.
      - Rewrite ONLY between `<!-- epic:index:start -->` / `<!-- epic:index:end -->`; file absent → create with markers when ≥1 story exists; content outside markers byte-preserved (R5.3); stable number ordering; second run with no state change → zero diff (R5.4).
      - GOTCHA: the index file lives at `.epic/EPIC.md` (NOT inside archive/) — orchestrator tools may write it, but this script writes via Bash for symmetry and headless use.
    - Tests: Unit · `tests/epic-index.bats` — location-correct links, outside-marker content byte-preserved, double-regen zero diff, creation rules
    - Validation: bats: regen idempotence (diff empty); external content preserved; row set matches fixture state
    - Requirements: R5.1, R5.3, R5.4

  - [x] 4.2 - Archive integration
    - Objective: archiving retargets the story's link automatically.
    - ToDo:
      - archive-story.sh calls epic-index.sh as its final step; regen failure → warning in JSON (`index: "regen-failed"`), move stands (design: never roll back for the index).
      - Post-archive row links into `.epic/archive/` (R5.2).
    - Tests: Integration · `tests/epic-index.bats` — real archive-story.sh run retargets the row into archive/; regen failure leaves the move standing
    - Validation: bats: archived fixture's row href switches to archive/; simulated regen failure leaves moved story + warning
    - Requirements: R5.2

  - [x] 4.3 - Commit
    - Validation: group 4 bats green; shellcheck clean on epic-index.sh
    - Commit: "feat(005): managed EPIC.md index with regeneration on archive"

- [x] 5 - In-flow offers, references and guard message
  - _Complexity: Simple | Tests: None (reference prose; contract covered by archive-story.bats) | Risks: headless pause regression | Dependencies: Tasks 1-4_
  - Objective: archive becomes a moment in the flow, and every document points at the script instead of prose.

  - [x] 5.1 - Offers in validate-mode and run-mode
    - Context:
      - Files: `references/validate-mode.md` (:80-81), `references/run-mode.md` (:465-466 — the "Run Validator? y/n" precedent)
    - Objective: the y/n offer appears exactly where the corpus proved archives happen.
    - ToDo:
      - validate-mode: after a passing verdict on a story that is `done` OR `validated`, offer "Archive story NNN? [y/n]" → yes runs archive-story.sh and surfaces its JSON verdict (R4.1). Ordering contract: this offer runs AFTER 006's integration warning and AFTER 004's `status: validated` write — hence the `done|validated` condition.
      - Both validate-mode and run-mode completion steps also invoke `epic-index.sh` (design component 3 invocation points); LIST refreshes it opportunistically (one line in list-mode.md).
      - run-mode: same offer when the session ends with the story transitioned to `done` (R4.2).
      - Headless/CI: no pause — log the suggestion (reuse the preferred-tooling headless rule wording) (R4.3).
      - `done-except-external`: offer text lists the deferred items; acceptance passes them through (they are already in the manifest via task 1.2 counts) (R4.4).
    - Tests: None — prose offer wording (R4.1–R4.4) followed by the orchestrator; grep Validation is the appropriate check
    - Validation: both references contain the offer step with the headless branch; wording references the script, not manual mv
    - Requirements: R4.1, R4.2, R4.3, R4.4

  - [x] 5.2 - References, routing and guard message
    - Context:
      - Files: `references/list-mode.md` (:52-89), `skills/epic/SKILL.md` (ARCHIVE routing :190-191, :205-206), `scripts/hook-archive-guard.sh` (:17-22 message), `bin/epic-validate` (wrapper pattern)
    - Objective: one entry point, consistently documented.
    - ToDo:
      - Replace the list-mode prose procedure with the script contract (flags, JSON fields, guard semantics); CARRY FORWARD story 004's updated completion-definition wording at list-mode.md:74 — this rewrite covers the same line range and must not silently revert it. SKILL ARCHIVE mode delegates to the script (`stories archive NNN[-MMM]|--done` iterates it).
      - hook-archive-guard message now says: "Archived stories are read-only. Use scripts/archive-story.sh for sanctioned archive operations."
      - Add `bin/epic-archive` thin wrapper following `bin/epic-validate` (symlink-safe invocation note from the audit).
    - Tests: None — documentation rewrite + trivial delegating wrapper; underlying contract covered by tests/archive-story.bats
    - Validation: grep: no remaining manual-mv instructions in references/; wrapper runs `--help` successfully
    - Requirements: R1.1

  - [x] 5.3 - Commit
    - Validation: full bats suite green; stories 004-007 validate clean
    - Commit: "feat(005): in-flow archive offers, script-first docs and guard message"

- [x] 6 - Remediation of the validate-mode findings (2026-08-05)
  - _Complexity: Moderate | Tests: Unit (epic-index.bats) | Risks: rendering a story whose directory is gone must not invent a link | Dependencies: Task 4_
  - Objective: close the two halves of design.md component 3 that reached neither tasks.md nor the code — the index generator scans only `stories/` and `archive/`, and never renders a spike's Verdict.
  - Context: the Auditor pass on 2026-08-05 found both gaps. They are *unimplemented design*, not accepted deviations, so they are closed here rather than registered. The record-level findings from the same pass (the 1.2/1.3 evidence sentence, the two unregistered 5.1 divergences, the 3.1 metadata nuance, the `.gitleaksignore` and unscanned-summary residuals, the dead `!` assertion in `tests/epic-index.bats`) were corrected in place by the orchestrator and are not sub-tasks here.

  - [x] 6.1 - Manifest-backed rows for stories no longer on disk
    - Context:
      - Files: `scripts/epic-index.sh` (`scan_area`, `build_rows`, `status_cell`), `scripts/archive-story.sh` (`manifest_entry_yaml` — the 16-key shape the reader must parse), `references/list-mode.md` (:187 the manifest entry contract)
    - Objective: the index reflects the manifest's permanent record, so pruning `.epic/archive/` on disk does not erase a story from the index.
    - ToDo:
      - After scanning `stories/` and `archive/`, read `.epic/archive/manifest.yaml` and emit a row for every recorded story that neither scan found (design.md:67 "scans `stories/` + `archive/` + manifest"). Number, slug, status and progress come from the recorded entry — derived at archive time, never recomputed from files that no longer exist.
      - The Location cell carries NO link: the row renders the recorded state plus an explicit "archived (directory removed)" marker, following the `superseded by MMM (missing)` precedent already in `status_cell`. R5.1 asks for a link resolving to the story's current location; a story with no location must say so rather than emit a href that 404s.
      - GOTCHA (deviations.yaml, concurrency fix cycle, hand-off to 4.1/4.2): the manifest lock serializes WRITERS, NOT READERS. Only the LAST entry can ever be torn. Tolerate a trailing incomplete entry — skip it — and do NOT treat it as a corrupt manifest or block on it.
      - Manifest absent or unreadable → no manifest rows, exit 0, everything else renders. The index is a rendering, never a gate.
    - Tests: Unit · `tests/epic-index.bats` — a manifest-only story gets a row with its recorded counts and no link; a torn trailing entry is skipped without failing the run; an absent manifest changes nothing
    - Validation: bats: manifest-only row present with recorded status/progress and no href; truncated last entry skipped, exit 0; second regeneration with no state change still produces zero diff (R5.4 holds with manifest rows in play)
    - Requirements: R5.1, R5.4

  - [x] 6.2 - Spike rows render the Verdict status
    - Context:
      - Files: `scripts/archive-story.sh` (`parse_verdict` — the sibling implementation of the same 007 R1.7 rule), `scripts/epic-index.sh` (`status_cell`)
    - Objective: a `scale: spike` story's row states its Verdict, not a lifecycle status the spike does not use.
    - ToDo:
      - For `scale: spike`, read the `## Verdict` status and render it (design.md:67). Reuse `parse_verdict`'s GRAMMAR verbatim — the same one-grammar-many-consumers rule already recorded for the checkbox census; if 007 later amends the grammar, both consumers move together.
      - A spike with no parseable Verdict renders the same em dash a story with no `status:` renders — absent is absent, never invented.
    - Tests: Unit · `tests/epic-index.bats` — a spike with a `wont-do` Verdict renders it; a spike with `promote` + `promoted-to:` renders it; a spike with no Verdict renders an em dash
    - Validation: bats: the three spike fixtures render as specified; a non-spike story's row is byte-unchanged by this sub-task
    - Requirements: R5.1

  - [x] 6.3 - Commit
    - Validation: full bats suite green; `shellcheck -S warning` clean on `epic-index.sh`; stories 004-007 validate clean
    - Commit: "fix(005): close the index generator's two design gaps found by validate"

## Quality Gates

- [x] All acceptance criteria validated (R1.1–R6.2 traced by cross-reference.sh)
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [x] Error handling implemented (fail-closed paths exercised: guards, interrupted move, regen failure)
