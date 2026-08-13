# List Mode

Triggered by `/epic:epic stories`, `/epic:epic stories full`, or `/epic:epic stories NNN`.

## Procedure

1. Glob `.epic/stories/*/tasks.md` to find all stories (exclude `.epic/archive/`)
2. Run the workspace policy lint — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-gitpolicy.sh"` from the workspace root — and render the header notice it decides, before the first story row (see Policy Notice). **One invocation for the whole listing, before the per-story loop below**: it measures the workspace, not a story, so its cost is the same at 4 stories and at 400 and there is no gate to apply
3. For each story, read the frontmatter (type, scale, version, status) and parse task checkboxes
4. Take the checkbox census — `total`, `closed` and `deferred` are defined once, in [tasks.md](tasks.md#completion). Census the task list and the Quality Gates separately: each renders its own pair
5. Derive the story's computed condition from the census (see Status and Progress) — except for a `scale: spike` story, whose condition comes from its `## Verdict` plus one staleness pass for the whole listing (see Spike Lifecycle)
6. For each story, ask `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --should-annotate <status> <story-count> <is-stories-full>` whether this story is annotated at all — exit 0 evaluates, exit 1 skips — and on exit 0 pipe `story-git-status.sh` into the same script's `--list` mode and append what it writes (see Integration Annotation). That one decision holds both gates: only `done`/`validated` stories are annotated, and more than 50 stories skips unless the command is `stories full`
7. Refresh the managed index block opportunistically — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-index.sh"`; a non-zero exit warns and never blocks the listing (defined once, in [validate-mode.md](validate-mode.md#index-refresh))

## Policy Notice

**One line, and only when the workspace contradicts itself (R4.2).** A project's declared `.epic` versioning policy and what git actually does can disagree for months without git ever mentioning it: the corpus's `kpranois` had **47 `.epic` files committed through a `.gitignore` that said they were never committed**. Nothing was broken in any way a git command reports — the workspace was merely arguing with itself. This is the line that says so, in the one place the user is already looking.

**The decision is the script's; only the wording is this mode's.** [`scripts/epic-gitpolicy.sh`](../scripts/epic-gitpolicy.sh) measures and prints `{git, policy, gitignore_ignores_epic, gitignore_source, tracked_md, tracked_draft, verdict}`, and **the notice fires on exactly one condition — `verdict != "consistent"` — which is read from that JSON and never re-derived here.** No `grep` over `.gitignore` to decide whether `.epic` is ignored, no `git ls-files` to decide whether anything is tracked, no reading of the index at all: the script already asked git, with `--no-index`, which is the only way "tracked *through* an ignoring `.gitignore`" answers truthfully, and a second reading of the same facts would be a second thing to keep in step. Unlike the Integration Annotation below there is no rendering script, so the *sentences* here are this mode's own — which is exactly why the *trigger* must not be.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-gitpolicy.sh"
```

Run it from the **workspace root** — it resolves `.epic/` against `$PWD`. Every measurement path exits 0; exit 2 is a usage error only (the script takes no arguments), so a non-zero exit is a bug in the call and never a finding about the workspace. **A failed call, absent `jq`, or output that does not parse all render nothing and never block the listing** — the same silent degradation the annotation takes (R1.4). "Not computable" must not dress up as a finding.

**One invocation per listing, never one per story.** The Cost rule (R2.1) below exists because each *annotation* is a git evaluation and a 400-story project would otherwise pay for 400 of them. This lint has no such gate and needs none: it answers a question about the workspace, not about a story, so it is one call whatever the story count. Procedure step 2 is where it runs — **before** the per-story loop, so the header can be printed before the first row. Read its JSON once and hold it; re-running it per story would be exactly the cost the rule below forbids.

### Where the notice renders

| Command | Verdict notice | `undeclared` line |
|---|---|---|
| `/epic:epic stories` | yes | no |
| `/epic:epic stories full` | yes | yes |
| `/epic:epic stories NNN` | yes | no |
| `/epic:epic archive` | no | no |

It is the **first line of the output**, followed by a blank line, above `Stories in .epic/stories/:` — a state line printed under the story rows is a footnote, and R4.2 exists so the state is seen before the list is read. `/epic:epic archive` renders the archive manifest rather than the workspace's stories and carries neither line.

```
⚠ .epic git state is self-contradictory (contradiction: 47 files tracked while .gitignore ignores .epic/)

Stories in .epic/stories/:

  001-fruit-management-api
     full | feature | v1 | done · integrada | Tasks: 11/11 | Gates: 5/5
```

### Read order is a contract, and getting it wrong aborts the listing

`git`, `policy` and `verdict` are **total** — present on every path the script takes, safe to read unconditionally. The other four (`gitignore_ignores_epic`, `gitignore_source`, `tracked_md`, `tracked_draft`) are **absent when `git` is `false`**, and `jq -r` renders an absent key as the literal text `null`, not as `false`, `""` or `0`. Under `set -u` a `-gt` against that word aborts with `null: unbound variable` — measured, bash 5.3. **Read a measurement key only inside the `verdict != "consistent"` branch**, which is where every arm of the table below already lives.

That is safe today by an invariant of the *script* rather than of the JSON, and it is stated here so a later edit cannot lose it: the non-git object always reports `verdict: "consistent"`, so the gate is never open on the one path where those four keys are missing. **If a future line ever needs a measurement key outside that branch, gate it on `git == true` instead** — the script's own stated consumer requirement, in [`scripts/epic-gitpolicy.sh`](../scripts/epic-gitpolicy.sh)'s header, and the same contract [init-mode.md](init-mode.md#step-51--measure-before-asking) reads it under.

```bash
lint=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-gitpolicy.sh" 2>/dev/null) || lint=''
verdict=$(jq -r '.verdict' <<<"$lint" 2>/dev/null); verdict=${verdict:-consistent}
policy=$(jq -r '.policy' <<<"$lint" 2>/dev/null);   policy=${policy:-undeclared}

# The four measurement keys are read HERE and nowhere else:
if [ "$verdict" != consistent ]; then
  tracked_md=$(jq -r '.tracked_md' <<<"$lint")
  tracked_draft=$(jq -r '.tracked_draft' <<<"$lint")
  ignore_source=$(jq -r '.gitignore_source' <<<"$lint")
fi
```

The two `${…:-}` defaults are what make an unreadable answer silent rather than fatal: no `jq`, a parse error or an empty capture all leave `verdict` at `consistent`, and `consistent` renders nothing.

### The arms

Reached **only** when `verdict != "consistent"`. The five rows are the script's five non-`consistent` verdict arms, one each, and they are mutually exclusive: `verdict` chooses the pair, then one further field — read from the same JSON, never from git — chooses the row.

| The lint says | This mode renders, verbatim |
|---|---|
| `contradiction`, `tracked_md + tracked_draft > 0` | `⚠ .epic git state is self-contradictory (contradiction: <N> files tracked while <source> ignores .epic/)` |
| `contradiction`, `tracked_md + tracked_draft == 0` | `⚠ .epic git state is self-contradictory (contradiction: tracked-md declared, but <source> ignores .epic/ — no artifact can be committed)` |
| `partial`, `tracked_draft > 0` | `⚠ .epic tracks scratch space (partial: <tracked_draft> .draft/ files tracked — .draft/ is in no policy's tracked set)` |
| `partial`, `tracked_draft == 0` and `policy: tracked-md` | `→ .epic artifacts are declared tracked-md but not committed yet (partial: 0 tracked) — git add .epic && git commit` |
| `partial`, `tracked_draft == 0` and `policy: local-only` | `⚠ .epic tracking does not match declared policy (partial: local-only declared, <tracked_md> artifacts tracked)` |

`<N>` is `tracked_md + tracked_draft`; `<source>` is the `gitignore_source` field — the `ignore_source` capture above, sanitised as the next section requires. Filled in, they read:

```
⚠ .epic git state is self-contradictory (contradiction: 47 files tracked while .gitignore ignores .epic/)
⚠ .epic git state is self-contradictory (contradiction: tracked-md declared, but .git/info/exclude ignores .epic/ — no artifact can be committed)
⚠ .epic tracks scratch space (partial: 3 .draft/ files tracked — .draft/ is in no policy's tracked set)
→ .epic artifacts are declared tracked-md but not committed yet (partial: 0 tracked) — git add .epic && git commit
⚠ .epic tracking does not match declared policy (partial: local-only declared, 12 artifacts tracked)
```

**No head claims a declaration that may not exist.** `undeclared` is not a quiet verdict — kpranois's own shape was 47 files tracked through an ignoring `.gitignore` with no `.gitpolicy` at all — and a `.draft/` file in the index is wrong under every policy and under none. So rows 1–3 name the measured facts and nothing else; only rows 4 and 5, whose arms require a declaration, mention one. **If some future arm produces a combination no row matches, render the generic form** — `⚠ .epic tracking does not match declared policy (<verdict>: policy=<policy>, tracked_md=<n>, tracked_draft=<n>)` — rather than inventing a sentence. Naming the numbers is always true; a guessed diagnosis is not.

**Two markers, and the difference is load-bearing.** `⚠` (U+26A0, bare — no U+FE0F variation selector) means the workspace state is wrong: two settings fighting each other, or files where no policy puts them. `→` (U+2192) means nothing is wrong and there is a next step. Row 4 is the whole reason the distinction exists: it is what a project reports on its **very next listing after choosing the recommended option at init** — `tracked-md` declared, first commit not made yet — and [init-mode.md](init-mode.md#after-init--making-a-tracked-md-declaration-real) already documents that state as *correct*, with this same command to close it. Do not invent a second explanation for it, and do not warn a user about the correct choice they just made: a true signal that fires on healthy workspaces is how people learn to skip the line. Row 3 is the damaging partial it must never be confused with — run logs, phase snapshots and authored tests in the index, travelling with the repository forever.

### Naming the real ignore source, never assuming `.gitignore`

Both `contradiction` rows print `<source>` = the `gitignore_source` field **verbatim**. Git consults three exclude sources and the verdict fires for any of them: the root `.gitignore`, `.git/info/exclude` (local to this clone, and it travels with nothing), or the user's global `core.excludesFile` (an absolute path anywhere on the machine — a large population has `.epic` in it, from the older "never commit `.epic`" doctrine). Writing "gitignore" for the second and third would send the user to open a file that has nothing in it, which is worse than saying nothing. The script guarantees the field is non-null exactly when `gitignore_ignores_epic` is `true`, which both rows require; if it ever arrives `null` anyway, write the words `an exclude rule` — never the text `null`, and never `.gitignore` on a guess.

**`gitignore_source` is untrusted text.** It is the one externally-authored string in the object: a filesystem path git hands over, which may be absolute, may point outside the workspace, and may legitimately contain control bytes (the script escapes them for JSON transport; `jq -r` hands them back raw). Before printing, **replace every character below U+0020 and U+007F with a single space.** The notice is exactly one line, and a raw newline in a directory name would split it in two — the second half reading like a finding of its own. Print it as plain text; never as a link, and never as anything a renderer would interpret.

### `undeclared` is a second signal, and it is not this notice

A workspace that never answered init's question reports `policy: "undeclared"`, and with nothing tracked its `verdict` is **`consistent`** — the ordinary state of a fresh workspace, and of this plugin's own repository. It therefore produces no notice at all by the rule above. That is deliberate: a line on every listing of every undeclared project is precisely the noise the lint was weighed against. Under `/epic:epic stories full`, and there only, add one further line:

```
→ No .epic versioning policy declared — run /epic:epic init to choose one (tracked-md or local-only).
```

Its condition is `policy == "undeclared"` read on its own; it does not consult `verdict`, and it is **not** R4.2's notice. When a verdict notice is showing too, the two are separate lines and the verdict comes first — R4.2 asks for one line naming the contradiction, and this is a different sentence about a different fact. `policy` is total, so this line needs no `git` gate: a declaration is valid before `git init` and takes effect the moment the directory becomes a repository ([init-mode.md](init-mode.md#versioning-policy)).

## Status and Progress

**Status is persisted, conditions are computed.** The status column carries the `status:` frontmatter value verbatim — one of `draft`, `in-progress`, `done`, `validated`, `superseded`, `archived`. When the field is absent, render `—` and say nothing more: most stories predate the field and its absence is neither an error nor a warning.

A computed condition is appended after a `·`. It is derived from the boxes at read time and is never written to a file — the box states it reads are defined once, in [tasks.md](tasks.md#completion):

| Condition | Rendered when | Rendered as |
|---|---|---|
| `done-except-external` | no `[ ]` remains and at least one box is `[~] (deferred: …)` | `done-except-external (N deferred)` |

So `in-progress · done-except-external (2 deferred)` reads: the file says `in-progress`, the boxes say nothing is open here and two items are still owed by an actor outside this repo. The pairing is the normal one — Run mode writes `done` only when no `[ ]` and no deferred box remains (R1.3), so a story waiting on an external actor keeps `in-progress` until that work lands. The persisted enum has no value for "done except external"; that is deliberate, and the reason the condition is computed rather than stored.

**Progress renders as `closed/total`, plus `(+D deferred)` when D > 0** — and only then. By the census in [tasks.md](tasks.md#completion), `closed` is `[x]` plus terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), so a waived gate closes its box and a finished story reads `5/5`, never an eternal `4/5`. Deferred boxes are closed too, but counted apart: that work is settled in the plan and still owed in the world.

## Spike Lifecycle

**A spike's status is its Verdict.** A `scale: spike` story is a time-boxed probe whose deliverable is an answer, and the answer lives in the `## Verdict` section of its `tasks.md` — template and grammar defined once, in [tasks.md](tasks.md#spike-scale-adaptations). The status column therefore carries the Verdict **instead of** the frontmatter status, never beside it: a spike's `in-progress` tells a reader nothing they came for, and printing both would put two competing claims in one column.

The arms below **document what [`scripts/epic-index.sh`](../scripts/epic-index.sh)'s `verdict_cell` renders** — the managed index and this listing are two views of one fact, and a second spelling here would be a second thing to keep in step:

| Verdict | Rendered as |
|---|---|
| `open`, `wont-do` | the value, verbatim |
| `promote`, with `promoted-to:` naming a story that exists | `promote to NNN` |
| `promote`, with `promoted-to:` naming no story on disk | `promote to NNN (missing)` |
| `promote`, with no target recorded | `promote` |
| absent, or unreadable | `—` |

`(missing)` is also the interrupted-promote case — the Verdict written, the follow-up story never created (see the offer below). Absent renders the same em dash a story with no `status:` gets: inventing `open` would state a verdict nobody wrote.

**Stale open spikes (R1.5).** A Verdict left `open` is the failure mode this scale exists to prevent, so it expires: **14 days** since the last change to `tasks.md`. **That number is [`scripts/monitor-stale.sh`](../scripts/monitor-stale.sh)'s and so is the measurement** — it owns the threshold (`SPIKE_THRESHOLD_DAYS`, user option `spikeStaleThresholdDays`) and the mtime read. Ask it; never `stat` a file here and never restate the deadline as arithmetic, or the day someone tunes the option this listing keeps quoting 14.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/monitor-stale.sh" --once
```

One pass over every story, **one invocation for the whole listing** — unlike the per-story git evaluation below, there is no cost rule to apply. `--once` deliberately ignores `enableStaleMonitor`: that option governs the *background watcher*, the thing that speaks unasked, while R1.5 asks for this flag in the story list whether or not anyone opted into being notified in their sleep.

| The script writes | This mode renders |
|---|---|
| `Epic spike '031-probe-cache' has an open Verdict untouched for 15 days — promote or close.` | ` · spike open 15 days — promote or close` on that story's row |
| `Epic story '…' has pending tasks untouched for N days.` | nothing — the generic nag belongs to the background watcher |

The **decision** is the script's; only the shortening is this mode's, like the `·` separators and the column layout. A terminal Verdict never produces a line whatever its boxes say, and an `open` spike inside the deadline produces none either — silence here means "not stale", and it is the only thing that does.

**Promote hands off to CREATE (R1.6).** When a spike's Verdict becomes `promote` in an interactive session — set during a run, or found here as a `promote` row whose target is absent or `(missing)` — **offer** to create the follow-up story, pre-filled with the spike's `conclusion:` as the seed of its problem statement. The conclusion is what the spike learned, and re-typing it into CREATE is how the finding gets quietly rewritten. On acceptance, run CREATE and then write `promoted-to: NNN` back into the spike's Verdict, with the number CREATE actually assigned.

Both halves are load-bearing: **never create the story without asking** (a promote is a decision to open work, and only the user opens work), and **never record `promoted-to:` before the story exists** — a number guessed ahead of CREATE is a pointer to nothing, and the manifest never recycles numbers to make it true later. A run interrupted between the two leaves exactly the `(missing)` row above, which is why the offer is repeated at the next `stories` invocation instead of being made once and forgotten.

**Archive eligibility (R1.7).** A spike is complete for archive purposes when its Verdict is `wont-do`, or `promote` with a `promoted-to:` recorded — and never because of its checkboxes, which are probe steps rather than a contract. This is not a rule to apply by hand: [`scripts/archive-story.sh`](../scripts/archive-story.sh)'s preflight already reads a spike that way and refuses one whose Verdict is `open`, absent or a `promote` with no target, naming the missing piece. What it means for this mode is the `--done` expansion below: a concluded spike belongs in the sweep even with open probe boxes, and an `open` spike stays out of it even with every box ticked.

## Integration Annotation

**Computed live, stored nowhere, blocking nothing.** A `done` or `validated` status says the work is finished; whether it ever reached the main branch is a separate fact, and this is where the list surfaces it.

**The annotation is one script, never a prose rendering.** [`scripts/story-git-status.sh`](../scripts/story-git-status.sh) measures and prints `{story, main_branch, integrated, evidence, checked_at}`; [`scripts/render-integration.sh`](../scripts/render-integration.sh) turns that JSON into the label. This mode pipes one into the other and appends what comes back — it never derives the label itself. A rendering rule written down twice is two things to keep in step, and the copy the test suite exercises must be the copy the command runs.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/story-git-status.sh" <story-dir> \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --list
```

`--list` reads the detector's JSON on **stdin** and writes the bare label; the separator is the list's business, so append it after a ` · `. What it writes, per the `integrated` field, **documents the script's arms — it is not an instruction to render them by hand**:

| `integrated` | The script writes |
|---|---|
| `true` | `integrada` |
| `false` | `não-integrada` |
| `null` | nothing — no main branch was queryable, so no search happened and there is no answer to report |

`null` and `false` are opposite claims and the script keeps them apart: `false` says a search ran and came back empty, `null` says no search was possible. Even a neutral "unknown" in the `null` row would be read as a finding by someone scanning the column.

Exit 2 from the detector — not a git repository, or story not found — also renders nothing: nothing reaches the pipe and `--list` degrades silently (R1.4). A workspace without git is legal, and "not computable" must never dress up as a finding — no annotation, no warning, no error. Unparseable JSON, a missing `integrated` key and a machine without `jq` all mean the same thing and take that same silent path.

**Every rendering path exits 0**, so a label that was produced and one that deliberately was not carry the same exit status: there is nothing here to branch on. That is a contract rather than a convenience — R2.2 requires this signal to inform and never to gate, and a caller reading `$?` would turn it into a verdict. The one non-zero exit that is not `--should-annotate` is exit 2, an unknown or missing mode: a caller error, unreachable from a well-formed call.

The labels `integrada` and `não-integrada` are contract strings, spelled once in the script (`ANNOTATION_INTEGRATED`, `ANNOTATION_NOT_INTEGRATED`) and reproduced here verbatim — Portuguese and accented on purpose, the `ã` being U+00E3 (UTF-8 `0xC3 0xA3`), so a file re-saved in another encoding breaks the contract without breaking the syntax. The annotation is informational only: it never changes list ordering, filtering, or any verdict — whether a `não-integrada` story needs a merge, a cherry-pick or nothing at all is the user's decision, not this mode's.

**Cost rule (R2.1) — a decision, not a rendering.** Each annotation is one git evaluation, so this is where a 400-story project stops paying for 400 of them. The rule is the script's third mode: it reads no stdin, writes no output, and **its exit code is the answer**.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --should-annotate <status> <story-count> <is-stories-full>
```

| Exit | Means |
|---|---|
| 0 | evaluate this story — run the pipe above |
| 1 | skip it — no git call, no annotation |

**This is the only non-zero exit a well-formed call can produce** — the exit 2 above answers a caller that called the script wrong, never a question about a story — and it is the reason the two renderings can afford to be exit-code-free. `<is-stories-full>` is `true` only for `/epic:epic stories full`. Three gates answer in this order: `status` — only `done`/`validated` stories are ever annotated, which is not a cost control and no sweep flag overrides it; then the full sweep, which answers before the count is looked at; then the count — **more than** 50 skips, so a project with exactly 50 stories is still evaluated.

## Summary View (`/epic:epic stories`)

```
Stories in .epic/stories/:

  001-fruit-management-api
     full | feature | v1 | done · integrada | Tasks: 11/11 | Gates: 5/5

  002-user-dashboard
     standard | feature | v1 | in-progress | Tasks: 4/8 (+1 deferred) | Gates: 0/5

  003-payment-webhooks
     standard | feature | v1 | in-progress · done-except-external (2 deferred) | Tasks: 4/6 (+2 deferred) | Gates: 5/5

  004-legacy-import
     standard | feature | v1 | — | Tasks: 1/4 | Gates: 0/5

  005-notification-digest
     standard | feature | v1 | validated · não-integrada | Tasks: 6/6 | Gates: 5/5
```

One line per story: scale, type, version, status (with any computed condition and integration annotation), task progress, gate progress. Here 001's finished work is on the main branch and 005's is not yet; 002–004, not being `done` or `validated`, are never evaluated.

## Detailed View (`/epic:epic stories full`)

Same as summary, plus expand each story's task list showing checkbox state, task name, and metadata line. Do not show sub-task content fields (ToDo, Context, etc.) — only titles and status.

```
001-fruit-management-api (full, feature, v1) | done · integrada | Tasks: 11/11

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

List archived stories from `.epic/archive/manifest.yaml` — the append-only record `archive-story.sh` writes at the moment of each move. Render each row **from the entry's own fields**; never re-derive them by re-reading the archived story. The entry is what the boxes said when the story left `stories/`, and re-deriving it is how a rendering starts disagreeing with the record it claims to render.

```
Archived stories:

  001-fruit-management-api  | archived 2026-03-15 | validated  | 11/11
  003-payment-webhooks      | archived 2026-08-05 | validated  | 5/7 (+2 deferred)
  004-legacy-import         | archived 2026-08-05 | in-progress | 1/2 (forced: superseded by the new bulk loader)
```

- `archived_at` is a full ISO-8601 timestamp — render the date part.
- `status` is the story's **own frontmatter status as it read at move time**, never a verdict the archive invented. A `--force`d archive of unfinished work therefore says `in-progress`, and shows its open boxes.
- `forced_reason` is present only on a forced entry. Always show it: it is the only record that a refusal was overridden, and by whom for what.
- Progress renders `tasks_closed/tasks_total`, plus `(+N deferred)` when `tasks_deferred > 0` — the manifest's own three numbers. Note they partition differently from the census above: the manifest counts **every** `[~]` as `tasks_deferred`, where this mode's Progress column folds terminal `[~]` into `closed`. One grammar, two aggregations — see the contract below.

## Archive Command (`/epic:epic stories archive NNN[-MMM]|--done`)

**Archiving is one script, never a manual move.** [`scripts/archive-story.sh`](../scripts/archive-story.sh) runs preflight → guards → prune → derived manifest entry → move → index regeneration as one fail-closed sequence. This mode resolves *which* stories to archive and calls it once per story. It never moves a directory itself and never writes a manifest entry itself: an entry written by hand can claim a completion the checkboxes contradict, which is precisely what the old prose procedure allowed.

```
/epic:epic stories archive 001          ← story 001
/epic:epic stories archive 001-005      ← stories 001 through 005
/epic:epic stories archive --done       ← every complete story
```

### Resolving the argument

**One story per invocation.** The script accepts exactly one story and rejects a second positional argument with exit 2. Ranges and `--done` are expanded *here* and the script is called once per story, in ascending number order.

| Argument | Expands to |
|---|---|
| `NNN` | that one story |
| `NNN-MMM` | every existing story in the inclusive range; a number with no directory is skipped, not an error |
| `--done` | every story in `.epic/stories/` that is **complete** — no `[ ]` box remains, in the task list or in the Quality Gates. `[x]` and terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`) both close a box; see [tasks.md](tasks.md#completion). A `scale: spike` story is complete by its **Verdict** instead, never by its boxes (see Spike Lifecycle) |

A `done-except-external` story clears that gate — nothing is open — and is reported with its deferred count, so work owed outside this repo is stated rather than buried. If any `[ ]` remains, the story is **not** `--done`; archiving it anyway is the user's explicit `--force <reason>` decision, never this mode's.

**One verdict per story, and a batch never stops on one.** Each call returns its own verdict; a `blocked` or `refused` story is reported and the batch continues with the next number. Surface every verdict exactly as [validate-mode.md](validate-mode.md#archive-offer) prescribes — that table is the single definition of how each `status` is presented, here and at the offer. Close a batch with a one-line tally (`archived N, blocked M, refused K`) so a partial sweep is visible as a partial sweep.

### Invocation and flags

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/archive-story.sh" <NNN|story-dir> [flags]
```

The story number (`003`) resolves against the nearest `.epic/`; a directory path also works.

| Flag | Effect | Recorded as |
|---|---|---|
| `--allow-heavy` | Archive despite files >10 MB or non-text | `overrides_used: ["allow-heavy"]` |
| `--skip-secrets` | Skip the secrets scan entirely | `overrides_used: ["skip-secrets"]` |
| `--keep-logs` | Keep `.draft/logs/` instead of collapsing it | `overrides_used: ["keep-logs"]` |
| `--keep-copies` | Keep `.draft/` files identical to their promoted sibling | `overrides_used: ["keep-copies"]` |
| `--force <reason>` | Archive an incomplete story. **The reason is required** — omitting it is exit 2 | `overrides_used: ["force"]` + `forced_reason: "<reason>"` |
| `--help`, `-h` | Usage on stdout, exit 0 | — |

**Never add a flag on the engine's own initiative.** Every flag is a user decision and every one is recorded permanently in the manifest entry; an override the engine chose for itself is an override nobody agreed to. A blocked archive is reported, not retried with the guard turned off.

### Output and exit codes

**One JSON object on stdout, every diagnostic on stderr** — so stdout pipes straight into `jq`. Keys: `story`, `path`, `status`, `moved`, `reason`, `tasks{total, closed, deferred, open}`, `pruned{logs_kb, copies_removed}`, `guard{violations[]}`, `secrets{}`, `index`, `overrides_used[]`, `manifest_entry{}`.

| Exit | `status` | Meaning |
|---|---|---|
| 0 | `archived` | The move completed |
| 1 | `blocked` | A guard hit — **nothing was moved** |
| 1 | `refused` | Preflight said no (already archived, incomplete without `--force`, not a story directory) — **nothing was moved** |
| 2 | — | Invalid input, and **no JSON is printed at all**: stderr only |

`index` reads `ok`, `regen-failed` or `skipped`. `regen-failed` is a warning, never a failure — the index is a *rendering* of the move (see [validate-mode.md](validate-mode.md#index-refresh)), so the archive stands and the next refresh retries. `skipped` means the run never reached that step, which is the normal value on `blocked` and `refused`.

### Guards — nothing destructive runs until both pass

| Guard | Blocks on | Absent / skipped |
|---|---|---|
| **Weight and binary** (always on) | any file >10 MB, or any non-text file (NUL bytes) | `--allow-heavy` overrides, and the override is recorded |
| **Secrets** (`gitleaks`, when installed) | any finding — reports the count and the report path | Scanner **absent** → proceed with a note (`secrets.scanned: false`, `secrets.skipped` says why). Scanner **ran and failed** → block: a scan that errored proved nothing. `--skip-secrets` skips it, recorded |

`guard.violations[]` holds **objects**, not sentences: `{file, size, reason}` per offender, with `size: null` when it could not be established — a size that was never measured must not read as a measurement that came back zero. `secrets{}` keeps one uniform shape on every path (`scanner`, `scanned`, `findings`, `unscanned_files`, `report`, `skipped`, `error`, `allowlist_root`), because "scanned and clean" and "nobody looked" must never be indistinguishable in a permanent record. `allowlist_root` names the project root the scan was anchored to, and is `null` when none was — on `--skip-secrets`, when no scanner ran, and on the fallback below. Branch on its **value**, never on the key being present: `jq -r` renders an absent key and a null key identically.

**The repository's `.gitleaksignore` is part of the guard's configuration, and the guard now names it.** The scan is anchored at the project root — git's top level, or the nearest directory owning `.epic/` when the project is not a git repository — and the story is passed relative to it, so every fingerprint gitleaks emits is project-root-relative and a committed allowlist entry can match it. The allowlist is located from that same root and passed explicitly, rather than inherited from wherever the caller happened to be standing.

So `secrets.scanned: true, findings: 0` still means *"the scanner found nothing it was configured to report"*, not *"there is nothing there"* — and `allowlist_root` is how you find the file that did the configuring. Review it like configuration, because it is: an entry there suppresses one `file:rule:line` and nothing else, but it suppresses it on every future run.

**When `allowlist_root` is `null` on a scan that ran, no allowlist could apply.** The root did not resolve, or resolved to a directory that does not contain the story — an inherited `GIT_WORK_TREE` does that. The scan still covers the whole story and reports every finding; it simply emits absolute fingerprints, which no committed allowlist can match. That direction is safe (it reports more, never less), but a classified fixture will be reported again, so it is stated rather than left to be discovered.

### Pruning (after the guards, before the move)

- `.draft/logs/` collapses into a single `.draft/logs-summary.md`; the freed size lands in `pruned.logs_kb`. Override: `--keep-logs`.
- `.draft/` files **byte-identical** to their promoted sibling are removed; the count lands in `pruned.copies_removed`. Override: `--keep-copies`.

Both are default-on because archived evidence is kept forever: the corpus archived 55 MB of run logs and several exact duplicates of files that were already promoted next to them.

**The summary is written after the secrets scan, so it is never scanned.** Pruning runs at step 4 and the scan at step 3, so `.draft/logs-summary.md` — which carries `tail -40` of the newest log — enters `.epic/archive/` without any guard having read it. This is deliberate (blocking would put a verdict after a destructive step, and every byte of that tail was already in the story when the scanner read it) and every generated summary states its own coverage in a `secrets_scan:` line. But on the three paths where nothing scanned the source either — `--skip-secrets`, no `gitleaks` installed, or a log above the scanner's 15,000,000-byte limit, which it skips *without reporting the skip* — that tail reaches the archive unread. The real defences are upstream: run the scan, and keep credentials out of logs.

### The manifest entry — derived, never declared

`.epic/archive/manifest.yaml` is created on first use with a comment header carrying the never-recycle policy, then appended to — one entry per archived story, written by this script only. Every field is derived from the story's own artifacts at move time:

```yaml
archived:
  - story: "003-payment-webhooks"
    number: "003"
    slug: "payment-webhooks"
    type: "feature"
    scale: "standard"
    status: "validated"
    tasks_total: 7
    tasks_closed: 5
    tasks_deferred: 2
    tasks_open: 0
    deferred_items:
      - "2.1 — Register the production callback URL (deferred: needs the provider's live account)"
      - "2.2 — Verify the first live event (deferred: needs a real payment in production)"
    archived_at: "2026-08-05T14:43:19-03:00"
    pruned:
      logs_kb: 15
      copies_removed: 1
    overrides_used: []
```

- `status` is the story's frontmatter value, not a verdict — a forced archive records `in-progress` and the open count beside it.
- `tasks_*` partition the census: `closed + deferred + open == total`, where `deferred` is **every** `[~]` box whatever its qualifier. That is deliberately not this mode's Progress aggregation (which folds terminal `[~]` into `closed`) — one grammar, one aggregation per consumer, and the manifest's job is three disjoint numbers.
- `deferred_items[]` records one `N.N — title (qualifier: reason)` line per `[~]`. A count alone tells a future reader nothing about what is still owed.
- `forced_reason` appears only when `--force` was used.
- The same object is echoed in the report's `manifest_entry` key, rendered from the very scalars written to the file, so stdout and the file cannot drift.

**Numbers are NEVER recycled.** A new story always takes the next highest number, even when a lower one now exists only in this file — once a story leaves `stories/`, the manifest is the only place that still knows the number was used.

### After the move

The script sets `status: archived` in the moved artifacts' frontmatter and regenerates the managed index block as its final step, so the story's row retargets into `.epic/archive/` automatically ([validate-mode.md](validate-mode.md#index-refresh)). Everything under `.epic/archive/` is read-only for the `Edit` and `Write` tools — `scripts/hook-archive-guard.sh` blocks them — and this script is the one sanctioned path in.
