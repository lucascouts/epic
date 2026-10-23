<!-- epico:start — managed by the Epico plugin; `/epico:epico init --repair` rewrites everything up to epico:end -->
## Epico

- Project rules: `.epico/constitution.md` — Defaults, Quality, Security floor. Read it before deciding anything it covers.
- Stories and their plans: `.epico/stories/`; the index: `.epico/EPICO.md`.
- Project docs: `ARCHITECTURE.md`.

### Where to look, in order

1. The code itself — grep for the name before assuming anything.
2. Memory, as a pointer only: verify every recalled fact against the code.
3. The installed dependency at the lockfile version — its source, types and `--help`.
4. The language server (LSP) for definitions, references and types.
5. The official docs for that exact version.
6. The dependency's issue tracker — only when its behaviour contradicts its docs.
7. The web, last.

### Before committing

- Formatting — omitted: the scripts were never `shfmt`-formatted (32 files differ); adopting `shfmt -l scripts bin hooks` is a decision of its own
- Lint — `shellcheck scripts/*.sh bin/*` exits 0
- Types — omitted: bash has no type checker
- Error handling — every script runs under `set -euo pipefail` and refuses with its reason in the JSON; the story's bats cases prove the refusal paths
- Unit tests — `bats tests/` passes, as a normal user
- Lockfile and frozen install — no dependencies: the plugin installs nothing
- Dependency vulnerabilities — no dependencies; `trivy fs .` gives the verdict
- Secrets — `gitleaks git .` reports no leaks; the pre-commit hook runs it on staged changes
- README — `README.md` names how to install and how to run the checks
- `.gitignore` and `.editorconfig` — `.gitignore` exists; `.editorconfig` missing (recommended — not written)
- Supported and declared runtime — Claude Code 2.1.295+ is declared in the README and CHANGELOG; bash, jq and git have no declaration a tool reads (recommended: `.tool-versions`)
- Dependencies justified and current — none to justify
- Hardened workflows — `.github/workflows/` present; `zizmor .github/workflows` (recommended — not installed) · `actionlint` (recommended — not installed); meanwhile `opengrep scan --config p/github-actions .github/workflows`
- Pre-commit hook — `.pre-commit-config.yaml`; `pre-commit run --all-files`
- Licence, SBOM, signing — distributed through a marketplace: `LICENSE` exists; no build artifact to SBOM or sign
- Security policy — `SECURITY.md` exists and names a private channel
- Branch protection — `gh api repos/lucascouts/epico/rules/branches/main` lists `deletion`, `non_fast_forward` and `required_status_checks` (today: none — the ruleset targets no branch)
- Minimum dependency age — Dependabot `cooldown` of 7 days on GitHub Actions
- CI mirror — `act -j shellcheck`, `act -j validate-examples`, `act -j plugin-validate` before a push; `act -j bats` fails only its unreadable-file cases (root)
- Plugin schema — `claude plugin validate --strict` on `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills`, `agents`

### Code rules

- Files stay under 500 lines; split by responsibility before one grows past it.
- Names are unique and greppable: no two symbols share a name across modules.
- Comments say why, and where a value or rule came from — never what the next line does.
- One command runs every test.
- Fakes are named for what they stand in for (`FakeClock`, `InMemoryOrders`).
- Dependencies arrive through parameters or constructors, never through globals.
- The formatter runs in pre-commit.
- Logs are JSON, one event per line.

Living examples of these rules: `assets/examples/`.
<!-- epico:end -->
