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
> Story directory: [path to .epic/stories/NNN-slug]
> Completed tasks: [list of tasks marked `[x]`]
> Closed without work: [list of tasks marked `[~]`, each with its qualifier — these have nothing to run]
> Project root: [path]
>
> For each completed task and sub-task:
> 1. Run the Validation command specified in the sub-task
> 2. If a Tests field exists, verify the test file exists and tests pass
> 3. If a Commit sub-task exists, verify the commit was made (check git log)
>
> Then settle the Quality Gates: for each gate in the Quality Gates section, decide from the task results whether it is satisfied, and record it PASS or FAIL with its evidence.
>
> Then, as the LAST step before composing any textual summary, write the whole verdict to `.draft/validation-report.yaml` in the story directory, creating `.draft/` on demand — fast and spike stories have none. The orchestrator concludes from that file, not from your reply:
>
> ```yaml
> story: "NNN-slug"                       # the story directory name
> generated_at: "2026-08-17T14:03:11Z"    # UTC, ISO 8601
> verdict: pass                           # pass | fail — fail when any result is FAIL
> results:
>   - task: "1.1"
>     result: PASS                        # PASS | FAIL | SKIP
>     qualifier: null                     # on a SKIP from a [~] box: deferred | waived | n-a | superseded-by
>     detail: "bats tests/foo.bats — 12 tests, 0 failures"
>   - task: "2.1"
>     result: SKIP
>     qualifier: deferred
>     detail: "closed without the work — needs the provider's live account"
> gates:
>   - gate: "All task validations pass"
>     result: PASS                        # PASS | FAIL
>     evidence: "no FAIL in results[]"
> ```
>
> One results[] entry per sub-task you were given, `[x]` and `[~]` alike, and one gates[] entry per Quality Gate. A SKIP never fails the run.
>
> Only then summarize in prose:
> - PASS: task N.N — validation succeeded
> - FAIL: task N.N — [what failed and why]
> - SKIP: task N.N — nothing to run (a Commit sub-task with no prior failures, or a `[~]` box closed without the work being done — name its qualifier)
> - each Quality Gate as PASS or FAIL with evidence
>
> Do NOT modify any other file: that report is your only write, and any other write is a protocol violation — report what is wrong, never fix it."

## Auditor Sub-agent

Triggered after all tasks are complete and Validator has passed. Performs a holistic review comparing what was planned vs what was built.

> "Review the implementation against the story and design artifacts.
>
> Story directory: [path to .epic/stories/NNN-slug]
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
> 10. Red precedence: every sub-task whose `Tests:` field is **not `None`** has both a pre-authored test and an entry in `.draft/red-evidence.yaml` with `failed: true` (or `red_deferred: true` for `E2E`); a missing entry is reported as a finding. Since Red evidence is recorded in Phase 3 and implementation happens in Run, the entry's existence establishes precedence by construction. Quantify over the `Tests:` field, never over the set of authored tests — a sub-task added by a refinement after Phase 3 ran has no authored test, so "every sub-task with a pre-authored test" excludes the very sub-task that is broken. Report a non-`None` `Tests:` field with no authored test as its own finding.
>
> Then, as the LAST step before composing any textual summary, write the whole audit to `.draft/audit-report.yaml` in the story directory, creating `.draft/` on demand — fast and spike stories have none. The orchestrator concludes from that file, not from your reply; the head is the Validator's, key for key, so one reader parses both:
>
> ```yaml
> story: "NNN-slug"                       # the story directory name
> generated_at: "2026-08-17T14:03:11Z"    # UTC, ISO 8601
> verdict: pass                           # pass | fail — see below
> gaps:
>   - requirement: "R2.3"                 # requirement number, component name or file path
>     detail: "no recovery path when the report is unparseable"
> unmet_gates:
>   - gate: "All tests written and passing"
>     evidence: "tests/foo.bats — 2 failures"
> deviations_reviewed:
>   - deviation: "2.1 — parser inlined instead of extracted"
>     accurate: false                     # is the deviation's stated impact accurate?
>     detail: "claims no callers; src/cli.ts calls it"
> scope_creep:
>   - item: "retry/backoff added to the HTTP client"
>     detail: "not in story.md, not confirmed during clarify"
> missing_red:
>   - task: "2.2"
>     kind: no-entry                      # a pre-authored test with no entry in .draft/red-evidence.yaml
>   - task: "3.1"
>     kind: no-test                       # a non-`None` Tests: field with no authored test at all
> findings:
>   - severity: issue                     # info | warning | issue
>     check: "Dead code"                  # the checklist item it came from
>     location: "src/db/pool.ts:88"
>     detail: "import left behind by the refactor"
> ```
>
> Every array is present even when empty (`gaps: []`) — only the empty one says checked and clean. `verdict` is `fail` when any gap, unmet gate, inaccurate deviation, scope-creep item, `missing_red` entry or `issue`-severity finding exists, and `pass` otherwise. `missing_red`'s `kind` keeps the two absences apart: `no-entry` for a pre-authored test with no Red evidence, `no-test` for a non-`None` `Tests:` field with no test at all.
>
> Only then summarize in prose:
> - List of gaps found (cite requirement numbers, component names, file paths)
> - List of quality gates not met
> - List of unverified or inaccurate deviations (if any)
> - List of scope creep items (if any)
> - List of sub-tasks with a pre-authored test missing a Red-evidence entry in `.draft/red-evidence.yaml` (if any)
> - List of sub-tasks whose `Tests:` field is not `None` but which have no pre-authored test at all (if any) — the refine-added case, reported separately
> - 'All checks passed' if clean
>
> Do NOT modify any other file: that report is your only write, and any other write is a protocol violation — report what is wrong, never fix it. Your memory directory is not a second path in the code under audit — it is your own store, governed by the Memory section of your agent definition."

