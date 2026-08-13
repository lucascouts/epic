# Changelog

All notable changes to the Epic plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release notes the **minimum Claude Code version** required to use the new
capabilities introduced in that version. Earlier Claude Code versions degrade
gracefully (see README "Prerequisites").

## [Unreleased]

### Fixed

- **The interrupted-run completion is offered again, instead of just happening**
  (`scripts/supersede-story.sh`, `references/supersede-mode.md`). Wiring
  supersede behind a script had traded a prompt for an assumption: re-invoking
  `supersede NNN --by MMM` over a run that died mid-write finished it
  unconditionally, while the requirement says the system SHALL *offer* to
  complete. An operator who re-ran the command might not know a prior run was
  interrupted at all, so the second invocation carried no informed consent to
  finish a half-applied write.
  - The script now **classifies and stops**: a finishable interrupted state
    returns exit 1 with `status: "recovery-offer"`, a `reason` naming exactly
    what remains, and `banner_written: false`, `closed_subtasks: 0`,
    `artifacts_flipped: []`. **Nothing is written** — the artifacts are
    byte-identical across the offering run, which is the whole content of
    "offer".
  - **`--complete-interrupted`** authorizes the completion, and unlocks that one
    arm only: on a fresh story it changes nothing, and it can never turn a
    refusal into a completion or write a second banner.
  - The `[y/n]` and its headless branch live with the caller, exactly as the
    archive offer does. A headless session logs the offer and stops rather than
    answering on the user's behalf.
  - Exit 1 has always been documented as "refused (matrix) or **recovery
    declined**". There was no declined path until now; declining is simply not
    re-invoking with the flag, so that contract is accurate for the first time.

- **A sub-task added by `stories refine` never reached the step that records its
  Red.** Phase 3 is where the Test Advisor authors a test per `Unit`/
  `Integration`/`E2E` sub-task, confirms it fails, and records that in
  `.draft/red-evidence.yaml`. Refine is the only mode that can add a sub-task to
  a story whose Phase 3 has already run, and it stopped at propagation — so a
  refinement could ship a sub-task carrying a `Tests:` field with no authored
  test and no Red entry, and every consumer downstream was written assuming
  Phase 3 had covered the whole task list.
  - `references/refine-mode.md` gains the producing step: each added sub-task
    with a non-`None` `Tests:` field goes through the Test Advisor before the
    status census, appending to `.draft/red-evidence.yaml` rather than
    rewriting it, with `E2E` deferring its Red exactly as in Phase 3. A Red
    that cannot be established is recorded as a deviation instead of being
    invented or silently dropped.
  - `references/run-mode.md`'s materialization step gains the guard: a pending
    sub-task with a non-`None` `Tests:` field, no file under
    `.draft/authored-tests/` and no Red entry stops the Run by number rather
    than executing as if it were test-first. Copying what exists cannot see
    what is absent, so the check is stated over the plan, not over the tree.
  - `agents/auditor.md` and `references/validate-mode.md` had both phrased the
    invariant as *"every sub-task **with a pre-authored test** has an
    entry"* — a quantifier over the artifacts, which excludes precisely the
    sub-task that has no artifact. Both now quantify over the `Tests:` field
    and report a missing authored test as a finding distinct from a missing
    entry.

  Found by measurement rather than review: story `006`'s sub-task 12.3 was
  refine-added, shipped seven bats cases, and carries no `12.x` entry in its Red
  register at all.

### Added

