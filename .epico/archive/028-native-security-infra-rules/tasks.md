---
story: 028-native-security-infra-rules
type: feature
scale: standard
scale_reason: six requirements across the quality catalog, two agents, two run-mode references and a script, each needing a traceable contract test
engineering: product
requester: developer
run-model: sonnet
version: 1
created: 2026-10-23
status: archived
---

# Implementation Plan - Native security and infra rules

## Overview

One new contract suite, `tests/security-infra-contract.bats`, pins every rule; each sub-task adds its assertions first (Red) and then the text that satisfies them. The catalog rows come first because the validate rule and the report keys cite them; the per-language reference comes before the wiring that names its sections; the eval/exec rule closes the plan because it touches the managed CLAUDE.md block, whose line budget is checked by an existing test.

## Task List

- [x] 1 - Quality-catalog rows
  - _Complexity: Simple | Tests: Unit (bats contract) | Risks: rows read by position in security-floor-gates.bats and engineering-level.bats | Dependencies: None_
  - Objective: The catalog carries the CI mirror, the log rules, tracing, trufflehog, Harden-Runner, Scorecard and Socket

  - [x] 1.1 - CI mirror row and its product activation
    - Context:
      - Files: `references/quality-catalog.md` (By context table, line 12 level sentence), `references/engineering-level.md` (product cell, line 57), `tests/engineering-level.bats` (E10/E13b read these sections)
    - Objective: A `CI mirror` row next to `Hardened workflows`, named among the CI-shaped items `product` activates
    - ToDo: Add the row with signal `.github/workflows/`, command `act -j <job>`, the clean-checkout environment and the root false-red note; add "CI mirror" to the CI-shaped list in quality-catalog.md line 12 and engineering-level.md's product cell
    - Validation: `bats tests/security-infra-contract.bats tests/quality-catalog.bats tests/engineering-level.bats` passes
    - Requirements: R1.1, R1.2, R1.3, R1.5, R6.1
    - Quality: Q2

  - [x] 1.2 - Log rules and tracing
    - Context:
      - Files: `references/quality-catalog.md` (Structured logs and health row; On request table)
    - Objective: The logs row forbids secrets/PII with redaction at the logger and defines levels and a runtime level switch; tracing is on request
    - ToDo: Extend the `Structured logs and health` row's "What it proves" and command cells; add a `Tracing (OpenTelemetry)` row to `## On request`
    - Validation: `bats tests/security-infra-contract.bats tests/quality-catalog.bats` passes
    - Requirements: R4.1, R4.2, R4.3, R6.1
    - Quality: Q2

  - [x] 1.3 - Secrets in CI, Harden-Runner, Scorecard and Socket
    - Context:
      - Files: `references/quality-catalog.md` (Always Secrets row line 29 — NOT the floor row; Hardened workflows row; On request), `tests/engineering-level.bats` E13 (floor must keep gitleaks)
    - Objective: trufflehog named for CI in the always-tier Secrets row, Harden-Runner in Hardened workflows, Scorecard and Socket on request
    - ToDo: Edit only the always-tier Secrets row; append Harden-Runner to the Hardened workflows command cell; add two On request rows
    - Validation: `bats tests/security-infra-contract.bats tests/quality-catalog.bats tests/engineering-level.bats tests/security-floor-gates.bats` passes
    - Requirements: R5.4, R5.5, R5.6, R6.1, R6.2
    - Quality: Q2

  - Commit: "feat(028): CI mirror, log rules and supply-chain items in the quality catalog"

- [x] 2 - CI mirror at validate
  - _Complexity: Simple | Tests: Unit (bats contract) | Risks: None | Dependencies: Task 1_
  - Objective: Validate runs the CI mirror gate when a container runtime exists and records it as not run otherwise

  - [x] 2.1 - Settle the CI mirror gate without a container runtime
    - Context:
      - Files: `references/validate-mode.md` (how Quality Gates are settled), `agents/auditor.md`
    - Objective: A missing Docker/Podman records `not run — no container runtime`, never a failure
    - ToDo: Add the rule where validate settles the generated Quality Gates: check `command -v docker || command -v podman` before `act`; absent both, record the gate as not run with that reason
    - Validation: `bats tests/security-infra-contract.bats tests/audit-contract.bats` passes
    - Requirements: R1.4, R6.1
    - Quality: Q2
    - Commit: "feat(028): the CI mirror gate is not run, not failed, without a container runtime"

