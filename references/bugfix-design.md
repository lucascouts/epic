# Design Template (Bugfixes)

Use this template for the `design.md` file in bugfix stories. Lighter than the feature design template, focused on surgical fixes.

## Template

```markdown
# Design - Bugfix: [Bug Title]

## Root Cause Analysis

- **Symptom:** [What the user/system observes]
- **Root cause:** [The actual code/logic/data issue]
- **Why it wasn't caught:** [Missing test? Edge case? Incorrect assumption?]

## Affected Components

| Component | Role in Bug | Change Needed |
|---|---|---|
| `path/to/file.ts` | [How it's involved] | [What changes] |

## Fix Approach

[Describe the specific changes needed. Be surgical — change as little as possible.]

1. [Change 1: what and why]
2. [Change 2: what and why]

## Regression Test Strategy

- **Bug verification test:** [Test that reproduces the bug — should fail before fix, pass after]
- **Regression tests:** [Tests for unchanged behavior from story.md]
- **Existing test impact:** [Do any existing tests need updating?]

## Side Effects Assessment

| Potential Side Effect | Risk Level | Mitigation |
|---|---|---|
| [Side effect 1] | Low/Medium/High | [Why it's safe or how to mitigate] |
```

## Guidelines

1. **Root Cause Analysis is the most important section.** Without understanding why, the fix may address symptoms, not the cause.
2. **Fix Approach should be minimal.** If the fix touches more than 3-4 files, question whether it's still a bugfix or becoming a refactor.
3. **Regression Test Strategy maps directly to the Unchanged Behavior section in story.md.** Every "SHALL CONTINUE TO" item should have a corresponding test.
