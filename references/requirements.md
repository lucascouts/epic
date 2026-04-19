# Story Template (Features)

Use this template for the `story.md` file in feature stories.

## Template

```markdown
---
story: <story-name>
type: feature
scale: standard | full
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

1. WHEN [trigger event] THE SYSTEM SHALL [expected behavior]
2. WHEN [error condition] THE SYSTEM SHALL [error handling behavior]
3. IF [conditional state] THEN THE SYSTEM SHALL [conditional response]

### R2. [Next Requirement Title]

**User Story:** As a [role], I want [functionality], so that [benefit]

#### Acceptance Criteria

1. WHEN [trigger] THE SYSTEM SHALL [behavior]

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

1. **Number hierarchically:** R1, R1.1, R1.2, R2, R2.1 — use sub-requirements for complex areas
2. **One requirement = one testable behavior.** If you can't write a single test for it, split it.
3. **User stories are optional** for technical/infrastructure requirements. Use them for user-facing features.
4. **Acceptance criteria use EARS notation.** See `ears-notation.md` for keyword reference.
5. **Out of Scope is mandatory.** Explicitly stating what you're NOT building prevents scope creep.
6. **Constraints inform design.** List anything that limits architectural choices.
