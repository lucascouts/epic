---
story: 028-native-security-infra-rules
type: feature
scale: standard
engineering: product
version: 1
created: 2026-10-23
status: archived
---

# Story - Native security and infra rules

## Introduction

The owner keeps project-level security and infra rules in a personal global `CLAUDE.md`: mirror CI locally before a push, say what no test covers, write secure code per language, never log a secret, and a handful of supply-chain checks. A project managed by Epico gets none of them unless its owner happens to carry the same file. This story moves the rules that hold for any project, and can be proved by a command, into Epico itself — the quality catalog, the Auditor's report, a per-language reference the Executor and the Tech Reviewer read, and the managed `CLAUDE.md` block — so every story Epico plans carries them.

## Requirements

### R1. CI mirror as a quality-catalog item

**User Story:** As a developer whose project has GitHub workflows, I want Epico to run the CI jobs locally before I push, so that a red is caught on my machine instead of on someone else's runner.

#### Acceptance Criteria

- R1.1: THE SYSTEM SHALL list a `CI mirror` item in the `## By context` table of `references/quality-catalog.md`, with the signal `.github/workflows/` and the command `act -j <job>`
- R1.2: THE SYSTEM SHALL state in the CI mirror item that the run mirrors the runner's environment — a clean checkout, with no local build artifacts, dependencies or `.env`
- R1.3: THE SYSTEM SHALL state in the CI mirror item that a job asserting a refusal on an unreadable file fails under `act`'s root user, and that a plain local run as a normal user is the faithful check for those cases
- R1.4: WHEN validate settles the CI mirror gate and no container runtime (Docker or Podman) is on PATH THE SYSTEM SHALL record the gate as `not run — no container runtime` instead of failing it
- R1.5: THE SYSTEM SHALL name the CI mirror among the CI-shaped items that the `product` level activates without waiting for a signal, in both `references/quality-catalog.md` and `references/engineering-level.md`

### R2. The report says what was not tested and at which rung

**User Story:** As a developer reading a validation report, I want to see which part of the change no test covers and how faithful the verification was, so that a green from a low rung is not read as a green from a high one.

#### Acceptance Criteria

- R2.1: THE SYSTEM SHALL add an `untested` list to the Auditor's report, beside `not_verified`, naming each changed behaviour no test covers
- R2.2: THE SYSTEM SHALL add a `verified_at` field to the Auditor's report, naming the fidelity rung the verification ran on and what that rung does not cover
- R2.3: WHEN every changed behaviour has a test THE SYSTEM SHALL write `untested: []` explicitly, never leave the key out
- R2.4: THE SYSTEM SHALL describe both keys in `agents/auditor.md` and in the audit template of `references/validate-mode.md`, and present them to the user with `not_verified`

### R3. Secure-coding rules per language

**User Story:** As a developer, I want the agents that write and review my code to know the secure-coding rules of my language, so that the code avoids the mistakes a linter does not catch.

#### Acceptance Criteria

- R3.1: THE SYSTEM SHALL provide `references/language-rules.md` with one section per language: Go, Rust, Python, JavaScript/TypeScript, PHP, shell, SQL and Docker
- R3.2: THE SYSTEM SHALL cover in each section the rules of the owner's global rule files for that language: Go (`-race`, a context timeout on network I/O, `%w`), Rust (no `unwrap`/`expect` in production, `cargo audit`), Python (no `shell=True` with input, `raise … from`), JS/TS (`strict`, no `any`, schema validation of external data), PHP (PDO prepared statements, `htmlspecialchars`), shell (`set -euo pipefail`, quoted expansions), SQL (parameterized only) and Docker (digest pin, multi-stage, `.dockerignore`, non-root, no secret in the image)
- R3.3: WHEN the orchestrator delegates a sub-task to the Executor THE SYSTEM SHALL name the `language-rules.md` section of each detected language in the prompt
- R3.4: WHEN the main agent runs a sub-task on the inline route THE SYSTEM SHALL read the same `language-rules.md` sections before implementing
- R3.5: WHEN the orchestrator spawns the Tech Reviewer THE SYSTEM SHALL name the `language-rules.md` sections of the technologies under review in the prompt
- R3.6: IF no section matches a detected language THEN THE SYSTEM SHALL name none and say so in one line, without inventing rules for it