- **Git-aware story lifecycle** (story `006-git-aware-lifecycle`). Epic can now
  tell whether a finished story's work ever reached the main branch, and can
  retire a story in favour of its replacement as a first-class operation.
  - **`scripts/story-git-status.sh`** — a new read-only detector. It emits JSON
    (`{story, main_branch, integrated, evidence, checked_at}`) from two kinds of
    git evidence: a merged `feat/NNN-*` branch (`branch-merged`), and a commit
    subject reachable from the main branch carrying the story's `(NNN)` token or
    its `NNN-slug` (`message-ref`). A bare number never counts as evidence.
    The evidence rules run in both directions. One merged branch is reported
    **once**, however many refs point at it; and two branches are never
    reported as one — a remote-tracking ref folds into a like-named local
    branch only when it is genuinely that branch's mirror, meaning its
    configured upstream or the same commit, so a fork's branch that merely
    shares a name keeps its own entry. The reported detail always names a ref
    that is itself merged, and two entries denoting different branches always
    carry details that can be told apart, so a consumer counting distinct
    details never reads two branches as one. And when a ref's remote cannot be
    told apart from its branch — a repository configuring remotes named both
    `a` and `a/b` — the detector reports the branches separately rather than
    guessing where the remote name ends and silently dropping one of them.
    **The main branch is resolved from the ref's own full path**, never from
    git's short spelling of it. That short spelling is *ambiguity-aware*: it
    changes as soon as any unrelated ref claims the same name. So a stray
    branch or tag called `origin/main` used to corrupt both the reported
    `main_branch` and the revision the evidence was searched on, reporting an
    integrated story as un-integrated and putting the mangled name into the
    validate warning's text. Adding an unrelated ref now changes neither
    answer.
    And **"not integrated" is now only ever said about a story that was
    actually checked.** Resolving the main branch answers two separate
    questions — what it is *called*, and which revision to search — and a
    repository can answer the first while the second points at nothing: a
    `git fetch --prune` that deletes `origin/main` leaves the pointer naming it
    behind. Both evidence searches then fail, and the empty result used to be
    reported as a finding, so validate warned about a story nothing had managed
    to look at. That case now reports the integration as **unknown**, which
    every consumer passes over in silence, while still reporting the branch
    name it did resolve.
    Everything is **evaluated live and stored nowhere** — no commit SHA, branch
    name or merge-base is ever written into an artifact, so the answer can never
    go stale. A project that is not a git repo, or has no main branch that can
    be searched, degrades silently: no annotation, no warning, no error.
  - **`references/list-mode.md`** and **`references/validate-mode.md`** — the
    signal is **surfaced, never enforced**. LIST annotates the status cell of
    each `done` / `validated` story (skipped above 50 stories unless the command
    is `stories full`, since each annotation costs one git evaluation), and a
    passing validate appends an integration warning before anything acts on the
    verdict. Neither changes a verdict, a status write or an exit code, and
    neither gates the archive.
  - **`/epic:epic stories supersede NNN --by MMM`** — a new first-class
    operation (**`references/supersede-mode.md`**, routed from
    **`skills/epic/SKILL.md`**, listed in **`README.md`**). It prepends a
    standardized ⛔ banner to `NNN` carrying the date, the replacement story, a
    one-line rationale and one remap row per open sub-task; writes
    `status: superseded` plus the machine-readable companion
    `superseded-by: MMM` into every `NNN` artifact; closes each open sub-task as
    `[~] (superseded-by: MMM)`; regenerates the index; and offers the archive on
    the spot. `MMM` must already exist, so a typo in `--by` can never mint a
    story. A story that already carries a banner gets one of three answers, and
    the banner is written at most once whichever it is: a re-run over a
    **completed** supersede refuses, an **interrupted** one is offered
    completion of only its remaining steps, and a story whose frontmatter was
    written while its scope was still open — a shape this command cannot
    produce — refuses and says so rather than being offered a completion
    supersede could not honestly perform.
    - **The verbatim rule is stated rather than assumed** (`references/supersede-mode.md`,
      new *The verbatim rule* section). The mode tells the session to surface a
      refusal's `reason` verbatim; it now says what "verbatim" permits — a
      `Refused: ` lead-in and a closing full stop are the session's own
      presentation, and everything between them is the script's text, the story
      slug included. The worked example previously rendered `story 042` where
      the JSON says `story 042-legacy-import`, dropping exactly the token that
      distinguishes two story directories sharing a number; the example now
      quotes the reason whole.
  - **`references/tasks.md`** — commit guidance gains the story anchor the
    detection reads: `type(NNN): subject` for commits, `feat/NNN-slug` for
    branches. A recommendation, not an enforcement — nothing gates on the shape.
  - **`scripts/story-git-status.sh` JSON escaping** — the emitter escapes the
    full C0/C1 control range as `\uXXXX`, so a control character in a commit
    subject can no longer make the emitted document unparseable by `jq`.
