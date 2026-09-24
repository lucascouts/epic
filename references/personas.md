# Personas — the sub-agents and when they are spawned

Loaded before a phase, a run or a validation spawns a sub-agent. Moved out of [SKILL.md](../skills/epic/SKILL.md) so a run that does not need it does not carry it.

## Personas

Sub-agents with specialized roles. Scale determines which personas are activated.

### Planning Personas (story creation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Analyst** | Context discovery, domain research, checklist generation | standard + full | `agents/analyst.md` |
| **Architect** | Codebase pattern research, design context gathering | full only | `agents/architect.md` |
| **Test Advisor** | Authors one failing test per Unit/Integration sub-task during Phase 3, runs Red verification, records red-evidence | standard + full at engineering level `project` or `product` (Phase 3, and per added sub-task in Refine); an `experiment` or `tool` story writes its tests at run time, as Fast does ([engineering-level.md](engineering-level.md)) | `agents/test-advisor.md` |
| **Reviewer** | Cross-artifact review, gap detection, consistency check | full only | `agents/reviewer.md` |

### Execution Personas (task implementation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Executor** | Implements a sub-task following the strict 6-step protocol; step 5 is conditional (Refactor for test-first sub-tasks, Tests for test-after). Ends its report with a machine-liftable **closing block** — sub-task id, outcome (`done` / `close-tilde` + qualifier + reason / `failed`) and the pre-authored commit message it validated against. **Marks no box and runs no `git commit`**: the orchestrator lifts that block into `scripts/close-subtask.sh`, the one writer of the checkbox grammar | all scales (delegated route) | `agents/executor.md` |
| **Tech Reviewer** | Reviews implementation at technology boundaries; holds `Bash` for measurement only (never mutating files or git state), so a finding resting on a runnable check carries the command and its output | all scales (multi-tech tasks) | `agents/tech-reviewer.md` |

### Post-Implementation Personas (validation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Validator** | Runs validation commands and tests per completed task, writing the verdict to `.draft/validation-report.yaml` before any prose summary | all scales | `agents/validator.md` |
| **Auditor** | Compares implemented code against story + design artifacts, writing `.draft/audit-report.yaml` before any prose summary | all scales | `agents/auditor.md` |

The **main agent** (this skill) orchestrates: generates artifacts (story.md, design.md, tasks.md) during planning, delegates to Executors during run-mode, and coordinates Validators/Auditors during validation. The main agent retains conversation context with the user and handles git operations (commits) — post-merge, with the pre-authored message verbatim. It closes boxes too, but never by editing one: it invokes `scripts/close-subtask.sh` with the Executor's closing block, and the script performs the marking, the census and the `status:` stamp in a single transaction (a `failed` outcome makes no call at all).

**Every sub-agent this skill spawns runs in the foreground — `run_in_background: false` on the Agent call.** The orchestrator's next step is the sub-agent's result: the Analyst's scan feeds the proposal, the Test Advisor's tests gate Phase 3, the Executor's closing block closes the box, the Validator's and the Auditor's verdicts end the mode. A turn ended to wait for a sub-agent is a turn the requester spends saying "still waiting". Measured on 2026-09-17: a Standard run for a beginner spawned the Test Advisor in the background, spent 12 of 12 user turns on "ainda tá fazendo?", wrote no code and cost US$ 7; a developer's run did the same for ten turns. Both registers assume the assistant is working, not waiting. A parallel Executor group is not an exception: it is several foreground calls in one message, joined before the next step.

### MCP Integration

During triage, detect and health-check available MCPs. Load [mcp-integration.md](mcp-integration.md) for the full health-check procedure and category mapping.

Key rule: Never suggest an MCP without a successful health-check first. For Fast mode: skip MCP detection.

### Preferred Tooling

During triage, detect available E2E testing tools and the `frontend-design` aid, then resolve which to use. Load [preferred-tooling.md](preferred-tooling.md) for the favorite/optional tiers, the detection procedure, and the no-favorite recommendation.

Key rule: prefer a favorite (`playwright`, `chrome-devtools`); an optional tool is selected only when already installed AND the task context calls for it. Unlike MCP detection, preferred-tooling detection runs in **all modes, including Fast**.
