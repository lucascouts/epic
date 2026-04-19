# Example: Standard Scale Feature

> Scenario: API key authentication for workspaces

This example shows the two files generated for a standard scale story (story.md + tasks.md).

---

## story.md

```markdown
---
story: api-key-authentication
type: feature
scale: standard
version: 1
created: 2026-04-01
---

# Story - API Key Authentication

## Introduction

Workspaces need authentication to protect API endpoints. In the MVP, each workspace has a single API key. Requests include the key in the `x-api-key` header. The system extracts the workspace ID from the key and injects it into the request context.

## Requirements

### R1. API Key Validation

**User Story:** As an API consumer, I want to authenticate with an API key, so that my requests are associated with my workspace.

#### Acceptance Criteria

- R1.1: WHEN a request includes a valid API key in the `x-api-key` header THE SYSTEM SHALL authenticate the request and inject the workspace ID into the request context
- R1.2: WHEN a request includes an invalid or missing API key THE SYSTEM SHALL return HTTP 401 with error message "Invalid or missing API key"
- R1.3: WHEN a request includes an API key for a soft-deleted workspace THE SYSTEM SHALL return HTTP 401

### R2. API Key Generation

**User Story:** As an administrator, I want each workspace to have a unique API key generated automatically.

#### Acceptance Criteria

- R2.1: WHEN a new workspace is created THE SYSTEM SHALL generate a unique UUID v4 API key
- R2.2: THE SYSTEM SHALL ensure API keys are unique across all workspaces

## Constraints

- No JWT, no users, no roles in MVP — API key per workspace only
- API key stored as plain UUID (not hashed) in MVP

## Out of Scope

- API key rotation
- Multiple keys per workspace
- JWT authentication (Phase 2)
- Rate limiting (separate story)
```

---

## tasks.md

```markdown
---
story: api-key-authentication
type: feature
scale: standard
version: 1
created: 2026-04-01
---

# Implementation Plan - API Key Authentication

## Overview

Implement API key guard as a NestJS Guard. Workspace lookup by apiKey, inject workspaceId into request. Apply globally with opt-out decorator for public endpoints.

## Task List

- [ ] 1 - API Key Guard
  - _Complexity: Moderate | Tests: Unit + Integration | Risks: None | Dependencies: Workspace model exists in Prisma schema_
  - Objective: Create NestJS guard that validates x-api-key header and injects workspace context

  - [ ] 1.1 - Implement guard logic
    - Context:
      - Files: `src/guards/` (existing guard patterns, if any)
      - Docs: NestJS Guards documentation (context7)
    - Objective: Create ApiKeyGuard implementing CanActivate
    - ToDo: Implement guard that reads `x-api-key` header, queries workspace by apiKey, rejects deleted workspaces, injects workspaceId into request object.
    - Tests: Unit · `src/guards/api-key.guard.spec.ts` — valid key accepted, invalid key rejected (401), missing header rejected (401), deleted workspace rejected (401)
    - Validation: `npm test -- api-key.guard` passes with all 4 cases
    - Requirements: R1.1, R1.2, R1.3

  - [ ] 1.2 - Integration test
    - Objective: Verify guard works in full HTTP request cycle
    - ToDo: Write integration test using NestJS testing module with real HTTP requests against the guard.
    - Tests: Integration · `test/api-key.e2e-spec.ts` — full request with valid key returns 200, invalid key returns 401
    - Validation: `npm run test:e2e -- api-key` passes
    - Requirements: R1.1, R1.2

  - [ ] 1.3 - Commit
    - Validation: All unit and integration tests pass
    - Commit: "feat: add API key guard for workspace authentication"

- [ ] 2 - API Key Auto-Generation
  - _Complexity: Trivial | Tests: None | Risks: None | Dependencies: None_
  - Objective: Ensure workspace creation generates unique API key

  - [ ] 2.1 - Verify Prisma schema and uniqueness
    - Context:
      - Files: `prisma/schema.prisma` (workspace model definition)
    - Objective: Confirm apiKey field has default UUID and unique constraint
    - ToDo: Verify workspace model has `apiKey String @default(uuid()) @unique`. If missing, add the constraint.
    - Validation: `npx prisma validate` passes, `@unique` constraint present on apiKey
    - Requirements: R2.1, R2.2
    - Commit: "chore: verify workspace apiKey uniqueness constraint"

## Quality Gates

- [ ] All acceptance criteria validated
- [ ] Unit tests pass for guard (4 cases)
- [ ] Integration test passes (full HTTP cycle)
- [ ] Prisma schema validates with unique constraint
```
