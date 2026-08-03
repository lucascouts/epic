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

**Ordering at the pass point.** Three things happen on a passing verdict, in this fixed order. Only step 2 exists today — steps 1 and 3 are slots, named here so the order is settled before their behavior lands.

| # | Step | Owner | Why here |
|---|---|---|---|
| 1 | Integration warning — validation passed but the story's work is not integrated into the main branch | story 006, **not implemented** | The caveat reaches the user before anything acts on the verdict |
| 2 | The status write above (`validated`) | this section | — |
| 3 | Archive offer, gated on a status of `done` or `validated` | story 005, **not implemented** | Its gate is true only once step 2 has written the value — which is why the gate reads `done` or `validated`, and not `done` alone |

Do not implement steps 1 or 3 here. This section fixes their order and the reason for it; stories 005 and 006 own the behavior.
