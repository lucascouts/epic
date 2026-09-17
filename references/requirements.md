# Story Template (Features)

Use this template for the `story.md` file in feature stories.

## Template

```markdown
---
story: <story-name>
type: feature
scale: standard | full
engineering: experiment | tool | project | product
version: 1
created: <date>
---

# Story - [Feature Name]

## Introduction

[2-3 sentences: what this feature does, who benefits, and why it matters. Include business context.]

## Related Stories

[Only if expand mode — reference source stories here. Otherwise omit this section.]

- Related: `.epic/stories/<name>/story.md` — [brief relationship description]

## Requirements

### R1. [Requirement Title]

**User Story:** As a [role], I want [functionality], so that [benefit]

#### Acceptance Criteria

- R1.1: WHEN [trigger event] THE SYSTEM SHALL [expected behavior]
- R1.2: WHEN [error condition] THE SYSTEM SHALL [error handling behavior]
- R1.3: IF [conditional state] THEN THE SYSTEM SHALL [conditional response]

### R2. [Next Requirement Title]

**User Story:** As a [role], I want [functionality], so that [benefit]

#### Acceptance Criteria

- R2.1: WHEN [trigger] THE SYSTEM SHALL [behavior]

## Quality Requirements

- Q1: Formatting — `<command>` exits 0
- Q2: Lint — `<command>` exits 0
- Q3: [context item] — `<command>` (signal: [what activated it])

## Success Metrics

- [Metric 1: quantifiable indicator of success]
- [Metric 2: quantifiable indicator of success]

## Constraints

- [Technical constraint: e.g., must work with ESM-only modules]
- [Business constraint: e.g., must not require downtime]

## Out of Scope

- [Explicitly excluded functionality 1]
- [Explicitly excluded functionality 2]
```

## Writing Guidelines

1. **Number hierarchically.** Each requirement is a group header `### Rn.` (`R1`, `R2`…). Each acceptance criterion under it is a leaf, labelled `Rn.m` (`R1.1`, `R1.2`…). Tasks reference the leaf `Rn.m` numbers — so every criterion must carry one.
2. **One requirement = one testable behavior.** If you can't write a single test for it, split it.
2b. **A criterion whose deliverable is not code says so.** Some criteria are answered by an artifact rather than by a task: a regression guard, a feasibility verdict, a decision record. Append the sanctioned suffix and both orphan readers — `cross-reference.sh` and `validate-story.sh --cross-ref` — treat the criterion as satisfied instead of untraced:

   ```
   - R1.2: THE SYSTEM SHALL keep the CRLF round-trip guarded (satisfied-by: tests/close-subtask-roundtrip.bats)
   - R3.4: THE SYSTEM SHALL record the feasibility verdict for the native runner (satisfied-by: design.md#tooling-decisions)
   ```

   The artifact must be named: `(satisfied-by: )` with nothing after the colon is a validation warning, because the class legalizes a deliverable, not a way to silence the check. The suffix binds to the criterion it closes, so a criterion wrapped over several lines can carry it at the end.
3. **User stories are optional** for technical/infrastructure requirements. Use them for user-facing features.
4. **Acceptance criteria use EARS notation.** See `ears-notation.md` for keyword reference.
5. **Out of Scope is mandatory.** Explicitly stating what you're NOT building prevents scope creep.
6. **Constraints inform design.** List anything that limits architectural choices.
7. **Quality requirements are the story's legend.** One line per active item of the [quality catalog](quality-catalog.md), numbered `Qn` in catalog order, each with the command that proves it on this project. The set starts from the constitution's `## Quality` block and adds what the Analyst detected and the request asked. Sub-tasks cite the lines in a `Quality:` field, the Quality Gates section of `tasks.md` carries one box per line, and `cross-reference.sh` reports which lines no sub-task cites. The engineering level bounds the set ([engineering-level.md](engineering-level.md)): an `experiment` legend reads `none`, a `tool` carries the always tier, a `project` adds the context items with a signal, a `product` adds the CI-shaped ones.
