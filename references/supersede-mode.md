# Supersede Mode (`/epic:epic stories supersede NNN --by MMM`)

Supersede is the sanctioned story replacement — banner, remap, closure, archive offer. Story `MMM` takes over `NNN`'s scope: `NNN` is closed with a banner pointing at its replacement, every `NNN` artifact flips to `status: superseded` with `superseded-by: MMM`, the index re-renders, and the archive is offered on the spot. `MMM` must already exist before the command runs — creating the replacement is a separate CREATE, so a typo in `--by` can never mint a story.

**Superseding is one script, never a hand-edit.** [`scripts/supersede-story.sh`](../scripts/supersede-story.sh) runs verify → banner → close-then-flip → index as one fail-closed sequence. This mode supplies the two things only a conversation can — the rationale and the remap targets — calls the script **once**, and surfaces its verdict. It never prepends the banner itself, never closes a box itself and never writes `status: superseded` itself, for the reason [list-mode.md](list-mode.md) gives about the archive (Archive Command): a banner written by hand can claim a remap the checkboxes contradict, and a status written by hand can declare an operation finished over scope that is still open — the false completion `archive-story.sh`'s gate would then wave through.

## Procedure

Three steps: **ask**, **call**, **surface and offer**. The mechanical half — the refusal matrix, the banner and its idempotence, the remap rows, the closures, the `status:` / `superseded-by:` writes, the interrupted-run classification and the index — belongs to the script. The sections below **document what the script does**; they are not a procedure to carry out by hand.

