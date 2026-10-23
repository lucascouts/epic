# Language rules — secure coding per language

Read by the Executor, by the main agent on the inline route, and by the Tech Reviewer — **only the sections of the languages the run detected** ([run-mode.md](run-mode.md#tech-stack-detection)), never the whole file. Each rule is one a linter does not reliably catch and a generalist implementer gets wrong. A language with no section here gets no rules from this file: say so in one line, and never invent a section for it.

These rules sit under the project's own: the constitution and the code already in the tree win where they say more.

## Go

- Handle every error — never `_` — and wrap it with `%w`, so the cause survives `errors.Is`/`errors.As`.
- A context with a timeout bounds every network I/O call (`context.WithTimeout`); a call with no deadline hangs forever on a dead peer.
- Shared state is guarded by a mutex or owned by one goroutine behind a channel, and tests run with `-race`.
- `go vet` and `staticcheck` pass before the sub-task closes.
- Logs go through `log/slog` with fields, never `fmt.Println`; a library returns errors and does not log them.

## Rust

- No `unwrap()` or `expect()` in production code — propagate with `?` and a `Result`. Tests may use them.
- `unsafe` only with a comment that states the invariant it relies on.
- `cargo clippy` and `cargo audit` pass before the sub-task closes.
- No clone to silence the borrow checker where a borrow would do.

## Python

- `subprocess` with an argument list, never `shell=True` with input that came from outside.
- Keep the cause: `raise NewError(...) from err`; inside `except`, `logger.exception` keeps the traceback.
- Type hints on public functions, and `ruff` plus `mypy` pass.
- Logs through `logging` or `structlog` with fields, never `print` for diagnostics.

## JavaScript/TypeScript

- TypeScript in `strict`; no `any` — take `unknown` and narrow it.
- Validate external data at the boundary with a schema (`zod` or the project's validator) before any code trusts its shape.
- Keep the cause: `throw new Error(msg, { cause })`.
- No `child_process` call through a shell on a backend; pass an argument list.
- Logs through the project's structured logger, with secrets redacted at the logger.

## PHP

- Every query through PDO prepared statements, never a string built from input.
- Escape every output written into HTML with `htmlspecialchars`, against XSS.
- Never `include`, `require` or `eval` a path or code that came from input.
- Composer with a committed lockfile.

## Shell

- `set -euo pipefail` at the top of every script.
- Quote every expansion — `"$var"`, `"${arr[@]}"` — and build argument lists in arrays, never by splitting a string.
- Never parse `ls`; never `curl | bash` a script nobody has read.
- `shellcheck` passes before the sub-task closes.

## SQL

- Parameterized or prepared statements only — never concatenate or interpolate input into a query.
- Migrations are versioned and reversible; the application connects with a least-privilege user.
- Index foreign keys and the columns a hot query filters or joins on; read its `EXPLAIN`.

## Docker

- Pin the base image by digest (`image@sha256:…`), never by `latest` or a mutable tag.
- A multi-stage build, so compilers and build dependencies stay out of the final image; a `.dockerignore` keeps the context small and `.env` out of it.
- Run as a non-root `USER`.
- Never put a secret in the image — no `ENV` or `ARG` holding a credential, no copied key file; use a build secret or the runtime environment.
- Scan the image (`trivy image`) before it is published.