- **Supersede and the integration surfacing gained entry points**
  (**`scripts/supersede-story.sh`**, **`scripts/render-integration.sh`**). Both
  operations were specified as orchestrator prose, which meant no test could
  drive them and every claim about their behaviour rested on reading. The steps
  that **write to artifacts** — the refusal matrix, the banner and its
  idempotence, the remap rows, the sub-task closures, the `status:` /
  `superseded-by:` writes, and the interrupted-run classification — now live in
  a script with `archive-story.sh`'s exit conventions — `0` superseded, `1`
  refused, `2` invalid input — and one JSON object on stdout on every path that
  reaches a verdict. It is **silent on stderr** wherever it emits JSON, unlike
  `archive-story.sh`: a diagnostic beside the object breaks any caller that
  pipes stdout into `jq`, and the supersede *conversation* belongs to the
  orchestrator, which reads `reason` out of the report and says it in the
  session's own voice. The steps that are **decisions** stay a conversation: the
  rationale, the remap targets and the archive offer are inputs, not behaviour.
  The LIST annotation and the validate warning are a pure function of the
  detector's JSON, so they are a script too — one that exits `0` on every path,
  because a renderer that can fail lets a caller turn a warning into a verdict.
- **Those entry points are now on the path the commands take.** They shipped
  wired to nothing: `references/supersede-mode.md`, `references/list-mode.md`
  and `references/validate-mode.md` still described the behaviour in prose, so
  the copy the suite exercised was not the copy the command ran. All three now
  **invoke** the scripts, and the prose tables they used to render from are
  demoted to documentation of what the scripts emit. **One user-visible
  behaviour changes with it, and it is a loss:** completing an interrupted
  supersede used to be offered, because the orchestrator performed those steps
  by hand; the script completed unconditionally on re-invocation instead, and
  had no prompt anywhere. **That loss is repaired below in this same release —
  see "The interrupted-run completion is offered again" under Fixed.** The gap
  was recorded rather than papered over, and it was owed a fix rather than an
  amendment; it got one.
- **`scripts/validate-story.sh` — a status can no longer lag its checkboxes in
  silence.** The validator already warned when a story claimed `done` over an
  open box; the converse was *prevented* by Run mode rather than *detected* by
  anything, so when the prevention failed to fire nothing reported it — and a
  story that has finished every task while still reading `in-progress` is never
  offered the archive. A story whose census shows no open `[ ]` **and no
  deferred `[~]`** while its status reads `draft` or `in-progress` now warns. A
  **deferred** box deliberately blocks `done`, so a story resting over one is
  correct and stays silent; `superseded` and `archived` are terminal and are
  exempt for the same reason. Warning, never error.
- **`skills/epic/SKILL.md` — the 10-entry history cap no longer applies to
  artifacts that are not in git.** The rule relegates older entries to "see git
  history", and relegation needs a destination. Where `.epic/` is gitignored —
  the default this plugin ships — dropping the eleventh entry destroys it, so
  the cap is lifted there and holds unchanged wherever the artifacts are
  tracked.
