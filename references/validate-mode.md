# Validate Mode

Triggered by `/epic:task stories validate NNN`.

## Post-Implementation Personas

These personas are activated **after implementation**, not during story creation. They are optional — activated when the user invokes `/epic:task validate` on a story directory, or when a sub-agent execution flow completes all tasks.

| Persona | Role | When | Sub-agent type |
|---|---|---|---|
| **Validator** | Runs validation commands and tests per completed task | After tasks marked `[x]` | `validator` |
| **Auditor** | Compares implemented code against story + design artifacts | After all tasks complete | `auditor` |

## Validator Sub-agent

Triggered per-task or in batch after implementation. Can be invoked incrementally (after each task) or at the end.

> "Validate the implementation of these completed tasks.
>
> Tasks file: [path to tasks.md]
> Completed tasks: [list of tasks marked [x]]
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
> - SKIP: task N.N — no validation command (e.g., Commit sub-task with no prior failures)
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
>
> Return:
> - List of gaps found (cite requirement numbers, component names, file paths)
> - List of quality gates not met
> - List of unverified or inaccurate deviations (if any)
> - List of scope creep items (if any)
> - 'All checks passed' if clean
>
> Do NOT modify any files. Only report results."

## Validate Mode Procedure

1. Resolve story directory from NNN
2. Read tasks.md and check for completed tasks (`[x]`)
3. Spawn Validator sub-agent — runs validation commands and tests per task
4. If Validator passes, spawn Auditor sub-agent — compares code against story + design, reviews deviation register
5. Present combined results to the user
6. If gaps found, offer to create new tasks to address them
