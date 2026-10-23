---
story: quality-catalog-and-legend
type: feature
scale: standard
version: 1
created: 2026-09-17
status: archived
---

# Story - A quality catalog, a legend in the story, and gates generated from it

## Introduction

The Quality Gates section of `tasks.md` is a fixed list of five items: acceptance criteria, task validations, tests, integration, error handling. Nothing in it names formatting, lint, types, dependency vulnerabilities, secrets or a README, and nothing chooses by context: a service and a one-file CLI get the same five boxes. This story adds a catalog of quality resources in three tiers — always, by context, on request — a `## Quality Requirements` legend in the story that numbers the active ones, a `Quality:` field on sub-tasks that cites them, Quality Gate boxes generated from the legend with the command that proves each, and coverage measured by `cross-reference.sh`, so a reader sees both what was required and in which task each requirement acted.

## Requirements

### R1. A catalog of quality resources, in three tiers

#### Acceptance Criteria

- R1.1: THE SYSTEM SHALL ship `references/quality-catalog.md` with an always tier, a context tier that names the signal activating each item, and an on-request tier
- R1.2: WHEN an item is activated THE SYSTEM SHALL prefer an installed tool, recommend one and pause when none is installed, and never install one

### R2. The story carries the legend

#### Acceptance Criteria

- R2.1: WHEN a Standard or Full story is written THE SYSTEM SHALL carry a `## Quality Requirements` section listing each active item as `Qn: <item> — <command that proves it>`
- R2.2: WHEN a Fast story is written THE SYSTEM SHALL carry the same legend at the top of `tasks.md`
- R2.3: WHEN init writes the constitution THE SYSTEM SHALL write a `## Quality` block with the always tier and the context items its scan detected, from which a story's legend starts

### R3. Tasks cite the legend and the gates are generated from it

#### Acceptance Criteria

- R3.1: WHEN a sub-task exercises a quality requirement THE SYSTEM SHALL cite it in a `Quality: Qn` field beside `Requirements:`
- R3.2: WHEN `tasks.md` is generated THE SYSTEM SHALL carry one Quality Gate box per active `Qn` with its command, after the five fixed gates
- R3.3: WHEN validate settles the gates THE SYSTEM SHALL settle a `Qn` gate by running its command
- R3.4: WHEN `requester.level` is `layperson` THE SYSTEM SHALL render the legend as the checks it ran, never by identifier

### R4. Coverage is measured

#### Acceptance Criteria

- R4.1: WHEN `cross-reference.sh` reads a story whose `story.md` declares `Q` identifiers THE SYSTEM SHALL emit a `quality` object with `declared`, `cited`, `orphans` and `phantoms`
- R4.2: WHEN a declared `Qn` is cited by no sub-task THE SYSTEM SHALL list it in `quality.orphans` and exit 1
- R4.3: WHEN a cited `Qn` is declared by no legend line THE SYSTEM SHALL list it in `quality.phantoms` and exit 1
- R4.4: WHEN neither the legend declares nor a sub-task cites a `Q` identifier THE SYSTEM SHALL omit the `quality` key rather than emit zeros

## Quality Requirements

- Q1: Unit tests — `bats tests/` green (the doc contract is the plugin's test surface)
- Q2: Lint — `shellcheck scripts/*.sh bin/*` clean

## Constraints

- `cross-reference.sh` keeps its contract: `story`, `scale`, `status` total on every JSON path; measurement keys absent, never zeroed; the R parser untouched
- The five fixed gates stay; generated gates are added after them
- Activating a resource never installs a tool — the preferred-tooling policy applies

## Out of Scope

- `validate-story.sh` checks on the `Quality:` field or the legend (it warns on nothing new; a lint is a follow-up)
- Running the catalog's commands from the plugin's own scripts; the gate settlement is the validator persona's job