- **`scripts/validate-story.sh` — a group header can no longer lie about its own
  sub-tasks.** A task group's checkbox is a claim about the sub-tasks under it,
  and nothing checked it: a group left `- [ ]` over sub-tasks that are all
  closed, or marked `- [x]` over a sub-task still open, validated clean. Both
  are now **errors**, because the rule is an identity and half an identity is
  not one. `[~]` is untouched — a group closed without doing the work is a
  legitimate third state and neither direction applies to it — and a group with
  no sub-tasks has nothing to be consistent with. Sub-tasks belong to a group by
  their number, so group `1` owns `1.1` and never `10.1`, and a **repeated**
  group number is its own error rather than one header quietly replacing the
  other. Two parts of a `tasks.md` are excluded from the check, because a group
  header is not the only thing shaped like one: **Quality Gates** (which share
  the checkbox grammar by design, so `- [ ] 3 - Coverage >= 80%` is a legal gate
  and a plausible header at once) and **fenced code blocks** (where a task list
  is an illustration, not a claim). Neither exclusion depends on how a heading
  is spelled or on locating where a section ends. The box counts everything else
  depends on are unaffected — they still cover the whole file. Where a group's
  state cannot be read at all — an unqualified
  `[~]` child, or two headers claiming one number — the check says so instead
  of guessing. The practical effect is on the archive gate: a group header left
  open over finished work reads as pending to `archive-story.sh`,
  `monitor-stale.sh` and the precompact hook alike, and the archive is the one
  that refuses on it.

## [0.3.1] — 2026-05-17

Patch release. Fixes plugin metadata so the version is shown in the Claude Code
plugin UI.

**Minimum Claude Code:** unchanged from 0.2.0.

### Fixed

- The plugin entry in `.claude-plugin/marketplace.json` was missing a `version`
  field, so the **Plugins → Installed** details view displayed no version.
  Added `"version"` to the marketplace entry, kept in sync with
  `plugin.json`.

## [0.3.0] — 2026-05-17

Feature release. Adds **Fast-mode run-time test-first execution** and an
opinionated **preferred-tooling policy** for E2E tool selection across all
modes.

**Minimum Claude Code:** unchanged from 0.2.0.

### Added

- **Fast-mode run-time test-first execution** (story `002-fast-mode-test-first`).
  A Fast sub-task carrying a `Tests` field now has its test authored and
  confirmed failing (**Red**) before implementation, then proceeds
  **Green-then-Refactor**. Test authoring happens at run time and is
  single-author — the main agent writes the test directly; no `test-advisor`
  sub-agent is involved (that pipeline remains Standard/Full only).
- **Optional Fast-only `Acceptance` field** — 1-3 observable-behaviour
  statements on a Fast sub-task. Every implementing (non-Commit) Fast sub-task
  now carries either a `Tests` field or an `Acceptance` field.
- Standard and Full mode test-first behaviour is **unchanged**.
- **`agents/executor.md`** is reused **unmodified** — its existing conditional
  six-step protocol already consumes a pre-authored test (step 5 Refactor for a
  sub-task with a pre-authored test, Tests otherwise).
- **Preferred-tooling policy** (story `003-preferred-tooling-policy`).
  - **`references/preferred-tooling.md`** — a new opinionated policy reference.
    Favorite E2E tools are `playwright` and `chrome-devtools`; optional E2E
    tools are `puppeteer`, `selenium`, `browser-use` and `stagehand`. Detection
    uses three mechanisms — MCP health-check, dependency-manifest inspection,
    and skill-list presence — and runs in **all modes, including Fast**. When no
    favorite is installed the policy is recommend-and-pause: Epic surfaces a
    recommendation and waits rather than silently selecting an optional tool.
  - **`skills/epic/SKILL.md`** — triage gains step 7b "Detect preferred
    tooling", a `### Preferred Tooling` subsection, and a `> - Tooling:`
    proposal line. The resolved selection is persisted to `design.md`'s
    `## Tooling Decisions` block.
  - **`agents/test-advisor.md`** — the Test Advisor now also authors `E2E` test
    files (in addition to `Unit` and `Integration`), using the story's selected
    E2E tool. Red-phase verification for an `E2E` test is **deferred to Run
    mode**, which confirms the deferred Red before implementation and Green
    after. The `frontend-design` skill is the preferred frontend implementation
    aid when installed.

## [0.2.0] — 2026-05-17

