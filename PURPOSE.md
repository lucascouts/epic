# Purpose & Scope

Epic has a single, narrow purpose: **create, structure, and manage the epics of a project** — the epic being the container that groups stories (`story.md` / `design.md` / `tasks.md`) and drives their planned execution.

Every feature of this plugin exists to serve that purpose. Anything outside it is out of scope by design and must be refused.

---

## In scope

Epic is responsible for:

- **Epic/story creation** — turn a request into EARS-notation requirements, an optional design document, and a hierarchical task breakdown (`tasks.md`).
- **Story management** — list, refine, archive, and version stories under `.epic/stories/`.
- **Task orchestration** — drive the Executor sub-agent through the 6-step protocol (context → implementation → design fidelity → validation → tests → report) for each sub-task in `tasks.md`.
- **Planned validation & audit** — run the Validator and Auditor *against the story artifacts the plugin produced*, to verify implementation matches the planned scope.
- **Traceability** — enforce the R-number → design-component → sub-task chain via `scripts/cross-reference.sh` and the archive immutability guard.

---

## Out of scope (explicitly refused)

Epic must refuse the following, even when asked directly. The skill responds with a short message pointing the user to the correct Claude Code command or plugin.

| Request | Out-of-scope because… | Suggested alternative |
|---|---|---|
| **Code review** of arbitrary code, a PR, or a branch | Reviews not tied to an Epic story have no artifacts to anchor to | `/review`, `/security-review`, or `/code-review` (bundled) |
| **Security review** of arbitrary code | Same reason | `/security-review` |
| **Refactor** outside the scope of an existing story's `tasks.md` | Refactors without a planned story skip the design-fidelity contract | Create a new story first, then `run` its tasks |
| **Analysis / architecture advice** without an attached story | Epic artifacts (`story.md`, `design.md`) are the only valid containers for analysis under this plugin | `/gsd-explore`, `/gsd-map-codebase`, `/tab`, or a regular chat turn |
| **Exploratory code generation** outside a story | Implementation only happens inside Executor, driven by an approved sub-task | Create a Fast-mode story if the change is small |
| **Repo-wide refactor as a single story** | Violates the story-is-a-unit-of-work contract | Split into multiple linked stories (`based on` / `extends`) |
| **Execution of ad-hoc scripts / commands / investigations** | Epic only executes what is declared in a sub-task's `Validation:` or `Tests:` field | Run manually outside `/epic:epic` |
| **Debugging** a production incident | Debug flows live elsewhere and require different artifacts | `/gsd-debug` |

The refusal is not soft-fail; the skill surfaces a one-line rejection explaining *why* and pointing to the alternative.

---

## Why this boundary exists

- **Artifacts are the contract.** The Executor, Validator, and Auditor only work because they compare code against `story.md`, `design.md`, and `tasks.md`. Without those artifacts, the sub-agent pipeline has no anchor — the 6-step protocol degenerates into ad-hoc prompting.
- **Scope discipline prevents drift.** Every Epic run is traceable R-number → design-component → sub-task → commit. Accepting "just analyze this" or "just refactor this" breaks the chain and erodes the value proposition.
- **Claude Code has better tools for the rest.** `/review`, `/security-review`, `/code-review`, `/gsd-debug`, `/gsd-explore`, `/tab`, and plain chat cover analysis, review, and exploration. Epic's job is to formalize *decided* work, not to explore or audit *existing* work.

---

## How this is enforced

- The skill body (`skills/epic/SKILL.md`) opens with a scope check. Out-of-scope requests short-circuit to the refusal table.
- The skill refuses to write to paths outside `.epic/`, source files not listed in an approved sub-task's `Context:`, or archived stories (`.epic/archive/**`, blocked by `hook-archive-guard.sh`).
- `references/` files are only loaded when the relevant mode is active — there is no "free-form" mode.

---

## If you need to extend

Adding a new mode (`/epic:epic <verb>`) is allowed only if the verb still serves *creating, structuring, or managing an epic or its stories*. Modes that would widen the purpose (e.g., `review`, `refactor`, `debug`) are rejected at contribution time — see `ARCHITECTURE.md` → Extension points.

---

## Non-goals (reiteration for contributors)

- No idea exploration.
- No generic code generation outside a story.
- No code review of existing code.
- No refactor suggestions outside a story's tasks.
- No runtime dependencies beyond `bash`, `git`, `jq`.
- No version-controlled drafts (`.epic/` is `.gitignored`).
