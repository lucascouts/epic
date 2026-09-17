# Changelog

All notable changes to the Epic plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release notes the **minimum Claude Code version** required to use the new
capabilities introduced in that version. Earlier Claude Code versions degrade
gracefully (see README "Prerequisites").

## [Unreleased]

### Added

- **`RELEASING.md` — what a version cut actually involves, and the traps in
  it.** Written from the 0.5.0 and 0.6.0 cuts; every step in it has been
  executed. It names the four version sites that must agree, the CHANGELOG
  link-block repoint, the merge-commit convention this repository uses, and
  the annotated tag on the merge commit. Two traps are stated rather than left
  to be rediscovered: **`bats` must run as a normal user**, because 14 cases
  make a file unreadable and require a refusal that root cannot trigger (11 in
  `archive-story.bats`, 3 in `epic-index.bats`) — which is why `act -j bats` is
  not the faithful run — and **`Analyze`/`CodeQL` have no local equivalent**,
  the one part of a release that cannot be verified before the push.
  - It also fixes the release step the plan asked for and the repository had
    nowhere to put: **take a triage-variance sample and record the
    distribution in the release's CHANGELOG entry.** Scale instability — the
    same request drawing Fast once and Standard twice on v0.5.0 — is invisible
    to the test suite, because it is a property of a model's judgement rather
    than of a script. It is a **monitor, never a gate**: one run that disagrees
    is information, and a gate of that shape was already measured flapping
    0/30 then 5/5 against a tree with no edit at all.

- **`story-telemetry.sh` reads both sub-agent markers.** The two stream shapes
  differ and only one was handled: an interactive session transcript carries
  `isSidechain` on every assistant event, while a `claude -p` stream has no
  `isSidechain` at all and marks a child with a non-null `parent_tool_use_id`
  (measured: 135 of 358 assistant events in one `-p` run). Reading only the
  first attributed every sub-agent token to the orchestrator, silently, on
  exactly the runs where delegation is what you are trying to measure. Both are
  now read, and a case pins the `-p` shape.

- **`scripts/story-telemetry.sh` — what a story cost, without mining a
  transcript by hand.** Reads a session transcript and reports tokens and wall
  clock as one JSON object on stdout, split orchestrator vs sub-agent, with an
  optional `--since` / `--until` window for a single phase. Writes no files and
  makes no network call.
  - **Tokens, never dollars.** The transcript carries `message.usage` and no
    price; a price table shipped inside the plugin would age into a confident
    wrong answer. The reader knows the current prices.
  - **Summed per distinct `message.id`.** The transcript writes one event per
    content block and repeats the same usage on each — measured at 462 events
    for 190 messages, a 2.4x inflation. `events` and `unique_messages` are both
    emitted so the deduplication is visible rather than promised.
  - **`subagent_split_verified`** is `false` until a run actually saw an
    `isSidechain` event, so a zeroed `subagent` block reads as *none seen*
    rather than *confirmed none*. No transcript available when this was written
    had run a sub-agent, and the field says so instead of implying otherwise.
  - A malformed trailing line is skipped rather than fatal: a live session's
    transcript is being written while you read it.
  - This is the on-demand half of the planned cost telemetry. The other half —
    writing the figures into the story and surfacing them in `epic-index` —
    was **deliberately not built**: it would put the plugin back to writing
    files into the user's repository, which 0.6.0 had just stopped doing.

### Changed

- **The requester is a four-field block, and the level never changes the
  scale** (`skills/epic/SKILL.md`, `references/plain-register.md`, new
  `references/developer-register.md`). Triage records `requester.level`
  (`layperson` | `developer`, developer when unsure), `requester.persona`
  (one line ending with the evidence the reading rests on), and
  `requester.always` / `requester.never`, seeded from the level's register and
  extended from Clarify answers — "I don't know how to run a command" becomes
  a `never`. The level changes the register, the question budget, the defaults
  taken silently and the shape of a gate, and nothing else. **The 0.6.0 rule
  that held a layperson at Fast is retired**: it came from one trivial request,
  and everything that had made Standard hurt a beginner — out-of-reach
  questions, document reviews, 23k-character turns — is closed by the register,
  the budget and the defaults. A beginner who asks for something Full-shaped is
  owed Full, with its gates in one line. The plain register gains the positive
  rule it lacked — explain by one example or analogy per new concept — and the
  developer register is new: direct, with context and an example on every
  option, never the basics, and honest that nothing about it is measured yet.

## [0.6.0] — 2026-09-16

