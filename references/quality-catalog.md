# Quality Catalog

The checks a piece of software is expected to carry, in three tiers, and how the Epic decides which of them a story activates. It is the source that the `## Quality` block of the constitution ([init-mode.md](init-mode.md)), the `## Quality Requirements` legend of a story ([requirements.md](requirements.md)) and the generated Quality Gates of `tasks.md` ([tasks.md](tasks.md#generated-quality-gates)) all draw from: each names an item by its row here.

## How the set is chosen

1. **The constitution's `## Quality` block** is the project's default legend: the always tier, plus the context items init's scan detected. Written once by init, read by every story.
2. **The Analyst's scan** (Function 1, [analyst.md](../agents/analyst.md)) reports which context signals the tree carries — a `Dockerfile`, a `.github/workflows/` directory, a database configuration, an HTTP surface, a UI — and which always-tier tools the tree is already configured for.
3. **The request** adds what the constitution could not know: an API consumed by more than one client activates contract tests; a stated performance requirement activates a benchmark.
4. **The story's legend** is the result: `## Quality Requirements`, one line per active item, numbered `Q1`…`Qn` in the order of this catalog, each with the command that proves it on this project. A Fast story, which has no `story.md`, carries the legend at the top of `tasks.md`.

**The engineering level bounds the set** ([engineering-level.md](engineering-level.md)): `experiment` activates the **security floor** below and nothing else; `tool` activates the always tier; `project` adds every context item whose signal the tree or the request carries; `product` adds the CI-shaped context items — pinned Actions, minimum dependency age, licence, SBOM and signing — without waiting for a signal, and the on-request tier when a requirement names it. The four steps above choose inside that bound.

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
| Dependency vulnerabilities | no known CVE in the dependency list (SCA) — **a project with no dependencies satisfies this item**: zero dependencies is zero CVEs | `trivy fs .` · `osv-scanner .` · `cargo audit` · `govulncheck ./...` |
| Secrets | no credential in the tree or the history | `gitleaks detect` |
| README | how to run and how to test, in the repository | the two commands the README names exist and run |
| `.gitignore` and `.editorconfig` | generated files stay out; indentation is agreed | both files exist; `git status --short` is clean after a build |
| Supported and declared runtime | the runtime is a supported release with no known vulnerability — an LTS or the current widely-used stable, **whichever is clean** — and the project declares it: `engines` in `package.json`, the `go` directive of `go.mod`, `requires-python`, `.tool-versions` | the declaration exists and names a supported version; `node --version` · `go version` against the vendor's support table |
| Dependencies justified and current | every dependency has a one-line reason the standard library or the code already there was not enough, recorded where the choice was made, and is a current release | the manifest's list against the story's `## Constraints` or the design's decisions; `npm outdated` · `go list -m -u all` · `pip list --outdated` |

### The security floor — four items no level drops

**`experiment` is the only level that activates nothing else, and it still activates these four.** A throwaway is thrown away; the machine it ran on is not, and neither is the account whose token it carried.

| Floor item | Why it survives every level | Typical command |
|---|---|---|
| Supported and declared runtime | a program is only as safe as the interpreter under it — a hello world on an end-of-life runtime is vulnerable before its first line, because the environment is the hole. **Prefer the LTS; take the current widely-used stable instead when the LTS is the one carrying a known vulnerability** | the declaration exists; `node --version` · `go version` against the vendor's support table, then the CVE scanner against that version |
| Secrets | a credential leaked from a script leaks exactly as far as one leaked from a product | `gitleaks detect` |
| README | a program nobody can run is not a program you can "go on using exactly as it is" — the level's own promise. Two lines: how to run it, how to check it | the commands the README names exist and run |
| Dependency vulnerabilities (SCA) | a malicious or vulnerable package does not ask what the project's engineering level is | `trivy fs .` · `cargo audit` · `govulncheck ./...` — see the empty-manifest note below |

**No dependencies is a verdict, not a failure.** A project that declares none satisfies the SCA item outright, and that is the *common* case at `experiment`, not the exception. Some scanners disagree with their own exit code: measured 2026-09-19, `osv-scanner .` on a zero-dependency Node project exits **128** with `no package sources found` — an error, where the honest answer is "nothing to report". Pick a tool that gives the verdict (`trivy fs .` does), or record `no dependencies` as the result and move on. **A story is never failed for having nothing to scan.**

The four are chosen as much for their price as for their weight: **one command or one file each, no checker configuration, seconds to run.** A floor that cost minutes would be argued with; this one is cheaper than the argument. The README is the only one that is written rather than run, and it is here for the same reason as the rest: `experiment` promises the thing stays usable as it is, and a program whose run command lives only in a chat transcript does not.

**The floor is checked, not asked for.** `validate-story.sh` reads the Quality Gates section of `tasks.md` and reports, as an **error**, every floor item that has no gate — so a story that skipped one fails validation instead of passing quietly. It matches the item's name, never a particular command, because the command is the project's own: `trivy fs .`, `cargo audit` and `govulncheck ./...` all prove the SCA item. The check is gated on a declared `engineering:` level, this file's rule for every field the plugin added rather than inherited — fail-open on absence, fail-closed on a value present — so a story written before 0.7.0 validates exactly as it did. **Measured 2026-09-19, before the check existed:** four of fourteen Epic arms in a seven-language matrix dropped floor items — one dropped the README, the secrets scan *and* the SCA together — and all four validated clean. A floor nothing verifies is a request.

Everything else in this catalog stays bound by the level.

**At `tool`, the tier is paid with defaults — no configuration file.** Every always item stays active, and every one is proved by **one command**: whatever the checker needs rides on the command line (`npx tsc --noEmit --allowJs --checkJs src`), and the command is recorded where the project already records commands — a `scripts` entry, a `Makefile` target, the README. **A new configuration file for a checker is a `project` cost, not a `tool` cost.** Measured on 2026-09-17: a beginner's Pokédex at `tool` wrote 28 files, of which seven were toolchain configuration and five were the Epic's own artifacts, and closed at 11× its control where the level promises 2–3× and the owner's rule allows 5× ([engineering-level.md](engineering-level.md)). Defaults buy the same guarantee for one line instead of one file; what they give up is that the next person's run may disagree with yours, which is precisely what a level with no other dependants can afford. Files that *are* the deliverable — the README, `.gitignore`, `.editorconfig`, the lockfile, the runtime declaration — are written at every level: they are the item, not its configuration.

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