- [x] 3 - The report says what was not tested and at which rung
  - _Complexity: Moderate | Tests: Unit (bats contract) | Risks: count-pinned `.draft` phrases in reports-by-artifact-policy.bats | Dependencies: None_
  - Objective: The Auditor's report carries `untested` and `verified_at`, written explicitly and presented to the user

  - [x] 3.1 - `untested` and `verified_at` in the Auditor's report
    - Context:
      - Files: `agents/auditor.md` (The Report File yaml, lines 64-108), `references/validate-mode.md` (Audit — Part 2 template, Procedure step 5), `tests/reports-by-artifact-policy.bats` (lines 500-564 count pins), `tests/audit-contract.bats`
    - Objective: Two new keys beside `not_verified`, with `untested: []` written when nothing is untested
    - ToDo: Add both keys to the yaml template and the prose in auditor.md and to validate-mode.md's template and step 5; add no new sentence that mentions `.draft` near "creat" or "is part of"
    - Validation: `bats tests/security-infra-contract.bats tests/audit-contract.bats tests/reports-by-artifact-policy.bats` passes
    - Requirements: R2.1, R2.2, R2.3, R2.4, R6.1, R6.2
    - Quality: Q2
    - Commit: "feat(028): the audit report names what no test covers and the rung it ran on"