### R4. Logs that cannot leak, and tracing on request

**User Story:** As a developer of a long-running service, I want the log rules to cover what must never be logged and how levels behave, so that observability does not become a leak.

#### Acceptance Criteria

- R4.1: THE SYSTEM SHALL extend the `Structured logs and health` row of the quality catalog with: no secret, token, credential or PII in any log line, redacted at the logger rather than at each call site
- R4.2: THE SYSTEM SHALL extend the same row with: levels that mean something (ERROR a human must act, WARN degraded and recovered, INFO a business event, DEBUG off in production) and a way to raise the level without a redeploy
- R4.3: THE SYSTEM SHALL add `Tracing (OpenTelemetry)` to the `## On request` table of the quality catalog

### R5. The remaining security rules

**User Story:** As a developer, I want Epico's checks to include the supply-chain and injection rules the owner already follows, so that a project gets them without a personal configuration.

#### Acceptance Criteria

- R5.1: THE SYSTEM SHALL state "never `eval`/exec input, never build a command or query from it" in the Executor's implementation rules
- R5.2: THE SYSTEM SHALL state the same rule in the Tech Reviewer's focus areas, beside the parameterized-SQL rule
- R5.3: THE SYSTEM SHALL state the same rule in the `### Code rules` of the managed `CLAUDE.md` block written by `scripts/claude-md.sh`, keeping the block under 100 lines
- R5.4: THE SYSTEM SHALL name `trufflehog` as the CI-side scanner in the `Secrets` row of the always tier, leaving the security-floor row unchanged
- R5.5: THE SYSTEM SHALL name StepSecurity Harden-Runner in the `Hardened workflows` row
- R5.6: THE SYSTEM SHALL add `Repo posture score (OpenSSF Scorecard)` and `Behavioural malware scan (Socket)` to the `## On request` table

### R6. The rules are pinned by tests

#### Acceptance Criteria

- R6.1: THE SYSTEM SHALL assert each rule of R1–R5 in a bats contract test, so a later edit that drops one fails the suite
- R6.2: THE SYSTEM SHALL keep every existing assertion over the edited files passing, including the count-pinned ones in `tests/reports-by-artifact-policy.bats`

## Quality Requirements

- Q1: Lint — `shellcheck scripts/*.sh bin/*` exits 0
- Q2: Unit tests — `bats tests/` passes, as a normal user
- Q3: Dependency vulnerabilities — no dependencies; `trivy fs .` gives the verdict
- Q4: Secrets — `gitleaks git .` reports no leaks
- Q5: README — the install and check commands `README.md` names exist and run
- Q6: Supported and declared runtime — Claude Code 2.1.295+ stays declared in `README.md` and `CHANGELOG.md`
- Q7: Data integrity — no persisted data: the story writes only reference text, an agent prompt and one script line
- Q8: Plugin schema — `claude plugin validate --strict` passes on `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills`, `agents` (signal: a published plugin)
- Q9: CI mirror — `act -j shellcheck`, `act -j validate-examples`, `act -j plugin-validate` pass (signal: `.github/workflows/`)

## Success Metrics

- Every rule listed in R1–R5 is found by a `grep` in its reference, agent or script, and asserted by a test
- The managed `CLAUDE.md` block stays under 100 lines
- `bats tests/` stays green with no existing assertion deleted

## Constraints

- [CONSTITUTION] Scripts depend on bash, jq and git only; this story adds no runtime dependency
- [CONSTITUTION] TDD: each contract assertion is written and seen failing before the text that satisfies it
- Activating a catalog item never installs a tool — `act`, `trufflehog`, Harden-Runner, Scorecard and Socket are named, never installed
- The security-floor rows of the catalog keep their text: tests read them by position
- Assumption (owner's answer): `untested` and `verified_at` are new keys, not entries folded into `not_verified`
- Assumption (owner's answer): agents read only the `language-rules.md` sections of the detected languages
- Assumption (owner's answer): the CI mirror runs at validate when a container runtime is present

## Out of Scope

- The owner's personal-environment rules: the language of replies, aliases, the machine inventory, `playwright-cli`, the port-in-use check
- Installing `act`, `zizmor`, `actionlint`, `trufflehog` or any other tool
- Running Scorecard, Socket or OpenTelemetry in this repository
- Per-language rules beyond the eight sections in R3.1
