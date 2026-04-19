# Constitution Template

The constitution is an optional governance file at `.epic/constitution.md` that defines cross-story constraints. All stories must respect these constraints.

## Template

```markdown
# Constitution

## Architecture
- [Architectural principle 1]
- [Architectural principle 2]
- [Module/project isolation rules]

## Data
- [PK strategy: e.g., UUID via @default(uuid())]
- [Status field conventions]
- [Financial value precision]
- [Soft delete conventions]
- [Mandatory fields across entities]

## Security
- [Credential storage approach]
- [API key handling]
- [Authentication requirements]

## Testing
- [Required test coverage]
- [Testing approach: unit, integration, e2e]
- [Testing framework conventions]

## Naming
- [File naming conventions]
- [Variable/function naming conventions]
- [API endpoint naming conventions]
```

## Guidelines

1. **Keep it concise.** The constitution is a set of rules, not documentation. Each item should be one line.
2. **Only include cross-cutting concerns.** If a rule applies to only one story, it belongs in that story's constraints, not here.
3. **Rules are soft constraints.** Constitution violations generate `[CONSTITUTION]` warnings in stories, not blocks. The user decides whether to address them.
4. **Update rarely.** The constitution should be stable. If you're changing it frequently, the rules may be too specific.
5. **Sections are optional.** Only include sections relevant to your project.

## Example

```markdown
# Constitution

## Architecture
- NestJS Modular Nativo — no extra abstraction layers
- Project isolation: each project-* has its own database and Prisma schema
- CLI-first: everything must be actionable via terminal

## Data
- PKs: UUID via @default(uuid())
- Status fields: String (no Prisma enums)
- Financial values: Decimal @db.Decimal(15, 4)
- Soft delete: deletedAt DateTime? on mutable entities

## Security
- Credentials: AES-256-GCM
- API keys: stored as SHA-256 hash, never plaintext
```

## How It's Used

- Read before Phase 1 of any story creation
- Constraints appear as `[CONSTITUTION]` tags in requirements when relevant
- Violations in design generate warnings, not blocks
- The user always has final say over whether to follow or override a constraint
