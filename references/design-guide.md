# Design Guide

Covers both the **process** (when to use design-first, depth options) and the **output template** (sections to include in design.md).

## When to Use Design-First Workflow

- **Infrastructure/tooling:** monorepo setup, CI/CD, database configuration
- **Technical constraints:** ESM compatibility, specific library versions, performance targets
- **Non-functional requirements:** latency < 50ms, 99.9% uptime, compliance
- **Existing designs:** formalizing architecture from diagrams, whiteboards, or prior art
- **Feasibility exploration:** validating that an approach works before defining behavior

## Design Depth

Choose depth based on context:

### High Level

Full system architecture: component diagrams, interactions, data flow, non-functional properties.

Best for: multi-person projects, complex systems, thorough documentation needs.

### Low Level

Implementation specifics: pseudocode, interface contracts, data structures, performance considerations.

Best for: solo development, single-component changes, rapid validation.

## Key Principle

Derived requirements (in design-first workflow) must be **testable and independent** — not restatements of the design in EARS notation.

Bad (restates design):
```
WHEN the system starts THE SYSTEM SHALL use Redis for job queuing
```

Good (testable behavior):
```
WHEN a flow execution is requested THE SYSTEM SHALL enqueue the job and return a job ID within 100ms
```

## Design Document Template

```markdown
# Design - [Feature Name]

## Overview

[2-3 sentences: architectural approach and key design decisions.]

## Architecture

[Mermaid diagram showing system components and their relationships.]

## Components & Interfaces

### [Component Name]

- **Responsibility:** [What it does]
- **Interface:** [Public API / methods / endpoints]
- **Dependencies:** [What it depends on]

[Repeat for each component.]

## Data Models

[Mermaid ER diagram for new or modified data models.]

## API Design

[Table of endpoints if applicable.]

| Method | Path | Purpose | Request | Response |
|---|---|---|---|---|
| POST | /api/resource | Create resource | `{ name: string }` | `{ id: string }` |

## Sequence Diagrams

[Mermaid sequence diagram for key flows.]

## Error Handling Strategy

- [Error type 1]: [How handled]

## Security Considerations

- [Security concern 1]: [Mitigation]

## Performance Considerations

- [Performance concern 1]: [Approach]

## Testing Strategy

- **Unit tests:** [What to test at unit level]
- **Integration tests:** [What to test at integration level]
- **E2E tests:** [What to test end-to-end, if applicable]

## Integration Points

- [System/component 1]: [How this feature integrates]
```

## Template Guidelines

1. **Scale sections to complexity.** A simple feature may need only Overview + Components + Testing. Don't pad sections for the sake of completeness.
2. **Mermaid diagrams are preferred** but not mandatory. Use them when they clarify relationships that prose cannot.
3. **Omit irrelevant sections.** If there are no security considerations, don't include the section.
4. **API Design applies to HTTP APIs, CLI interfaces, and SDK methods.** Adapt the table format as needed.

## Gotchas

- Design-first derived requirements must be independently testable, not restatements of design decisions in EARS notation
- A requirement like "THE SYSTEM SHALL use PostgreSQL" is a design restatement; instead write "WHEN data is persisted THE SYSTEM SHALL guarantee ACID transactions"

## Tips for Design-First Workflow

- Start Phase 1 by stating technical constraints and required services explicitly
- Iterate on design before locking requirements — explore trade-offs
- In Phase 2, verify each derived requirement can be tested without knowledge of the architecture
- Upload or reference existing diagrams (draw.io, Lucidchart, whiteboard photos) as input
