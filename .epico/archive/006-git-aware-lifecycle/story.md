---
story: git-aware-lifecycle
type: feature
scale: full
version: 13
created: 2026-08-02
last-refined: 2026-08-09
status: archived
history:
  - v1: Initial story
  - v2: R1.7 added — the emitted JSON must survive control characters in evidence text (found by the story's own validate)
  - v3: R3.5 trigger amended to a complete prior run; R1.8 added (evidence uniqueness) — both raised by the story's second validate
  - v4: R3.4 guarded to a *complete* prior supersede (v3's R3.5 amendment had made the two collide); R1.8 widened to require the reported detail to name a merged ref — third validate
  - v5: R1.9 and R1.10 added — R1.8 only ever forbade duplicating one branch, never forbade merging two, and the fourth validate found both halves of that gap in the shipped code; R1.5 split into name-vs-revision with R1.11 stating the revision rule the code has always used
  - v6: R1.12 and R1.13 added — the fifth validate found the main-branch NAME still resolved through an ambiguity-aware spelling (the one call site group 6's own discovery never reached, and the only defect so far that changes `integrated`), and the remote/branch split still able to lose a branch. R1.10 is deliberately unchanged: its defect was in the code, not in the rule
  - v8: no v7 exists here either — the plan reached v7 and v8 by gaining task groups, neither of which changed a requirement, so this file stayed at v6 while `tasks.md` moved twice. Synced by 9.1. **One criterion is corrected and no shipped behaviour moves:** R1.8 gains a `WHERE at most one configured remote name is a prefix …` qualifier. R1.8 and R1.13 were unsatisfiable together — remotes `a` and `a/b` configured over one genuine mirror satisfies BOTH antecedents, R1.8 demanding a single entry and R1.13 an entry of its own, so a validate could "find" a defect in either direction depending on which it read first. The code follows R1.13 and design.md argues that direction is the safe one, which is the right call; the qualifier makes the antecedents disjoint so the text says what the code does. Reproduced at the fifth and sixth validates and re-measured at 9.1: R1.8's antecedent yields 1 entry, R1.13's yields 2
  - v9: **no criterion changed, and that is the entry.** Group 11 closes the seventh validate, which found no code defect and no behavioural finding of any kind — six statements stronger than the measurement behind them, all of them records. Synced by 11.3 **in the group that opens the skew**, not at the next validate: `tasks.md` gains a group while no requirement and no design bullet moves, which is the exact shape that left this file at v6 while the plan reached v8, twice unrepaired until 9.1 caught it. The only line of this file group 11 touches is this one; the version advances so a reader diffing the three artifacts finds no gap to explain
  - v10: **no criterion changed here either, but one is now known to be unmet, and that is the entry.** Group 12 closes the eighth validate, which found the first code-level defect in four validates and inverted this story's pattern: `scripts/supersede-story.sh` and `scripts/render-integration.sh` were correct, tested and green, and invoked by nothing — so R2 and R3 were satisfied by code the command never reached. Wiring them made a second thing visible that no validate could have seen while the script was unreachable: **R3.5's recovery half is unimplemented.** The requirement says the system SHALL *offer* to complete an interrupted run; the shipped script offers nothing and completes unconditionally. The criterion is NOT amended here — amending a requirement to match the code it was meant to constrain is the move this story has spent eight validates learning not to make. It is recorded in `.draft/deviations.yaml` under `12.1`, marked OWED, and a future group either implements the offer or argues the amendment on its merits. Synced by 12.4 in the group that opens the skew, on 11.3's precedent
  - v11: **no criterion changed, and the one known to be unmet is now named where it is certified rather than only where it is registered.** Group 13 closes the ninth validate, which found no code defect and a suite green at a higher rung than any previous validate measured (`bats tests/` **314 ok / 0 not ok** as uid 1000, re-derived independently by `command grep -c '^@test' tests/*.bats`). All six findings are records, and for the first time in this story the drift was **manufactured by the correcting commit rather than inherited from the code it corrected** — four times by the end of the group's own Run, the last two produced by the sub-tasks written to correct the first two. **R3.5 remains unimplemented and unamended**, exactly as v10 left it: what changes is that `tasks.md`'s acceptance-criteria gate now carries R3.5's *offer* half as its fifth exception clause, citing `.draft/deviations.yaml` entry `12.1`, instead of covering the gap with a universal quantifier. Its *refuse* and *no-second-banner* halves meet the removal standard and are shown to. The standing rule the group owes was measured before it was proposed and **retired**: no mechanical check is available, because the precise one needs a before-state that a gitignored artifact tree does not have — `references/self-review-checklist.md` **item 17** carries the prose instead. Synced by 13.4 in the group that opens the skew, on 11.3's and 12.4's precedent
  - v12: **no criterion changed, no requirement text moved, and no task group was opened — that last part is what makes this entry different from v9, v10 and v11.** The tenth validate found **no code defect**: `bats tests/` **314 ok / 0 not ok** as uid 1000, bare `shellcheck scripts/*.sh bin/*` clean at CI severity, `validate-story.sh` 0/0 and `cross-reference.sh` 23/23 on this story and clean on all seven. Its ten findings are again all records, and the dominant mechanism is again the one group 13 named — **the correcting commit falsifying its own numbers**, this time inside `.draft/deviations.yaml`'s `13.4` entry, the entry written to retire that very question, which stated five figures (95 / 18 / 13 / "seven spellings" / 72%) of which none reproduces plus one CONTENT claim that never did. The corrections were applied **pointwise, at the user's direction, without a group 14**, so `tasks.md` gains no task and this file's requirements are untouched; the version advances only so a reader diffing the three artifacts finds no gap to explain, on 11.3's, 12.4's and 13.4's precedent. **R3.5 remains unimplemented and unamended**, exactly as v10 and v11 left it — what changes is that `.draft/deviations.yaml` entry `12.1` now names a **third** divergent surface, `design.md`'s Error Handling Strategy bullet ("re-run detects banner and offers to complete the remaining steps"), anchored by that quoted phrase; v10 had scoped the class to two sentences that both live in the Interface paragraph, so every later sweep searched a paragraph instead of the promise. One new gap is recorded and OWED rather than closed: 12.3's seven cases carry **no Red standing in any artifact**, because 11.1's enumeration is a dated sweep with no trigger to re-run and a refine-added sub-task never reaches the Phase-3 step that writes one
  - v13: **the first version of this story in which a criterion moves from unmet to MET, and it moved by implementing the code rather than by amending the text.** R3.5's *offer* half — OWED since v10, restated unamended at v11 and v12 — is implemented: `scripts/supersede-story.sh` gains `--complete-interrupted` and an `offer_recovery` terminator, so an interrupted prior run that is not authorized is reported as `recovery-offer` with **nothing written**, and the `[y/n]` plus its headless branch live with the orchestrator exactly as R3.6's archive offer does. The fork `.draft/deviations.yaml` entry `12.1` set out — implement or amend — was decided against amending on the register's own ground: the doc sentence that would have justified the amendment ("the re-invocation is the acceptance") was written at group 12 to describe the script as built, so it records the code rather than reasoning about the requirement. Demonstrated by REMOVAL, the standard the rest of the gate uses: the authorization guard replaced with `if false` reddens the hostile case and the exhaustiveness case and nothing else, script restored byte-identical (sha256 e90f95d627ee5b00). **No requirement text changed.** Applied pointwise, without a task group, at the user's direction
---

# Story - Git-Aware Lifecycle

## Introduction

The corpus proved two blind spots. "Complete" and "integrated to main" are independent axes Epic cannot see — one project died with 21/21 stories checkbox-complete and zero merges, and the plugin said nothing. And replacing a story has no sanctioned path — users hand-invented ⛔ banners and `superseded` statuses. This story adds a live, storage-free `integrated` detection surfaced as a non-blocking warning, and a first-class `stories supersede NNN --by MMM` operation with a standardized banner, per-task remap and an immediate archive offer.

## Related Stories

- Related: `.epic/stories/004-story-state-machine-checkbox-grammar/story.md` — `superseded` state and `superseded-by:` qualifier
- Related: `.epic/stories/005-archive-in-the-flow/story.md` — the archive offer after supersede delegates to its operation

## Requirements

### R1. Live Integration Detection

**User Story:** As an Epic user, I want to know whether a done story's work actually reached main, so that completed-but-orphaned work becomes visible before the project reboots.

#### Acceptance Criteria

- R1.1: WHEN a story has a branch matching its number-and-slug pattern fully merged into the main branch THE SYSTEM SHALL report the story as integrated with the branch evidence
- R1.2: WHEN a commit reachable from the main branch carries the story number as a delimited token (conventional `type(NNN):` or `NNN-slug`) in its subject THE SYSTEM SHALL report the story as integrated with the commit evidence
- R1.3: WHEN a commit subject contains the story number only as a bare undelimited number THE SYSTEM SHALL NOT count it as integration evidence
- R1.4: WHERE the workspace is not a git repository THE SYSTEM SHALL report integration as non-computable and produce no annotation or warning downstream
- R1.5: WHEN the main branch is resolved THE SYSTEM SHALL take its name from the remote HEAD default when available, otherwise a local `main`, otherwise `master`, and report integration as non-computable when none exists
- R1.6: WHEN the repository history changes (a branch is deleted or rewritten) THE SYSTEM SHALL reflect the new state on the next evaluation without relying on any previously stored evidence
- R1.7: WHEN a commit subject or branch name reported as evidence contains characters that JSON requires escaped THE SYSTEM SHALL escape them so that the emitted document parses as valid JSON
- R1.8: WHERE at most one configured remote name is a prefix of the ref's remainder, WHEN one merged branch is reachable under more than one ref THE SYSTEM SHALL report it as a single evidence entry, and the reported detail SHALL name a ref that is itself merged into the main branch
- R1.9: WHEN a merged remote-tracking ref is neither the configured upstream of the like-named local branch nor points at that branch's commit THE SYSTEM SHALL report it as an evidence entry of its own
- R1.10: WHEN two evidence entries denote different branches THE SYSTEM SHALL report details that differ from each other
- R1.11: WHEN evidence is evaluated THE SYSTEM SHALL query the local branch carrying the resolved main-branch name when it exists, otherwise the remote-tracking ref, so that unpushed integration commits count as integration
- R1.12: WHEN the main-branch name is resolved from the remote HEAD default THE SYSTEM SHALL derive it from the ref's full path, so that adding an unrelated ref never changes the reported name
- R1.13: WHERE more than one configured remote name is a prefix of a merged remote-tracking ref THE SYSTEM SHALL report that ref as an evidence entry of its own

### R2. Non-Blocking Surfacing

**User Story:** As an Epic user, I want the integration signal visible but never in my way, so that a warning can inform without freezing legacy workflows.

#### Acceptance Criteria

- R2.1: WHEN the story list is rendered THE SYSTEM SHALL annotate each `done`/`validated` story as integrated or not-integrated where computable
- R2.2: WHEN validation passes on a story that is not integrated THE SYSTEM SHALL emit a warning naming the missing evidence kinds, and SHALL NOT fail the validation for that reason
- R2.3: WHEN a story is archived THE SYSTEM SHALL NOT require integration evidence

### R3. Supersede Operation

**User Story:** As an Epic user, I want a sanctioned way to replace a story, so that superseded work carries an auditable banner and its open scope is remapped instead of dangling.

#### Acceptance Criteria

- R3.1: WHEN `supersede NNN --by MMM` runs with a valid pair THE SYSTEM SHALL prepend the standardized banner to story NNN and set its status to `superseded` in every artifact
- R3.2: WHEN the banner is generated THE SYSTEM SHALL include the date, the target story, a user-provided rationale, and one remap row for every open sub-task of NNN
- R3.3: WHEN the operation completes THE SYSTEM SHALL close every open sub-task of NNN as `[~] (superseded-by: MMM)`
- R3.4: IF NNN equals MMM, MMM does not exist, NNN is already `archived`, or NNN carries a *complete* prior supersede THEN THE SYSTEM SHALL refuse the operation naming the reason
- R3.5: WHEN supersede runs on a story that already carries the banner from a *complete* prior supersede THE SYSTEM SHALL refuse rather than duplicate it; WHERE the prior run was interrupted before its status writes or closures THE SYSTEM SHALL offer to complete the remaining steps and SHALL NOT write a second banner
- R3.6: WHEN the operation completes in an interactive session THE SYSTEM SHALL offer to archive NNN immediately; WHERE the session is headless THE SYSTEM SHALL log the suggestion instead
- R3.7: WHEN the index is regenerated after a supersede THE SYSTEM SHALL render NNN as superseded by MMM

## Success Metrics

- A bleach-v0-shaped fixture (complete story, unmerged branch) produces the not-integrated warning
- Supersede on a fixture with 3 open sub-tasks yields 3 remap rows and 3 `[~] (superseded-by:)` closures
- Zero SHAs or branch names written into any artifact by either capability
- A commit subject carrying a raw control character still yields output that `jq -e .` accepts
- Two same-named branches on two remotes at different tips, with the like-named local branch also merged, yield two evidence entries whose details differ from each other
- A branch named `origin/<default>` added to a repository that has `origin/HEAD` set changes neither the reported `main_branch` nor the reported `integrated`
- Three merged branches whose short names collide pairwise yield three details that are pairwise distinct
- Remotes `a` and `a/b` with a merged `refs/remotes/a/b/feat/NNN-slug` yield two evidence entries, never one

## Constraints

- Evaluate live, store nothing: no commit SHA, branch name or merge-base is ever written into artifacts (recorded SHAs died in 100% of corpus cases)
- Detection cost control: per-story git evaluation in LIST limited to `done`/`validated` stories; full sweep only in `stories full`
- Supersede's artifact writes use `Edit` (Write-matcher hook not re-triggered); banner insertion is idempotent
- The story-anchor commit convention (`type(NNN):`, branch `feat/NNN-slug`) becomes documented guidance in this wave; enforcement is wave 3

## Out of Scope

- Blocking any operation on integration state (warning-only by decision)
- Persisted `integrated` status value (computed display only)
- Automatic supersede detection (e.g., inferring replacement from similar slugs)
- Commit-message enforcement gates (wave 3, item 3.1)