Feature release. Introduces **test-first execution with independent test
authorship**, narrows the plugin's purpose with an explicit scope contract,
makes MCP selection cost-aware, and adds agent-teams flag-mismatch detection.
Ships a **breaking command rename** — `/epic:task` is now `/epic:epic`.

**Minimum Claude Code:** unchanged from 0.1.5 (v2.1.105 for the full
capability surface; degraded operation on v2.1.85+).

### Changed

- **BREAKING — the command is renamed `/epic:task` → `/epic:epic`.** The skill
  directory moved `skills/task/` → `skills/epic/`, and every reference across
  docs, `references/*`, evals, monitors and output styles was updated. Existing
  `/epic:task` invocations no longer resolve — use `/epic:epic`.
- **`references/mcp-integration.md`** — MCP selection is now cost-aware. A
  priority order (`context7` > `brave-search` > `exa` > `tavily` > `firecrawl`)
  replaces flat detection; `perplexity` is demoted to a last-resort option and
  is no longer health-checked by default, since each query is paid.
- **`.gitignore`** — ignores the entire `.claude/` directory (local settings
  and sub-agent agent-memory), not just `.claude/settings.local.json`.

### Added

- **Test-first execution with independent test authorship** (story
  `001-test-first-execution`). Standard and Full stories now execute test-first:
  - **`agents/test-advisor.md`** — becomes a failing-test author. Gains the
    `Write` and `Bash` tools (`maxTurns` 15→30, `effort` medium→high). For each
    Standard/Full sub-task whose Tests field is Unit or Integration it authors
    one failing test into the story's `.draft/authored-tests/`, runs it to
    confirm it fails (Red), and records `.draft/red-evidence.yaml`. It receives
    the EARS requirement, Objective, Tests scenarios and — Full only — the
    `design.md` contract, but never the `ToDo` field. An unexpected-green test
    is revised up to 2 times, then escalated to the user.
  - **`agents/executor.md`** — the protocol keeps six steps, but step 5 is now
    conditional: **Refactor** for a sub-task with a pre-authored test (improve
    code while the test and validation stay green), **Tests** for one without.
    Adds a frozen-test rule (assertions immutable; imports / signature
    call-sites adjustable only for an intentional design deviation, recorded
    with `test_surface_adjusted: true`) and behavior-deviation escalation.
  - **`agents/auditor.md`** — new audit check #10: every sub-task with a
    pre-authored test must have a Red-evidence entry recorded before
    implementation.
  - **`references/run-mode.md`** — an idempotent test-materialization step
    (copies `.draft/authored-tests/**` into the real test tree, skip-and-warn
    on existing paths) and a read-only Pre-Authored Test input in the Executor
    prompt template.
  - **`references/phase-gates.md`**, **`references/validate-mode.md`**,
    **`references/tasks.md`** — orchestration prompt templates and the Tests
    field documentation updated to match the new authoring role.
- **`PURPOSE.md`** + a hard-refusal scope table in `skills/epic/SKILL.md` —
  Epic now states a single narrow purpose (create, structure and manage epics
  and their stories) and refuses out-of-scope requests (code review, refactor,
  debug, ad-hoc analysis) with a pointer to the correct Claude Code command.
- **`skills/epic/SKILL.md`** — a runtime dependency precheck for
  `AskUserQuestion` and `TaskCreate` / `TodoWrite` before Standard/Full triage,
  with explicit fallbacks and no silent degradation; frontmatter gains the
  `Task*` tools.