Seven commits, one through-line: **measure, then move.** A 59-minute Standard
run was decomposed first — 49% of the clock inside sub-agents, 49% in the
orchestrator, 1.9% doing the work — and a persona simulation of one beginner
was run three times against the same request. Every change below answers a
number from one of the two. Execution routes per sub-task and no longer
delegates a closed spec; a proven parallel group runs without asking; Full is
opt-in on an architectural signal; triage reads who is asking and gives a
layperson Fast, a plain register and a question budget; `ai-memory` is an
optional, detected dependency; the archive refuses a `node_modules/` tree.

Measured after, same beginner, same request, four runs: scale went from
Fast-once / Standard-twice to Fast 4/4; questions from 6–18 to 1; sub-agents
from 6–9 to 0; wall clock from 33–59 minutes to 9–15; cost from US$ 11–24 to
5–9; and every run shipped a working program with its tests green. Residual,
fixed in the last two commits and measured once: the orchestrator narrated its
test steps between tool calls, so a layperson's build turn now speaks once, at
the end.

**Minimum Claude Code:** unchanged from 0.2.0. `--serial`, the requester
profile and the memory category are prose the orchestrator follows; nothing in
the runtime moved. `subagent_type: "fork"` was measured **absent** in
`claude -p` (2.1.269 and 2.1.273) and nothing here relies on it.

### Added

- **`ai-memory` as an optional, detected dependency** (`references/mcp-integration.md`
  § Memory MCP; triage step 7a in `skills/epic/SKILL.md`; § Prior Knowledge in
  `references/context-discovery.md`; `references/run-mode.md`,
  `references/validate-mode.md`, `references/init-mode.md`; `userConfig.aiMemory`).
  One local `memory_status` call at triage — every scale, Fast included — decides
  for the whole story. When the server answers, the story is enriched at three
  points: prior knowledge before the Analyst, prior deviations and discoveries in
  every Executor's Project State, and prior structural audit findings handed to
  the Auditor as things to verify. The orchestrator writes two kinds of page from
  files that already exist — the deviation register at End of Run, structural
  audit findings after the verdict — at stable paths, so a rewrite is the
  supersession (`memory_write_page` has no `supersedes`; the path is the
  identity). When the server does not answer, nothing changes and nothing is said
  beyond one line in the proposal. Three rules are hard: memory is never evidence
  (a finding still needs the file and the line), `memory_feedback` is never
  called, and no secret is copied into a page. Sub-agents get no memory tool and
  their own `.claude/agent-memory/` stores are untouched — moving those to pages
  waits until the path-rewrite supersession has proven itself here.
- **Triage reads who is asking, and a layperson gets a plain register, a
  question budget and Fast** (`references/plain-register.md`;
  `skills/epic/SKILL.md` Triage and Clarify; `references/phase-gates.md`,
  `references/run-mode.md`, `references/preferred-tooling.md`,
  `references/init-mode.md`, `references/context-discovery.md`). Measured on a
  persona simulation of one beginner, three runs: the same request drew Fast
  once and Standard twice, and Fast served her best by every measure; the
  chat carried executor ×6, framework ×4, box ×4, commit ×8 and story ×3;
  she was asked 1 question out of her reach in Fast and 5–8 in Standard —
  how to commit on `master`, whether to version a data file, and to approve
  requirements documents she could not evaluate ("Aprovo, pode seguir",
  three times); and the same data file was gitignored in two runs and
  versioned in the third. Four changes answer those four measurements.
  - **Requester, read from the request alone, never from a question** —
    `developer` or `layperson`, `developer` when unsure. A layperson changes
    two things and nothing else: Fast is proposed and held unless they ask
    for more, and the chat switches to the plain register. Files, protocols
    and sub-agents are untouched.
  - **The plain register** — process words stay in the files and the chat
    says what happens in the requester's terms; decisions they cannot
    evaluate are taken from defaults and mentioned in one clause; a gate is
    one line, not a file review; run and show instead of "run it yourself";
    a stop promised per group is one group per turn; ~1,500 visible
    characters per turn.
  - **One question budget per story**, counted from triage to the last box
    across Clarify rounds, phase gates and run-time questions — layperson
    Fast 1 / Standard 3, developer Fast 2 / Standard 5 / Full 7. Spent
    budget means defaults and recorded assumptions, not more questions. And
    **each round is built from what the last one left open**: an
    out-of-scope answer removes its branch, a default removes its
    follow-ups, an answer in tool vocabulary re-reads the requester; when
    triage was unsure, round 1 opens with one calibration question.
  - **`## Defaults` in the constitution**, written by init whether or not
    the questions are answered — data files gitignored, tests silent in
    Fast, free text validated as text, the current branch — so the same
    request gets the same answer on every run.
