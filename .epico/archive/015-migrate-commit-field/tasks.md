---
story: migrate-commit-field
type: feature
scale: full
status: archived
version: 2
created: 2026-08-16
---

# Implementation Plan - Migrate and the Commit Field

## Overview

Contract before rewriters (the dry-run/apply/refusal skeleton is what every
variant plugs into), rewriters before the template flip (migrate must be able
to convert the legacy shape the moment the template stops prescribing it), and
the consumer sweep last, rebased on story 010's run-mode text per the wave
sequencing. The all-variants fixture closes the story.

## Task List

- [x] 1 - migrate-story.sh: the contract
  - _Complexity: Moderate | Tests: Unit | Risks: stdout purity — the diff goes to stderr or the house JSON contract breaks | Dependencies: None_
  - Objective: Dry-run by default, apply on demand, refusals loud, idempotency by grammar.

  - [x] 1.1 - Skeleton: dry-run, JSON verdict, refusal arms
    - Context:
      - Files: `scripts/archive-story.sh:81-284` (house contract), `scripts/supersede-story.sh:464-483` (`rewrite_file`), `scripts/cross-reference.sh:142-161` (majority frontmatter dialect), `scripts/validate-story.sh:514-528` (fence tracking)
    - Objective: `migrate-story.sh <NNN|dir> [--apply]` detects, reports, and without `--apply` writes nothing.
    - ToDo: story resolution + archive self-refusal (the PreToolUse guard blocks tools, not Bash), unknown-story refusal, unreadable-file refusal before any partial diff, and unparseable-mixture refusal naming lines — all exit 1 (R1.3); dry-run default emits JSON `{story, applied:false, changed_files, rewrites:{t1_headers, covers_fields, boxes_added, wrapper_tags, fast_requirements, commit_subtasks}, validate:null}` on stdout (`changed_files` = would-change list on dry-run, did-change under --apply), unified diff on stderr (R1.1); detector table runs fence-aware over each artifact; `set -euo pipefail`, exits 0/1/2.
    - Tests: Unit · `tests/migrate-story.bats` — filter `^1.1:`: dry-run stdout is one JSON object (applied:false, validate:null, all six rewrite counters), unified diff on stderr, tree byte-identical; archive-resident target refused exit 1 with the reason on stderr and applied:false JSON intact; unparseable mixture refused exit 1 naming the offending lines, tree byte-identical; unknown story refused exit 1; unreadable file refuses before any partial diff; no arguments exits 2
    - Validation: bats: dry-run on a variant fixture emits valid JSON + diff and leaves the tree byte-identical; archive target refuses
    - Requirements: R1.1, R1.3

  - [x] 1.2 - Apply: atomic rewrite, embedded validate, idempotency, version bump
    - Context:
      - Files: `scripts/validate-story.sh` (invocation + verdict shape), `scripts/archive-story.sh:150-170` (full JSON escape table)
    - Objective: A migration is proven by the validator it triggers, and a second run is a no-op.
    - ToDo: `--apply` rewrites via `rewrite_file` (CRLF preserved); then run `validate-story.sh` guarded (`|| rc=$?`) and embed `{errors,warnings,status}` (R1.2); bump `version:` only in changed artifacts (R1.5); idempotency by grammar — canonical lines match no detector, second run reports `rewrites: 0`, no diff (R1.4); no marker files.
    - Tests: Unit · `tests/migrate-story.bats` — filter `^1.2:`: --apply embeds the `{errors,warnings,status}` verdict and the variant is gone; second --apply reports rewrites summing to 0, no diff, tree unchanged; CRLF fixture round-trips (tag stripped, every surviving line still ends CRLF); `version:` bumps only in the changed artifact, the untouched sibling keeps its version; a failing embedded validate keeps exit 0 with `validate.errors >= 1` in the JSON and the rewrite standing (no rollback)
    - Validation: bats: apply → validate verdict embedded; second apply → `rewrites:0`, tree unchanged; CRLF fixture round-trips
    - Requirements: R1.2, R1.4, R1.5

  - Commit: "feat(015): migrate-story.sh — dry-run-first normalizer with embedded proof"

