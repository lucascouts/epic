---
story: quick-create
type: feature
scale: full
status: archived
version: 1
created: 2026-08-16
---

# Story - Quick-Create (Batch Story Creation from a Source Document)

## Introduction

Creating stories one at a time repeats the most expensive part — the interview
— for every story: ~951k fresh tokens isolated versus 163-366k per story in
batch, measured across the 2026-07 corpus. This story adds
`stories create --batch <doc>`: derive N proposals from a source document, run
one consolidated triage and one clarify round-set, materialize every approved
story through its normal per-scale pipeline. It officializes the audit→wave
pipeline the corpus proved is how stories get born after audits. Derived from
`design.md` (design-first).

## Requirements

### R1. Batch entry and derivation

#### Acceptance Criteria

- R1.1: WHEN invoked as `stories create --batch <doc>` THE SYSTEM SHALL enter
  batch-create mode — the routing arm matches before the bare `stories` LIST
  arm
- R1.2: WHEN the source document is unreadable or empty THE SYSTEM SHALL
  refuse, naming the path, before any number is reserved
- R1.3: WHEN derivation finds story-shaped items THE SYSTEM SHALL present one
  consolidated triage block carrying each proposal's type, complexity and
  scale from the existing triage table
- R1.4: IF derivation finds zero story-shaped items THEN THE SYSTEM SHALL
  report that and stop — a batch is never padded with invented stories
- R1.5: WHEN a batch starts THE SYSTEM SHALL run the runtime dependency
  precheck, MCP detection and preferred-tooling detection once for the whole
  batch

### R2. Numbers are reserved once, race-closed

#### Acceptance Criteria

- R2.1: WHEN triage is confirmed THE SYSTEM SHALL allocate N consecutive
  numbers from the highest across `.epic/stories/` AND `.epic/archive/`,
  create all N placeholder directories immediately — directory existence is
  the reservation — and rename each placeholder to its real `NNN-slug/` in the
  same confirmation step
- R2.2: IF a re-scan after creation detects a collision THEN THE SYSTEM SHALL
  re-slot the colliding tail and report it — never overwrite an existing
  directory
- R2.3: WHEN any create flow (batch or single) allocates a number THE SYSTEM
  SHALL obtain it from `scripts/next-story-number.sh` — one tested allocator
- R2.4: WHEN allocation would exceed 999 THE SYSTEM SHALL surface the existing
  maximum-story-count message

### R3. One interview for the whole batch

#### Acceptance Criteria

- R3.1: WHEN clarification is needed THE SYSTEM SHALL bundle questions for all
  Standard/Full members into one round-set — questions tagged
  `[story N/M — slug]`, 3-7 per call, at most 3 rounds for the entire batch,
  remaining ambiguity documented as assumptions
- R3.2: WHEN a batch member is Fast-scale THE SYSTEM SHALL apply the existing
  clarify skip for that member
- R3.3: WHILE running headless THE SYSTEM SHALL present the assertion-style
  numbered list for the whole batch, log assumptions, and proceed without
  pausing

### R4. Batch amortizes conversation, never contract

#### Acceptance Criteria

- R4.1: WHEN a Standard/Full member is approved THE SYSTEM SHALL run its
  Phase 3 with the Test Advisor — authored tests and red-evidence — before
  materialization, exactly as in single create
- R4.2: WHEN a story is materialized THE SYSTEM SHALL require a clean
  `validate-story.sh` pass for it
- R4.3: WHEN a generated story trips the authoring size ceiling THE SYSTEM
  SHALL surface the warning in the approval block and defer any split to a
  post-batch create — the live interview is never re-entered

### R5. One approval, per-story verdicts

#### Acceptance Criteria

- R5.1: WHEN the batch concludes THE SYSTEM SHALL present one approval moment
  with a verdict per story (`created` / `skipped` / `blocked`), never stopping
  the batch on one story, closing with a one-line tally
- R5.2: WHEN a proposal is skipped THE SYSTEM SHALL persist its reserved
  directory as a draft seed — `.draft/meta.yaml` with `phase: 0`, the
  proposal, and the `source-doc:` path it derived from — recoverable by
  resume detection, which groups drafts by that persisted field
- R5.3: WHEN a story is materialized THE SYSTEM SHALL write `status: draft`
  frontmatter and refresh the story index
- R5.4: WHEN a batch is interrupted THE SYSTEM SHALL leave N ordinary
  per-story drafts — resume stays per-story, with an aggregated batch line
  when several drafts share one source document

## Success Metrics

- The next improvement wave of this plugin is created through `--batch` end to
  end (dogfood), with one interview and one approval
- Per-story creation cost in batch lands in the corpus band (roughly 4-6×
  cheaper than isolated), observable in session transcripts
- Zero number collisions and zero recycled numbers across batch + concurrent
  single creates in the allocator's bats suite

## Constraints

- The quality contract is untouched: per-scale phases, Test Advisor, validate
  gates all run per story
- `references/batch-create.md` cites the LIST batch-verdict grammar as the
  single definition — no restated grammar
- Helper script follows the house contract: one JSON object on stdout,
  diagnostics on stderr, exit 0/1/2

## Out of Scope

- Inline-list batch (N requests typed in chat) — deferred at clarify;
  document-source only
- Agent-teams proposals during batch (each story's Run decides)
- Auto-running stories after creation
- Deriving stories from anything but a readable local document (URLs, issues:
  future work)