- **The archive guard refuses a `node_modules/` tree, once, by directory**
  (`scripts/archive-story.sh`). Three projects in the July 2026 corpus carried
  one under `.epic/`, left by an executor's `npm install`, and every file in it
  is small enough to pass the 10 MB check on its own. The tree is now the
  offender — one violation naming the directory, its files neither scanned nor
  counted — and the guard refuses rather than deletes: nothing destructive runs
  before step 4, and a reinstallable tree is still the user's to remove.
  `--allow-heavy` archives it as it is and records the override, as for any
  other guard finding.
- **Init keeps the plugin's own litter out of the repository**
  (`references/init-mode.md`). `.epic/.gitignore` gains `node_modules/` beside
  `.draft/` and `*.wip`; and a new step, under either policy, offers — default
  yes, consent-gated, additive — to append `.claude/agent-memory/` to the root
  `.gitignore`: Claude Code writes the auditor's and analyst's project memory
  there, and a persona simulation found those notes untracked and unignored in
  a beginner's repo. Headless never edits; it logs the recommendation.

### Changed

- **A proven parallel group runs without asking** (`references/run-mode.md`).
  Detection's fourth step used to ask "Execute in parallel? [y/n]", and Run
  mode's first rule was "Sequential by default" — so the measured story ran its
  nine executors in series while the platform allows twenty. A group that
  passed the three checks (satisfied dependencies, no dependency inside the
  group, no shared file) is proven independent and is now *stated* in the
  execution plan, not asked; everything not proven runs in order as before.
  `--serial` is the one way to decline, for the whole run. The question also
  cost a round of the question budget on every run that had a group.
- **The story's evidence stays in `.draft/` by decision, and init says so**
  (`references/init-mode.md`, README). `deviations.yaml`, `red-evidence.yaml`
  and the validation and audit reports are a working record; their durable
  forms are the archive's summary and, where `ai-memory` is detected, the pages
  the orchestrator writes. Decided, not defaulted — the prior wording left it
  looking like an omission.

- **Execution routing is decided per sub-task, not read off the parent's
  `Complexity`** (`references/run-mode.md`). `Complexity` is a parent-task field
  — `references/tasks.md` makes it *Always on parent* and merely optional on the
  sub-task — so the old Execution Threshold sent every sub-task of a `Moderate`
  parent to its own Executor, the ones whose spec was already closed included.
  That is rediscovery sold as isolation: the sub-agent starts empty and re-reads
  what the orchestrator is already holding. The threshold now reads the
  sub-task's own body and takes the first matching route — verification always
  delegates (the fresh context *is* the product), exploration delegates (the
  throwaway reading dies with the sub-agent), a closed spec runs inline, and
  anything that does not say enough to route itself delegates by default.
  `Complexity` keeps the two columns the route does not decide, Tech Review and
  Context Gathering. The route changes *where* the work happens and never what
  it is: inline still runs the six steps, still gathers context when a Context
  field exists, and still closes its box through `close-subtask.sh`.
  - The two sub-sections are renamed to the routes they now describe —
    **Inline Route — Main Agent** and **Delegated Route — Executor Sub-agent**.
    "Trivial Complexity" had stopped being true of either.
- **Parallel detection runs at both levels, parent tasks and sibling sub-tasks**
  (`references/run-mode.md`). Building the graph from the parent `Dependencies`
  field alone looks for parallelism one layer above where the work is: a run
  executes sub-tasks, and a parent whose siblings are sequential can still hold
  independent sub-tasks. **Numbering is not dependency** — 2.1 and 2.2 are in
  order because a list has an order, and are dependent only when one says so.
  File conflicts stay the disqualifier, and are the usual one at this
  granularity.
- **Full is opt-in on an architectural signal, not on file count**
  (`skills/epic/SKILL.md`). The `Moderate` row of the complexity table now
  recommends **Standard**; Full asks for at least one stated signal — a new
  contract between systems, a data migration, a cross-cutting change with no
  established pattern, 2+ tracks that must be designed to fit together, or the
  user asking for it. A design doc earns its cost only when there is a decision
  to record before the code exists, and file count measures typing rather than
  design risk.
  - **Downgrade is now as legitimate as upgrade.** The upgrade rule on the
    `Simple` row gains its mirror: when clarify resolves the open questions and
    no architectural signal survives, the lighter mode is *proposed*, naming what
    the user gives up. Never silent, and never a feature demoted to a spike.
  - The triage examples in `output-styles/epic.md` and
    `references/batch-create.md` name the signal that earns their `Full`, instead
    of letting `Moderate` read as the reason.

