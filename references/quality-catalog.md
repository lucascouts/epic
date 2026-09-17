# Quality Catalog

The checks a piece of software is expected to carry, in three tiers, and how the Epic decides which of them a story activates. It is the source that the `## Quality` block of the constitution ([init-mode.md](init-mode.md)), the `## Quality Requirements` legend of a story ([requirements.md](requirements.md)) and the generated Quality Gates of `tasks.md` ([tasks.md](tasks.md#generated-quality-gates)) all draw from: each names an item by its row here.

## How the set is chosen

1. **The constitution's `## Quality` block** is the project's default legend: the always tier, plus the context items init's scan detected. Written once by init, read by every story.
2. **The Analyst's scan** (Function 1, [analyst.md](../agents/analyst.md)) reports which context signals the tree carries — a `Dockerfile`, a `.github/workflows/` directory, a database configuration, an HTTP surface, a UI — and which always-tier tools the tree is already configured for.
3. **The request** adds what the constitution could not know: an API consumed by more than one client activates contract tests; a stated performance requirement activates a benchmark.
4. **The story's legend** is the result: `## Quality Requirements`, one line per active item, numbered `Q1`…`Qn` in the order of this catalog, each with the command that proves it on this project. A Fast story, which has no `story.md`, carries the legend at the top of `tasks.md`.

**The engineering level bounds the set** ([engineering-level.md](engineering-level.md)): `experiment` activates nothing and its legend reads `none`; `tool` activates the always tier; `project` adds every context item whose signal the tree or the request carries; `product` adds the CI-shaped context items — pinned Actions, minimum dependency age, licence, SBOM and signing — without waiting for a signal, and the on-request tier when a requirement names it. The four steps above choose inside that bound.

**Activating an item never installs a tool.** The [preferred-tooling policy](preferred-tooling.md) applies: prefer the tool already installed for that item, name a recommendation and pause when none is, and record the choice on the legend line. A layperson is never paused for a tool choice — the best installed tool is taken and recorded.

## Always

Cheap, universal, and each provable by one command. A story that leaves one out says why on its legend.

| Item | What it proves | Typical command |
|---|---|---|
| Formatting | one style, applied by a tool, never by hand | `gofmt -l .` · `prettier --check .` · `ruff format --check` · `cargo fmt --check` |
| Lint | probable defects and known bad practice are absent | `golangci-lint run` · `eslint .` · `ruff check` · `cargo clippy` · `shellcheck` |
| Types | the program type-checks; a dynamic language carries annotations and a checker | `tsc --noEmit` (strict) · `mypy` · the compiler, for Go and Rust |
| Error handling | every error carries context and none is swallowed | the story's tests; a grep for bare `catch {}`, `_ = err`, `except: pass` |
| Unit tests | each unit of logic has a test, written first | `go test ./...` · `npm test` · `pytest` · `cargo test` · `bats tests/` |
| Lockfile and frozen install | the same dependency versions on every machine | `npm ci` · `--frozen-lockfile` · `pip install --require-hashes` · `go mod verify` |
| Dependency vulnerabilities | no known CVE in the dependency list (SCA) | `trivy fs .` · `osv-scanner .` · `cargo audit` · `govulncheck ./...` |
| Secrets | no credential in the tree or the history | `gitleaks detect` |
| README | how to run and how to test, in the repository | the two commands the README names exist and run |
| `.gitignore` and `.editorconfig` | generated files stay out; indentation is agreed | both files exist; `git status --short` is clean after a build |
| Supported and declared runtime | the runtime is a supported release — an LTS or the current stable — and the project declares it: `engines` in `package.json`, the `go` directive of `go.mod`, `requires-python`, `.tool-versions` | the declaration exists and names a supported version; `node --version` · `go version` against the vendor's support table |
| Dependencies justified and current | every dependency has a one-line reason the standard library or the code already there was not enough, recorded where the choice was made, and is a current release | the manifest's list against the story's `## Constraints` or the design's decisions; `npm outdated` · `go list -m -u all` · `pip list --outdated` |

**A syntax check is not a lint.** `node --check`, `python -m py_compile` and `bash -n` prove that a file parses and nothing else; a legend line that names one of them as Lint counts the item as **omitted**, not covered, and says so on the line. Measured on eleven attempts at one beginner's request (15–17 September 2026): every run accepted the runtime it found — Node 20, out of support since April 2026 — none declared a version, and none carried a formatter, a linter, a type checker or an `.editorconfig`; tests and error handling were the only always-tier items that appeared without being asked. The runtime version is chosen the way every technical decision is: a recommended version with its reason, in one line ([SKILL.md](../skills/epic/SKILL.md#clarify-protocol)).

## By context

Activated by a signal in the tree or in the request. The signal is the rule; the Analyst reports which are present.

| Item | Signal | What it proves | Typical command |
|---|---|---|---|
| Integration and E2E tests | an HTTP surface, a UI, a database | the parts work together, as the user reaches them | authored by the Test Advisor; E2E by the selected tool ([preferred-tooling.md](preferred-tooling.md)) |
| Contract tests | an API with more than one consumer | producer and consumers agree on the shape | a schema check per consumer (OpenAPI, JSON Schema, Pact) |
| Structured logs and health | a process that stays running | one event per line with keys, and a health endpoint answers | a log line parses as JSON or key=value; `curl /health` returns 200 |
| Versioned migrations | a database | schema changes are ordered and reversible | the migration tool's `status`, and a down migration |
| SAST | code that receives external input or handles auth | defects in the project's own code, not its dependencies | `opengrep` (or `semgrep`) with a registry ruleset |
| Image digest, non-root, scan | a `Dockerfile` | base pinned by `sha256:`, no root user, no known CVE in the image | `grep '@sha256:' Dockerfile`; a `USER` line; `trivy image` |
| Pinned Actions | `.github/workflows/` | every action pinned to a commit SHA, never a mutable tag | `pinact` or `zizmor`; a grep for `@v[0-9]` |
| Accessibility | a frontend | the UI is usable without a mouse or a screen | an axe run on the rendered pages |
| Licence, SBOM, signing | something published or distributed | who may use it, what is in it, that it is what it claims | `LICENSE` exists; `syft`; `cosign` |
| Minimum dependency age | dependencies and a CI | a version younger than seven days is not taken | Renovate `minimumReleaseAge` or `depsguard` |
| Atomic write | the program writes a file it reads back — a save file, a cache, a configuration | a crash mid-write leaves the previous file intact, and a format can be told apart from its successors | write to a temporary file and rename over the target; a version field in the format; the story's test kills the write halfway |

## On request

Costly or narrow; activated only by a requirement that names them.

| Item | When | Typical command |
|---|---|---|
| Fuzzing | a parser, a protocol, a file format | `cargo fuzz` · `afl-fuzz` · `go test -fuzz` |
| Benchmarks | a stated performance requirement | `hyperfine` · `wrk` · `vegeta` · `go test -bench` |
| Coverage threshold | a team policy that names a number | the test runner's coverage flag against the number |
| Mutation testing | a suite whose strength is in question | `cargo-mutants` · `stryker` |

## The legend line

```
- Q2: Lint — `golangci-lint run ./...` exits 0
- Q7: Dependency vulnerabilities — `osv-scanner .` reports none (tool: installed; `trivy` absent)
- Q12: Contract tests — the three frontends validate against `openapi.yaml` (request: three consumers)
```

Number in catalog order, one command per line, the reason on the line when the item is a context or on-request one. A sub-task that exercises an item cites it — `- Quality: Q2, Q7` beside `Requirements:`. The Quality Gates section of `tasks.md` then carries one box per line, `- [ ] Q2 — Lint: golangci-lint run ./... exits 0`, after the five fixed gates, and validate settles each by running its command ([validate-mode.md](validate-mode.md)). `cross-reference.sh` reports the legend's coverage: a `Qn` no sub-task cites is an orphan; a cited `Qn` the legend does not declare is a phantom.

**To a layperson the legend is rendered as the checks that were run**, each named by what it checked — "I checked the code for known mistakes", "I checked the libraries for known security problems" — never by identifier ([plain-register.md](plain-register.md)).
