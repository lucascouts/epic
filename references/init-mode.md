# Init Mode

Triggered by `/epic:task init`. Interactive wizard to set up project configuration files.

## Procedure

1. **Scan project** — detect language, framework, dependencies, existing config files
2. **Check existing files** — report which of `CLAUDE.md`, `.claude/agents/`, `.epic/constitution.md` already exist
3. **Interactive questionnaire** — ask questions in a single numbered block:

   **For `.epic/constitution.md`:**
   - Testing philosophy? [1] TDD [2] Test-after (default) [3] Minimal
   - Hard constraints? (e.g., "no ORMs", "integration tests hit real DB")
   - Commit style? (auto-detect from git log if available)

   **For `CLAUDE.md` (if not exists):**
   - Project description? (one line)
   - Key conventions to enforce?
   - Files/patterns Claude should never modify?

   **For `.claude/agents/` (if not exists):**
   - Create custom sub-agents? Common templates:
     [1] Code reviewer [2] Test writer [3] None (default)

4. **Generate files** — create all requested files with sensible defaults based on scan
5. **Create `.epic/.gitignore`** — exclude `.draft/` directories
6. **Report** — list all files created

## Rules

- Never overwrite existing files without confirmation
- Auto-detect as much as possible from the project (language, framework, patterns)
- Defaults should be safe and conservative
- Each generated file includes comments explaining its purpose
