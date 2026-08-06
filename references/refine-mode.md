# Refine Mode

Triggered by `/epic:epic stories refine NNN`.

## Procedure

1. Read existing story from `.epic/stories/<name>/`
2. Identify what changed
3. Produce delta document for affected phases:

```markdown
## Delta: story.md

### ADDED
- R2.4: WHEN user enables 2FA THE SYSTEM SHALL require TOTP verification

### MODIFIED
- R1.3: Changed timeout from 120s to 180s (reason: portal latency)

### REMOVED
- R2.3: Remember Me (deferred to next sprint)

### UNCHANGED
- All other requirements remain as-is
```

4. Delta shown for approval before merging into original
5. Propagation: story change > update design > update tasks. Design change > update tasks. Tasks change > no propagation.
6. Original files untouched until all gates pass
7. After the merged tasks.md is written, take the checkbox census and apply the status transition — see [Status Census](#status-census)

## Status Census

Refine is the one mode that can **add** open work to a story that already reads `done` or `validated`: a new requirement becomes a new task, and a new task is a new `- [ ]`. Nothing else in the engine does that — Run mode only ever closes boxes. So once the merged `tasks.md` is on disk (and only then: the boxes are what the census reads), census the task list and the Quality Gates, then apply the transition table in [run-mode.md](run-mode.md#status-transitions).

Exactly one rule may fire here:

- **Rule 2, the reopen edge (R1.7, R1.8)** — the story reads `done` or `validated` and the merge left at least one `[ ]`: write `in-progress` to every artifact that carries frontmatter. Without this write the story would keep claiming it is finished while owing open work — the lie `validate-story.sh` reports as "status is ahead of the checkboxes".
- **Every other outcome leaves the field exactly as it was.** Refine is a writer of this one transition and of no other value: it never writes `draft`, `done`, `validated`, `superseded` or `archived`. A refinement observes that work was *added*, never that work was *finished* or that execution *started* — those are things only a run can see, and a story with no `status:` at all keeps having none.

The write mechanism is defined once, in [run-mode.md](run-mode.md#status-transitions): `Edit` on the frontmatter line and never `Write`, the same value in every artifact, a failed write reported while the refinement continues. Do not restate it here.

## Gotchas

- Always propagate changes downstream via delta documents (story → design → tasks)
- Original files untouched until all gates pass — abort leaves originals intact
- A refinement that adds an open box to a `done` or `validated` story reopens it — census after writing tasks.md ([Status Census](#status-census))

## Expand Mode

1. Read the referenced existing story
2. Create new story in new directory (next sequential number)
3. Add "Related Stories" section in Introduction
4. Follow standard create flow
