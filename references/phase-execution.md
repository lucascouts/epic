# Phase execution and recovery — Standard and Full

Loaded when a Standard or Full story writes its phases, saves drafts or resumes. Moved out of [SKILL.md](../skills/epic/SKILL.md) so a run that does not need it does not carry it.

## Completeness Checklist

For standard/full: spawn Analyst sub-agent per procedure in [context-discovery.md](context-discovery.md#completeness-checklist).
For Fast: ask 1-2 inline questions only if needed.

## Phase Execution

Before entering any phase, load the corresponding reference files:

- Before writing any phase artifact: load [self-review-checklist.md](self-review-checklist.md)
- For Phase Gates, Checkpoint Recovery, Cascade Rollback, sub-agents: load [phase-gates.md](phase-gates.md)
- For reference files per phase (ears-notation, requirements, design-guide, etc.): see table in phase-gates.md
- On format doubts, load the relevant example from `assets/examples/`
- For a `layperson` requester, every phase gate takes the one-line shape in [plain-register.md](plain-register.md#gates-are-one-line) and counts against the question budget

**Authoring ceiling at Phase 3.** When the generated `tasks.md` passes the size threshold defined once in [tasks.md](tasks.md) (Authoring Ceiling) — warn and make the two offers: **cut** the scope, or **split** the plan into waves. Interactively as a question, headless as a logged note that proceeds. It is a warning, never a block: a story that genuinely needs a large plan keeps it. **There is no ceiling on the number of tasks** — how many a story has follows from the work; what is bounded is the unit, and a sub-task that cannot be proved on its own by its `Validation:` command is too big whatever the total. In batch create the offer is not re-entered into the live interview; the warning surfaces in the approval block and the split happens post-batch (see [batch-create.md](batch-create.md)).

## Persistence and Recovery

### Draft Saving (Standard and Full modes only)

After each phase approval, save to draft:

```
.epic/stories/<name>/
  .draft/
    story.md       <- after Phase 1 approval
    design.md      <- after Phase 2 approval (full only)
    meta.yaml      <- phase progress + project state + analyst output
```

Draft metadata (`meta.yaml`):
```yaml
phase: 2
approved: 2026-04-01
project-hash: <short SHA of HEAD at approval time>
requester:                  # read at triage, re-read from Clarify answers
  level: layperson          # layperson | developer
  persona: "beginner, informal, has never opened a terminal. Read from: 'the black window'"
  always:
    - explain by example, one per new concept
  never:
    - ask about git, npm or versioning
engineering: tool          # experiment | tool | project | product — proposed at triage, confirmed by its gate
questions_asked: 2          # questions spent against the story's question budget
analyst_output: |
  <cached output from Codebase Analysis Analyst>
```

### Resume Detection

If `.epic/stories/<name>/.draft/` exists when Create mode is detected for the same topic:

1. Compare `project-hash` with current HEAD
2. If diverged: "Found a draft (Phase N approved), but the project has commits since then. Resume anyway, or start fresh?"
3. If unchanged: "Found a draft with Phase N approved. Resume from Phase N+1?"

### Rules

- Draft saved only after explicit user approval of each phase
- Resume is always optional — user can choose to start fresh
- Draft cleared after successful completion (final artifacts replace draft)
- Refine mode: abort leaves original files untouched
- `.draft/` directories should be gitignored
- Fast mode does not use drafts (single phase)