## [0.5.0] — 2026-09-15

Twelve stories (`010`–`021`). The through-line is **one deterministic writer for
the checkbox grammar**, and then making everything that *reads* that grammar
honest: verdicts land as files instead of chat text, assertions pin direction
instead of co-occurrence, and the eval harness reports what it actually measured.

**Minimum Claude Code:** unchanged from 0.2.0. `scripts/run-evals.sh` is dev
tooling and needs a `--plugin-dir`-capable CLI; nothing in the plugin runtime
does.

### Added

- **`scripts/close-subtask.sh` — the one sanctioned writer of the checkbox
  grammar** (story `010-executor-owns-marking`). Closing a finished sub-task used
  to cost model output in the most expensive context there is: the orchestrator
  hand-edited `tasks.md`, re-read it for the census, and hand-ran the status
  transition. One invocation now marks the box, closes the parent group header
  when no open child remains, takes the census, applies run-mode's four status
  rules, stamps `status:` in every artifact carrying frontmatter, self-invokes
  `validate-story.sh`, and reports all of it as one JSON object. Its box regex
  and qualifier grammar are the existing readers' own, copied verbatim, so it is
  a *writer of* that grammar rather than a variant of it.
  - **`--fulfill "<evidence>"`** (story `021`) — the one exit from a
    `[~] (deferred: …)`. The box becomes `[x]` carrying both the evidence and the
    original reason. The line shape is forced by measurement, not taste: the
    canonical qualifier regex every reader shares matches the obvious
    `(was deferred: …)` spelling, which would have seven scripts go on counting a
    *closed* box as an outstanding deferral, and the story could never reach
    `done`.
  - **`--restate "<reason>"`** — the box does not move; only its reason does.
    For a deferral that still stands after its explanation stopped being true.
    Census unchanged, no status transition, group header untouched. It is also
    the only tool that can repair a `(deferred: )` carrying no reason at all.
  - Both accept **only** `[~]` carrying `deferred:` and refuse every other state
    by naming what they found. A terminal qualifier records a decision already
    taken, and neither flag will overwrite one.

- **Verdicts are artifacts, not chat text** (story `011-reports-by-artifact`).
  The validator and auditor write `.draft/validation-report.yaml` and
  `.draft/audit-report.yaml`; the validate flow concludes from those files. A
  sub-agent that ends on intermediate prose no longer loses the whole suite it
  just ran. The tech-reviewer gains `Bash` under a measurement-only protocol —
  its findings are measured rather than argued.

- **`stories create --batch <doc>`** (story `013-quick-create`) — one interview,
  N stories, a per-story verdict. Both create flows now draw numbers from one
  tested allocator (`scripts/next-story-number.sh`), so two stories can no longer
  claim the same number.

- **EARS form lint, `satisfied-by`, and an authoring ceiling** (story
  `014-ears-lint-authoring-ceiling`). An unlabeled acceptance criterion is an
  error — nothing downstream can trace it. A criterion carrying more than one
  `SHALL`, or a trigger word outside a code span, warns. `satisfied-by` lets a
  legitimately non-code requirement close without a task, accepted by both orphan
  sites. A plan passing **32 KB or 60 checkboxes** warns at Phase 3, at
  validation, and in batch create — a warning at every site, never a block.

- **`scripts/migrate-story.sh`** (story `015-migrate-commit-field`) — a
  dry-run-first normalizer that converts legacy stories, fence-aware, with its
  proof embedded. Five corpus variants round-trip through one apply to a clean
  validate.

- **`scripts/trigger-detect.sh`** (story `021`) — the single scorer of a trigger
  run. It reads a transcript and answers `triggered` / `not-triggered` / `error`,
  so a run that could not be measured never scores as one that did not fire.

- **`evals/README.md`** — the measurement methodology, which had no home.

### Changed

- **`Commit:` is a group field** (story `015`), not a per-sub-task one — in the
  template, in the ordering, and in every consumer copy. A group commits once,
  after its last box closes.

