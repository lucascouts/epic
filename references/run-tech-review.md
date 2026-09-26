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

The Tech Reviewer's focus areas, its measurement rule and its report format live in its agent definition ([tech-reviewer.md](../agents/tech-reviewer.md)), which Claude Code loads as its system prompt. The spawn prompt carries only the inputs:

> "Review the [technology] boundary of this sub-task. Follow your agent definition.
>
> ## Technology and boundary
>
> [technology] — [the boundary, e.g. handler → template, app → SQL]
>
> ## Files to Review
>
> [Files created/modified by the Executor]
>
> ## Design Contract
>
> [Relevant interface from design.md for this boundary]"

### Orchestrator Handling of Tech Review

- If all Tech Reviewers report PASS: proceed to next sub-task
- If any report ISSUES:
  1. Present issues to user (in `--auto` mode: attempt fix first)
  2. Spawn a new Executor instance with the original task + issues to fix
  3. Re-run only the affected Tech Reviewers
  4. Maximum 2 fix cycles. If still failing after 2 cycles, stop and escalate to user
- Tech Reviews are skipped for a group's `Commit:` field — there is no implementation to review