1. **Ask** — the conversational half, collected before the call: the one-line **rationale** (why `NNN` is being replaced) and a **target per open sub-task** (default `MMM / re-scoped`; `dropped: <reason>` for scope that dies with the story). A headless session asks nothing and passes neither — see [Banner Template](#banner-template).
2. **Call** — one invocation, which performs the whole mechanical sequence:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/supersede-story.sh" <NNN|story-dir> --by <MMM> [--rationale <text>] [--remap <N.N=target>]...
```

3. **Surface, then offer** — report the verdict out of the JSON ([Output and exit codes](#output-and-exit-codes)), then, on exit 0 only, make [the archive offer](#the-archive-offer).

### Flags

| Flag | Supplies | When omitted |
|---|---|---|
| `--by <MMM>` | **Required.** The replacement story — a number (`051`) or a directory name (`051-modern-import`). It must already exist | Exit 2. Creating `MMM` is a separate operation, which is what keeps a typo in `--by` from minting a story |
| `--rationale <text>` | The one line asked at op time; it becomes the banner's second line | The script records `Superseded by story MMM-<slug>; no rationale was supplied at op time.` |
| `--remap <N.N=target>` | Where sub-task `N.N`'s scope went. Repeatable, one per open sub-task. Only the **first** `=` separates, so `--remap 3.1=dropped: the v1 sandbox died` arrives intact | That row takes `MMM / re-scoped` |
| `--help`, `-h` | Usage on stdout, exit 0 | — |

`NNN` is a story number (`042`) or a story directory; the number resolves against the nearest `.epic/`.

**Never invent a flag value.** The rationale and every target are the user's words. A headless run defaults them *visibly* — the recorded default states that no rationale was supplied instead of manufacturing one.

### Output and exit codes

**One JSON object on stdout on every path that reaches a verdict** — `{story, path, by, status, reason, banner_written, remap_rows, closed_subtasks, artifacts_flipped[], index, index_error}`.

| Exit | `status` | Surface |
|---|---|---|
| 0 | `superseded` | A fresh run. Report `remap_rows`, `closed_subtasks` and `artifacts_flipped[]` — what this run wrote — then offer the archive |
| 0 | `completed` | An **interrupted** prior run was carried over the line. `banner_written: false` with `remap_rows: 0` is the proof no second banner was written; say what was finished, then offer the archive |
| 1 | `refused` | Nothing finished, so no archive offer. Report `reason` **verbatim**; `banner_written`, `closed_subtasks` and `artifacts_flipped[]` say what this run wrote before it stopped |
| 2 | — | Invalid input, and **no JSON is printed at all**. Report the stderr message: this is a bad invocation, not a user decision |

**The script is silent on stderr wherever it emits JSON, so the verdict reaches the user in your voice and in no other.** `archive-story.sh` prints `Refused: …` for the human and the same fact in JSON; this one prints nothing beside the object. A consumer piping stdout into `jq` — and bats' `run`, which merges the streams — would otherwise find a diagnostic in the middle of the object it is parsing. Read `reason` and `index_error` out of the report and say them in the session's own voice; a second, differently-worded copy of the same sentence is a second author for it. Exit 2 is the one path that speaks on stderr: it reaches no verdict and emits no JSON, so there is nothing to parse and nothing to duplicate.

**The index is regenerated by the script, not by this mode.** `index` reads `ok`, `regen-failed` or `skipped`. `regen-failed` is a warning and never a failure — the index is a *rendering* of the operation (see [validate-mode.md](validate-mode.md#index-refresh)), so the supersede stands and the next refresh retries: surface `index_error` and move on rather than re-running the generator here. `skipped` means the run never reached that step, which is the normal value on a refusal.

### The archive offer

**Offer on exit 0 only** — `superseded` and `completed` both leave `NNN` in the state `archive-story.sh`'s preflight accepts. Make it exactly as [validate-mode.md#archive-offer](validate-mode.md#archive-offer) defines it: interactive sessions prompt `Archive story NNN? [y/n]`; headless sessions log the offer and proceed without pausing. Acceptance delegates to `archive-story.sh`, whose preflight accepts `superseded` as a completion state — a just-superseded story archives cleanly, no `--force` needed. The offer adds no preflight of its own — archive never consults integration state (R2.3).

## Refusal Matrix (R3.4, R3.5)

What the script refuses, and why. Rows 1-3 are decided in its step 1, row 4 in its step 2. Every refusal is hard: exit 1, nothing written by this run, and the one-line message in `reason`. Surface it verbatim.

| # | Cause | `reason` |
|---|---|---|
| 1 | `NNN` equals `MMM` — asked twice, first numerically and again by identity once `MMM` resolves, so `--by 42`, `--by 042` and `--by 042-legacy-import` are all the same story | `a story cannot supersede itself (NNN == MMM)` |
| 2 | `MMM` does not exist | `replacement story MMM does not exist — create it first, then re-run supersede` |
| 3 | `NNN` is already `archived` | `story NNN is archived — archived stories are immutable history; nothing was modified` |
| 4 | `NNN` carries a **complete** prior supersede — banner present, `status: superseded` written, no open sub-task left | `story NNN already carries the supersede banner — re-running would duplicate it (R3.5)` |

**Row 4 is one row, not two, and that is the fix for a real collision.** Earlier revisions listed *"`NNN` is already `superseded`"* and *"already carries the banner"* as separate causes, both hard refusals, the first checked in step 1. But a run interrupted between its status write and its closures satisfies the first while still owing work — so the story was refused in step 1 before recovery could ever be offered, and the only command that produces that state could not repair it. The two causes describe the same thing (a supersede that *finished*), so they are one row, evaluated once, in the step that can tell finished from interrupted. R3.4 carries the same guard in its own text: *"NNN carries a complete prior supersede"*.

**Not every exit 1 is the matrix.** The script also refuses when it cannot proceed honestly: a `tasks.md` it cannot read (the remap rows and the closures are both derived from those checkboxes, so it would have to invent the scope it claims moved), a story directory that is a symlink pointing out of the project, a banner-bearing state it cannot classify, or a failed write in close-then-flip. Those messages are equally verbatim-surfaceable, and the report — not an assumption — is what says whether anything was written before the stop: read `banner_written`, `closed_subtasks` and `artifacts_flipped[]`.

## Banner Template

The script prepends the banner immediately below the frontmatter block of `NNN/story.md`, before any other content. (A `compact` story with no `story.md` takes `tasks.md`, that scale's front page — a recorded deviation.) The template it writes, verbatim:

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

**The `Edit`-not-`Write` constraint is met by construction now.** The prose procedure used to carry it because the validate hook's PostToolUse matcher is `Write`-only, so an artifact rewritten with that tool re-triggers validation mid-transition. A hook observes Claude's tool calls, and the script's own file writes are not tool calls at all — there is no longer a rule to remember here.

How the template is filled (R3.1, R3.2):

- **Date** — the operation date.
- **Rationale** — `--rationale`, the line this mode asks for. Omitted, the recorded default says a rationale was not supplied rather than inventing one.
- **Remap rows** — **derived, never passed**: one per open sub-task of `NNN`, read out of its tasks.md — every `[ ]` and every `[~] (deferred: …)`. Deferred work is still owed, so it must land somewhere; `[x]` and terminal `[~]` boxes get no row. Declaring the rows at the call site would rebuild the hand-written summary that can contradict the boxes it summarizes.
- **Targets** — `--remap N.N=target`, collected here row by row; default `MMM / re-scoped`. Scope that dies with the story takes `dropped: <reason>` in place of a target. Headless: pass none and every row takes the default without pausing.
- **No open scope at all** — the script writes `> No open scope to remap — every sub-task was already settled.` in place of the table. A header row with no data rows still announces "here is where the scope went", which for a story with nothing open is a claim about nothing.

## Closure

With the banner in, the script closes `NNN` to a terminal, archivable state (R3.3):

- **Sub-tasks** — every open sub-task (the same set the remap rows were built from) is closed in `NNN`'s tasks.md as `[~] (superseded-by: MMM)`, qualifier on the same line per story 004's grammar — see [tasks.md#checkbox-grammar](tasks.md#checkbox-grammar). Example: `- [~] 2.1 - Switch the reader (superseded-by: 012)`. On a deferred box the `deferred:` qualifier is **replaced**, never joined — a line carrying both stays owed, because `deferred:` wins.
- **Frontmatter** — `status: superseded` plus the machine-readable companion `superseded-by: MMM` in every `NNN` artifact with frontmatter; `artifacts_flipped[]` names the ones this run wrote. The companion is what `epic-index.sh` reads to render the supersede target in the index.

`superseded-by:` is a terminal qualifier, so no box stays open and nothing remains owed — the story archives cleanly whenever the offer is taken.

**The closures precede the status write, and the order is load-bearing.** The status write is the **commit point**. Doing it first would leave an interruption looking like `status: superseded` with open boxes — a story that reads finished, that `archive-story.sh`'s completion gate would accept with unremapped scope still open, and that the banner step would then have to disentangle. Closing first means the only state an interruption can leave is *banner, maybe closures, no status* — unambiguously incomplete, and exactly what recovery is written to finish.

## Interrupted-Run Recovery

A run can die between banner and closure. On the next invocation the banner alone does not decide — completeness does, and the script classifies the state before it writes anything:

| Prior run | Found | Response |
|---|---|---|
| Complete | banner present, every artifact `status: superseded`, no open sub-task left | refuse — row 4 above |
| Incomplete | banner present **and no `status: superseded` written anywhere yet** — whether the closures are untouched, partial or already complete; or every box closed and the `status:`/`superseded-by:` writes reached only some artifacts | complete **only** the remaining steps |
| Not from this command | banner present, **some or every** artifact `status: superseded`, **and at least one sub-task still open** | refuse: `story NNN carries a supersede banner in a state this command cannot produce (status written with scope still open) — repair the frontmatter by hand, then re-run` |

**Re-running the same command is how an interrupted run is completed.** There is no separate mode and no second prompt: `supersede NNN --by MMM` again redoes only what is missing, in the same order (unclosed sub-tasks first, then the absent `status:` / `superseded-by:` writes, then the index), and returns exit 0 with `status: completed`, `banner_written: false`, `remap_rows: 0`. The re-invocation is the acceptance — the user asked for the same operation a second time, and an interrupted op is not a re-run but the same operation finishing.

The three rows are **disjoint AND exhaustive over every banner-bearing state**, and both halves are load-bearing. Disjoint: *Complete* needs every artifact flipped and no box open, *Incomplete* needs either no status anywhere or no box open, *Not from this command* needs a status write **and** an open box — no story matches two. Exhaustive: enumerate `status ∈ {none, some, all} × open-box ∈ {yes, no}` and every cell lands in exactly one row.

**Exhaustiveness is not decoration here, and an earlier revision lost it.** The banner is written unless a row says not to, so a banner-bearing state matching NO row falls straight through to a second banner — which R3.5 forbids unconditionally and which the paragraph below calls impossible. A revision that narrowed *Incomplete* to obtain disjointness (its Found cell had read "banner present, but status writes **or** closures missing", which matched the open-box case through its second clause and gave one state two answers) removed the overlap and left a gap in its place: the states now covered by the third row matched nothing at all. Disjointness alone is half a table; a classification that decides a found state must answer for every state it can be handed.

The R3.5 refusal targets a re-run over a *complete* prior op. Recovery therefore never touches the banner — it is written at most once, ever.

**Why `status: superseded` with an open box is not a state RECOVERY has to handle:** close-then-flip never produces it. The closures precede the status write precisely so that the last thing written is the one that declares the operation finished — an interruption leaves the story visibly unfinished rather than falsely complete. A story found in that shape did not come from this command (the pre-reorder flip-then-close procedure could produce it; hand-edited frontmatter and a half-applied `Edit` sweep still can), and repairing it is not supersede's job.

**Out of scope for recovery is not the same as out of scope for the table**, and conflating the two is what put a second banner one fall-through away. The shape still has to be *classified*, because the banner is written unless something stops it — so it gets the third row, which refuses and names the reason instead of offering a completion supersede cannot honestly perform. Refusing is what R3.5 requires here: the banner is written at most once, ever, and a state this command cannot produce is the last one that should be allowed to produce a duplicate.

## Walkthrough

Fixture: `/epic:epic stories supersede 042 --by 051` — story `042-legacy-import` replaced by `051-modern-import`. `042`'s tasks.md before the op, one closed box and three open ones:

```markdown
- [x] 1.1 - Parse the legacy CSV export
- [ ] 2.1 - Map legacy fields to the new schema
- [ ] 2.2 - Validate mapped rows
- [~] 3.1 - Import against the live feed (deferred: vendor credentials pending)
```

Three open sub-tasks (`2.1` and `2.2` as `[ ]`, `3.1` as a deferred `[~]`) → three remap rows; `1.1` gets none. The mode asks for the rationale and for a target per open row — `2.1` is left unanswered on purpose, so it takes the default — and then makes one call:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/supersede-story.sh" 042 --by 051 \
  --rationale 'Vendor retired the v1 export API; 051 rebuilds the import on the v2 bulk endpoint.' \
  --remap '2.2=task 2.3' \
  --remap '3.1=dropped: the v1 sandbox died with the API'
```

The banner instance it prepends below `042/story.md`'s frontmatter:

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

And the report, on stdout, exit 0:

```json
{
  "story": "042-legacy-import",
  "path": "/home/dev/project/.epic/stories/042-legacy-import",
  "by": "051",
  "status": "superseded",
  "reason": "",
  "banner_written": true,
  "remap_rows": 3,
  "closed_subtasks": 3,
  "artifacts_flipped": ["design.md","story.md","tasks.md"],
  "index": "ok",
  "index_error": ""
}
```

`index: "ok"` says the index already re-renders `042` as superseded by `051`, so the only thing left is the archive offer. A second `supersede 042 --by 051` finds banner, status and no open box — a complete prior run — and refuses with exit 1 and `banner_written: false`:

```json
{
  "status": "refused",
  "reason": "story 042-legacy-import already carries the supersede banner — re-running would duplicate it (R3.5)",
  "banner_written": false,
  "index": "skipped"
}
```

which reaches the user in the session's own voice, once:

> Refused: story 042 already carries the supersede banner — re-running would duplicate it (R3.5).
