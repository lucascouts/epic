---
story: requester-block-and-registers
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Story - The requester is a four-field block, and the level never changes the scale

## Introduction

Since 0.6.0 triage reads who is asking as a bare `requester: developer | layperson`, and a `layperson` is held at Fast. That rule came from one trivial request; a beginner who asks for something Full-shaped is refused the plan they need. What had made Standard hurt a beginner — out-of-reach questions, document reviews, 23k-character turns — is closed by the plain register, the question budget and the constitution defaults. This story records the requester as a block (`level`, `persona`, `always`, `never`), gives the developer a register of their own, and decouples the level from the scale: the level governs how the Epic speaks and asks, the request governs what is built.

## Requirements

### R1. The requester is recorded as a block

**User Story:** As the orchestrator, I want who is asking recorded with its evidence and its rules, so that a wrong reading can be challenged and the rules grow from the answers.

#### Acceptance Criteria

- R1.1: WHEN triage reads the request THE SYSTEM SHALL record `requester.level` as `layperson` or `developer`, choosing `developer` when unsure
- R1.2: WHEN triage records the requester THE SYSTEM SHALL record `requester.persona` as one line that ends with the evidence the reading rests on
- R1.3: WHEN the level is read THE SYSTEM SHALL seed `requester.always` and `requester.never` from that level's register
- R1.4: WHEN a Clarify answer reveals how to work with this requester THE SYSTEM SHALL append the rule to `always` or `never` and apply it for the rest of the story

### R2. The level never changes the scale

#### Acceptance Criteria

- R2.1: WHEN triage recommends a mode THE SYSTEM SHALL derive it from the request and the complexity table alone, for every level
- R2.2: WHEN the level is `layperson` THE SYSTEM SHALL change only the register, the question budget, the defaults taken silently and the shape of a gate

### R3. Both levels have a register

#### Acceptance Criteria

- R3.1: WHEN `level` is read THE SYSTEM SHALL load the register that matches it — `plain-register.md` for `layperson`, `developer-register.md` for `developer`
- R3.2: WHEN a new concept reaches a layperson THE SYSTEM SHALL explain it by one example or one analogy, inside the per-turn ceiling
- R3.3: WHEN a developer is asked THE SYSTEM SHALL ask directly, keep the context and one example on every option, and never explain the basics

## Constraints

- The register is the orchestrator's voice: no artifact, protocol or sub-agent changes with the level
- `tests/requester-register.bats` anchors on section headings; headings keep their names

## Out of Scope

- The shape of the Clarify questions themselves (story 023)
- A third level; the evidence covers two, and `persona` carries the nuance
