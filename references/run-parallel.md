# Parallel Execution — RUN

Loaded from [run-mode.md](run-mode.md) when a run has two or more pending tasks
whose dependencies are satisfied. A run that executes one sub-task at a time
never needs this file.

When multiple pending tasks share the same dependency set and all dependencies are **satisfied** ([tasks.md](tasks.md#dependency-satisfaction) — deliberately not the same test as story *completion*), these tasks are **non-blocking** relative to each other.

### Detection

**Run the detection at both levels — parent tasks *and* sibling sub-tasks.** Reading only the parent `Dependencies` field finds parallelism one layer above where the work actually is: what a run executes one at a time is sub-tasks, and a parent whose siblings are all sequential still hides independent sub-tasks inside itself. **Numbering is not dependency.** Sub-tasks 2.1 and 2.2 are written in order because a list has an order; they are dependent only when one of them says so.

1. Build the dependency graph from the `Dependencies` field on parent tasks, **and from the sibling sub-tasks inside each pending parent**. A sub-task depends on a sibling only when it names one (`Task 2.1`) or when its ToDo consumes something the sibling creates — a file, a symbol, a migration. Otherwise the siblings are independent
2. Identify parallel group: items where all deps are **satisfied** ([tasks.md](tasks.md#dependency-satisfaction) — `[x]` or terminal `[~]`; a dep closed as `[~] (deferred: …)` is **not**) and no item in the group depends on another item in the same group
3. Verify no file conflicts: items that modify the same files are NOT parallelized. At sub-task granularity this is the usual disqualifier — siblings edit one file far more often than sibling *tasks* do, and `tasks.md` rule 9 already forbids splitting a task across the same file, which makes the check cheap to run and usually decisive
4. **State the group in the execution plan and go** — "Tasks N, M, P are independent: they depend only on satisfied tasks and touch no common file, so they run in parallel." No question is asked. A group that passed steps 1–3 is proven independent, and asking cost more than it protected: one round of the question budget per run, and every run where nobody said yes — the measured story ran its nine executors in series with the detection looking one layer too high and this gate defaulting to no. `--serial` declines, for the whole run

### Execution

For each parallel group, unless `--serial` was passed:
1. **Create an isolated worktree per task** using the native `EnterWorktree` tool (Claude Code v2.1.105+). Each worktree branches from the current HEAD into `.epic/worktrees/<story>-<task>/` so parallel Executors cannot collide on the same files.
   - **Fallback (< v2.1.105):** spawn each Executor with `isolation: "worktree"` (Agent tool option) or manually create worktrees via `Bash + git worktree add`.
2. Each Executor follows the full 6-step protocol in its isolated worktree — and closes **no** box there: tasks.md is never edited inside a worktree
3. Wait for all Executors to complete
4. Run Tech Reviews for each Executor's output (can be parallel)
5. If ALL pass: merge worktrees **sequentially**, and after each merge close that task's boxes **in the main tree** — one `close-subtask.sh` call per box, in task order, from the merged Executor's closing block (see Closing a Box). When every worktree has been merged and closed, execute the group's `Commit:` field. Call `ExitWorktree` on each worktree after merging to clean up.
6. If ANY fail: report failures, ask user how to proceed (retry failed tasks, skip, or abort). Worktrees of failed executors are preserved for inspection until the user decides. A failed Executor's boxes are **not** closed — `outcome: failed` makes no close call, here as anywhere else

### Rules

- **Boxes are closed only in the main tree, sequentially, after each merge — never inside a worktree copy of tasks.md (R3.3).** A worktree branches from HEAD with its own copy of the file, so a box closed there is closed in a copy the merge then has to reconcile, and two Executors closing at once are two rewrites of one file. Serialising the closes behind the merges — which are already sequential — also makes each returned `census` a census of the file everyone else will read
- A group's `Commit:` field is ALWAYS executed sequentially (post-merge), by the main agent, using the pre-authored message verbatim (R3.4)
- `--serial` runs every group in order with no worktree created — the one way to decline parallel execution, and it applies to the whole run
- Maximum parallel Executors: 5 (to avoid resource exhaustion)
- Each parallel Executor gets the full story context (story.md, design.md relevant sections)
- Deviation register is merged after parallel execution completes (before commit)
- `EnterWorktree` integrates with Claude Code checkpointing — `ExitWorktree` is cancellable and safe to call on already-exited worktrees
