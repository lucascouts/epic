# Example: Fast Scale Feature

> Scenario: Add email field to user profile form

This example shows the single file generated for a fast scale story.

---

## tasks.md

```markdown
---
story: add-email-field
type: feature
scale: fast
version: 1
created: 2026-04-01
---

# Implementation Plan - Add Email Field to Profile

## Overview

Add an email field to the user profile form with validation. Single-component change touching the form component and its schema.

## Task List

- [ ] 1 - Add email field to profile form
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_
  - Objective: Add email input with Zod validation to the existing profile form

  - [ ] 1.1 - Update form schema
    - Context:
      - Files: `src/schemas/profile.ts` (existing schema to extend)
    - Objective: Add email to the Zod schema and TypeScript type
    - ToDo: Add `email: z.string().email()` to the profile schema in `src/schemas/profile.ts`. Update the inferred TypeScript type.
    - Validation: Schema rejects invalid emails, accepts valid ones

  - [ ] 1.2 - Add email input to form component
    - Context:
      - Files: `src/components/ProfileForm.tsx` (existing form to extend)
    - Objective: Render email input and wire to form state
    - ToDo: Add email input field to `src/components/ProfileForm.tsx`. Wire to existing react-hook-form setup. Add blur validation.
    - Tests: Unit · `src/components/__tests__/ProfileForm.test.tsx` — valid email accepted, invalid email shows error, empty email shows required error
    - Validation: `npm test -- ProfileForm` passes with all 3 cases

  - [ ] 1.3 - Commit
    - Validation: All tests pass, form renders and submits correctly
    - Commit: "feat: add email field to user profile form"

## Quality Gates

- [ ] All acceptance criteria validated
- [ ] Unit tests pass (3 cases)
- [ ] Form submits correctly with new field
```
