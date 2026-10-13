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

## Report as Given

Kept apart, because only the first is a fact. The reporter's diagnosis and fix are hypotheses Phase 2 confirms or rejects; they never become Current Behavior or a requirement on their own.

- **Observed:** [what the reporter saw happen, in their words — the symptom only]
- **Expected:** [what they expected instead]
- **Reporter's diagnosis:** [their theory of the cause, or "none given" — unverified]
- **Proposed fix:** [the change they suggest, or "none given" — unverified]

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

0. **Report as Given separates fact from theory.** Current Behavior is written from **Observed** and the reproduction, never from the reporter's diagnosis. When the root cause is found in Phase 2, say whether it confirms or contradicts the diagnosis.

1. **Unchanged Behavior is mandatory.** Minimum 2 items. This is the most valuable section — it forces you to think about what the fix might break.
2. **Use EARS notation** in all three behavior sections. `SHALL` for expected, `SHALL CONTINUE TO` for unchanged.
3. **Reproduction steps must be exact.** Someone unfamiliar with the codebase should be able to reproduce the bug from these steps alone.
4. **Current Behavior describes what IS happening** — use plain language without `SHALL`.
5. **Expected Behavior describes what SHOULD happen** — use `SHALL`.
6. **Think about adjacent features.** If you're fixing authentication, what about authorization? If you're fixing retry logic, what about timeout handling?