- [x] 4 - Secure-coding rules per language
  - _Complexity: Moderate | Tests: Unit (bats contract) | Risks: the inline route never loads executor.md | Dependencies: None_
  - Objective: `references/language-rules.md` exists and the Executor, the inline route and the Tech Reviewer are pointed at the detected languages' sections

  - [x] 4.1 - Create `references/language-rules.md`
    - Context:
      - Files: `~/.claude/rules/{go,rust,python,javascript,php,shell,sql,docker}.md` (the owner's source rules), `references/lookup-order.md` (reference shape)
    - Objective: Eight sections — Go, Rust, Python, JavaScript/TypeScript, PHP, Shell, SQL, Docker — each with the rules of R3.2
    - ToDo: Write one `## <Language>` section per language, short bullets, an opening paragraph saying who reads it and that only the matching sections are read
    - Validation: `bats tests/security-infra-contract.bats` passes
    - Requirements: R3.1, R3.2, R6.1
    - Quality: Q2

  - [x] 4.2 - Name the sections in the Executor prompt and the inline route
    - Context:
      - Files: `references/run-mode.md` (Tech Stack Detection 62-85, Inline Route 140-148, delegated route 154, Executor prompt 413)
    - Objective: The delegated prompt names `language-rules.md#<language>` per detected language; the inline route reads the same sections; no match names none and says so
    - ToDo: Add the sentence to the Executor prompt template and step 1 of the delegated route; add the read to the Inline Route; add the no-match line
    - Validation: `bats tests/security-infra-contract.bats tests/routing-rule.bats tests/context-contract.bats` passes
    - Requirements: R3.3, R3.4, R3.6, R6.1
    - Quality: Q2

  - [x] 4.3 - Name the sections in the Tech Reviewer prompt
    - Context:
      - Files: `references/run-tech-review.md` (prompt template 23-41), `agents/tech-reviewer.md`
    - Objective: The Tech Reviewer prompt names the `language-rules.md` sections of the technologies under review
    - ToDo: Add the line to the template; add a one-line pointer in tech-reviewer.md's Protocol
    - Validation: `bats tests/security-infra-contract.bats tests/reports-by-artifact-policy.bats` passes
    - Requirements: R3.5, R3.6, R6.1
    - Quality: Q2

  - Commit: "feat(028): per-language secure-coding rules read by the Executor and the Tech Reviewer"

- [x] 5 - Never eval or exec input
  - _Complexity: Simple | Tests: Unit (bats contract) | Risks: the managed CLAUDE.md block must stay under 100 lines | Dependencies: Task 4_
  - Objective: The injection rule is in the Executor, the Tech Reviewer and the managed CLAUDE.md block

  - [x] 5.1 - The rule in both agents and the Code rules
    - Context:
      - Files: `agents/executor.md` (Step 2), `agents/tech-reviewer.md` (Focus Areas, line 32), `scripts/claude-md.sh` (Code rules, lines 93-102), `tests/claude-md.bats` (lines < 100), `tests/project-contract.bats` P2 (template)
    - Objective: "never `eval`/exec input, never build a command or query from it" in all three places
    - ToDo: Add the bullet to executor.md Step 2 and tech-reviewer.md beside the SQL rule; add one echo line to claude-md.sh Code rules
    - Validation: `bats tests/security-infra-contract.bats tests/claude-md.bats tests/project-contract.bats` passes and `shellcheck scripts/claude-md.sh` exits 0
    - Requirements: R5.1, R5.2, R5.3, R6.1
    - Quality: Q1, Q2
    - Commit: "feat(028): never eval or exec input, in both agents and the managed CLAUDE.md"

- [x] 6 - Whole-suite verification
  - _Complexity: Simple | Tests: None | Risks: None | Dependencies: Task 1, Task 2, Task 3, Task 4, Task 5_
  - Objective: Every existing assertion still passes and CI mirrors green

  - [x] 6.1 - Full local verification
    - Objective: The whole suite, the linters, the plugin schema and the CI mirror pass on the final tree
    - ToDo: Run Q1–Q9; fix any regression in the sub-task that caused it
    - Tests: Unit · `tests/security-infra-contract.bats` — CI mirror is a row of the `## By context` table with `.github/workflows/` and `act -j`; the row states the clean-checkout environment (no artifacts, dependencies or `.env`); the row states the root false-red under `act` and the normal-user local run; "CI mirror" in the product sentence of quality-catalog.md and in the product cell of engineering-level.md
    - Tests: Unit · `tests/security-infra-contract.bats` — scoped to the `Structured logs and health` row only: no secret/token/credential/PII, redacted at the logger; ERROR/WARN/INFO/DEBUG with their meaning; level raised without a redeploy; `Tracing (OpenTelemetry)` is a row of `## On request`
    - Tests: Unit · `tests/security-infra-contract.bats` — first, the security-floor Secrets row is byte-equal to its current text; trufflehog in the always-tier Secrets row, scoped before `### The security floor`; Harden-Runner in the `Hardened workflows` row; Scorecard and Socket rows in `## On request`
    - Tests: Unit · `tests/security-infra-contract.bats` — validate-mode.md, where Quality Gates are settled, records the CI mirror gate as `not run — no container runtime` when neither Docker nor Podman is on PATH; both runtimes named; the same line says it is not a failure
    - Tests: Unit · `tests/security-infra-contract.bats` — `untested:` and `verified_at:` are their own yaml keys in the auditor.md report template and `not_verified:` stays; `untested: []` written explicitly; `verified_at` names the rung and what it does not cover; both keys in validate-mode.md's audit template and in the step that presents `not_verified`
    - Tests: Unit · `tests/security-infra-contract.bats` — language-rules.md has eight `## ` sections (Go, Rust, Python, JavaScript/TypeScript, PHP, Shell, SQL, Docker); each section's keywords asserted only inside its own section
    - Tests: Unit · `tests/security-infra-contract.bats` — the Executor prompt template names `language-rules.md` per detected language; the Inline Route section reads the same sections (asserted in its own section); the no-match line names none, says so, invents no rules
    - Tests: Unit · `tests/security-infra-contract.bats` — run-tech-review.md prompt template names the `language-rules.md` sections under review; tech-reviewer.md carries the pointer; the no-match line applies to the reviewer prompt
    - Tests: Unit · `tests/security-infra-contract.bats` — the eval/exec rule in executor.md implementation rules; in tech-reviewer.md Focus Areas beside the parameterized-SQL rule; in `### Code rules` of the CLAUDE.md `scripts/claude-md.sh` generates in a real temp git repo; that block stays under 100 lines
    - Tests: None — whole-suite verification of the existing suites (R6.2), no new behaviour
    - Validation: `bats tests/` green as a normal user; `shellcheck scripts/*.sh bin/*`; `gitleaks git .`; `trivy fs .`; `claude plugin validate --strict` on the four targets; `act -j shellcheck`, `act -j validate-examples`, `act -j plugin-validate`
    - Requirements: R6.2
    - Quality: Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8, Q9
    - Commit: "test(028): whole-suite verification"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [~] Error handling implemented (n-a: no new error path — the story adds reference prose and one echo line)
- [x] Q1 — Lint: `shellcheck scripts/*.sh bin/*` exits 0
- [x] Q2 — Unit tests: `bats tests/` passes, as a normal user
- [x] Q3 — Dependency vulnerabilities: `trivy fs .` — no dependencies
- [~] Q4 — Secrets: `gitleaks git .` reports no leaks (waived: pre-existing before story 028, owner decision 2026-10-23 — fix owned by a separate story (gitleaks: AKIA fixture e378ef8:tests/archive-story.bats:1561 missing from .gitleaksignore))
- [x] Q5 — README: the install and check commands `README.md` names exist and run
- [x] Q6 — Supported and declared runtime: Claude Code 2.1.295+ declared in `README.md` and `CHANGELOG.md`
- [x] Q7 — Data integrity: no persisted data
- [~] Q8 — Plugin schema: `claude plugin validate --strict` on `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills`, `agents` (waived: pre-existing before story 028, owner decision 2026-10-23 — fix owned by a separate story (plugin.json --strict: root CLAUDE.md and missing icon))
- [~] Q9 — CI mirror: `act -j shellcheck`, `act -j validate-examples`, `act -j plugin-validate` pass (waived: pre-existing before story 028, owner decision 2026-10-23 — fix owned by a separate story (act -j plugin-validate: root CLAUDE.md warning))
