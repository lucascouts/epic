---
story: quality-catalog-and-legend
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Implementation Plan - Quality catalog and legend

## Overview

The catalog is written first because every other site cites it. The templates and the modes that read them follow: requirements, tasks, init, constitution, analyst, validate, plain register. The script gains the coverage measurement last, with its cases, and the doc contract pins the prose.

## Task List

- [x] 1 - The catalog and the templates
  - _Complexity: Simple | Tests: Unit | Risks: a template change the validator reads as a missing section | Dependencies: None_
  - Objective: The catalog exists, the story and tasks templates carry the legend and the field, and every mode that reads them knows.

  - [x] 1.1 - `references/quality-catalog.md`
    - Context:
      - Files: `references/preferred-tooling.md` (the never-install rule to cite), `references/plain-register.md` (how the legend is rendered to a layperson)
    - Objective: One file names the three tiers, the selection rule, the Q grammar and the never-install rule.
    - ToDo: Write the always tier (formatting, lint, types, error handling with context, unit tests, lockfile and frozen install, dependency vulnerabilities, secrets, README, `.gitignore` and `.editorconfig`), the context tier with the signal per item (integration/E2E, contract tests, structured logs and health, migrations, SAST, image digest and non-root and scan, pinned Actions, accessibility, licence/SBOM/signing, minimum dependency age), and the on-request tier (fuzzing, benchmarks, coverage threshold, mutation). State how the set is chosen (constitution `## Quality` plus the Analyst's detection plus the request), the `Qn` grammar, one command per item, and that activating never installs.
    - Tests: Unit · `tests/quality-catalog.bats` — the three tier headings exist; the always tier names lint, types, secrets; the context tier names a signal column; the file says `never installs`
    - Validation: `bats tests/quality-catalog.bats` green
    - Requirements: R1.1, R1.2
    - Quality: Q1

  - [x] 1.2 - Story and tasks templates
    - Context:
      - Files: `references/requirements.md` (story template and guidelines), `references/tasks.md` (template, Content Fields, Rules, Fast Scale Adaptations, Quality Gates)
    - Objective: The story template carries `## Quality Requirements`; the tasks template carries `Quality:` and generated gates; the rules say coverage is measured.
    - ToDo: In requirements.md add the section to the template and guideline 7 on the legend. In tasks.md add `- Quality: Q1, Q3` to the sub-task example, a `Quality` row to Content Fields, a generated-gate line to the Quality Gates template with prose that says one box per active `Qn` with its command after the five fixed gates, rule 12 on quality coverage naming `cross-reference.sh`, and the Fast adaptation that the legend lives at the top of `tasks.md`.
    - Tests: Unit · `tests/quality-catalog.bats` — requirements.md template has the section; tasks.md documents the field, the generated gates and rule 12; the Fast adaptation names the legend
    - Validation: `bats tests/quality-catalog.bats` green; `bats tests/validate-story.bats tests/cross-reference.bats` still green
    - Requirements: R2.1, R2.2, R3.1, R3.2
    - Quality: Q1

  - [x] 1.3 - The modes that read the legend
    - Context:
      - Files: `references/init-mode.md` (Defaults block, Rules), `references/constitution.md` (template), `agents/analyst.md` (Function 1), `references/phase-gates.md` (Reference Files Loaded Per Phase), `references/validate-mode.md` (gate settlement), `references/plain-register.md` (Words that stay in the files)
    - Objective: Init writes `## Quality`, the Analyst detects the context tier, Phase 1 and 3 load the catalog, validate runs a `Qn` gate's command, and a layperson sees checks rather than identifiers.
    - ToDo: Add the `## Quality` block to the init procedure and a Rules line; add the section to the constitution template and example; add a Function 1 step to the Analyst that reports the catalog's context signals present in the tree; add `quality-catalog.md` to the Phase 1 and Phase 3 rows; extend the validate prompt so a `Qn` gate is settled by its command; add a row to the plain register mapping `Q1…Qn` to "the checks I ran".
    - Tests: Unit · `tests/quality-catalog.bats` — init Procedure names `## Quality`; constitution template has it; analyst Function 1 names the catalog; phase-gates rows name it; validate-mode names the command; plain-register maps the identifier
    - Validation: `bats tests/quality-catalog.bats tests/requester-register.bats` green
    - Requirements: R2.3, R3.3, R3.4
    - Quality: Q1

  - Commit: "feat(024): a quality catalog, a legend in the story, and gates generated from it"

- [x] 2 - Coverage in the script
  - _Complexity: Moderate | Tests: Unit | Risks: touching a script with a known group-header defect; the R parser must not move | Dependencies: Task 1_
  - Objective: `cross-reference.sh` reports quality coverage when a story declares Q identifiers, and nothing when it does not.

  - [x] 2.1 - The `quality` object
    - Context:
      - Files: `scripts/cross-reference.sh` (the tasks parse loop, the output block, the absent-not-zeroed rule in the header), `tests/cross-reference.bats` (case style)
    - Objective: Declared, cited, orphan and phantom Q identifiers are measured from the legend and the `Quality:` fields.
    - ToDo: Collect `Q[0-9]+` tokens from the `## Quality Requirements` section of story.md; in the existing tasks loop add a `Quality:` branch that maps each token to the sub-task, on the same heading regex; compute orphans and phantoms; emit `"quality": {"declared", "cited", "orphans", "phantoms"}` only when the legend declares at least one token, and fold orphans and phantoms into `HAS_ISSUES`; on error keep the script's exit contract. Document the key in the header comment and `--help`.
    - Tests: Unit · `tests/cross-reference.bats` — legend fully cited → `orphans: []` and exit 0; one uncited Q → listed and exit 1; one cited undeclared Q → phantom and exit 1; no legend → the `quality` key is absent and an R-clean story stays exit 0
    - Validation: `bats tests/cross-reference.bats` green; `shellcheck scripts/cross-reference.sh` clean
    - Requirements: R4.1, R4.2, R4.3, R4.4
    - Quality: Q1, Q2

  - Commit: "feat(024): cross-reference.sh measures quality coverage"

- [x] 3 - Suite and changelog
  - _Complexity: Trivial | Tests: Unit | Risks: None | Dependencies: Task 2_
  - Objective: The doc contract pins the catalog and the changelog records it.

  - [x] 3.1 - `tests/quality-catalog.bats`
    - Context:
      - Files: `tests/requester-register.bats` (the anchored-block style to copy)
    - Objective: One suite pins every prose site of task 1.
    - ToDo: Write the cases named in 1.1, 1.2 and 1.3 in the anchored-block style, with a header index.
    - Tests: Unit · `tests/quality-catalog.bats` — the suite is its own test
    - Validation: `bats tests/quality-catalog.bats` green; `bats tests/` green
    - Requirements: R1.1, R2.1, R2.3, R3.1, R3.2, R3.3, R3.4
    - Quality: Q1

  - [x] 3.2 - Changelog entry
    - Objective: `[Unreleased]` records the catalog, the legend, the field, the generated gates and the measurement.
    - ToDo: Add an entry under `### Added` naming the three tiers, `## Quality Requirements`, `Quality:`, the generated gates and the `quality` object of `cross-reference.sh`.
    - Acceptance:
      - The entry names `quality-catalog.md`, `Quality Requirements` and `cross-reference.sh`
    - Validation: `command grep -c 'quality-catalog.md' CHANGELOG.md` is at least 1
    - Requirements: R1.1, R4.1
    - Quality: Q1

  - Commit: "test(024): the doc contract pins the catalog; changelog records it"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [x] Error handling implemented
- [x] Q1 — Unit tests: `bats tests/` green
- [x] Q2 — Lint: `shellcheck scripts/*.sh bin/*` clean
