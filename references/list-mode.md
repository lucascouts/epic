# List Mode

Triggered by `/epic:task stories`, `/epic:task stories full`, or `/epic:task stories NNN`.

## Procedure

1. Glob `.epic/stories/*/tasks.md` to find all stories (exclude `.epic/archive/`)
2. For each story, read the frontmatter (type, scale, version) and parse task checkboxes
3. Calculate progress: count `[x]` vs `[ ]` across all tasks and sub-tasks
4. Parse Quality Gates section: count checked vs unchecked

## Summary View (`/epic:task stories`)

```
Stories in .epic/stories/:

  001-fruit-management-api
     full | feature | v1 | Tasks: 10/11 (91%)

  002-user-dashboard
     standard | feature | v1 | Tasks: 0/5 (0%)
```

One line per story: scale, type, version, progress.

## Detailed View (`/epic:task stories full`)

Same as summary, plus expand each story's task list showing checkbox state, task name, and metadata line. Do not show sub-task content fields (ToDo, Context, etc.) — only titles and status.

```
001-fruit-management-api (full, feature, v1) — 10/11 tasks

  - [x] 1 - Project Scaffolding
    - [x] 1.1 - Install dependencies
  - [x] 2 - Database Layer
  - [x] 3 - User Model
    - [x] 3.1 - Implement password hashing
    - [x] 3.2 - Implement user CRUD
    - [x] 3.3 - Commit
  ...

  Quality Gates: 4/5 passed
    [ ] Full flow integration test
```

## Single Story View (`/epic:task stories NNN`)

Same as detailed view but for one story only. Additionally show:
- Next pending task (first `[ ]` in order)
- Quality gates status (each gate individually)

## Archive View (`/epic:task archive`)

List archived stories from `.epic/archive/manifest.yaml`:

```
Archived stories:

  001-fruit-management-api  | archived 2026-03-15 | complete
  002-user-dashboard        | archived 2026-03-20 | complete
```

## Archive Command (`/epic:task stories archive NNN[-MMM]`)

Move completed stories to `.epic/archive/`:

```
/epic:task stories archive 001          ← archive story 001
/epic:task stories archive 001-005      ← archive stories 001 through 005
/epic:task stories archive --done        ← archive all stories at 100% completion
```

Procedure:
1. Verify story exists and is 100% complete (all tasks `[x]`, all quality gates passed)
   - If not 100%: warn and require `--force` flag to proceed
2. Move directory from `.epic/stories/NNN-name/` to `.epic/archive/NNN-name/`
3. Update or create `.epic/archive/manifest.yaml` with entry:
   ```yaml
   archived:
     - number: "001"
       name: fruit-management-api
       archived_at: 2026-04-02
       status: complete
       tasks_total: 11
       tasks_completed: 11
   ```
4. Numbers are NEVER recycled — new stories always get the next highest number
5. Report: "Story NNN archived to `.epic/archive/NNN-name/`"
