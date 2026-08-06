# Validate Mode

Triggered by `/epic:epic stories validate NNN`.

## Post-Implementation Personas

These personas are activated **after implementation**, not during story creation. They are optional — activated when the user invokes `/epic:epic validate` on a story directory, or when a sub-agent execution flow completes all tasks.

| Persona | Role | When | Sub-agent type |
|---|---|---|---|
| **Validator** | Runs validation commands and tests per completed task | After tasks marked `[x]` | `validator` |
| **Auditor** | Compares implemented code against story + design artifacts | After all tasks complete | `auditor` |

## Validator Sub-agent

Triggered per-task or in batch after implementation. Can be invoked incrementally (after each task) or at the end.

> "Validate the implementation of these completed tasks.
>
> Tasks file: [path to tasks.md]
> Completed tasks: [list of tasks marked `[x]`]
> Closed without work: [list of tasks marked `[~]`, each with its qualifier — these have nothing to run]
> Project root: [path]
>
> For each completed task and sub-task:
> 1. Run the Validation command specified in the sub-task
> 2. If a Tests field exists, verify the test file exists and tests pass
> 3. If a Commit sub-task exists, verify the commit was made (check git log)
>
> Report per sub-task:
> - PASS: task N.N — validation succeeded
> - FAIL: task N.N — [what failed and why]
> - SKIP: task N.N — nothing to run (a Commit sub-task with no prior failures, or a `[~]` box closed without the work being done — name its qualifier)
>
> At the end, check Quality Gates:
> - For each gate in the Quality Gates section, determine if it is satisfied based on task results
> - Report each gate as PASS or FAIL with evidence
>
> Do NOT modify any files. Only report results."

## Auditor Sub-agent

Triggered after all tasks are complete and Validator has passed. Performs a holistic review comparing what was planned vs what was built.

> "Review the implementation against the story and design artifacts.
>
> Files to read:
> - [path to story.md]
> - [path to design.md] (if exists)
> - [path to tasks.md]
> - [path to .draft/deviations.yaml] (if exists)
>
> Check:
> 1. Every requirement in story.md is implemented (trace to actual code, not just task checkboxes)
> 2. Every component in design.md exists in the codebase with the specified interfaces
> 3. Error handling strategy in design.md is followed in the actual handlers/controllers
> 4. Security considerations in design.md are addressed in the implementation
> 5. Testing strategy levels in design.md all have corresponding test files
> 6. Quality gates in tasks.md are all satisfied
> 7. No scope creep — nothing implemented that wasn't in the story or confirmed during clarify
> 8. If deviations.yaml exists: for each deviation, verify the stated impact is accurate and no downstream breakage occurred. For each deviation marked with limited impact, check actual callers of the deviated component to confirm.
> 9. If deviations.yaml has discoveries: verify each discovery was addressed in subsequent tasks (e.g., if a template engine gotcha was found, check that later tasks using templates account for it)
> 10. Red precedence: every sub-task with a pre-authored test has an entry in `.draft/red-evidence.yaml` with `failed: true`; a missing entry is reported as a finding. Since Red evidence is recorded in Phase 3 and implementation happens in Run, the entry's existence establishes precedence by construction.
>
> Return:
> - List of gaps found (cite requirement numbers, component names, file paths)
> - List of quality gates not met
> - List of unverified or inaccurate deviations (if any)
> - List of scope creep items (if any)
> - List of sub-tasks with a pre-authored test missing a Red-evidence entry in `.draft/red-evidence.yaml` (if any)
> - 'All checks passed' if clean
>
> Do NOT modify any files. Only report results."

## Validate Mode Procedure

