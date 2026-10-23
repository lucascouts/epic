---
story: reports-by-artifact
type: feature
scale: standard
status: archived
version: 1
created: 2026-08-16
---

# Story - Reports by Artifact, Findings by Measurement

## Introduction

The Validator's and Auditor's verdicts live today in their final chat message —
which sometimes never arrives: the agent ends on an intermediate line and the
whole suite's result is swallowed (recovery costs a SendMessage round; a
respawn re-runs everything). This story makes the verdict a file the
orchestrator reads from disk, and gives the Tech Reviewer the one tool it
lacks to *measure* its findings instead of arguing them. Both changes follow
the same principle the wave applies everywhere: state lives in artifacts,
messages are courtesy.

## Requirements

### R1. The verdict is a file, written before the summary

#### Acceptance Criteria

- R1.1: WHEN the Validator completes its checks THE SYSTEM SHALL write the
  full verdict to `.draft/validation-report.yaml` as its final protocol step
  before composing any textual summary
- R1.2: WHEN the Auditor completes its review THE SYSTEM SHALL write the full
  report to `.draft/audit-report.yaml` before composing any textual summary
- R1.3: WHEN either agent runs for a story with no `.draft/` directory THE
  SYSTEM SHALL create it on demand — fast and spike stories included
- R1.4: WHEN a report file is written THE SYSTEM SHALL record the story
  number, a generation timestamp, the overall verdict, per-sub-task results,
  and — for the Auditor — findings, gaps, unmet gates, deviations and
  missing-Red items, as parseable YAML
- R1.5: WHILE holding the Write grant THE SYSTEM SHALL treat any write outside
  the agent's own report file as a protocol violation — the no-modify rule
  narrows to a carve-out, it does not disappear

### R2. The orchestrator reads the file, not the message

#### Acceptance Criteria

- R2.1: WHEN the validate flow consumes results THE SYSTEM SHALL take the
  verdict from the report files; the agent's final message SHALL NOT be the
  source of any pass/fail decision
- R2.2: WHEN the orchestrator spawns the Validator or Auditor THE SYSTEM SHALL
  remove that agent's stale report file first, so a leftover from a prior run
  can never read as a fresh verdict
- R2.3: IF the report file is absent or unparseable after the agent returns
  THEN THE SYSTEM SHALL request it once from the same agent via SendMessage,
  and IF it is still absent THEN treat the run as failed — never respawn
  silently, never infer a verdict from prose
- R2.4: WHEN the pass-point acts (stamping `validated`, offering archive) THE
  SYSTEM SHALL key those actions off the report file's verdict field

### R3. Tech Reviewer findings are measured, not argued

#### Acceptance Criteria

- R3.1: WHEN the Tech Reviewer is spawned THE SYSTEM SHALL expose Bash to it,
  restricted by instruction to read-only measurement (linters, compilers,
  greps, query plans — never mutation of files or git state)
- R3.2: WHEN a Tech Reviewer finding rests on a runnable check THE SYSTEM
  SHALL include the command and its observed output in the finding
- R3.3: THE SYSTEM SHALL retain the Tech Reviewer's no-modification rule,
  reworded to coexist with the measurement grant
- R3.4: WHEN any of these agent contracts change THE SYSTEM SHALL land the
  change in the agent definition AND its duplicated prompt template
  (`references/validate-mode.md` for Validator/Auditor, `references/run-mode.md`
  for Tech Reviewer) in the same story

## Success Metrics

- A validate pass whose agents end on an intermediate message still concludes
  correctly from the files alone — the swallowed-report failure mode costs
  zero respawns
- Tech Reviewer findings in the next dogfood story each carry a command +
  output pair where a runnable check exists
- Report schemas parse with the same reader style as story 010's close JSON
  (`story`, `verdict`, timestamp keys aligned)

## Constraints

- `.draft/` is gitignored and travels into `.epic/archive/` on archive — the
  reports inherit both behaviors; no new ignore rules
- No new scripts: agent definitions and mode references only (the schema check
  rides the policy bats file, not a runtime validator)
- Validator/Auditor tool grants grow by exactly `Write`; Tech Reviewer by
  exactly `Bash` — least-privilege stays the norm

## Out of Scope

- Changing what the Validator or Auditor actually checks
- Report files for other personas (Executor and Tech Reviewer keep
  message-based reports — their consumers are synchronous)
- Retiring the SendMessage recovery path (it remains the fallback R2.3 uses)
- Orchestrating validation as a native Workflow (separate maintenance story)
