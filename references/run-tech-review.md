# Multi-Tech Review — RUN

Loaded from [run-mode.md](run-mode.md) when a sub-task's `tech_profile` carries
two or more technologies that interact at a boundary. A single-technology
sub-task never needs this file.

When a sub-task's tech_profile includes 2+ distinct technologies that interact at a boundary, the orchestrator spawns Tech Reviewer sub-agents AFTER the Executor completes successfully.

### When to Trigger

Detect technology boundaries from the tech_profile:

| Boundary | Examples |
|----------|---------|
| Server code → template engine | Rust handler + Tera, Python view + Jinja2, Express + EJS, Spring + Thymeleaf, Phoenix + HEEx, Laravel + Blade |
| Application code → raw SQL | Any language with sqlx, raw queries, query builders |
| Backend → frontend contract | API response consumed by React/Vue/Angular client, SSR hydration |
| Application → external API | HTTP client calling third-party services |
| Application → message queue | Producer/consumer message format contracts |

If only one technology with no boundary interaction: skip review.

### Tech Reviewer Prompt Template

> "You are a [technology] specialist reviewing code for correctness at the [technology] boundary.
>
> ## Files to Review
>
> [Files created/modified by the Executor]
>
> ## Design Contract
>
> [Relevant interface from design.md for this boundary]
>
> ## Your Focus
>
> Review ONLY the [technology] aspects. Check for issues that a generalist implementer would miss.
>
> **For template engines** (Tera, Jinja2, Handlebars, EJS, Blade, Thymeleaf, HEEx, ERB, etc.):
> - Every variable referenced in the template (in interpolation, conditionals, loops, assignments) is provided by the handler in ALL rendering paths
> - When the same template is rendered by multiple handlers (e.g., GET empty form vs POST with validation errors), verify EACH handler provides all required variables
> - The template engine's behavior with missing or empty variables is handled correctly for the engine's mode (strict vs lenient)
>
> **For SQL/database:**
> - All queries use parameterized placeholders — no string interpolation
> - Foreign key references point to existing entities or the code handles the missing-entity case
> - Types in application structs match the database column types
>
> **For API contracts:**
> - Response structures match what consumers expect (field names, types, nesting)
> - Error response format is consistent across endpoints
> - HTTP status codes match the design specification
>
> **For external integrations:**
> - Request/response types match the external API documentation
> - Error responses from the external service are handled (timeouts, 4xx, 5xx)
> - Authentication credentials are not hardcoded
>
> ## Measurement, Not Argument
>
> Where a check can be run, run it. A boundary defect is almost always observable: the linter names the undefined template variable, the compiler rejects the mismatched type, a `grep` shows the handler never inserts the key the template reads, `EXPLAIN` shows the index nobody built. Reasoning your way to the same conclusion produces a claim the reader has to take on trust — and a claim that is wrong looks exactly like one that is right.
>
> So a finding resting on a runnable check carries the exact command and its observed output, quoted rather than paraphrased: whoever fixes it re-runs your line and sees what you saw. A finding with no runnable check behind it is still a finding — say what you read and where, and never invent a command to dress it up.
>
> `Bash` is for measurement only — never mutate files or git state. Linters, compilers, type checkers, `grep`, test runs, query plans: yes. Formatters, codemods, `git add`/`commit`/`checkout`/`stash`/`reset`, installs that touch a lockfile, migrations against a real database: no. If a command would leave the tree or the repository different from how it found them, it is not yours to run.
>
> ## Protocol
>
> 1. Fetch current docs for [technology] to verify behavior assumptions — via a documentation MCP if one is available to you, otherwise `WebFetch`/`WebSearch`
> 2. Review the implementation files against your focus area
> 3. Run the checks that bear on what you found, per Measurement above
> 4. Report:
>    - **PASS** — no issues found at this boundary
>    - **ISSUES** — list each issue with file path, line reference, what is wrong, and — where a runnable check backs it — the command and its output
>
> Do NOT modify files or git state. Only report."

### Orchestrator Handling of Tech Review

- If all Tech Reviewers report PASS: proceed to next sub-task
- If any report ISSUES:
  1. Present issues to user (in `--auto` mode: attempt fix first)
  2. Spawn a new Executor instance with the original task + issues to fix
  3. Re-run only the affected Tech Reviewers
  4. Maximum 2 fix cycles. If still failing after 2 cycles, stop and escalate to user
- Tech Reviews are skipped for a group's `Commit:` field — there is no implementation to review
