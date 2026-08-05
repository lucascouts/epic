# List Mode

Triggered by `/epic:epic stories`, `/epic:epic stories full`, or `/epic:epic stories NNN`.

## Procedure

1. Glob `.epic/stories/*/tasks.md` to find all stories (exclude `.epic/archive/`)
2. For each story, read the frontmatter (type, scale, version, status) and parse task checkboxes
3. Take the checkbox census — `total`, `closed` and `deferred` are defined once, in [tasks.md](tasks.md#completion). Census the task list and the Quality Gates separately: each renders its own pair
4. Derive the story's computed condition from the census (see Status and Progress)

## Status and Progress

**Status is persisted, conditions are computed.** The status column carries the `status:` frontmatter value verbatim — one of `draft`, `in-progress`, `done`, `validated`, `superseded`, `archived`. When the field is absent, render `—` and say nothing more: most stories predate the field and its absence is neither an error nor a warning.

A computed condition is appended after a `·`. It is derived from the boxes at read time and is never written to a file — the box states it reads are defined once, in [tasks.md](tasks.md#completion):

| Condition | Rendered when | Rendered as |
|---|---|---|
| `done-except-external` | no `[ ]` remains and at least one box is `[~] (deferred: …)` | `done-except-external (N deferred)` |

So `in-progress · done-except-external (2 deferred)` reads: the file says `in-progress`, the boxes say nothing is open here and two items are still owed by an actor outside this repo. The pairing is the normal one — Run mode writes `done` only when no `[ ]` and no deferred box remains (R1.3), so a story waiting on an external actor keeps `in-progress` until that work lands. The persisted enum has no value for "done except external"; that is deliberate, and the reason the condition is computed rather than stored.

**Progress renders as `closed/total`, plus `(+D deferred)` when D > 0** — and only then. By the census in [tasks.md](tasks.md#completion), `closed` is `[x]` plus terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), so a waived gate closes its box and a finished story reads `5/5`, never an eternal `4/5`. Deferred boxes are closed too, but counted apart: that work is settled in the plan and still owed in the world.

## Summary View (`/epic:epic stories`)

```
Stories in .epic/stories/:

  001-fruit-management-api
     full | feature | v1 | done | Tasks: 11/11 | Gates: 5/5

  002-user-dashboard
     standard | feature | v1 | in-progress | Tasks: 4/8 (+1 deferred) | Gates: 0/5

  003-payment-webhooks
     standard | feature | v1 | in-progress · done-except-external (2 deferred) | Tasks: 4/6 (+2 deferred) | Gates: 5/5

  004-legacy-import
     standard | feature | v1 | — | Tasks: 1/4 | Gates: 0/5
```

One line per story: scale, type, version, status (with any computed condition), task progress, gate progress.

## Detailed View (`/epic:epic stories full`)

Same as summary, plus expand each story's task list showing checkbox state, task name, and metadata line. Do not show sub-task content fields (ToDo, Context, etc.) — only titles and status.

```
001-fruit-management-api (full, feature, v1) | done | Tasks: 11/11

  - [x] 1 - Project Scaffolding
    - [x] 1.1 - Install dependencies
    - [x] 1.2 - Commit
  - [x] 2 - Database Layer
    - [x] 2.1 - Schema and migrations
  ...

  Quality Gates: 5/5
    [~] Load test at 1k rps (waived: no load-test rig on this host — user decision)
```

Render every box as the file writes it, qualifier included. Under the gate count, list the gates that are not `[x]`: the count says a gate is settled, the line says how it was settled.

```
003-payment-webhooks (standard, feature, v1) | in-progress · done-except-external (2 deferred) | Tasks: 4/6 (+2 deferred)

  - [x] 1 - Webhook Receiver
    - [x] 1.1 - Signature verification
    - [x] 1.2 - Commit
  - [x] 2 - Provider Handshake
    - [~] 2.1 - Register the production callback URL (deferred: needs the provider's live account)
    - [~] 2.2 - Verify the first live event (deferred: needs a real payment in production)

  Quality Gates: 5/5
```

## Single Story View (`/epic:epic stories NNN`)

Same as detailed view but for one story only. Additionally show:
- Next pending task — the first `[ ]` in order. A `[~]` box is closed and is never the next pending task
- When no `[ ]` remains, report the story complete instead, and list every `[~] (deferred: …)` line with its reason: those are the only items still owed, and they name who owes them
- Quality gates status (each gate individually)

```
003-payment-webhooks (standard, feature, v1) | in-progress · done-except-external (2 deferred) | Tasks: 4/6 (+2 deferred)

  No pending tasks — complete. Still owed by an external actor:
    - [~] 2.1 - Register the production callback URL (deferred: needs the provider's live account)
    - [~] 2.2 - Verify the first live event (deferred: needs a real payment in production)

  Quality Gates: 5/5
```

## Archive View (`/epic:epic archive`)

List archived stories from `.epic/archive/manifest.yaml`:

```
Archived stories:

  001-fruit-management-api  | archived 2026-03-15 | complete
  002-user-dashboard        | archived 2026-03-20 | complete
```

## Archive Command (`/epic:epic stories archive NNN[-MMM]`)

Move completed stories to `.epic/archive/`:

```
/epic:epic stories archive 001          ← archive story 001
/epic:epic stories archive 001-005      ← archive stories 001 through 005
/epic:epic stories archive --done       ← archive every complete story (no `[ ]` remains)
```

Procedure:
1. Verify the story exists and is **complete** — no `[ ]` box remains, in the task list or in the Quality Gates. `[x]` and terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`) both close a box; see [tasks.md](tasks.md#completion)
   - If any `[ ]` remains: warn with the census (`closed/total`) and require the `--force` flag to proceed
   - A `done-except-external` story clears the gate — nothing is open — and is reported with its deferred count, so work owed outside this repo is stated rather than buried
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
