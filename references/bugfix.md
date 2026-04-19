# Story Template (Bugfixes)

Use this template for the `story.md` file in bugfix stories. Same filename as features — the `type: bugfix` frontmatter and content structure differentiate it.

## Template

```markdown
---
story: <story-name>
type: bugfix
scale: standard | full
version: 1
created: <date>
---

# Bugfix - [Bug Title]

## Summary

[1-2 sentences: what is broken, where, and impact.]

## Reproduction Steps

1. [Step 1: exact precondition or setup]
2. [Step 2: exact action that triggers the bug]
3. [Step 3: observe incorrect behavior]

## Current Behavior (Defect)

WHEN [trigger condition] THEN the system [incorrect behavior observed]
WHEN [second trigger if applicable] THEN the system [second incorrect behavior]

## Expected Behavior (Correct)

WHEN [trigger condition] THEN the system SHALL [correct behavior expected]
WHEN [second trigger if applicable] THEN the system SHALL [correct behavior expected]

## Unchanged Behavior (Regression Prevention)

WHEN [related but unaffected trigger] THEN the system SHALL CONTINUE TO [existing correct behavior]
WHEN [adjacent feature trigger] THEN the system SHALL CONTINUE TO [existing correct behavior]
[Minimum 2 items. Add more for complex bugs.]

## Constraints

- [What must not change: e.g., "public API signature must remain identical"]
- [Performance: e.g., "fix must not increase latency by more than 10ms"]
```

## Writing Guidelines

1. **Unchanged Behavior is mandatory.** Minimum 2 items. This is the most valuable section — it forces you to think about what the fix might break.
2. **Use EARS notation** in all three behavior sections. `SHALL` for expected, `SHALL CONTINUE TO` for unchanged.
3. **Reproduction steps must be exact.** Someone unfamiliar with the codebase should be able to reproduce the bug from these steps alone.
4. **Current Behavior describes what IS happening** — use plain language without `SHALL`.
5. **Expected Behavior describes what SHOULD happen** — use `SHALL`.
6. **Think about adjacent features.** If you're fixing authentication, what about authorization? If you're fixing retry logic, what about timeout handling?
