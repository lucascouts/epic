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
  - v2: Task 5 — close the validate-007 findings (spike exemption in Run, four unpinned branches, honest gates and complete registers). No requirement or component changed.
---

# Implementation Plan - Spike Scale & .epic Versioning Policy

## Overview

Three groups: scale-aware validation first (it is the foundation the spike checks build on, and independently closes the `scale: medium` hole), then the spike scale end-to-end (routing, contract, validation, lifecycle), then the versioning-policy wizard with its contradiction lint. Legacy behavior (no `scale:` field) is pinned byte-identical before anything else changes.

## Task List

- [x] 1 - Scale-aware validation
  - _Complexity: Simple | Tests: Unit (scale-validation.bats) | Risks: breaking the file-inference fallback used by every legacy story; dueling goldens with story 004 | Dependencies: story 004 tasks 1-2 (same script — land after 004 and re-record the legacy golden then)_
  - Objective: validate-story.sh reads the declared scale first, errors on invalid values, and keeps legacy inference intact.

  - [x] 1.1 - Read `scale:` first, enum check, mismatch warning
    - Context:
      - Files: `scripts/validate-story.sh` (file-inference at :71-88, frontmatter parsing convention)
    - Objective: declared scale governs validation; `medium`-style values become errors; absent field keeps today's behavior.
    - ToDo:
      - Parse `scale:` from frontmatter (same sed/grep pattern); value outside `fast|standard|full|spike` → add_error naming value and the valid set (R2.1).
      - Absent field → fall through to the existing file-presence inference untouched — pin with a legacy fixture asserting byte-identical JSON (R2.2).
      - Declared scale contradicting files present (e.g. `spike`/`fast` with story.md; `full` without design.md) → add_warning naming both sides (R2.3).
      - Messages through `json_escape()`; counters plain integers (bash 5.3 set -u GOTCHA).
    - Tests: Unit · `tests/scale-validation.bats` — `medium` errors naming value + valid set, 4 valid scales accepted, absent scale = byte-identical legacy golden, mismatch warnings naming both sides
    - Validation: bats matrix (4 valid values, `medium` error, absent = golden legacy output, 2 mismatch warnings)
    - Requirements: R2.1, R2.2, R2.3
    - Commit: "feat(007): scale-aware validation with enum enforcement"