- [x] 2 - The five variant rewriters
  - _Complexity: High | Tests: Unit | Risks: over-eager detection — fences and satisfied-by are the immunity lines | Dependencies: Task 1_
  - Objective: Every corpus variant converts; nothing else changes.

  - [x] 2.1 - Variants 1-2: T1/Covers house style, checkbox-less lists
    - Context:
      - Files: `scripts/validate-story.sh:670-674` (existing detection hint regexes), `references/tasks.md` (canonical shapes)
    - Objective: The 17 invisible bentoolkit-shaped files become parseable.
    - ToDo: `## T1`/`### T2` headers + `**Covers:**`/`Covers:` fields → `- [ ] N - Name` + `- Requirements:` lines (R2.1); checkbox-less list items under task headings → boxes added as `[ ]` only — never `[x]`, migrate records shape, not completion (R2.2); fence-aware throughout.
    - Tests: Unit · `tests/migrate-variants.bats` — filter `^2.1:`: T1/Covers fixture converts to canonical boxes + `- Requirements:` lines and `cross-reference.sh` reports status clean with a non-empty mapping; checkbox-less items gain only `[ ]` boxes (zero `[x]`) and field lines stay fields; a `## T1` inside a fenced block survives while the naked one converts
    - Validation: bats: bentoolkit-shaped fixture converts and `cross-reference.sh` mapping goes non-empty; checkbox-less fixture gains only `[ ]` boxes
    - Requirements: R2.1, R2.2

  - [x] 2.2 - Variants 3-4: wrapper tags, fast-scale Requirements
    - Context:
      - Files: `scripts/validate-story.sh:311-316` (scale predicate), story 014's satisfied-by grammar (wave sibling — coordinate the token regex)
    - Objective: Leak artifacts strip; dangling pointers go; sanctioned suffixes stay.
    - ToDo: `</content>`/`</invoke>` outside fences → stripped, inside → untouched (R2.3); when resolved scale (tasks.md authoritative, majority dialect) is fast/spike: remove `Requirements:` fields and R-tokens, preserving any `satisfied-by:` suffix byte-for-byte (R2.4).
    - Tests: Unit · `tests/migrate-variants.bats` — filter `^2.2:`: naked `</content>` strips while the fenced `</invoke>` survives; fast fixture loses its suffix-less `Requirements:` line and R-token while `satisfied-by:` survives byte-for-byte; a fully canonical standard story is a byte-identical no-op (rewrites sum 0)
    - Validation: bats: fenced wrapper tag survives, naked one strips; fast fixture loses `Requirements:` and keeps `satisfied-by:`; standard fixture untouched by variant 4
    - Requirements: R2.3, R2.4

  - [x] 2.3 - Variant 5: Commit sub-task → group field, gap preserved
    - Context:
      - Files: `references/tasks.md:46-48,206-212` (both legacy shapes), `.epic/archive/` fixtures for real Commit sub-task shapes
    - Objective: The false-partial factory's existing inventory converts without touching provenance.
    - ToDo: `- [ ] N.M - Commit` (and `[x]`/`[~]` closed forms) with their `Commit:`/`Validation:` body → group-level `- Commit: "..."` on the parent, message verbatim; the N.M gap remains — no renumbering ever (R2.5); a closed Commit box's state is simply dropped (the field has no box; the census consequences are story-level, stated in Task 3).
    - Tests: Unit · `tests/commit-field.bats` — filter `^2.3:`: `[x] 1.3 - Commit` becomes exactly one group-level `- Commit:` field inside group 1 with the message verbatim; the closed box's state is dropped (no Commit-titled box of any state remains); 1.1/1.2 survive verbatim, no `1.3` reappears, task 2/2.1 keep their numbers; the `Dependencies: Task 1.2` pointer still resolves
    - Validation: bats: group with 1.1, 1.2, 1.3-Commit → field on parent, 1.3 absent, 1.1/1.2 untouched; deviations-style pointer `Task 1.2` still resolves
    - Requirements: R2.5

  - Commit: "feat(015): the five corpus variants convert — honestly and fence-aware"

