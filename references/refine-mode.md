# Refine Mode

Triggered by `/epic:task stories refine NNN`.

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

## Gotchas

- Always propagate changes downstream via delta documents (story → design → tasks)
- Original files untouched until all gates pass — abort leaves originals intact

## Expand Mode

1. Read the referenced existing story
2. Create new story in new directory (next sequential number)
3. Add "Related Stories" section in Introduction
4. Follow standard create flow
