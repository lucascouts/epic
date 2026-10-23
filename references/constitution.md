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

## Quality
- [Always tier, one line per item with its command — see quality-catalog.md]
- [Context items detected at init, each with its signal]

## Defaults
- [Each decision the requester is never asked, with its answer — see init-mode.md]

## Security floor
- Supported and declared runtime — [the runtime and version, LTS where there is one]
- Secrets — [`gitleaks detect`, or the scanner this host has]
- Dependency vulnerabilities — [`trivy fs .` · `osv-scanner .` · the ecosystem's auditor]
- README — how to run it and how to check it
- Data integrity — a file the program reads back is written through a temporary file and a rename; a missing, corrupted or wrong-shaped one never crashes the program or gets overwritten, an earlier set-aside copy is never replaced, and a failed save says so (`no persisted data` when there is none)

## Reversibility
- An irreversible step — deleting data, a migration without a down, a force push, a publish, a release — runs only with a way back recorded first (a backup, a down migration, a tag) or on the user's explicit yes

## Runtime
- [host | venv | container] — [why: a `layperson` requester defaults to an isolated runtime (a venv or a container), so a program never touches the system it runs on]

## Invariants
- Never [X] — [the incident or finding that made it a rule]
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
- NestJS native modules — no extra abstraction layers
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

## Quality
- Formatting — `prettier --check .`
- Lint — `eslint .`
- Types — `tsc --noEmit`
- Secrets — `gitleaks detect`
- Hardened workflows — `.github/workflows/` present; `zizmor .github/workflows`
```

**The constitution is mandatory.** `init` always writes it — every answer left unanswered takes its default — and triage refuses Standard and Full without one ([triage.md](triage.md#constitution-gate)). Tooling in `## Quality` and `## Security floor` is derived from what the host has (`command -v` per tool); a tool that is missing is recommended on its line, never installed without the user's yes.

## How It's Used

- Read before Phase 1 of any story creation; the `## Quality` block seeds the story's `## Quality Requirements` legend ([quality-catalog.md](quality-catalog.md))
- Constraints appear as `[CONSTITUTION]` tags in requirements when relevant
- Violations in design generate warnings, not blocks
- The user always has final say over whether to follow or override a constraint
