---
story: reports-by-artifact
type: feature
scale: standard
status: archived
version: 1
created: 2026-08-16
---

# Implementation Plan - Reports by Artifact

## Overview

Agent definitions first (the contract), consumption second (the reader), Tech
Reviewer last (independent of the other two). Every contract edit lands in the
agent file AND its duplicated prompt template in the same sub-task — the
auditor's own project memory flags half-landed protocol changes as drift.

## Task List

- [x] 1 - Report contract in the agent definitions
  - _Complexity: Simple | Tests: Unit | Risks: Write grant is a real privilege change — carve-out wording must be airtight | Dependencies: None_
  - Objective: Validator and Auditor write their verdict files as a mandatory final protocol step, and may write nothing else.

  - [x] 1.1 - Validator: Write grant, carve-out, report step, schema
    - Context:
      - Files: `agents/validator.md` (tools line, no-modify rule at :43, report section), `references/validate-mode.md:14-39` (duplicated Validator prompt template)
    - Objective: `.draft/validation-report.yaml` exists after every validator run, written before the textual summary.
    - ToDo: add `Write` to the frontmatter tools; rewrite the no-modify rule as the carve-out — write ONLY `.draft/validation-report.yaml`, creating `.draft/` on demand (fast/spike have none) — treating any other write as a protocol violation; specify the schema (`story`, `generated_at`, `verdict: pass|fail`, `results[]` per sub-task with PASS/FAIL/SKIP + qualifier, `gates[]`); order the protocol: file write is the final step BEFORE the summary; mirror every change in the validate-mode template verbatim.
    - Tests: Covered by Task 2.2 — the policy suite's `1.1:` cases pin the Write grant, the report path + verdict + before-summary ordering, the protocol-violation carve-out with on-demand `.draft/`, and the validate-mode template mirror
    - Validation: both copies show the carve-out and the schema; `command grep -c 'validation-report.yaml' agents/validator.md references/validate-mode.md` ≥1 each
    - Requirements: R1.1, R1.3, R1.4, R1.5

  - [x] 1.2 - Auditor: same contract, audit schema
    - Context:
      - Files: `agents/auditor.md` (tools :6, no-modify rule at :78, report bullets :66-74), `references/validate-mode.md:41-74` (duplicated Auditor prompt template)
    - Objective: `.draft/audit-report.yaml` carries what the report bullets already enumerate — as data.
    - ToDo: add `Write`; carve-out for exactly `.draft/audit-report.yaml`; schema extends the validator's with `findings[]`, `gaps[]`, `unmet_gates[]`, `deviations_reviewed`, `missing_red[]` — mirroring the existing report bullets; same final-step ordering; mirror in the validate-mode template; note the auditor's project memory (`.claude/agent-memory/epic-auditor/`) may cite the old protocol — the memory is the agent's to update on its next run, not this story's.
    - Tests: Covered by Task 2.2 — the policy suite's `1.2:` cases pin the same four facts on the auditor's side (Write grant, `audit-report.yaml` + verdict + ordering, carve-out, template mirror)
    - Validation: both copies updated; schemas of 1.1 and 1.2 share key style (`story`, `generated_at`, `verdict`)
    - Requirements: R1.2, R1.3, R1.4, R1.5

  - [x] 1.3 - Commit
    - Validation: All checks from 1.1 and 1.2 pass
    - Commit: "feat(011): validator and auditor verdicts become draft artifacts"

