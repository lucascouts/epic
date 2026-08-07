# Supersede Mode (`/epic:epic stories supersede NNN --by MMM`)

Supersede is the sanctioned story replacement — banner, remap, closure, archive offer. Story `MMM` takes over `NNN`'s scope: `NNN` is closed with a banner pointing at its replacement, every `NNN` artifact flips to `status: superseded` with `superseded-by: MMM`, the index re-renders, and the archive is offered on the spot. `MMM` must already exist before the command runs — creating the replacement is a separate CREATE, so a typo in `--by` can never mint a story.

## Procedure

Five steps, in order. A refusal (matrix below) ends the operation before anything is written.

1. **Verify** — resolve both `NNN` and `MMM` and check rows 1-3 of the refusal matrix; any hit refuses with its one-line message and stops. Row 4 is **not** checked here: it turns on whether a prior supersede *finished*, which is the same judgement [Interrupted-Run Recovery](#interrupted-run-recovery) makes, so it is made once, in step 2.
2. **Banner** — prepend the standardized supersede banner to `NNN/story.md`. Idempotent, but not by refusing on the banner alone: a **complete** prior supersede refuses (row 4), while an **interrupted** one is offered completion. Either way the banner is written at most once, ever (R3.5). *(template and remap rules: [Banner Template](#banner-template) · closures: [Closure](#closure) · interrupted prior runs: [Interrupted-Run Recovery](#interrupted-run-recovery))*
3. **Close, then flip** — in this order, and the order is load-bearing: first close every open sub-task as `[~] (superseded-by: MMM)` ([Closure](#closure)), and only then write `status: superseded` plus `superseded-by: MMM` via `Edit` in every `NNN` artifact with frontmatter (`Edit`, not `Write` — the validate hook's PostToolUse matcher is `Write` only, so the transition does not re-trigger validation). **The status write is the commit point.** Doing it first would leave an interruption looking like `status: superseded` with open boxes — a story that reads finished, that `archive-story.sh`'s completion gate would accept with unremapped scope still open, and that step 2 would have to disentangle. Closing first means the only state an interruption can leave is *banner, maybe closures, no status* — unambiguously incomplete, and exactly what recovery is written to finish.
4. **Index** — regenerate the managed index: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-index.sh"`; a non-zero exit warns and never blocks.
5. **Offer** — offer to archive `NNN` immediately, exactly as [validate-mode.md#archive-offer](validate-mode.md#archive-offer) defines it: interactive sessions prompt `Archive story NNN? [y/n]`; headless sessions log the offer and proceed without pausing. Acceptance delegates to `archive-story.sh`, whose preflight accepts `superseded` as a completion state — a just-superseded story archives cleanly, no `--force` needed. The offer adds no preflight of its own — archive never consults integration state (R2.3).

## Refusal Matrix (R3.4, R3.5)

Rows 1-3 are checked in step 1; row 4 in step 2. Every refusal is hard: state the one-line message naming the reason, write nothing, and stop.

| # | Cause | One-line refusal message |
|---|---|---|
| 1 | `NNN` equals `MMM` | Refused: a story cannot supersede itself (`NNN` == `MMM`). |
| 2 | `MMM` does not exist | Refused: replacement story `MMM` does not exist — create it first, then re-run supersede. |
| 3 | `NNN` is already `archived` | Refused: story `NNN` is archived — archived stories are immutable history. |
| 4 | `NNN` carries a **complete** prior supersede — banner present, `status: superseded` written, no open sub-task left | Refused: story `NNN` already carries the supersede banner — re-running would duplicate it (R3.5). |

**Row 4 is one row, not two, and that is the fix for a real collision.** Earlier revisions listed *"`NNN` is already `superseded`"* and *"already carries the banner"* as separate causes, both hard refusals, the first checked in step 1. But a run interrupted between its status write and its closures satisfies the first while still owing work — so the story was refused by step 1 before recovery could ever be offered, and the only command that produces that state could not repair it. The two causes describe the same thing (a supersede that *finished*), so they are one row, evaluated once, in the step that can tell finished from interrupted. R3.4 carries the same guard in its own text: *"NNN carries a complete prior supersede"*.

## Banner Template

The banner is prepended immediately below the frontmatter block of `NNN/story.md`, before any other content — via `Edit`, never `Write` (same reason as step 3: the validate hook's PostToolUse matcher is `Write`-only). The template, verbatim:

```markdown
> ## ⛔ SUPERSEDED (<date>) — by story MMM-<slug>
> <one-line rationale, asked from the user at op time>
>
> | This story's open scope | Where it went |
> |---|---|
> | <task N.N — title> | MMM / <target or "dropped: reason"> |
>
> Do not execute. Kept for traceability; numbers are never recycled.
```

Filling it (R3.1, R3.2):

- **Date** — the operation date.
- **Rationale** — one line, asked from the user at op time. Headless: a supplied `--reason`, or a logged default, without pausing.
- **Remap rows** — one per open sub-task of `NNN`: every `[ ]` and every `[~] (deferred: …)`. Deferred work is still owed, so it must land somewhere; `[x]` and terminal `[~]` boxes get no row.
- **Targets** — filled interactively, row by row; default `MMM / re-scoped`. Scope that dies with the story takes `dropped: <reason>` in place of a target. Headless: every row takes the default without pausing.

## Closure

With the banner in, `NNN` is closed to a terminal, archivable state (R3.3):

- **Sub-tasks** — every open sub-task (the same set the remap rows were built from) is closed in `NNN`'s tasks.md as `[~] (superseded-by: MMM)`, qualifier on the same line per story 004's grammar — see [tasks.md#checkbox-grammar](tasks.md#checkbox-grammar). Example: `- [~] 2.1 - Switch the reader (superseded-by: 012)`. On a deferred box the `deferred:` qualifier is **replaced**, never joined — a line carrying both stays owed, because `deferred:` wins.
- **Frontmatter** — `status: superseded` plus the machine-readable companion `superseded-by: MMM` in every `NNN` artifact with frontmatter, via `Edit` (step 3). The companion is what `epic-index.sh` reads to render the supersede target in the index.

`superseded-by:` is a terminal qualifier, so no box stays open and nothing remains owed — the story archives cleanly whenever the step-5 offer is taken.

## Interrupted-Run Recovery

A run can die between banner and closure. On the next invocation the banner alone does not decide — completeness does:

| Prior run | Found | Response |
|---|---|---|
| Complete | banner present, every artifact `status: superseded`, no open sub-task left | refuse — row 4 above |
| Incomplete | banner present, but status writes or closures missing | offer to complete **only** the remaining steps |

The R3.5 refusal targets a re-run over a complete prior op; an interrupted op is not a re-run — it is the same operation finishing. Recovery therefore never touches the banner (it is written at most once, ever) and redoes only what is missing, in step 3's order: unclosed sub-tasks first, then the absent `status:`/`superseded-by:` writes, then the index and the archive offer.

**Why `status: superseded` with an open box is not a state recovery has to handle:** step 3 never produces it. Closures precede the status write precisely so that the last thing written is the one that declares the operation finished — an interruption leaves the story visibly unfinished rather than falsely complete. A story found in that shape did not come from this command, and repairing hand-edited frontmatter is not supersede's job.

## Walkthrough

Fixture: `/epic:epic stories supersede 042 --by 051` — story `042-legacy-import` replaced by `051-modern-import`. `042`'s tasks.md before the op, one closed box and three open ones:

```markdown
- [x] 1.1 - Parse the legacy CSV export
- [ ] 2.1 - Map legacy fields to the new schema
- [ ] 2.2 - Validate mapped rows
- [~] 3.1 - Import against the live feed (deferred: vendor credentials pending)
```

Three open sub-tasks (`2.1` and `2.2` as `[ ]`, `3.1` as a deferred `[~]`) → three remap rows; `1.1` gets none. The rationale is asked, targets answered for `2.2` and `3.1`, defaulted for `2.1`. The banner instance, prepended below `042/story.md`'s frontmatter:

```markdown
> ## ⛔ SUPERSEDED (2026-08-06) — by story 051-modern-import
> Vendor retired the v1 export API; 051 rebuilds the import on the v2 bulk endpoint.
>
> | This story's open scope | Where it went |
> |---|---|
> | task 2.1 — Map legacy fields to the new schema | 051 / re-scoped |
> | task 2.2 — Validate mapped rows | 051 / task 2.3 |
> | task 3.1 — Import against the live feed | 051 / dropped: the v1 sandbox died with the API |
>
> Do not execute. Kept for traceability; numbers are never recycled.
```

The three closures as they land in `042`'s tasks.md — `3.1`'s `deferred:` replaced, not kept:

```markdown
- [~] 2.1 - Map legacy fields to the new schema (superseded-by: 051)
- [~] 2.2 - Validate mapped rows (superseded-by: 051)
- [~] 3.1 - Import against the live feed (superseded-by: 051)
```

Frontmatter after the op — the same two fields land in every `042` artifact:

```yaml
---
story: legacy-import
type: feature
scale: standard
version: 1
created: 2026-05-14
status: superseded
superseded-by: 051
---
```

The index then re-renders `042` as superseded by `051` (step 4) and the archive offer fires (step 5). A second `supersede 042 --by 051` finds banner, status, and no open box — a complete prior run — and refuses:

> Refused: story 042 already carries the supersede banner — re-running would duplicate it (R3.5).
