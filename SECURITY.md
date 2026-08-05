# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
private vulnerability reporting instead:

https://github.com/lucascouts/epic/security/advisories/new

Reports are handled on a best-effort basis; expect an acknowledgment within
seven days.

## Supported versions

Only the latest release receives security fixes.

## Scope

Epic is a Claude Code plugin: its scripts and hooks run on the machine of
every user who installs it. Reports we care about most:

- command or path injection through story artifacts, fixtures or frontmatter
  processed by `scripts/`, `bin/` or `hooks/`;
- the archive flow deleting or overwriting data outside `.epic/`;
- bypasses of the secrets guard (content that should be blocked but passes);
- anything that makes a validation gate report success without running.

Out of scope: the fake AWS-shaped keys in `tests/` (deliberate fixtures —
see `.gitleaksignore`), and attacks that require the attacker to already
control the machine the plugin runs on.