- **The skill `description` names every routed mode** (story `021`). `init`,
  `migrate`, `batch`, `archive`, `supersede` and `teams` were routable by the
  cascade and absent from the description, so they were unreachable by the
  phrasings they introduced. `tests/skill-description-coverage.bats` now fails on
  **either** side of a divergence — a declared term missing from the description,
  or a cascade arm with no row in the table.

- **`scripts/run-evals.sh` grades this working tree, and says how much it
  measured** (story `021`). It refuses outright when an installed plugin of the
  same name is enabled, because `--plugin-dir` does not outrank it and the suite
  would silently grade the cache. It reports `ran: N case(s), M trigger(s)`, so a
  suite that measured nothing can no longer read as a suite that passed.

- **The validator runs at `effort: medium`** (story `012-adaptive-effort`), down
  from `high`. Its work is majority-mechanical — running scripts, comparing
  outputs — while semantic judgment stays with the auditor at `max`. The full
  per-agent policy is pinned by a test, so future edits are deliberate rather
  than drift.

- **A trigger eval is no longer treated as a gate.** Measured on this repo, same
  commit and same `SKILL.md` md5: one query read **0/30** across two weeks and
  then **5/5** ten hours later, while another went **3/3 → 1/5** in the same
  window. One rose while the other fell — a routing change on the service side,
  not noise. Any gate of the form *"query X must fire"* flaps with no code
  changing, and *"no query that fired before may fail now"* fails identically
  against a tree carrying **no edit at all**: it measures the calendar, not the
  diff. Assertions belong in a deterministic lint; trigger evals belong in
  monitoring. `evals/README.md` carries the full record.

### Fixed

- **Tests that asserted nothing** (stories `019-pin-assertion-polarity`,
  `020-close-the-polarity-census`). An assertion matching *co-occurrence* passes
  whichever direction the text runs, and a negated assertion outside last
  position is inert — it cannot fail. Assertions now pin direction, and a census
  lint with a **measured allowlist** rejects a negation that cannot fail. The
  allowlist is data the suite derives, so a row naming a pattern the tree no
  longer contains is itself an error.

- **Facts an audit found stated but unmeasured** (stories `016`, `017`, `018`).
  The consumer roster became data the suite derives rather than a hand-kept list
  — an enumerated list silently drops every entry added after it.

- **A tasks-only story rendered `—` for its status.** `epic-index.sh` promised a
  fallback in its comment and only implemented it for `scale`, so every Fast
  story showed no status at all.

- **An EARS keyword is uppercase, and the check now listens for it.**

- **The legacy nudge counts what `migrate` actually converts**, not what it was
  assumed to.

- **The `shellcheck` CI job passes on the runner's shellcheck**, not only on the
  host's. Found by running the workflow locally with `act` before the branch's
  first push: the host's 0.11.0 was clean, the runner's apt 0.9.0 was not, and
  the job exits 1 even at info severity. `run-evals.sh`'s `cd … && claude … ||
  true` is now an explicit brace group — same semantics, no directive, clean on
  both versions.

## [0.4.0] — 2026-08-13

Feature release. Adds a **git-aware story lifecycle** — Epic can now tell
whether a finished story's work ever reached the main branch, and can retire a
story in favour of its replacement as a first-class operation — and moves
**supersede** and the **integration surfacing** out of orchestrator prose into
scripts a test suite can drive. Also tightens `validate` with two consistency
checks that had no detector at all.

**Minimum Claude Code:** unchanged from 0.2.0.

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

[Unreleased]: https://github.com/lucascouts/epic/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/lucascouts/epic/releases/tag/v0.6.0
[0.5.0]: https://github.com/lucascouts/epic/releases/tag/v0.5.0
[0.4.0]: https://github.com/lucascouts/epic/releases/tag/v0.4.0
[0.3.1]: https://github.com/lucascouts/epic/releases/tag/v0.3.1
[0.3.0]: https://github.com/lucascouts/epic/releases/tag/v0.3.0
[0.2.0]: https://github.com/lucascouts/epic/releases/tag/v0.2.0
[0.1.5]: https://github.com/lucascouts/epic/releases/tag/v0.1.5
[0.1.4]: https://github.com/lucascouts/epic/releases/tag/v0.1.4
[0.1.3]: https://github.com/lucascouts/epic/releases/tag/v0.1.3
[0.1.2]: https://github.com/lucascouts/epic/releases/tag/v0.1.2
[0.1.1]: https://github.com/lucascouts/epic/releases/tag/v0.1.1
[0.1.0]: https://github.com/lucascouts/epic/releases/tag/v0.1.0
