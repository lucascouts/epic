# Example: Bugfix Story (Standard Scale)

> Scenario: Retry logic incorrectly classifying authentication errors as retryable

---

## story.md

```markdown
---
story: fix-auth-retry-classification
type: bugfix
scale: standard
version: 1
created: 2026-04-01
---

# Bugfix - Auth Errors Classified as Retryable

## Summary

Authentication errors (wrong credentials) are being retried 3 times with exponential backoff, wasting ~21 seconds before failing. Auth errors should fail immediately since retrying with the same credentials cannot succeed.

## Reproduction Steps

1. Configure a flow with incorrect portal credentials
2. Execute the flow via `bam run`
3. Observe: script retries 3 times (1s + 4s + 16s delay) before marking as FAILED

## Current Behavior (Defect)

WHEN a script fails with an authentication error (HTTP 401, login form re-appears, "invalid credentials" message) THEN the system retries the script up to 3 times with exponential backoff

## Expected Behavior (Correct)

WHEN a script fails with an authentication error THE SYSTEM SHALL classify the error as non-retryable and mark the execution step as FAILED immediately

## Unchanged Behavior (Regression Prevention)

WHEN a script fails with a network timeout THE SYSTEM SHALL CONTINUE TO retry with exponential backoff up to the configured maximum attempts
WHEN a script fails with a selector not found error THE SYSTEM SHALL CONTINUE TO retry since the DOM may still be loading
WHEN a script fails with HTTP 403 or CAPTCHA detection THE SYSTEM SHALL CONTINUE TO retry with extended backoff
```

---

## tasks.md

```markdown
---
story: fix-auth-retry-classification
type: bugfix
scale: standard
version: 1
created: 2026-04-01
---

# Implementation Plan - Bugfix: Auth Errors Classified as Retryable

## Overview

Add authentication error pattern matching to the retry classifier. Surgical change to one file with comprehensive test coverage for both the fix and regressions.

## Task List

- [ ] 1 - Auth Error Classification Fix
  - _Complexity: Moderate | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: Classify authentication errors as non-retryable while preserving existing retry behavior

  - [ ] 1.1 - Add auth error patterns to classifier
    - Context:
      - Files: `src/services/retry-classifier.ts` (classifier to modify)
    - Objective: Match auth errors and return non-retryable classification
    - ToDo: Add pattern matching in retry-classifier.ts for HTTP 401 status, auth-related message patterns ("invalid credentials", "authentication failed", login form re-appearance). Return non-retryable for matched patterns.
    - Tests: Unit · `src/services/__tests__/retry-classifier.test.ts` — HTTP 401 returns non-retryable, auth message returns non-retryable, test fails before fix and passes after
    - Validation: `npm test -- retry-classifier` passes
    - Requirements: Expected Behavior

  - [ ] 1.2 - Regression tests for existing retry behavior
    - Objective: Verify unchanged behaviors are preserved
    - ToDo: Add test cases for timeout (retryable), selector not found (retryable), HTTP 403/CAPTCHA (retryable).
    - Tests: Unit · `src/services/__tests__/retry-classifier.test.ts` — timeout retryable, selector-not-found retryable, HTTP 403 retryable
    - Validation: `npm test -- retry-classifier` passes with all regression cases
    - Requirements: Unchanged Behavior (all 3 items)

  - [ ] 1.3 - Commit
    - Validation: All unit tests pass (fix + regression), no existing tests broken
    - Commit: "fix: classify auth errors as non-retryable in retry logic"

## Quality Gates

- [ ] Bug verification test passes (auth errors → non-retryable)
- [ ] All 3 regression tests pass (timeout, selector, 403)
- [ ] No existing tests broken
```