- **`hooks/hooks.json`** — `SessionStart` and `UserPromptSubmit` hooks
  (`hook-teams-session-start.sh`, `hook-teams-prompt-submit.sh`) that detect a
  stale `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag (set in settings but not
  active in the running session) and escalate over two prompts before
  disabling it.

## [0.1.5] — 2026-04-19

CI hotfix. Resolves three shellcheck warnings that were failing the
`shell-ci` workflow on `main` after v0.1.4. No behavioural changes to
the plugin or scripts.

**Minimum Claude Code:** unchanged from 0.1.4.

### Fixed

- **`scripts/run-evals.sh`** — SC2155: separated `local workdir`
  declaration from its command-substitution assignment so the subshell's
  exit status is no longer masked by `local`.
- **`scripts/run-evals.sh`** — SC2015: replaced
  `cd "$workdir" && claude ... || true` with an explicit
  `if cd "$workdir"; then claude ... || true; fi` block so control flow
  on `cd` failure is unambiguous.
- **`scripts/validate-story.sh`** — SC2034: removed the unused
  `HAS_DESIGN` variable. It was assigned but never read, since
  `design.md` presence is not required for structural validation.

## [0.1.4] — 2026-04-19

Documentation-only release. Introduces a dedicated `ARCHITECTURE.md` covering
the conceptual model, sub-agent pipeline, artifact contracts, hook matrix,
executor protocol, validation layers, and architectural decisions — content
previously scattered across `references/*` and inline agent prompts. No code
or behavioural changes.

**Minimum Claude Code:** unchanged from 0.1.3 (v2.1.105 for full capability
surface; degraded operation on v2.1.85+).

### Added

- **`ARCHITECTURE.md`** — design-level contributor guide at the repo root.
  Documents the Plan → Execute → Verify pipeline, which persona activates at
  each scale, artifact/frontmatter/cross-reference contracts, the hook matrix
  with per-event minimum CC versions, the executor 6-step protocol, the four
  validation layers (artifact, cross-reference, task, audit), story-directory
  lifecycle, and rationale for 9 architectural choices (bash-only scripts,
  single-skill routing, scale-adaptive modes, English-only artifacts,
  plugin-scope hooks, archive immutability via PreToolUse, agent-teams as
  opt-in, `defer` for headless commits, graceful MCP degradation).

## [0.1.3] — 2026-04-19

Adopt new Claude Code 2.1.105 capabilities across the plugin surface. All
changes are additive and backwards-compatible — older Claude Code versions
continue to work with degraded ergonomics (see README "Minimum Claude Code
version per component" table).

**Minimum Claude Code:** v2.1.105 for the full new capability surface.
Degraded operation on v2.1.85+.

### Added

- **README** — per-component minimum-version table covering conditional hooks,
  skill `effort`, `EnterWorktree.path`, plugin monitors, plugin `bin/`, output
  styles, `PermissionDenied` retry, `defer` commit gating, agent-teams,
  `--bare`, and `disableSkillShellExecution`.
- **`hooks/hooks.json`** — three new hook events:
  - `PostToolUseFailure(matcher: Bash)` → `hook-post-tool-failure.sh` (injects
    executor protocol reminder when a Bash command fails mid-story).
  - `CwdChanged` → `hook-cwd-changed.sh` (orients on `cd` into a `.epic/`
    project: surfaces story counts and constitution head).
  - `FileChanged(matcher: constitution.md)` → `hook-file-changed.sh`
    (re-surfaces constitution head when modified outside the session).
- **`hooks/hooks.json`** — `asyncRewake: true` on `TaskCompleted` so the
  validate re-run does not block the foreground.
- **`agents/auditor.md`** — `LSP` tool added; project-scoped memory declared
  for recurring scope-creep patterns and false-positive deviations.
- **`agents/analyst.md`** — project-scoped memory declared for accumulated
  pattern findings; documented `Explore` agent as a faster alternative for
  Function 1 when memory continuity is not required.
- **`skills/epic/SKILL.md`** — `AskUserQuestion` added to allowed-tools; Clarify
  Protocol reworked to use multiple-choice prompts (with legacy
  numbered-assertion fallback when the tool is unavailable). Architectural note
  documents why hooks live at plugin scope rather than skill frontmatter.
- **`references/ci-mode.md`** — typed `--json-schema` validation example for
  CI gating; `system/init` event recipe for detecting plugin load failures
  from `--output-format stream-json --verbose`.
- **`scripts/`** — `hook-cwd-changed.sh`, `hook-file-changed.sh`,
  `hook-post-tool-failure.sh`.

### Changed

- **`scripts/monitor-stale.sh`** — clarifies that the Claude Code runtime
  (not the script) is responsible for skipping plugin monitors on
  Bedrock/Vertex/Foundry and when `DISABLE_TELEMETRY` /
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are set.

## [0.1.2] — 2026-04-19

### Fixed
- **`plugin.json` userConfig schema** — install was failing with `Validation errors: userConfig.*.type: Invalid option ...` because each entry now requires `type` (one of `string` | `number` | `boolean` | `directory` | `file`) and `title`. Added both fields to all five userConfig entries and converted numeric defaults from string (`"7"`, `"3600"`) to number (`7`, `3600`).

## [0.1.1] — 2026-04-19

### Added
- **`.claude-plugin/marketplace.json`** — enables one-line install via `/plugin marketplace add lucascouts/epic` + `/plugin install epic@lucascouts`. Marketplace name: `lucascouts`; plugin `epic` sourced from the same repo (`source: "./"`).

## [0.1.0] — 2026-04-19

Initial public release. Internal pre-public history (referenced in `references/teams-mode.md` as "1.3.0 → 1.4.0") is collapsed into this release.

**Minimum Claude Code:** v2.1.105 for full capability surface (plugin monitors with `when:`, `PreCompact` hook, `EnterWorktree.path`, skill description cap of 1,536 chars, `effort` field on skills/agents). Degraded operation on v2.1.85+ (no compact recovery; conditional hooks still work; monitors absent).

### Plugin manifest (`plugin.json`)

- Top-level metadata: `name`, `version`, `description`, `author`, `license`, `homepage`, `repository`, `keywords`.
- **`userConfig`** with 5 options (all non-sensitive, exported as `CLAUDE_PLUGIN_OPTION_*` env vars):
  - `defaultScale` (string, default `"standard"`) — fallback mode when triage cannot determine complexity
  - `artifactLanguage` (string, default `"en"`) — override only if the organisation mandates non-English artifacts
  - `enableStaleMonitor` (boolean, default `false`) — opt-in for the stale-story background watcher
  - `staleThresholdDays` (number, default `7`) — days of inactivity before a story is flagged
  - `staleCheckIntervalSeconds` (number, default `3600`) — poll cadence

### Marketplace (`marketplace.json`)

- Single-plugin marketplace named `lucascouts`, sourced from the same repo (`source: "./"`).

### Skill — `/epic:epic`

- Scale-adaptive workflow with three modes (Fast / Standard / Full) and two workflow variants (Requirements-First / Design-First).
- Sub-routes: `init`, `stories`, `stories full`, `stories NNN`, `stories run NNN [--auto|--batch=N|--gate=commit]`, `stories validate NNN`, `stories refine NNN`, `stories archive NNN[-MMM]|--done`, `stories teams {status|enable|disable}`, `archive`.
- Frontmatter uses `effort: max`, `paths: [".epic/**", "tasks.md", "story.md"]`, full `allowed-tools` whitelist (incl. `EnterWorktree`/`ExitWorktree`).
- Inline shell `!` blocks for project-state context (existing stories, constitution head, git HEAD); falls back gracefully when `disableSkillShellExecution: true`.

### Sub-agents (8)

| Agent | Role | Activated for |
|---|---|---|
| `analyst` | Codebase scan, completeness checklist | Standard + Full |
| `architect` | Pattern research, gotcha capture | Full |
| `test-advisor` | Defines tests per sub-task | Standard + Full (Phase 3) |
| `reviewer` | Cross-artifact review | Full |
| `executor` | 6-step implementation protocol | Simple+ tasks (all scales) |
| `tech-reviewer` | Multi-tech boundary correctness | All scales (multi-tech) |
| `validator` | Runs validation commands | All scales |
| `auditor` | Story/design fidelity, scope creep | All scales |

All agents declare `model: inherit`, `tools` whitelist, `maxTurns`, and `effort` calibrated by role.

### Hooks (7 events, all `if:`-filtered or matcher-scoped)

- `PostToolUse(Write, if: Write(.epic/**))` → `validate-story.sh`
- `PreToolUse(Edit|Write, if: Edit/Write(.epic/archive/**))` → blocks edits to archive
- `PreToolUse(Bash, if: Bash(git commit *))` → `permissionDecision: "defer"` in CI/headless
- `PreCompact` → snapshots active story to `.draft/compact-snapshot.md` _(requires v2.1.105)_
- `SessionStart(compact)` → re-injects snapshot into context
- `SessionEnd(clear)` → cleanup
- `TaskCompleted` → re-runs validate against active story
- `PermissionDenied(matcher: mcp__.*)` → returns `{retry: true}` _(requires v2.1.89)_

### Plugin monitors (1, opt-in)

- `epic-stale-stories` (`when: on-skill-invoke:task`) — surfaces stories with no progress past `staleThresholdDays`. Requires `enableStaleMonitor: true` and Claude Code v2.1.105+.

### Output style (1, opt-in)

- `epic` style for triage proposals, phase gates, run reports, validator/auditor output. Declares `keep-coding-instructions: true` _(requires v2.1.94)_.

### `bin/` executables (PATH-exposed)

- `epic-validate` (wrapper around `validate-story.sh`)
- `epic-xref` (wrapper around `cross-reference.sh`)

_(Plugin `bin/` requires Claude Code v2.1.91+.)_

### Scripts (10)

- `validate-story.sh`, `cross-reference.sh` — validation engines (JSON output, exit 0/1/2).
- `hook-validate.sh`, `hook-archive-guard.sh`, `hook-defer-commit.sh`, `hook-precompact.sh`, `hook-session-restore.sh`, `hook-task-completed.sh`, `hook-session-end-cleanup.sh` — hook implementations.
- `monitor-stale.sh` — opt-in background watcher.
- `teams-config.sh` — manages `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag in `.claude/settings.local.json`.
- `run-evals.sh` — runs the eval suite.

### References (17 markdown files)

- Mode-specific operational guides: `init-mode.md`, `list-mode.md`, `run-mode.md`, `validate-mode.md`, `refine-mode.md`, `ci-mode.md`, `teams-mode.md`.
- Methodology: `ears-notation.md`, `requirements.md`, `design-guide.md`, `tasks.md`, `bugfix.md`, `bugfix-design.md`, `phase-gates.md`, `self-review-checklist.md`, `context-discovery.md`, `mcp-integration.md`, `constitution.md`.

### Examples & evals

- `assets/examples/`: `fast-feature.md`, `standard-feature.md`, `full-feature.md`, `bugfix-complete.md`.
- `evals/`: 6 cases + 24 trigger queries with `run-evals.sh`.

### Tests & CI

- `tests/`: `validate-story.bats`, `teams-config.bats` (bats unit tests).
- `.github/workflows/shell.yml`: shellcheck + bats + example validation.

### Agent-teams integration (experimental, opt-in)

- During Full-mode triage with 2+ independent tracks, offers `[y]/[n]/[never]` proposal to enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` _(requires v2.1.32)_.
- Teammates reuse the `executor` agent definition (one per track, in its own context).
- `/epic:epic stories teams {status|enable|disable}` for direct flag management.
- Per-project opt-out via `.epic/teams-opt-out` sentinel file.

[Unreleased]: https://github.com/lucascouts/epic/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/lucascouts/epic/releases/tag/v0.2.0
[0.1.5]: https://github.com/lucascouts/epic/releases/tag/v0.1.5
[0.1.4]: https://github.com/lucascouts/epic/releases/tag/v0.1.4
[0.1.3]: https://github.com/lucascouts/epic/releases/tag/v0.1.3
[0.1.2]: https://github.com/lucascouts/epic/releases/tag/v0.1.2
[0.1.1]: https://github.com/lucascouts/epic/releases/tag/v0.1.1
[0.1.0]: https://github.com/lucascouts/epic/releases/tag/v0.1.0