## Validate Mode Procedure

1. Resolve story directory from NNN
2. Read tasks.md and take the checkbox census. A story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Only `[x]` sub-tasks have an implementation to validate — see [tasks.md](tasks.md#completion)
3. Delete the stale `.draft/validation-report.yaml`, then spawn the Validator sub-agent — it runs each task's validation command and tests, and writes that file as its last step. Take the verdict from the file
4. If `.draft/validation-report.yaml` reads `verdict: pass`, delete the stale `.draft/audit-report.yaml`, then spawn the Auditor sub-agent — compares code against story + design, reviews the deviation register — and take its verdict from that file the same way. On `verdict: fail` the Auditor is not spawned
5. Present the combined results to the user, composed from the two files: the Validator's `results[]` and `gates[]`, the Auditor's `gaps[]`, `unmet_gates[]`, `deviations_reviewed[]`, `scope_creep[]`, `missing_red[]` and `findings[]`
6. If gaps found, offer to create new tasks to address them
7. Apply the status transition for this verdict — see Status Transition (`validated`)
8. On a passing verdict, surface **at most one** integration warning when it applies — run `story-git-status.sh` once, then either report its `anchored_commits == 0` sentence or pipe the same JSON into `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --validate <NNN>`, which writes the sentence or nothing — then offer the archive and refresh the index. See Ordering at the pass point, then Integration Warning (and its precedence table), Archive Offer and Index Refresh

### The verdict is the file; the reply is a courtesy (R2.1)

Both agents write their report as the **last** step of their protocol, before composing any prose ([validator.md](../agents/validator.md), [auditor.md](../agents/auditor.md)), and steps 3-5 conclude from those two files. The final message is a convenience for the human reading along and **the source of no pass/fail decision** — an agent that ends on an intermediate line swallows its own reply, and the verdict is on disk regardless. That failure is measured, not hypothetical: before the files existed it cost a `SendMessage` round, or a respawn that re-ran the entire suite.

**Read `verdict`; never re-derive it.** Each agent computes its own by its own rule — a SKIP never fails the Validator, and `info` and `warning` findings never fail the Auditor — so a second derivation here is a second rule, and two rules disagree on the first story that tells them apart. The arrays are what step 5 presents and step 6 turns into tasks, never what the pass/fail is computed from.

### Before each spawn, delete that agent's stale report file (R2.2)

Step 3 removes `.draft/validation-report.yaml` and step 4 removes `.draft/audit-report.yaml`, each immediately before spawning the agent that owns it. Once an agent fails to write, a leftover from a prior run is indistinguishable from a fresh verdict — and *does the file exist* is exactly the test the next step performs, so without the delete the flow reads last week's `pass` as this run's.

**That agent's file only, never both at once.** The Validator runs first and the Auditor only on its pass, so a single wipe at step 3 would destroy the Validator verdict steps 5, 7 and 8 still need. Pairing each delete with its spawn also settles the file the run never touches: a report is read only by the step that spawned its agent, so on a Validator `fail` the Auditor's file is neither refreshed nor consulted.

**Deleting what is not there is a no-op, never an error, and never a reason to skip the spawn.** A fast or spike story has no `.draft/` at all — both agents create it on demand — so a missing file and a missing directory are the ordinary first-run state.

### Absent or unparseable: one re-request, then the run is failed (R2.3)

Apply the first row that matches, once the agent returns:

| # | The report file | Then |
|---|---|---|
| 1 | Present and parses | read `verdict` and carry on — the ordinary case |
| 2 | Absent, empty, truncated, or not parseable as YAML | **one** `SendMessage` to the **same agent**, asking it to write its report file now |
| 3 | Still absent or still unparseable after that one request | **the run is failed** — report it in those terms and stop |

**One request, to the agent that already did the work**, because it still holds the context that produced the verdict: re-emitting the file costs a message rather than a validation suite.

**Never respawn silently.** A respawn re-runs every command and every test — precisely the cost the file exists to save — and a second agent that also ends on an intermediate line leaves the flow looping over one failure. Running validate again is the user's call, made with the failure in view.

**Never infer a verdict from prose.** Whatever the agent did say — including a summary that reads like a clean pass — is not a verdict, and R2.1 has no exception for the case where the file is missing: a verdict assembled from chat is the unverifiable claim the file was introduced to replace.

A failed run **writes no status and makes no offer** — rule 3 below, reached as any failure reaches it.

## Status Transition (`validated`)

Validate mode owns exactly one of the six `status:` values — `validated` — and writes it at exactly one point: a passing verdict. It never writes any of the other five; those belong to CREATE, RUN, the supersede operation and the archive operation. See [SKILL.md](../skills/epic/SKILL.md#lifecycle-status-status) for the full field spec.

**The write mechanism is defined once**, in [run-mode.md](run-mode.md#status-transitions) — `Edit` on the frontmatter line and never `Write`, the same value in every artifact that carries frontmatter, the `Edit` adding the field on a legacy story that never had one. Validate mode reuses it unchanged; restating it here is exactly how the two copies would drift apart. A failed write is reported and the flow continues: `status:` is advisory metadata and must never change, delay or block the verdict it is recording.

**The verdict read here is the files' (R2.4).** Rules 1-3 turn on the `verdict` field of `.draft/validation-report.yaml` and `.draft/audit-report.yaml` — never on what an agent said in chat, and never on a re-derivation from their arrays (see The verdict is the file, above). Apply the first rule that matches:

| # | The verdict | Then |
|---|---|---|
| 1 | Both files read `verdict: pass`, and no `[ ]` remains | write `validated` (nothing to do if the field already reads `validated`) |
| 2 | Both files read `verdict: pass`, and at least one `[ ]` remains | write nothing — report the pass and state why the status was not advanced |
| 3 | Either file reads `verdict: fail`, or no verdict was readable at all | write nothing — leave `status:` exactly as it was |

**Rule 2 — a partial validation must not manufacture the lie.** `/epic:epic stories validate NNN` can be invoked at any time, including on a story that still has open `[ ]` boxes: the Validator simply has fewer `[x]` sub-tasks to run, and it can still pass. Writing `validated` there would immediately trip `validate-story.sh`'s ahead-of-checkboxes warning — `done` or `validated` while a `[ ]` remains (R2.3) — so the engine would have written the exact claim that check exists to expose. Report the pass instead, and say why the status stayed where it is: **`validated` means "the finished story was verified", not "the part that exists so far looks fine".** When the remaining boxes close, Run mode writes its own transition, and the next passing verdict earns `validated`.

**Rule 3 — a failing verdict writes nothing at all.** Not `in-progress`, and not a rollback of a `validated` left by an earlier pass. A failure is a report, not a lifecycle transition; the story keeps whatever state its last real transition recorded. A run failed for want of a readable report lands here too: an unknown verdict is not a passing one.

**`in-progress → validated`, skipping `done`.** A story whose only non-`[x]` boxes are `[~] (deferred: …)` never receives `done`: Run mode writes `done` only when no `[ ]` **and** no deferred `[~]` remains, so such a story stays `in-progress` (see [run-mode.md](run-mode.md#status-transitions)). Nothing blocks it from being validated. Rule 1 asks for no `[ ]`, and a deferred box is closed, not open — the same reading `validate-story.sh` applies, whose ahead-of-checkboxes check counts `[ ]` only, so `validated` on a `done-except-external` story raises no warning. Such a story therefore runs `in-progress → validated`, skipping `done` entirely.

**design.md's state diagram does not draw that edge** — it shows only `done --> validated`. The edge falls out of the acceptance criteria all the same: R1.3 withholds `done` while a deferred box remains, R1.4 grants `validated` on a passing verdict. It is written down here rather than left implicit because an undocumented edge in a state machine is how the next maintainer gets it wrong.

**Ordering at the pass point.** Four things happen on a passing verdict, in this fixed order.

| # | Step | Owner | Why here |
|---|---|---|---|
| 1 | Integration warning — validation passed but the story's work is not integrated into the main branch, or carries no anchor for the detection to find | Integration Warning, below | The caveat reaches the user before anything acts on the verdict |
| 2 | The status write above (`validated`) | this section | — |
| 3 | Archive offer, gated on a status of `done` or `validated` | Archive Offer, below | Its gate is true only once step 2 has written the value — which is why the gate reads `done` or `validated`, and not `done` alone |
| 4 | Index refresh — regenerate the managed block in `.epic/EPIC.md` | Index Refresh, below | It renders what steps 2 and 3 changed: the new status, and the story's new location when the archive was accepted |

This section fixes the order and the reason for it — each step's behavior is defined where its Owner column points.

**The chain is `verdict` → `status:` → offer, and every link is a file.** Rules 1-3 read the two reports' `verdict`, step 2 writes the status they decide, step 3's gate reads that status back, and step 4 renders what steps 2 and 3 changed. No link in it consults an agent's chat message.

## Integration Warning

Step 1 of the pass point. A passing verdict says the work is finished; whether it ever reached the main branch is a fact the checkboxes cannot see — the corpus's worst case was a project with every story checkbox-complete and zero merges. The detection is the same live evaluation LIST annotates from, defined in [list-mode.md](list-mode.md#integration-annotation): computed live, stored nowhere, blocking nothing.

**The warning is rendered by the same script LIST annotates from** — [`scripts/render-integration.sh`](../scripts/render-integration.sh), asked for a different rendering of the same JSON — so the sentence the user reads is the sentence the test suite pins. On a passing verdict, pipe the detector into its `--validate` mode and append whatever comes back to the presented results:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/story-git-status.sh" <story-dir> \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --validate <NNN>
```

`<NNN>` is the story number **as the reader knows it** and is interpolated verbatim — pass `006`, not `6`. What the script writes, per the `integrated` field of the detector's JSON (`{story, main_branch, integrated, evidence, anchored_commits, checked_at}`), **documents its three arms rather than prescribing a rendering to perform by hand**:

| `integrated` | The script writes |
|---|---|
| `false` | the warning below, appended to the presented results |
| `true` | nothing — the work is on the main branch |
| `null` | nothing at all — no main branch is resolvable, so the fact is unknowable (R1.4) |

Exit 2 from the detector — not a git repository, or story not found — also emits nothing at all: nothing reaches the pipe and `--validate` degrades silently, the same rule LIST applies (R1.4). "Not computable" must never dress up as a finding, and a failed detection must never delay, dirty or block the verdict it decorates.

The sentence, spelled once in the script and reproduced here verbatim, with `<main>` filled from the JSON's `main_branch` and `NNN` the number passed on the command line:

```
story is done but no evidence of integration to <main> (no merged feat/NNN-* branch, no (NNN) commit)
```

`<main>` is read out of the report and never assumed: the detector resolves the default branch through four ordered candidates and it is regularly not named `main`, so a hard-coded name would print a branch the reader does not have. The sentence names the two evidence kinds the detection looked for and found missing — a merged `feat/NNN-*` branch (`branch-merged`) and a commit subject reachable from main carrying the `(NNN)` token (`message-ref`). Either alone would have flipped `integrated` to `true`.

**A warning, never a verdict (R2.2).** Appending it changes nothing else: not the pass, not step 2's status write, not step 3's offer, not the validation's exit semantics. The script holds its half by construction: **every rendering path exits 0**, warning or no warning, so there is no exit status to read and nothing here to branch on — a caller that checked `$?` would turn the warning into the verdict R2.2 forbids. The one non-zero exit that is not the cost decision (`--should-annotate`, see [list-mode.md](list-mode.md#integration-annotation)) is exit 2, an unknown or missing mode: a caller error, unreachable from a well-formed call.

**When to ask is this mode's half, and the script cannot check it.** The warning's first three words are a precondition — "story is done" is true only on a passing verdict with no `[ ]` left — and the renderer renders whatever JSON it is handed. Rule 2's partial pass must therefore not call it at all: there the sentence would manufacture the very claim rule 2 exists to refuse.

**It never gates the archive (R2.3).** `archive-story.sh`'s preflight does not consult integration state — an un-integrated story archives exactly like an integrated one. Whether a warned story needs a merge, a cherry-pick or nothing at all is the user's decision; the warning informs that decision and blocks nothing.

### The anchor warning, and which of the two fires (R4.2)

The detector answers **two nested questions**, and step 1 surfaces **at most one** of them. `integrated` asks *did this story's work reach the main branch*. `anchored_commits` — the number of commit subjects reachable from **HEAD** carrying this story's number as a delimited token, by the same `(NNN)` / `NNN-slug` rules the `message-ref` evidence kind applies (R4.3) — asks the question underneath it: *is the work findable at all*. Zero means this story's commits carry nothing that any detector can attribute back to it, on the main branch or anywhere else.

**Counted from HEAD, not from the main branch**, and that is what keeps the two questions apart: a just-validated story normally still sits on its own unmerged branch, so a main-relative count would read zero for every correctly anchored story awaiting its merge — the state the integration warning above already covers.

Same precondition as that warning — a passing verdict with no `[ ]` left, so `status:` reads `done` or `validated` (R4.2) — and the same severity. **A warning, never a verdict.** It is non-blocking and changes nothing else: not the pass, not step 2's status write, not step 3's offer, not the archive. The sentence, with `NNN` the story number as the reader knows it:

```
this story's commits carry no (NNN) anchor — integration detection cannot see them
```

**Run the detector once and decide from its JSON.** The count and `integrated` come out of the same object, so the pipe shown above becomes a second use of that object rather than a second detection — two runs could disagree, and the detector is the expensive half:

```
status_json=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/story-git-status.sh" <story-dir>) || status_json=""
# then, only when the table below says so:
printf '%s\n' "$status_json" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-integration.sh" --validate <NNN>
```

**Precedence — apply the first rule that matches.** Left to themselves the two warnings double-fire on one story: a story with no anchored commits has no `message-ref` evidence either, so `integrated` is usually `false` for the very same underlying fact, and the user reads two sentences about one problem.

| # | The detector's JSON | Step 1 surfaces |
|---|---|---|
| 1 | `integrated: null` — or nothing on the pipe at all, the detector's exit 2 | nothing whatsoever, whatever the count says |
| 2 | `anchored_commits == 0` | the anchor sentence above, and the `--validate` render is **not** run |
| 3 | `integrated` reads `false` | the integration sentence, from the render above |
| 4 | anything else — `integrated` reads `true` | nothing; the work reached the main branch |

`anchored_commits == 0` **wins** over rule 3 because it is the more specific finding: there is nothing for the detection to see at all, and "merge your branch" is the wrong instruction for a story whose commits carry no anchor to find. The integration warning therefore fires **only when** the story has anchored commits and none of them reached the main branch — the case it was written for.

`integrated: null` silences both, and it is first for that reason. No main branch resolved, so nothing was measured, and *"not computable" must never dress up as a finding* — the rule stated verbatim one field over, applied here to the pair rather than to one of them. `anchored_commits` can be `null` on the same principle, when the count itself was not computable (a repository with no commits at all): it is not `0`, so rule 2 does not match and the count simply adds nothing to a decision rules 3 and 4 already made without it. That combination is close to unreachable in practice — a repository with no commits resolves no main branch either, so rule 1 catches it first — and it is written down because a silence that depends on being unreachable is a silence nobody can check.

## Archive Offer

Step 3 of the pass point, and **the single definition of the offer**. Run mode makes the same offer at its own trigger and reuses this section unchanged (see [run-mode.md](run-mode.md#end-of-run--validator-archive-index)); a second copy of a prompt that spends guards is how one of the copies ends up spending them differently.

**Why here.** Archiving is Epic's most-skipped step — absent in 20 of 26 real projects — and the one archive that happened organically happened exactly here, glued to a passing validate. Offering it anywhere else asks the user to remember; offering it here asks them to confirm.

### Gate

Offer when **both** hold:

1. Both report files read `verdict: pass` **and no `[ ]` remains** — rule 1 of the status table above.
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
