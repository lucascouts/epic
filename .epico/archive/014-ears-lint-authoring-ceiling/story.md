---
story: ears-lint-authoring-ceiling
type: feature
scale: standard
status: archived
version: 1
created: 2026-08-16
---

# Story - EARS Form Lint and Authoring Ceiling

## Introduction

EARS quality degrades silently: the corpus measured trigger usage falling from
71% to 33% inside one client with zero warnings, criteria carrying four SHALLs
in one bullet, and criteria without the `Rn.m` label that makes them
addressable by the whole traceability chain. Separately, tasks.md files grew
to 51-109KB before authors learned the one-finding-per-story lesson the hard
way. This story gives validation a form lint for requirements, a sanctioned
`satisfied-by:` class for the one legitimate orphan the corpus keeps
producing, and a size ceiling with a split offer at authoring time.

## Requirements

### R1. EARS form checks in validation

#### Acceptance Criteria

- R1.1: WHEN a criterion bullet under an Acceptance Criteria heading carries
  no `Rn.m` label THE SYSTEM SHALL report an error naming the line — an
  unlabeled criterion is invisible to the entire traceability chain
- R1.2: WHEN a labeled criterion contains more than one `SHALL` THE SYSTEM
  SHALL warn naming the line — a compound criterion is untestable as one unit
- R1.3: WHEN a labeled criterion has no EARS trigger (WHEN/WHILE/WHERE/IF) and
  does not open with the ubiquitous form (`THE SYSTEM SHALL`) THE SYSTEM SHALL
  warn — the ubiquitous form is legal EARS and the warning text says so
- R1.4: WHILE the story's resolved scale has no requirements chain (fast,
  spike) or `story.md` is absent THE SYSTEM SHALL run none of these checks —
  the declared-scale fail-open discipline governs
- R1.5: WHEN checks R1.1-R1.3 scan the file THE SYSTEM SHALL skip fenced code
  blocks and bugfix behavior sections (`SHALL CONTINUE TO` items included) —
  the census's fence-exclusion discipline applies
- R1.6: WHEN the checks ship THE SYSTEM SHALL leave this repo's own stories
  and `assets/examples/` passing — the corpus this plugin carries is swept in
  the same story, because the new error blocks task completion through the
  TaskCompleted hook on any story that trips it

### R2. A sanctioned class for the legitimate orphan

#### Acceptance Criteria

- R2.1: WHEN a criterion's deliverable is not sub-task code THE SYSTEM SHALL
  accept a same-line `(satisfied-by: <artifact>)` suffix naming what satisfies
  it — the shape ≥6 corpus projects invented independently
- R2.2: WHEN the orphan check runs THE SYSTEM SHALL treat a `satisfied-by:`
  leaf as satisfied in BOTH orphan sites — `cross-reference.sh` and
  validate's `--cross-ref` gate — reported under a new list key with the
  `status` enum unchanged
- R2.3: IF a `satisfied-by:` suffix names nothing (empty artifact) THEN THE
  SYSTEM SHALL warn — the class legalizes a deliverable, not a blank
- R2.4: WHEN the Auditor traces requirements THE SYSTEM SHALL honor
  `satisfied-by:` — the named artifact, not code, is the trace target — in
  both the agent definition and its duplicated prompt template

### R3. Authoring ceiling with a split offer

#### Acceptance Criteria

- R3.1: WHEN Phase 3 produces a tasks.md exceeding the size threshold THE
  SYSTEM SHALL warn and offer a split into a wave — interactively as a
  question, headless as a logged note that proceeds
- R3.2: THE SYSTEM SHALL define the threshold in exactly one place
  (`references/tasks.md`), with the corpus rationale, and every consumer
  SHALL cite it
- R3.3: WHEN validation reads a tasks.md exceeding the threshold THE SYSTEM
  SHALL warn — a shipped oversized plan is visible after authoring time too
- R3.4: WHEN the ceiling fires during a batch create THE SYSTEM SHALL surface
  the warning in the batch approval block and defer the split offer to a
  post-batch create (story 013's rule, honored here)

### R4. The immunity set is proven, not assumed

#### Acceptance Criteria

- R4.1: WHEN the new checks run against fast, spike, bugfix-behavior,
  fenced-example and no-scale-declared fixtures THE SYSTEM SHALL produce
  byte-identical output to the pre-story validator on every one of them
- R4.2: WHEN validation emits the new findings THE SYSTEM SHALL add warning
  and error strings only — no new JSON count keys, per the legacy-golden
  constraint

## Success Metrics

- The three form checks fire correctly on hostile fixtures and stay silent on
  this repo's nine archived stories and four examples
- A criterion with a real non-code deliverable passes cross-reference clean
  with `satisfied-by:` instead of polluting a Requirements field
- The next oversized tasks.md draws the ceiling warning at Phase 3, before it
  ships

## Constraints

- New error severity is limited to R1.1 (the label) — everything else warns;
  `--strict` consequences are documented where the checks land
- BSD-safe regex spelling throughout (the house `spike_r_re` pattern, no `\b`)
- The R-leaf/group logic duplicated across `validate-story.sh` and
  `cross-reference.sh` moves together, and both movers-comments gain the new
  consumer entries

## Out of Scope

- Rewriting existing stories to conform (that is `epic migrate`, story 015)
- Subject-drift detection beyond the ubiquitous-form rule (`THE <component>
  SHALL` stays legal)
- Making the ceiling an error or a block at any severity
- EARS checks on design.md or tasks.md prose