- [x] 3 - Template flip and the consumer sweep
  - _Complexity: Moderate | Tests: Unit | Risks: half-swept copies become false audit findings — the inventory in design.md is the checklist | Dependencies: Task 2 (migrate must convert what the template stops prescribing)_
  - Objective: Every copy prescribes the field; ordering prose matches the new census reality.

  - [x] 3.1 - references/tasks.md + the four examples
    - Context:
      - Files: `references/tasks.md` (template :46-48, field table :160, §Commit Sub-tasks :206-212, Rule 10 :234, Gotchas :255, Fast adaptations :264, Acceptance note :203), `assets/examples/*.md` (all four)
    - Objective: The template and its teaching examples emit the field form only.
    - ToDo: template shows `- Commit: "type(NNN): ..."` on the parent group; §Commit Sub-tasks retitled §Commit Field with the anchor recommendation moved intact; Rule 10 reworded (field on every group); Fast adaptations + Acceptance notes updated; all four examples converted (they are protocol surfaces); create flows emit field-form only (R3.4).
    - Tests: None — documentation/template sweep with no executable logic; proven by the Validation grep (no checkbox-Commit shape left in `references/` or `assets/examples/`, anchor recommendation still present)
    - Validation: `command grep -rn '\- \[.\] .*- Commit' references/ assets/examples/` returns nothing; `command grep -rn 'Commit sub-task' references/ agents/ | command grep -v 'legacy\|migrate'` returns nothing; anchor recommendation still present
    - Requirements: R3.1, R3.3, R3.4

  - [x] 3.2 - run-mode ordering, validator arm, validate-story nudge
    - Context:
      - Files: `references/run-mode.md` (`--gate=commit` :31, §Commit Sub-tasks :222-224, parallel :551, Rules :566 — rebased on story 010's edits), `references/validate-mode.md:28` + `agents/validator.md:26,35`, `scripts/validate-story.sh:757-763` (`COMMIT_COUNT` already accepts the field)
    - Objective: The tail of a group is ordered for a world where `done` precedes the commit.
    - ToDo: run-mode ordering respecified: close boxes → status census (may write `done`) → execute the group's `Commit:` field → archive offer (R4.1); `--gate=commit` gates at field execution; parallel rule reworded; run-mode's PROSE copies of the sub-task form (:384 "via Commit sub-tasks", :546 "run Commit sub-task") rewritten too; `references/phase-gates.md:160,175,220` and `agents/test-advisor.md:139,142` Commit exemptions reworded to the field form; `references/list-mode.md:235,251` example lines converted; validator + validate-mode verify the commit per group field, SKIP arm updated (R3.3); validate-story: keep field acceptance, add the warning-level nudge naming checkbox Commit sub-tasks as the legacy shape migrate converts (R3.2); dependency-satisfaction consequence stated in tasks.md reference: satisfaction reads existing boxes — no Commit box, no commit wait (R4.3).
    - Tests: Unit · `tests/commit-field.bats` — filter `^3.2:`: PIN a field-only tasks.md raises no commit warning and no legacy nudge; a checkbox Commit sub-task raises the warning-level nudge naming the legacy shape and migrate; run-mode states the tail ordering (close boxes → census → `Commit:` field → archive) and the `--gate=commit` row stops naming sub-tasks; the references state that dependency satisfaction reads the boxes that exist
    - Validation: bats: field-only fixture raises no commit warning, legacy checkbox raises the nudge; ordering text greps in run-mode
    - Requirements: R3.2, R3.3, R4.1, R4.3

  - Commit: "feat(015): Commit is a group field — template, ordering and every consumer copy"

- [x] 4 - Wrapper, routing, and the all-variants round-trip
  - _Complexity: Simple | Tests: Integration | Risks: None | Dependencies: Task 1, Task 2, Task 3_
  - Objective: The entrypoint exists, the router knows it, and one fixture proves the whole pipeline.

  - [x] 4.1 - bin/epic-migrate + SKILL routing (fulfilled: trigger eval measured 5/5 runs on 2026-09-12, run-evals.sh --triggers exit 0 with the installed plugin disabled and --plugin-dir on this tree (log .draft/logs/task-5.1-deferred-evals.log); original deferral — bin/epic-migrate --help exits 2 with the usage, measured; the trigger-eval half is owed because the harness cannot measure this repo, and it is not a login gap: scripts/run-evals.sh calls `claude -p ... --bare`, and --bare's auth is strictly ANTHROPIC_API_KEY or apiKeyHelper -- "OAuth and keychain are never read" -- so no subscription session can satisfy it; dropping --bare does authenticate but resolves the installed epic@lucascouts 0.3.1 from the plugin cache instead of this working tree, so it would grade the wrong copy (two isolation attempts failed: --setting-sources project,local and --settings enabledPlugins=false). The supported path is `claude plugin eval <path>`, which resolves by path; it needs the cases converted to case.yaml/prompt.md/graders, not done here)
    - Context:
      - Files: `bin/epic-validate` (the 4-line exec pattern), `skills/epic/SKILL.md` (routing cascade + Mode Dispatch)
    - Objective: `stories migrate NNN [--apply]` resolves end to end.
    - ToDo: `bin/epic-migrate` exec wrapper; routing arm + dispatch row (order-safe vs the bare `stories` arm); `evals/trigger-queries.json` routing case.
    - Tests: None — 4-line exec wrapper plus routing rows, purely structural; the Validation pair (`--help` exits 2 with usage, trigger eval passes) is the honest check and the script's own contract is already covered by Task 1.1
    - Validation: `bin/epic-migrate --help` exits 2 with usage; trigger eval passes
    - Requirements: R3.3

  - [x] 4.2 - All-variants integration fixture
    - Context:
      - Files: `tests/` (fixture conventions), `tests/archive-story.bats` (counter assertions)
    - Objective: One story carrying all five variants migrates to a clean validate in one apply.
    - ToDo: fixture with T1 headers, a checkbox-less section, a fenced and a naked wrapper tag, a fast sibling with dangling Requirements + satisfied-by, and Commit sub-tasks; `--apply` → embedded validate clean; second apply → `rewrites: 0` (R1.4); archive the migrated fixture and assert manifest counters derive from the boxes that exist (R4.2).
    - Tests: Integration · `tests/migrate-roundtrip.bats` — filter `^4.2:`: one --apply on the all-variants fast fixture fires all six rewrite counters and embeds a clean validate (errors 0, status pass) with every immunity line honored; the second apply reports rewrites summing to 0, no diff, tree unchanged; a migrated field-form story archives with `tasks.total`/`closed` derived from the boxes that exist (exactly one fewer than before migration — the Commit box)
    - Validation: the integration bats file passes; full suite green
    - Requirements: R1.4, R4.2
    - Commit: "test(015): all-variants round-trip — one apply, clean validate, honest counters"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R4.3 each behind a passing test or grep-verifiable copy)
- [x] All task validations pass (fulfilled: the one clause it owed — 4.1's trigger-eval half — is discharged: 5/5 on 2026-09-12, run-evals.sh exit 0; every other task validation had already executed and passed; original deferral — every task validation executed and passed except 4.1's trigger-eval half — see its box: run-evals.sh's --bare flag refuses OAuth by design, and without --bare the CLI grades the cached plugin instead of this repo)
- [x] All tests written and passing (full suite green; immunity lines proven)
- [x] Code integrated (router dispatches; template, examples and validator agree on the field form)
- [x] Error handling implemented (archive refusal, unparseable mixture, stdout purity all exercised)
