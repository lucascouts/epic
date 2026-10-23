---
story: clarify-as-an-architect
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Story - Clarify asks as an architect asks a client

## Introduction

The 0.6.0 Clarify is adaptive between rounds but fixed inside one: a call bundles 3–7 questions, the questions ask mechanisms ("should tokens expire after?"), and the budget counts rounds. The requester came to have something built, not to give instructions: whatever their level, they know what it is and what it must do, and the how is not settled in their head. This story reshapes Clarify around that: an orientation round first, questions that ask the consequence the requester can observe, options that carry context and an example, the how proposed as a recommendation, rounds free in size and bundled only where answers are independent, and a budget counted in questions. Tried once, in September 2026, on a Standard-shaped request: nine questions in three rounds, and every technical decision came out without the requester naming a mechanism.

## Requirements

### R1. The Epic asks the way an architect asks a client

#### Acceptance Criteria

- R1.1: WHEN Clarify opens THE SYSTEM SHALL run an orientation round of at most three context questions or one open question in the requester's words, and skip it WHEN the request already answers them
- R1.2: WHEN a question is composed THE SYSTEM SHALL ask the consequence the requester can observe, never the mechanism that produces it
- R1.3: WHEN an option is offered THE SYSTEM SHALL carry its context and one example, adding an analogy WHEN the choice is technical and `requester.level` is `layperson`
- R1.4: WHEN a technical decision is due THE SYSTEM SHALL offer it as options with the recommended one first and labelled, its reason in one line, and never as an open question

### R2. Rounds are free in size and built from the last

#### Acceptance Criteria

- R2.1: WHEN composing a round THE SYSTEM SHALL bundle only questions whose answers cannot change each other, and ask alone and first any question whose answer can prune another
- R2.2: WHEN composing round N+1 THE SYSTEM SHALL build it from what round N left open

### R3. The budget counts questions

#### Acceptance Criteria

- R3.1: WHEN a question is asked THE SYSTEM SHALL count it against a per-story budget of questions — `layperson` Fast 3, Standard 9, Full 12; `developer` Fast 4, Standard 10, Full 14 — with the orientation round and each gate counting one each
- R3.2: WHEN the budget is spent THE SYSTEM SHALL decide by the constitution defaults and the register table, and record each decision as an assumption

### R4. The level sets directness, not the amount of context

#### Acceptance Criteria

- R4.1: WHEN `requester.level` is `developer` THE SYSTEM SHALL ask in the stack's own terms and keep the context and the example on every option
- R4.2: WHEN the Analyst's completeness checklist reaches the requester THE SYSTEM SHALL have reshaped each assertive item into the consequence form

## Constraints

- `tests/requester-register.bats` Q3 anchors on `## Clarify Protocol` and `### Question shape` and pins `budget`, `gate`, `Run`, `layperson`, `calibration question`, `left open`; the rewrite keeps every one of them
- The fallback for headless sessions (numbered list) stays

## Out of Scope

- The requester block itself (story 022)
- Measuring the format on a persona run; that is the 0.7.0 test plan