- [x] 2 - Spike scale end-to-end
  - _Complexity: Moderate | Tests: Unit (spike suites) + 1 Covered-by | Risks: spike leaking into the R-traceability model; stale logic duplicating mtime code | Dependencies: Task 1_
  - Objective: `scale: spike` exists in routing, has a validated Verdict contract, and a 14-day staleness deadline.

  - [x] 2.1 - Routing, template and references
    - Context:
      - Files: `skills/epic/SKILL.md` (scales table :243-249, complexity table :285-291, frontmatter :460), `references/tasks.md` (Fast adaptations :195-203 as the pattern), `.claude-plugin/plugin.json` (:24-29 userConfig.defaultScale)
    - Objective: spike is a first-class scale with its tasks-only + Verdict template.
    - ToDo:
      - Add the spike row to both SKILL tables (signals: "probe", "spike", "experiment", "harness", exploratory intent; never auto-downgrade a feature to spike) and to the frontmatter `scale:` line; accept `spike` in userConfig.defaultScale.
      - references/tasks.md gains a "Spike Scale Adaptations" block mirroring the Fast block: tasks.md only, no `Requirements:` fields, single-author, plus the mandatory `## Verdict` template (`status: open|promote|wont-do`, `conclusion:`, `promoted-to:` when promote) (R1.1).
    - Tests: Covered by Task 2.2 — structural doc edits (grep-validated); the template's tasks-only + Verdict contract is asserted by 2.2's conforming-spike-passes scenario
    - Validation: grep finds spike in both tables + template block; a spike fixture created per the block passes task 2.2's validation
    - Requirements: R1.1

  - [x] 2.2 - Spike validation
    - Context:
      - Files: `scripts/validate-story.sh` (scale branch from task 1)
    - Objective: the Verdict contract is enforced and the R-chain is forbidden.
    - ToDo:
      - `scale: spike` branch: `## Verdict` section with a valid `status:` line required → missing = add_error (R1.2); `status: promote` without `promoted-to:` → add_error (R1.3).
      - Any `Requirements:` field or delimited R-token in a spike tasks.md → add_error "spikes have no requirements chain — promote to a story for traceability" (R1.4).
    - Tests: Unit · `tests/spike-validation.bats` — conforming spike passes, missing Verdict error, promote w/o promoted-to error, wont-do passes, Requirements-field and R-token errors
    - Validation: bats matrix (no Verdict, open/promote/wont-do, promote w/o target, R-ref present)
    - Requirements: R1.2, R1.3, R1.4

  - [x] 2.3 - Spike lifecycle: staleness, promote offer, archive eligibility
    - Context:
      - Files: `references/list-mode.md`, `scripts/monitor-stale.sh` (:36-61 mtime helper), `.epic/stories/005-archive-in-the-flow/design.md` (preflight)
    - Objective: open spikes expire visibly at 14 days; promote hands off to CREATE; terminal spikes archive cleanly.
    - ToDo:
      - The 14-day threshold LIVES in `scripts/monitor-stale.sh` (add a spike-aware threshold branch there, sequenced AFTER story 004 task 2.2's edit of the same file); list-mode consumes that logic — no inline stat duplication (this is the surface `tests/spike-stale.bats` pins) (R1.5).
      - Interactive Verdict→`promote`: offer to run CREATE for the follow-up story pre-filled with `conclusion:`; record `promoted-to: NNN` back in the Verdict (R1.6).
      - Archive eligibility: Verdict `wont-do`, or `promote` with `promoted-to:` recorded, counts as complete — the CODE for this lives in 005's archive-story.sh preflight (already tasked there, 005 task 1.1); here: document it in list-mode + extend epic-index.sh spike rows to render the Verdict status, adding the spike-row case to `tests/epic-index.bats` at execution (test_surface_adjusted) (R1.7).
    - Tests: Unit · `tests/spike-stale.bats` — 15d open spike flagged, 13d not, 15d wont-do not flagged
    - Validation: touch-dated fixtures (13d vs 15d) flip the flag; promote flow documented with the offer; archive preflight sentence present
    - Requirements: R1.5, R1.6, R1.7

  - [x] 2.4 - Commit
    - Validation: full bats suite green; a real spike fixture validates clean end-to-end
    - Commit: "feat(007): spike scale — routing, verdict contract, staleness and promote flow"

- [x] 3 - Versioning policy wizard and contradiction lint
  - _Complexity: Moderate | Tests: Integration (epic-gitpolicy.bats) + Covered-by/None | Risks: silently changing git behavior in non-interactive runs; false contradiction on fresh repos | Dependencies: None (parallel-safe with Task 2)_
  - Objective: the policy is an explicit recorded choice, and git reality is linted against it.

  - [x] 3.1 - epic-gitpolicy.sh lint
    - Context:
      - Files: `scripts/validate-story.sh` (JSON conventions), `.epic/docs/analise-casos-reais-epic.md` (kpranois/bentoolkit evidence)
    - Objective: one read-only script computes the policy verdict.
    - ToDo:
      - New `scripts/epic-gitpolicy.sh`: read `.epic/.gitpolicy` (absent → `undeclared`); detect root-gitignore `.epic` rule; count `git ls-files` hits for `.epic/*.md`-class artifacts vs `.draft/` files; derive verdict: `consistent` (reality matches declared or undeclared+untracked), `contradiction` (tracked files under an ignoring gitignore, or policy says tracked-md but nothing tracked and gitignore blocks it), `partial` (`.draft/` files tracked, or subset tracking) (R4.1).
      - Not a git repo → `{git: false, verdict: "consistent"}` and nothing else (R4.3). JSON contract with `json_escape()`; exit 0 always except usage (2).
    - Tests: Integration · `tests/epic-gitpolicy.bats` — local-only/tracked-md consistent, kpranois-style contradiction, tracked-.draft partial, undeclared consistent, non-git silent
    - Validation: bats matrix in temp repos: local-only consistent, tracked-md consistent, kpranois-style contradiction, tracked-.draft partial, non-git silent
    - Requirements: R4.1, R4.3

  - [x] 3.2 - Init wizard question and writes
    - Context:
      - Files: `references/init-mode.md` (step 5, :25-27 — already writes `.epic/.gitignore` with `.draft/`)
    - Objective: init asks, writes the chosen state, and records it.
    - ToDo:
      - Extend init step 5 into the explicit two-option question (versioned-artifacts recommended; local-only) (R3.1); run epic-gitpolicy.sh first and present the detected state.
      - Versioned: write `.epic/.gitignore` (`.draft/`, `*.wip`); root gitignore has an `.epic` rule → ask consent to remove it (never remove silently); record `tracked-md` in `.epic/.gitpolicy` (R3.2).
      - Local-only: ensure root gitignore ignores `.epic/`; record `local-only` (R3.3).
      - Non-interactive init: apply local-only without prompting — never silently start committing (R3.4).
      - Document the policy + evidence (history destruction) in init-mode.md and README; note the per-project choice supersedes any global doctrine.
    - Tests: None — init wizard is agent-executed; both resulting file-states are exercised as real-repo fixtures in 3.1's tests
    - Validation: init walkthrough in both branches yields the right gitignore + `.gitpolicy` in a temp repo; non-interactive branch documented
    - Requirements: R3.1, R3.2, R3.3, R3.4

  - [x] 3.3 - LIST notice line
    - Context:
      - Files: `references/list-mode.md` (header area)
    - Objective: contradictions become visible where the user already looks.
    - ToDo:
      - LIST header: run epic-gitpolicy.sh; verdict != `consistent` → one line naming it (e.g. "⚠ .epic tracking contradicts declared policy (contradiction: 47 files tracked under ignoring gitignore)"); `undeclared` surfaces only in `stories full` (low noise) (R4.2).
    - Tests: Covered by Task 3.1 — the notice condition (verdict != consistent) is exactly the lint verdict tested there; rendering is agent doc
    - Validation: fixture project with contradiction shows the line; consistent project shows nothing
    - Requirements: R4.2

  - [x] 3.4 - Commit
    - Validation: full bats suite green; shellcheck clean on epic-gitpolicy.sh
    - Commit: "feat(007): versioning-policy wizard, .gitpolicy record and contradiction lint"

- [x] 4 - Pin the contract keys the tech review added (2026-08-09)
  - _Complexity: Simple | Tests: Unit (epic-gitpolicy.bats extension) | Risks: a pin that passes for the wrong reason — a case asserting a key nobody could remove is not coverage | Dependencies: Task 3_
  - Objective: the two JSON keys added after Phase 3 froze the test file get executable coverage, so removing one reddens the suite instead of silently orphaning two reference docs.

  - [x] 4.1 - Cases for `gitignore_source` and the non-git `policy`
    - Context:
      - Files: `tests/epic-gitpolicy.bats` (its six pre-authored cases and their fixture helpers), `scripts/epic-gitpolicy.sh` (the emitter and the `epic_ignore_probe` function)
    - Objective: four cases pin what two reference documents already instruct agents to read — three for `gitignore_source`, one for the non-git `policy`.
    - ToDo:
      - Extend `tests/epic-gitpolicy.bats` (append only — never alter a pre-authored assertion) with: `gitignore_source` naming the root `.gitignore` when the rule lives there; naming `.git/info/exclude` when it lives there instead; and `null` when nothing ignores `.epic` (R4.1).
      - One case asserting the **non-git** object carries `policy` with the declared value, alongside `git: false` and `verdict: consistent` (R4.3).
      - **Prove each new case by mutation, not by assertion**: temporarily break the behaviour in the script, show the new case reddens, restore, show it greens. A pin nobody can redden is the untested claim story 004 measured and rejected.
    - Tests: Unit · `tests/epic-gitpolicy.bats` — this sub-task's deliverable IS the test; it is characterization of shipped behaviour, so Red comes from the mutation proof rather than from a failing-first run
    - Validation: whole `bats tests/` green; each new case reddens under its own mutation and greens on restore; `shellcheck` clean
    - Requirements: R4.1, R4.3

  - [x] 4.2 - Commit
    - Validation: full bats suite green
    - Commit: "test(007): pin the two contract keys the tech review added"

- [x] 5 - Close the validate-007 findings (2026-08-09)
  - _Complexity: Moderate | Tests: Unit (run-mode exemption, `--once`, gitpolicy arms, spike/story.md contradiction) | Risks: the same defect this task exists to close recurring inside its own commit — a pin that cannot redden, a gate sentence written without re-reading its own output | Dependencies: Task 4_
  - Objective: the validate run found the implementation sound and the self-assessment layer not. Close the two defects that stop execution, pin the four branches nobody can redden, and make every gate sentence and register entry match what the artifacts actually support.

  - [x] 5.1 - Spike is exempt wherever Fast is exempt
    - Context:
      - Files: `references/run-mode.md` (:16 materialization scale scope, :18 the converse guard, :81-120 test-first ordering), `references/context-discovery.md` (:54 standard/full vs fast), `references/list-mode.md` (:157 the promote offer, today reachable only from LIST), `skills/epic/SKILL.md` (:259 — its carve-out says "in this document", which is why it does not reach run-mode.md)
    - Objective: a spike Run completes instead of stopping at step 7.
    - ToDo:
      - `run-mode.md:18`'s guard stops any sub-task whose `Tests:` is not `None` with no `.draft/authored-tests/` file, and exempts Fast alone. A spike has no `.draft/` either (design.md:20) and `Tests` is optional-but-permitted at spike scale (`references/tasks.md:264`), so today a spike sub-task carrying `Tests:` is refused execution. Name spike alongside fast in every scale-scoped clause: `:16`, `:18`, `:81-120`, and `context-discovery.md:54` (R1.1).
      - Run mode must reach the promote offer: `run-mode.md` mentions neither `spike` nor the Verdict today (its one `verdict` hit at `:569` is `archive-story.sh`'s JSON). Point at `list-mode.md:157` the way the Archive offer points at validate-mode.md — **define once, reuse**, never a second spelling (R1.6).
    - Tests: Unit · `tests/spike-run-exemption.bats` — the guard clause names spike wherever it names fast (one case per scale-scoped clause); run-mode.md carries a pointer to the promote offer. House-style doc-contract suite, same shape as `tests/hook-monitor-grammar.bats`
    - Validation: `bats tests/spike-run-exemption.bats` red before the edit and green after — this one is genuinely Red-first, the text does not exist yet
    - Requirements: R1.1, R1.6

  - [x] 5.2 - Executable cases for `--once`
    - Context:
      - Files: `scripts/monitor-stale.sh` (:27-57 arg parsing, :59-62 the deliberate ENABLED bypass, :228-231 the single-pass exit), `tests/spike-stale.bats` (:54 — every existing case runs loop mode under `timeout 3`, passing no argument)
    - Objective: the only entry point the docs tell an agent to call stops being readable by no test.
    - ToDo:
      - `--once` is what `references/list-mode.md:145` and `README.md:266` instruct callers to run, and no test in the repo passes any argument to the script. Add cases: `--once` emits the spike notice and exits 0 without the loop; it ignores `enableStaleMonitor` on purpose (set the option off, assert the notice still appears — this is the deviation's own claim, currently unasserted); an unknown argument exits 2 (R1.5).
      - This is characterization of shipped behaviour, so **Red comes from mutation**: break each behaviour in a scratch copy, show the case reddens, restore, show it greens — and **record the mutation and the case it reddened in `.draft/red-evidence.yaml` with `red_via: mutation`**. Task 4.1 did the mutation and wrote the proof only into prose, which is why an auditor could not tell "it ran" from "it was claimed".
    - Tests: Unit · `tests/spike-stale.bats` (append only — never alter a pre-authored assertion)
    - Validation: whole `bats tests/` green; each new case reddens under its own mutation and greens on restore, with both recorded in red-evidence.yaml
    - Requirements: R1.5

  - [x] 5.3 - Executable cases for the four unpinned branches
    - Context:
      - Files: `scripts/epic-gitpolicy.sh` (:403-407, :414-428, :429-434 — three verdict arms; :373-381 `epic_has_untracked_artifacts()`, whose only caller is :414), `scripts/validate-story.sh` (:649-650, the invalid-Verdict-status arm added by deviation 2.2), `tests/epic-gitpolicy.bats` (10 cases, all landing on arms 1, 3 or `consistent`), `tests/spike-validation.bats`
    - Objective: every branch a reference document tells an agent to render is readable by a test.
    - ToDo:
      - Three gitpolicy cases: `tracked-md` declared + an exclude rule blocking + nothing tracked → `contradiction`; declared tracking that never happened → `partial` (the sole caller of `epic_has_untracked_artifacts()`); `local-only` declared + artifacts tracked → `partial`. Each has a rendering row an agent is instructed to print (`references/list-mode.md:77, 79, 80`), and the `:414` arm is the state `references/init-mode.md:209` tells **every** user they will see right after choosing the recommended option — the most reachable non-consistent verdict in the product (R4.1).
      - One `validate-story.sh` case: a `## Verdict` whose `status:` is present but outside the enum errors naming the value and the enum. The arm exists only because deviation 2.2 split R1.2 into two messages; the second has never been executed (R1.2).
      - Characterization again → **mutation-proved and recorded** in `red-evidence.yaml`, same contract as 5.2.
    - Tests: Unit · `tests/epic-gitpolicy.bats` + `tests/spike-validation.bats` (append only)
    - Validation: whole `bats tests/` green; four mutations, four reddened cases, each restored; entries in red-evidence.yaml
    - Requirements: R4.1, R1.2

  - [x] 5.4 - Own the two unowned defects
    - Context:
      - Files: `scripts/validate-story.sh` (:665-679 the spike R-token rule, and the requirements-coverage check that fires in the same run), `ARCHITECTURE.md` (:140), `tests/spike-stale.bats` (:68-69), `.draft/deviations.yaml` (:152-166 — both were registered as discoveries and left unowned)
    - Objective: registration is not closure; the two open discoveries get an owner and a test.
    - ToDo:
      - A malformed spike that also carries a `story.md` reaches the requirements-coverage check and is told to add `Requirements:` fields — exactly what R1.4 forbids. Suppress the coverage check when the declared scale is `spike`; the R2.3 scale-mismatch warning still fires, so the real defect is still reported, just not with contradictory advice (R1.4).
      - `ARCHITECTURE.md:140` still spells `scale: fast | standard | full` — the only enum surface in the repo without `spike` (the four correct ones: `references/tasks.md:11`, `scripts/validate-story.sh:126`, `.claude-plugin/plugin.json:27`, `skills/epic/SKILL.md:471`) (R1.1).
      - `tests/spike-stale.bats:68-69`'s comment says the generic 7-day notice "may appear"; deviation 2.3 made the spike rule *replace* it (`monitor-stale.sh:201` `continue`), so a 13-day spike emits nothing at all. The assertion is right, the comment documents pre-deviation behaviour.
    - Tests: Unit · `tests/spike-validation.bats` — a spike carrying a story.md warns about the scale mismatch and is **not** told to add `Requirements:` fields. Red-first: today it is
    - Validation: the new case red before the edit, green after; whole `bats tests/` green; `command grep` (not `grep`, which skips `.epic/`) finds `spike` in every enum surface including ARCHITECTURE.md
    - Requirements: R1.1, R1.4

  - [x] 5.5 - Interactive local-only warns before it can manufacture a contradiction
    - Context:
      - Files: `references/init-mode.md` (:153-172 step 5.4a, which appends `.epic/` to the root gitignore with no reference to `tracked_md`; :35 forbids init from ever running `git rm --cached`; :191-197, where the headless path was hardened against exactly this)
    - Objective: the interactive path gets the guard the headless path already has.
    - ToDo:
      - Choosing local-only in a repo that already tracks artifacts leaves `gitignore_ignores_epic: true` with `tracked_md > 0` — `verdict: contradiction`, the kpranois shape, produced by the wizard itself. Init correctly never untracks anything, so the fix is disclosure, not action: when the pre-read lint reports `tracked_md > 0`, state the count, name the resulting verdict, and require an explicit confirmation before writing the rule — the same default-no shape as the gitignore-removal consent at `:127-140` (R3.3).
      - This is the mirror of the harm the story exists to prevent, and the headless branch already reasons about it; only the interactive branch is silent.
    - Tests: Covered by Task 5.3 — the deciding condition is the `local-only` + tracked-artifacts arm pinned there; the prompt itself is agent-executed prose
    - Validation: a temp repo with tracked artifacts reports `verdict: partial`/`contradiction` per 5.3's cases, and the documented flow names the count before writing
    - Requirements: R3.3

  - [x] 5.6 - Honest gates and complete registers
    - Context:
      - Files: `tasks.md` (the `## Quality Gates` block), `.draft/red-evidence.yaml` (four entries, none for 4.1), `.draft/deviations.yaml` (ten entries, none for the two below), `.draft/tasks.md` (:122 — the Phase-3 draft, which does **not** contain Gate 1's false clause)
    - Objective: no sentence in this story claims more than its artifacts support.
    - ToDo:
      - Gate 1: "every Rn maps to exactly one sub-task" is contradicted by the tool it cites — `cross-reference.sh` maps `R4.1` and `R4.3` to `["3.1","4.1"]` (and more sub-tasks after this task). The clause was added at check-off, after Task 4 created the second mapping; it is absent from the Phase-3 draft. Restate as the real mapping.
      - Gate 4 ("no orphaned implementations"): falsified by its own definition until 5.2 and 5.3 land — restate then, citing the cases rather than the claim.
      - Gate 5: its title names an "absent **scanner** path" that does not exist in this story — it is story 005's gitleaks path, copied into the draft (`.draft/tasks.md:126`) and checked off uncorrected. The three paths it actually evidences are real; name those.
      - Gate 2: "every sub-task's Validation command was executed" is not auditable for 3.2/3.3, whose Validation is an agent walkthrough leaving no artifact — say so instead of implying a record exists.
      - Gate 3: `tasks.md:128` says "three cases" where four exist; align the plan with its own deliverable.
      - `red-evidence.yaml`: retroactive entry for **4.1** with `red_via: mutation`, naming each mutation and the case it reddened, plus a header note that the file covers post-Phase-3 tasks too — a task group added after Phase 3 gets no Test Advisor pass, which is how this went unrecorded.
      - `deviations.yaml`: register the two unregistered changes — design.md:62's Integration testing level downgraded to `Tests: None`/"Covered by" (3.2, 3.3), and task 2.3's `test_surface_adjusted` ToDo that turned out to be a no-op (`tests/epic-index.bats` untouched by this story; the behaviour had already shipped in 005) yet was self-marked `[x]`.
    - Tests: None — register and gate text; every claim rewritten here is verified by executing the command it cites, which is the sub-task's own Validation
    - Validation: each rewritten gate re-verified by running its cited command and pasting the output; `cross-reference.sh` and `validate-story.sh` clean on the story; `bats tests/` green

  - [x] 5.7 - Commit
    - Validation: full bats suite green; `shellcheck` clean; story validates 0 errors / 0 warnings
    - Commit: "fix(007): close the validate findings — spike exemption in Run, four unpinned branches, honest gates"

## Quality Gates

Every claim below was re-verified at sub-task 5.6 by running the command it names. Where a claim has no command — an agent walkthrough leaves no artifact — the gate says so rather than phrasing the gap as a record.

- [x] All acceptance criteria validated (R1.1–R4.3 traced by cross-reference.sh) — `bash scripts/cross-reference.sh .epic/stories/007-spike-scale-and-epic-versioning-policy` reports `traced: 17`, `coverage: "17/17"`, `orphan_requirements: []`, `phantom_references: []`, `status: clean`. **Eight of the seventeen requirements map to more than one sub-task** — R1.1 and R4.1 to three, R1.2, R1.4, R1.5, R1.6, R3.3 and R4.3 to two — and nine map to exactly one, because Tasks 4 and 5 deliberately re-entered requirements Tasks 1–3 had already implemented, to pin branches no test could redden. This line ended "every Rn maps to exactly one sub-task" until 5.6: the tool it cites already said otherwise (`R4.1 → ["3.1","4.1"]` the moment Task 4 landed), and the clause is absent from the Phase-3 draft at `.draft/tasks.md:122` — it was written at check-off, not planned
- [x] All task validations pass, as far as "pass" is auditable — `bash scripts/validate-story.sh` on each of the seven directories under `.epic/stories/` returns `errors: 0, warnings: 0, status: pass`, seven times. **The per-sub-task half is NOT auditable for 3.2 and 3.3, and this line no longer implies a record exists**: their Validation is an init walkthrough and a LIST notice line, and init and LIST are agent-executed prose rather than scripts — no command in this repository re-runs either, and nothing was written down when they were walked. What *is* pinned for both is the condition they branch on (3.1's and 5.3's verdict cases); what is not is the walkthrough itself. **5.5 is the exception worth naming**: its Validation is a temp repo read by `scripts/epic-gitpolicy.sh`, so it does re-run, and it was re-run at 5.6 — `verdict: partial` with `tracked_md: 2` before the local-only append, `verdict: contradiction` with the same count after
- [x] All tests written and passing — `bats tests/` reports `1..360`, 360 ok / 0 not ok, across the 20 suites in `tests/`, up from 343 across 19 before Task 5. The +17: 8 in the new `tests/spike-run-exemption.bats` (5.1, genuinely Red-first — the text it greps for did not exist yet), 3 `--once` cases in `tests/spike-stale.bats` (5.2), 4 verdict-arm cases in `tests/epic-gitpolicy.bats` plus 1 invalid-Verdict-status case in `tests/spike-validation.bats` (5.3), and 1 spike-beside-story.md case in `tests/spike-validation.bats` (5.4). Task 4's **four** cases — three for `gitignore_source`, one for the non-git `policy` — and 5.2's and 5.3's eight are characterization of shipped behaviour, so Red came from an applied-and-reverted mutation rather than from a failing-first run; every mutation and the `not ok` line it produced is recorded case-by-case in `.draft/red-evidence.yaml`. `shellcheck scripts/*.sh` exits 0 across all 23 scripts. **"Written" is not "all of design.md's plan"**: design.md:66's **Integration** testing level is unfulfilled and stays that way — 3.2 shipped `Tests: None` and 3.3 `Tests: Covered by Task 3.1`, registered in `.draft/deviations.yaml` — because init and LIST are agent-executed prose with no callable entry point. What is pinned for both is the file-state and the verdict they produce, never the walkthrough. This clause was added at 5.6's own check-off, after 5.6 registered the deviation its title contradicted
- [x] Code integrated (no orphaned implementations) — orphaned here means: a reference document instructs an agent to read it, and no test can tell whether it still works. Three sets were, and each is now pinned by a case that reddens under an applied-and-reverted mutation of the shipped script. **Task 4's two JSON keys** (`tests/epic-gitpolicy.bats` cases 7–10): deleting the `gitignore_source` line from the emitter reddens cases 7, 8 and 9 — plus 5.3's case 11, which asserts the same field for another arm — while **all six pre-authored cases stay green**; deleting `policy` from the non-git object, which is literally this plan's own "and nothing else" at 3.1, reddens case 10 alone, with the pre-authored non-git case 6 green beside it because case 6 asserts only `.git` and `.verdict`. **`monitor-stale.sh --once`** (`tests/spike-stale.bats` cases 4–6, sub-task 5.2) — the entry point `references/list-mode.md:145` and `README.md:266` instruct callers to run, and to which no test passed any argument. **Three of the five verdict arms, arm 4's guard, and the invalid-Verdict-status arm** (`tests/epic-gitpolicy.bats` cases 11–14 and `tests/spike-validation.bats` case 8, sub-task 5.3), each with a row an agent is instructed to render. The Verdict grammar's four readers each name the count in their comment — `command grep -n "all four move together" scripts/epic-index.sh scripts/archive-story.sh scripts/validate-story.sh scripts/monitor-stale.sh` returns four lines — so amending a regex moves all four
- [x] Error handling implemented (non-git, non-interactive, absent-Verdict paths) — **non-git**: `{git: false, policy, verdict: "consistent"}` at exit 0 and exactly those three keys (`tests/epic-gitpolicy.bats` cases 6 and 10; measured at 5.6, case 10 is the only one of the fourteen that reddens when `policy` is dropped). **Non-interactive init (R3.4)**: applies local-only only where `policy` is `undeclared`, and leaves a declared `tracked-md` alone. That path is agent-executed prose in `references/init-mode.md` and **no test covers it**; what is measured is the counterfactual it exists to avoid — re-run at 5.6, applying local-only over a declared `tracked-md` with 2 artifacts tracked takes the lint from `verdict: consistent` to `contradiction`. **Absent or unreadable Verdict**: fail-closed in all four readers, executed for two of them (`tests/spike-validation.bats` case 2; `tests/epic-index.bats` "a spike with no readable Verdict renders the em dash") and measured directly at 5.6 for the other two, which no test covers — on a Verdict-less spike whose every box is closed, `archive-story.sh` answers `status: "refused"` at exit 1, and `monitor-stale.sh --once` still nags a 30-day-old one. This gate's title read "absent **scanner** paths" until 5.6: there is no scanner anywhere in this story — the phrase is story 005's gitleaks path (`.epic/stories/005-archive-in-the-flow/tasks.md:81`), copied into the Phase-3 draft at `.draft/tasks.md:126` and checked off uncorrected