1. Resolve story directory from NNN
2. Read tasks.md and take the checkbox census. A story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Only `[x]` sub-tasks have an implementation to validate — see [tasks.md](tasks.md#completion)
3. Spawn Validator sub-agent — runs validation commands and tests per task
4. If Validator passes, spawn Auditor sub-agent — compares code against story + design, reviews deviation register
5. Present combined results to the user
6. If gaps found, offer to create new tasks to address them
7. Apply the status transition for this verdict — see Status Transition (`validated`)
8. On a passing verdict, surface the integration warning when it applies, offer the archive and refresh the index — see Ordering at the pass point, then Integration Warning, Archive Offer and Index Refresh

## Status Transition (`validated`)

Validate mode owns exactly one of the six `status:` values — `validated` — and writes it at exactly one point: a passing verdict. It never writes any of the other five; those belong to CREATE, RUN, the supersede operation and the archive operation. See [SKILL.md](../skills/epic/SKILL.md#lifecycle-status-status) for the full field spec.

**The write mechanism is defined once**, in [run-mode.md](run-mode.md#status-transitions) — `Edit` on the frontmatter line and never `Write`, the same value in every artifact that carries frontmatter, the `Edit` adding the field on a legacy story that never had one. Validate mode reuses it unchanged; restating it here is exactly how the two copies would drift apart. A failed write is reported and the flow continues: `status:` is advisory metadata and must never change, delay or block the verdict it is recording.

Apply the first rule that matches:

| # | The verdict | Then |
|---|---|---|
| 1 | Validator **and** Auditor pass, and no `[ ]` remains | write `validated` (nothing to do if the field already reads `validated`) |
| 2 | Validator **and** Auditor pass, and at least one `[ ]` remains | write nothing — report the pass and state why the status was not advanced |
| 3 | Either sub-agent fails | write nothing — leave `status:` exactly as it was |

**Rule 2 — a partial validation must not manufacture the lie.** `/epic:epic stories validate NNN` can be invoked at any time, including on a story that still has open `[ ]` boxes: the Validator simply has fewer `[x]` sub-tasks to run, and it can still pass. Writing `validated` there would immediately trip `validate-story.sh`'s ahead-of-checkboxes warning — `done` or `validated` while a `[ ]` remains (R2.3) — so the engine would have written the exact claim that check exists to expose. Report the pass instead, and say why the status stayed where it is: **`validated` means "the finished story was verified", not "the part that exists so far looks fine".** When the remaining boxes close, Run mode writes its own transition, and the next passing verdict earns `validated`.

**Rule 3 — a failing verdict writes nothing at all.** Not `in-progress`, and not a rollback of a `validated` left by an earlier pass. A failure is a report, not a lifecycle transition; the story keeps whatever state its last real transition recorded.

**`in-progress → validated`, skipping `done`.** A story whose only non-`[x]` boxes are `[~] (deferred: …)` never receives `done`: Run mode writes `done` only when no `[ ]` **and** no deferred `[~]` remains, so such a story stays `in-progress` (see [run-mode.md](run-mode.md#status-transitions)). Nothing blocks it from being validated. Rule 1 asks for no `[ ]`, and a deferred box is closed, not open — the same reading `validate-story.sh` applies, whose ahead-of-checkboxes check counts `[ ]` only, so `validated` on a `done-except-external` story raises no warning. Such a story therefore runs `in-progress → validated`, skipping `done` entirely.

**design.md's state diagram does not draw that edge** — it shows only `done --> validated`. The edge falls out of the acceptance criteria all the same: R1.3 withholds `done` while a deferred box remains, R1.4 grants `validated` on a passing verdict. It is written down here rather than left implicit because an undocumented edge in a state machine is how the next maintainer gets it wrong.

**Ordering at the pass point.** Four things happen on a passing verdict, in this fixed order.

| # | Step | Owner | Why here |
|---|---|---|---|
| 1 | Integration warning — validation passed but the story's work is not integrated into the main branch | Integration Warning, below | The caveat reaches the user before anything acts on the verdict |
| 2 | The status write above (`validated`) | this section | — |
| 3 | Archive offer, gated on a status of `done` or `validated` | Archive Offer, below | Its gate is true only once step 2 has written the value — which is why the gate reads `done` or `validated`, and not `done` alone |
| 4 | Index refresh — regenerate the managed block in `.epic/EPIC.md` | Index Refresh, below | It renders what steps 2 and 3 changed: the new status, and the story's new location when the archive was accepted |

This section fixes the order and the reason for it — each step's behavior is defined where its Owner column points.

## Integration Warning

Step 1 of the pass point. A passing verdict says the work is finished; whether it ever reached the main branch is a fact the checkboxes cannot see — the corpus's worst case was a project with every story checkbox-complete and zero merges. The detection is the same live evaluation LIST annotates from, defined in [list-mode.md](list-mode.md#integration-annotation): computed live, stored nowhere, blocking nothing.

On a passing verdict, run the detection for the validated story and read the `integrated` field of its JSON output (`{story, main_branch, integrated, evidence, checked_at}`):

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/story-git-status.sh" <story-dir>
```

| `integrated` | Then |
|---|---|
| `false` | Append the warning below to the presented results |
| `true` | Nothing — the work is on the main branch |
| `null` | Nothing at all — no main branch is resolvable, so the fact is unknowable (R1.4) |

Exit 2 — not a git repository, or story not found — also emits nothing at all: degrade silently, the same rule LIST applies (R1.4). "Not computable" must never dress up as a finding, and a failed detection must never delay, dirty or block the verdict it decorates.

The warning, with `<main>` filled from the JSON's `main_branch` and `NNN` with the story's number:

```
story is done but no evidence of integration to <main> (no merged feat/NNN-* branch, no (NNN) commit)
```

It names the two evidence kinds the detection looked for and found missing — a merged `feat/NNN-*` branch (`branch-merged`) and a commit subject reachable from main carrying the `(NNN)` token (`message-ref`). Either alone would have flipped `integrated` to `true`.

**A warning, never a verdict (R2.2).** Appending it changes nothing else: not the pass, not step 2's status write, not step 3's offer, not the validation's exit semantics. And it is emitted only where its first three words are true — on a rule-2 partial pass the story is not done, and "story is done" would be exactly the manufactured claim rule 2 exists to refuse.

**It never gates the archive (R2.3).** `archive-story.sh`'s preflight does not consult integration state — an un-integrated story archives exactly like an integrated one. Whether a warned story needs a merge, a cherry-pick or nothing at all is the user's decision; the warning informs that decision and blocks nothing.

## Archive Offer

Step 3 of the pass point, and **the single definition of the offer**. Run mode makes the same offer at its own trigger and reuses this section unchanged (see [run-mode.md](run-mode.md#end-of-run--validator-archive-index)); a second copy of a prompt that spends guards is how one of the copies ends up spending them differently.

**Why here.** Archiving is Epic's most-skipped step — absent in 20 of 26 real projects — and the one archive that happened organically happened exactly here, glued to a passing validate. Offering it anywhere else asks the user to remember; offering it here asks them to confirm.

### Gate

Offer when **both** hold:

1. The verdict is a pass **and no `[ ]` remains** — rule 1 of the status table above.
2. `status:` reads **`done` or `validated`** after step 2.

The field can still read `done` at this point even though rule 1 writes `validated`: a failed status write is reported and the flow continues, and an advisory write that failed must not also cost the user the offer. That is the whole reason the gate reads `done` **or** `validated`.

**A partial pass never offers.** Rule 2 — a pass with at least one `[ ]` still open — writes no status and makes no offer, whatever the field already says. `archive-story.sh` would not stop it either: its completion check is an **OR** (frontmatter `status` of `done`/`validated`/`superseded` **or** no `[ ]` remaining), so a story left reading `validated` by an earlier pass satisfies preflight with an open box still in the file. The gate is therefore ours to hold. The offer means *this story is finished*, and proposing the archive over open work is the archive-with-a-false-stamp this story exists to end.

### The prompt

```
Archive story NNN? [y/n]
```

When the census shows deferred boxes — the computed condition `done-except-external`, defined once in [tasks.md](tasks.md#completion) — list them under the question, so the user accepts with the outstanding work in view:

```
Archive story 003? [y/n]
  Still owed by an external actor (2 deferred):
    - 2.1 — Register the production callback URL (deferred: needs the provider's live account)
    - 2.2 — Verify the first live event (deferred: needs a real payment in production)
```

Render each line as `N.N — title (qualifier: reason)` — the exact shape `archive-story.sh` derives into the manifest entry's `deferred_items[]`, so what the offer shows is what the archive will record.

**The items are shown, never passed.** On acceptance the offer hands the script **no** item list and no counts: `archive-story.sh` derives `deferred_items[]`, `tasks_total`, `tasks_closed` and `tasks_deferred` from the checkboxes itself. Declaring them at the call site would rebuild the hand-declared manifest this story replaced — a manifest that can contradict the boxes it summarizes.

### On `[y]`

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/archive-story.sh" <story-dir>
```

The story number (`005`) works in place of the directory — it resolves against the nearest `.epic/`. Pass **no flags**. `--allow-heavy`, `--skip-secrets`, `--keep-logs`, `--keep-copies` and `--force <reason>` are the user's decisions and each is recorded in the manifest entry as an override: an override the engine chose for itself is an override nobody agreed to. Never re-run a blocked archive with a guard flag on your own initiative — report the verdict and let the user ask for the override by name.

The script prints **one JSON object on stdout**, diagnostics on stderr. Surface the verdict by its `status`:

| Exit | `status` | Surface |
|---|---|---|
| 0 | `archived` | The move is done. Report `path`, `tasks{}`, `pruned{logs_kb, copies_removed}`, `overrides_used[]` when non-empty, and `secrets` — including a `skipped` scan, because a scan that did not happen is part of the verdict. `index: "regen-failed"` is a warning, not a failure: the story is archived and the next refresh retries |
| 1 | `blocked` | A guard stopped it. Report `reason` plus every `guard.violations[]` entry (`file`, `size`, `reason`) and `secrets` (`findings`, `report`) verbatim. **Nothing was moved** |
| 1 | `refused` | Preflight said no — already archived, incomplete without `--force`, not a story directory. Report `reason` verbatim. **Nothing was moved** |
| 2 | — | Invalid input, and **no JSON is printed at all**. Report the stderr message: this is a bad invocation, not a user decision |

**Never swallow a `blocked` or a `refused`.** Report the verdict in full, including the offending files and the findings count. A refusal the user cannot see is indistinguishable from an archive that happened — which is precisely how 20 of 26 projects ended up with no archive and nobody noticing.

### On `[n]`

One line, no argument, no second ask: the story stays in `.epic/stories/`. The offer returns on the next passing verdict, and `/epic:epic stories archive NNN` runs the same script at any time.

### Headless

**Headless / non-interactive session:** do **not** pause and do **not** call `AskUserQuestion`. Emit the offer as a logged note and proceed immediately — the archive is never performed without an accepted offer. The suggestion is informative, never gating, in a headless session. This is the same rule, in the same shape, that [preferred-tooling.md](preferred-tooling.md#no-favorite-available) applies to its install recommendation, and it reads the same session signal: `TaskCreate` present = interactive, per [SKILL.md](../skills/epic/SKILL.md#runtime-dependency-precheck-mandatory-before-standardfull-triage).

The note names the command, so a logged suggestion is still actionable:

```
Archive suggestion: story 003 is validated and complete (2 deferred, still owed
externally). To archive it, run:
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/archive-story.sh" 003
```

## Index Refresh

Step 4 of the pass point, and **the single definition of the completion-time refresh** — Run mode invokes it at the end of a completed run and LIST refreshes it opportunistically, both pointing here.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-index.sh"
```

It regenerates the managed block between the `<!-- epic:index:start -->` / `<!-- epic:index:end -->` markers in `.epic/EPIC.md` and preserves every byte outside them.

**Why it runs last.** It renders state, so it must run after the state changes: after step 2's `status:` write, and after step 3 resolves. An accepted archive moved the directory and `archive-story.sh` already regenerated the block as its own final step — the refresh is then a zero-diff no-op, which is exactly what idempotent buys here. A declined offer leaves only the new status to render.

**A non-zero exit warns and never gates the verdict.** Exit 1 is a failed regeneration (a broken marker pair, an unreadable or unwritable file — the file is left untouched); exit 2 is invalid input. The index is a rendering of the truth, not the truth: a stale rendering is never a reason to hold, delay or reverse a verdict, and the next refresh retries.