- [x] 2 - Orchestrator reads files; policy pinned by test
  - _Complexity: Simple | Tests: Unit | Risks: recovery path wording must not permit silent respawn | Dependencies: Task 1_
  - Objective: validate-mode's verdict source is the file, stale reports cannot lie, and a bats file pins the whole wave-011 contract.

  - [x] 2.1 - validate-mode consumption: stale guard, recovery, pass-point keys
    - Context:
      - Files: `references/validate-mode.md` (procedure steps 3-5 at :80-85, pass-point rules at :101, archive offer)
    - Objective: The flow concludes from disk even when the agent's message never arrives.
    - ToDo: before spawning, delete that agent's stale report file (R2.2); steps 3-5 read verdicts from the files — the message is courtesy (R2.1); absent/unparseable file → one SendMessage re-request to the same agent, still absent → the run is failed, stated in exactly those terms (R2.3); restate rule 2 (partial pass) and rule 3 (fail writes nothing) in terms of the file's `verdict`; `validated` stamp and archive offer key off the file (R2.4).
    - Tests: Covered by Task 2.2 — the policy suite's `2.1:` cases pin the four consumption points: stale-report guard, file-sourced verdicts in procedure steps 3-5, the one-SendMessage-then-failed recovery, and the pass point keying off the file's `verdict`
    - Validation: `command grep -n 'validation-report\|audit-report' references/validate-mode.md` covers spawn-guard, consumption, and pass-point
    - Requirements: R2.1, R2.2, R2.3, R2.4

  - [x] 2.2 - Policy test for the wave-011 contract
    - Context:
      - Files: `tests/` (house bats conventions), `agents/{validator,auditor,tech-reviewer}.md`
    - Objective: The contract survives future edits only deliberately.
    - ToDo: new bats file asserting: validator/auditor frontmatter `tools:` contain `Write`; each names its exact report path and the final-step-before-summary ordering; tech-reviewer `tools:` contains `Bash` and the measurement-only instruction; validate-mode names both report files at the three consumption points; no agent other than validator/auditor gained Write.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — validator/auditor frontmatter grant `Write` and name their report file, verdict, before-summary ordering and protocol-violation carve-out in both the agent file and its validate-mode template; validate-mode names the report files at the stale spawn-guard, the procedure's verdict reads and the pass point, with the absent/unparseable → one SendMessage → failed recovery stated; tech-reviewer grants `Bash` with the measurement-only/never-mutate rule, command+output findings and the run-mode template mirror; `Write`/`Bash` grant sets across `agents/` compared exactly (auditor, executor, test-advisor, validator / + tech-reviewer for Bash) and `Edit` pinned to the executor alone
    - Validation: new bats file passes; full suite green
    - Requirements: R1.5, R2.1, R3.1, R3.4

  - [x] 2.3 - Commit
    - Validation: All tests from 2.1 and 2.2 pass
    - Commit: "feat(011): validate flow concludes from report files, pinned by policy test"

- [x] 3 - Tech Reviewer measures
  - _Complexity: Trivial | Tests: Covered by Task 2.2 | Risks: None | Dependencies: None (parallel-safe with Tasks 1-2)_
  - Objective: Findings carry commands and outputs where a runnable check exists.

  - [x] 3.1 - Bash grant + measurement protocol, both copies, doc sweep
    - Context:
      - Files: `agents/tech-reviewer.md` (tools :7, no-modify rule :48), `references/run-mode.md:408-452` (duplicated Tech Reviewer prompt template), `ARCHITECTURE.md` (tool-scoping), `README.md` (sub-agent table), `skills/epic/SKILL.md` (persona tables)
    - Objective: The reviewer that today argues its findings can run the check instead.
    - ToDo: add `Bash` to tools; add the measurement rule — run, don't argue: each finding resting on a runnable check cites command + output (R3.2); reword no-modify to "Bash is for measurement only — never mutate files or git state" (R3.3); mirror in the run-mode template (R3.4); sweep ARCHITECTURE.md tool-scoping, README.md agent table and SKILL persona line for the changed grants of ALL THREE agents in this story (R3.4).
    - Tests: Covered by Task 2.2 — the policy suite's `3.1:` cases pin the Bash grant, the measurement-only/never-mutate rule, the command+output finding shape and the run-mode template mirror; the ARCHITECTURE/README/SKILL doc sweep is a grep-verifiable prose change validated below
    - Validation: `command grep -n 'Bash' agents/tech-reviewer.md` shows tools + instruction; doc surfaces list the new grants
    - Requirements: R3.1, R3.2, R3.3, R3.4
    - Commit: "feat(011): tech-reviewer measures — Bash grant with measurement-only protocol"

## Quality Gates

- [x] All acceptance criteria validated (R1.1-R3.4 covered by the policy test or a grep-verifiable prose change)
- [x] All task validations pass
- [x] All tests written and passing (policy bats file green; full suite green)
- [x] Code integrated (validate-mode actually reads the files it names)
- [x] Error handling implemented (absent-report recovery path stated; stale-report guard in place)
