---
story: ears-lint-authoring-ceiling
type: feature
scale: standard
status: archived
version: 2
created: 2026-08-16
---

# Implementation Plan - EARS Lint and Authoring Ceiling

## Overview

Checks first with their immunity fixtures authored in the same group (the
immunity set is the contract, not an afterthought), then the corpus sweep that
makes the new error safe to ship, then `satisfied-by:` across both orphan
sites, then the ceiling. Everything lands in existing scripts — no new
executable surface.

## Task List

- [x] 1 - EARS form checks with their immunity set
  - _Complexity: Moderate | Tests: Unit | Risks: the R1.1 error blocks task completion via the TaskCompleted hook — immunity and sweep ship in the same group or legacy stories break mid-run | Dependencies: None_
  - Objective: The three form checks fire on hostile shapes and provably change nothing anywhere else.

  - [x] 1.1 - Checks (a)-(c) in validate-story.sh, scale-gated and fence-aware
    - Context:
      - Files: `scripts/validate-story.sh` (scale predicate `scale_has_requirements_chain` :311-316, fence tracking :511-528, SHOULD check :371-374, BSD-safe regex spelling :889, no-new-count-keys rule :420-422), `references/ears-notation.md` (ubiquitous form), `references/requirements.md` (criterion shape)
    - Objective: Unlabeled criterion = error; compound SHALL = warning; trigger-less non-ubiquitous = warning.
    - ToDo: scan only bullets under `#### Acceptance Criteria` headings, fence-excluded (R1.5); gate the whole block on `HAS_STORY` + `scale_has_requirements_chain` (R1.4); (a) bullet without `R[0-9]+\.[0-9]+:` label → error naming line (R1.1); (b) labeled criterion with 2+ `SHALL` (not counting `SHALL CONTINUE TO`) → warning (R1.2, R1.5); (c) labeled criterion with no WHEN/WHILE/WHERE/IF and not opening `THE SYSTEM SHALL` → warning whose text names the ubiquitous form as the accepted exception (R1.3); new strings only, no new count keys (R4.2); BSD-safe spellings; document the `--strict` promotion consequence in the block comment.
    - Tests: Unit · `tests/ears-lint.bats` — unlabeled criterion → error naming the line; 4-SHALL criterion → exactly 1 warning naming the line, errors stay 0; trigger-less criterion → warning naming `THE SYSTEM SHALL` as the accepted exception; ubiquitous form silent (PIN); fenced unlabeled bullet never scanned (PIN)
    - Validation: bats fixtures: unlabeled → error; 4-SHALL bullet → 1 warning; trigger-less → warning; `THE SYSTEM SHALL …` → silent; fenced example → silent
    - Requirements: R1.1, R1.2, R1.3, R1.4, R1.5, R4.2

  - [x] 1.2 - Immunity fixtures + corpus sweep
    - Context:
      - Files: `tests/validate-story.bats`, `tests/scale-validation.bats`, `tests/spike-validation.bats`, `.epic/stories/`, `.epic/archive/` (this repo's corpus), `assets/examples/*.md`
    - Objective: Byte-identical output everywhere the checks must not fire, and this repo's own corpus passes.
    - ToDo: fixtures asserting byte-identical validator output pre/post for: fast, spike, bugfix behavior sections, no-scale-declared legacy (R4.1); run the new validator across every story in `.epic/stories/` + `.epic/archive/` and all four examples — fix any label the sweep finds in examples or live stories (archived stories are read-only: if one trips, the check gains the archive exemption instead and the exemption is documented) (R1.6); extend `tests/hook-task-completed.bats`: the new error blocks, the new warnings never do.
    - Tests: Unit · `tests/ears-lint-immunity.bats` — byte-identical pre-change goldens for fast with a hostile leftover story.md (R1.4), spike, bugfix SHALL CONTINUE TO items (R1.5) and no-scale legacy (all PINs); unlabeled-criterion error blocks hook-task-completed with exit 2; compound/trigger-less warnings never block (PIN)
    - Validation: sweep log in the PR body; full suite green including the new immunity cases
    - Requirements: R1.6, R4.1

  - Commit: "feat(014): EARS form lint — label error, compound and trigger warnings, immunity proven"

- [x] 2 - satisfied-by: the sanctioned non-code deliverable
  - _Complexity: Moderate | Tests: Unit | Risks: R-leaf logic is duplicated across two scripts — movers-comments keep them together | Dependencies: Task 1_
  - Objective: The legitimate orphan class the corpus invented six times becomes grammar both orphan sites accept.

  - [x] 2.1 - Grammar + both orphan sites
    - Context:
      - Files: `scripts/cross-reference.sh` (ORPHANS loop :386-392, REQ_MAP parse :339-372, movers-comment :176-191, JSON key notes :469-476), `scripts/validate-story.sh` (`--cross-ref` block :1096-1102, movers-comment :155-177)
    - Objective: A criterion ending `(satisfied-by: <artifact>)` is satisfied, not orphaned, in every reader.
    - ToDo: parse the same-line suffix on criterion lines (token-anchored, the `[~]` qualifier discipline) (R2.1); in cross-reference.sh, exclude such leaves from `orphan_requirements` and report them under new list key `satisfied_by` with `status` enum unchanged (R2.2); empty artifact → warning (R2.3); mirror the exclusion in validate's `--cross-ref` gate (R2.2); extend BOTH movers-comments with the new consumer entries.
    - Tests: Unit · `tests/satisfied-by.bats` — satisfied-by leaf not orphaned, status stays `clean`, leaf reported under the new list key in cross-reference.sh; no orphan warning in validate --cross-ref; empty artifact → warning; task reference matching no leaf is still a phantom (PIN)
    - Validation: bats: satisfied-by leaf not orphaned in either script; empty suffix warns; a satisfied-by pointing at a nonexistent R-leaf is still a phantom
    - Requirements: R2.1, R2.2, R2.3

  - [x] 2.2 - Documentation + auditor honor, both copies
    - Context:
      - Files: `references/requirements.md` (field documentation), `agents/auditor.md:38` (trace check), `references/validate-mode.md` (duplicated Auditor prompt, check 1)
    - Objective: Authors know the class exists; the Auditor traces to the named artifact instead of flagging a gap.
    - ToDo: document the suffix in requirements.md with the two corpus shapes as examples (regression guard, feasibility verdict); auditor check 1 honors `satisfied-by:` in agent definition AND validate-mode template (R2.4).
    - Tests: None — prose edits to references and agent prompts with no executable logic; the change is grep-verified by this sub-task's own Validation line
    - Validation: `command grep -c 'satisfied-by' references/requirements.md agents/auditor.md references/validate-mode.md` ≥1 each
    - Requirements: R2.4

  - Commit: "feat(014): satisfied-by — the legitimate non-code requirement, accepted by both orphan sites"

- [x] 3 - Authoring ceiling with the split offer
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None (parallel-safe with Tasks 1-2)_
  - Objective: The one-finding-per-story lesson the corpus paid for becomes a warning nobody has to rediscover.

  - [x] 3.1 - Threshold single-home, Phase 3 offer, validate warning
    - Context:
      - Files: `references/tasks.md` (the threshold's home), `skills/epic/SKILL.md` (Phase Execution), `scripts/validate-story.sh` (warning emission), `references/batch-create.md` if present (story 013 — batch surfacing rule)
    - Objective: Oversized plans warn at authoring and stay visible after.
    - ToDo: define the threshold once in references/tasks.md — 32KB or 60 boxes, whichever first, with the corpus rationale (healthy stories ~11KB; 51-109KB monsters preceded the lesson) (R3.2); SKILL Phase Execution: on threshold breach at Phase 3, warn + offer the split as a question interactively, logged-note-and-proceed headless (R3.1); validate-story.sh: warning when tasks.md exceeds the cited threshold (R3.3); batch mode surfaces the warning in the approval block, split deferred post-batch — a pointer to 013's rule, not a restatement (R3.4).
    - Tests: Unit · `tests/authoring-ceiling.bats` — >32KB tasks.md warns citing `references/tasks.md` as the threshold's home, errors stay 0; >60-box tasks.md warns even when small in bytes; normal-sized tasks.md silent (PIN)
    - Validation: bats: 33KB fixture warns naming the threshold's home; 10KB fixture silent; threshold value appears in exactly one file
    - Requirements: R3.1, R3.2, R3.3, R3.4
    - Commit: "feat(014): authoring ceiling — one threshold, Phase 3 split offer, validate visibility"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R4.2 covered by bats fixtures or grep-verifiable docs)
- [x] All task validations pass
- [x] All tests written and passing (full suite green; immunity set byte-identical)
- [x] Code integrated (both orphan sites and both auditor copies agree; threshold cited, defined once)
- [x] Error handling implemented (archive-trip arm decided and documented; empty satisfied-by warns)
