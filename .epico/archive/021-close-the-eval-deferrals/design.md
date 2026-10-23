---
story: close-the-eval-deferrals
type: bugfix
scale: full
version: 1
created: 2026-08-29
status: archived
---

# Design - Bugfix: The trigger-eval suite measured the opposite of what it claimed

## Root Cause Analysis

Three independent defects, one shared cause.

### Defect 1 — the detector matched the failure, not the success

- **Symptom:** every `should_trigger` query reports `triggered=false`, including
  `list my stories`, which fires reliably when run by hand.
- **Root cause:** `run_trigger` greps the transcript for
  `"skill":"epic:epic"` while asking the CLI for `--output-format json`. That
  format returns the final result alone — the `--help` text calls it "single
  result" — and carries no tool call. The only path that puts `tool_input` into
  a `json` payload is a **failed** invocation, whose error object echoes the
  call. So the assertion answered `true` exactly when the skill did not run, and
  `false` when it did.
- **Why it wasn't caught:** three defects upstream guaranteed the suite never
  produced a green it could be judged by. `--bare` refuses OAuth by design, so
  on a subscription host every case died on authentication before reaching the
  detector; `Skill` was missing from `--allowedTools`, so an invocation that got
  past that was denied; and `claude -p` inherited the `while read` loop's stdin,
  so the suite consumed its own input and measured one query out of 27. A
  detector is only wrong once something reaches it.

### Defect 2 — a routing mode reached the cascade without reaching the description

- **Symptom:** `stories create --batch <doc>` and `can you create an epic for
  the user onboarding flow?` fire 0 out of 3, while a positive control fires 3
  out of 3.
- **Root cause:** stories 013 and 015 added modes to the routing cascade and to
  `argument-hint`, but not to the skill `description`. Measured on the
  description in isolation (98 words): `batch` 0, `migrate` 0, `epic` 1 — and
  that one occurrence sits inside `even without saying "epic" or "story"
  explicitly`, a negation. The cascade decides where a request goes **after**
  the skill is chosen; the description decides **whether** it is chosen. A mode
  present only in the cascade is unreachable by the phrasing it introduced.
- **Why it wasn't caught:** the eval that would have caught it is the one both
  stories deferred, for the reasons defect 1 explains. Nothing else in the tree
  compares the cascade against the description.
- **Wider than the trigger evals could see (measured in Phase 3).** The coverage
  lint, run against `SKILL.md` at `5e8406b`, reports **six** modes absent from
  the description, not two:

  ```
  init  migrate  batch  archive  supersede  teams
  ```

  `batch` and `migrate` were the known pair because they are the only two with
  trigger queries — the evals could only report what someone had written a query
  for. The other four were never measured at all: no query exercises `init`,
  `archive`, `supersede` or `teams`, so their absence produced no signal
  anywhere. This is the same shape as the defect one level down — a gap is
  invisible until something looks for it — and it is why R3.3 checks the cascade
  against the description rather than checking the description against the
  trigger set.

  **Two consequences for the plan.** Sub-task 3.3 writes six vocabularies rather
  than two; and the dilution risk in the Side Effects table grows with it, since
  every added clause lengthens the description. The mitigation does not change —
  regression test 1 compares the full roster before and after — but it now has
  more to catch, and 3.4 is correspondingly more likely to block. Four of the six
  additions will have **no trigger query to prove them**: the lint is their only
  evidence, and that limit is stated here rather than discovered later.

### Defect 3 — a fulfilled deferral had nowhere to go

- **Symptom:** `close-subtask.sh 015 4.1` exits 1 with `already closed`;
  `tasks.md` is byte-identical.
- **Root cause:** the grammar models a deferral as a **closed** box, which is
  correct for the census, and every writer treats closed as terminal.
  `close-subtask.sh` refuses to re-close (R1.3); `REFINE` "never writes a
  checkbox"; reopening "is defined by `[ ]`, and only by `[ ]`". The state
  machine has an edge into `[~] (deferred:)` and none out of it.
- **Why it wasn't caught:** story 010 built the writer around the states a run
  produces. A deferral being *discharged later* is not a state a run produces —
  it arrives from outside, weeks later, which is exactly the case nobody had
  yet.

**The shared cause:** each defect is a guard that could not fail. A detector
that inverts, a description nothing checks, a state nothing can leave. This is
the same class stories 019 and 020 closed inside `tests/`, appearing one level
out — in the harness, the manifest, and the engine.

## Affected Components

| Component | Role in Bug | Change Needed |
|---|---|---|
| `scripts/run-evals.sh` | runs the suite, scores each query | drop `--bare`; grant `Skill`; detach stdin; delegate scoring; report denominator; accept a query filter and a run count; refuse when a same-named plugin is enabled |
| `scripts/trigger-detect.sh` | **new** — the scoring decision, alone | reads a transcript on stdin, emits one JSON verdict of three |
| `tests/fixtures/trigger/*.jsonl` | **new** — recorded transcripts | five cases, including a mutant, so the detector is exercised without a model call |
| `tests/trigger-detect.bats` | **new** — proves the detector | one case per fixture, plus the mutant red |
| `skills/epic/SKILL.md` | decides whether the skill is offered | description gains the vocabulary of every routed mode, with affirmative examples |
| `tests/skill-description-coverage.bats` | **new** — the missing guard | cascade arms vs description terms, failing on either side of the divergence |
| `scripts/close-subtask.sh` | the one writer of the checkbox grammar | a `--fulfill` path: `[~] (deferred:)` → `[x]`, carrying reason and evidence |
| `tests/close-subtask-fulfill.bats` | **new** — proves the transition | fulfil, the three refusals, and the census reaching `done` |
| `references/tasks.md` | defines the grammar | document the one transition out of a deferral |
| `references/run-mode.md` | defines who writes what | name `--fulfill` in the call table |
| `ARCHITECTURE.md` | script inventory | register the new script |

## Fix Approach

The bugfix template asks a fix touching more than three or four files to justify
itself. This one touches eleven, and the justification is that it is **three
surgical fixes that happen to share a story**, not one fix that sprawled: the
harness repair never enters `close-subtask.sh`, the description repair never
enters either script, and the engine repair never enters the harness. Splitting
them into three stories was weighed and rejected for one reason — the first two
are only provable together (a description claim needs a working detector), and
the third is what lets either result be recorded.

### 1. Move the verdict out of the harness and give it a third answer

`scripts/trigger-detect.sh` reads a `stream-json` transcript on stdin and emits
one JSON object on stdout, matching the convention `close-subtask.sh`,
`validate-story.sh` and `next-story-number.sh` already share:

```json
{"verdict": "triggered", "skill": "epic:epic", "runs_completed": true}
```

`verdict` is `triggered`, `not-triggered`, or `error`. The first two require the
terminal `{"type":"result","is_error":false}` event to be present: without it
the run did not happen, and the answer is `error` — never a pass, never a
failure. That distinction is the whole point. Today a network error scores every
`should_not_trigger` query as a pass, because "did not fire" and "did not run"
are the same `false`.

`triggered` is decided by a `Skill` tool-use event naming `epic:epic` inside an
`assistant` message. The format was recorded, not assumed:

```
{"type":"tool_use","name":"Skill","input":{"skill":"epic:epic","args":"list stories"}}
```

### 2. Repair the harness around it

Drop `--bare` (its auth model excludes every subscription host, and the
hermeticity it sells is already supplied by `--plugin-dir`). Grant `Skill`.
Redirect the CLI's stdin from `/dev/null`. Report `ran: N case(s), M
trigger(s)`. Accept a query filter and a run count, and report each query's rate
over its runs.

Add the refusal that makes a run attributable: read the plugin name from
`.claude-plugin/plugin.json`, ask `claude plugin list`, and exit 2 naming
`claude plugin disable <name>` when it is enabled. `--plugin-dir` does not
outrank an enabled plugin of the same name — measured: with the plugin disabled
and no `--plugin-dir`, no `epic:epic` event appears at all; adding
`--plugin-dir` brings this tree's skill back. Today that ordering lives in a
header comment, which is a sentence, and a sentence cannot fail.

### 3. Teach the description the modes the cascade already routes (six, measured)

Add the vocabulary of every routed mode, and at least one affirmative example
for the terms currently present only inside a negation. Then pin it:
`tests/skill-description-coverage.bats` holds a declared table of
`mode → required term(s)` and fails on **either** side of a divergence — a term
missing from the description, or a cascade arm missing from the table. A table
that only checked the first half would go stale the same way the description
did.

### 4. Give the deferral an exit

`close-subtask.sh --fulfill "<evidence>"` rewrites a `[~] (deferred: …)` box as
`[x]`, keeping both halves of the story on the line, then runs the census and
the `status:` stamp already wired into every other close.

**The line format is constrained by a measurement, not by taste.** The canonical
qualifier regex, shared by all seven scripts that read the grammar in code, is:

```
(^|[^[:alnum:]_-])deferred:
```

Measured against candidate line shapes:

| candidate | matches? | consequence |
|---|---|---|
| `- [x] 4.1 - t (was deferred: r; fulfilled: e)` | **yes** | seven readers score a closed box as deferred; the story never reaches `done` |
| `- [x] 4.1 - t (was-deferred: r; fulfilled: e)` | no | works, but only because `-` sits inside the excluded class — a sutlety no reader states |
| `- [x] 4.1 - t (fulfilled: e; original deferral — r)` | no | carries no qualifier token at all |

The third is chosen: it survives without depending on a regex detail. And
because a *preserved reason* could itself contain a qualifier token, `--fulfill`
refuses when it does, naming the token — the same stance the existing stowaway
guard takes for `--tilde`, rather than silently rewriting a maintainer's words.
Measured: all five real deferral reasons in stories 013 and 015 are clean, so
the refusal blocks none of the cases this story exists to close.

`--fulfill` accepts **only** `deferred:`. A terminal qualifier records a
decision already taken, and an operation that could overwrite `waived:` would be
a history eraser wearing a bugfix's clothes.

## Regression Test Strategy

Every `SHALL CONTINUE TO` in story.md maps to a check here.

- **Bug verification tests (fail before, pass after):**
  - the detector answers `triggered` on a recorded firing transcript — today's
    grep answers `false` on that same transcript
  - the detector answers `error` on a transcript with no terminal `result` —
    today's grep answers `false`, scoring it as a pass for a negative query
  - `skill-description-coverage.bats` fails on the description as it stands,
    naming `batch` and `migrate`
  - `close-subtask.sh --fulfill` closes a deferred box — today it exits 1
- **Regression tests, one per Unchanged Behavior item:**
  1. *22 of 27 still trigger* — the full suite is measured once **before** the
     description is touched, and that roster is the baseline the after-run is
     compared against, query by query
  2. *existing refusals unchanged* — `close-subtask.bats` and
     `close-subtask-transaction.bats` run untouched; the new suite adds cases
     rather than editing theirs
  3. *569 cases stay green* — full `bats tests/`, with the count reported; no
     existing case renamed or removed
  4. *validation output unchanged for every existing story* — validate all
     stories in `.epic/` before and after, and diff the JSON
  5. *no phrasing loses its route* — covered by regression test 1, since the
     description only gains vocabulary
- **Existing test impact:** none should need editing. If one does, it is
  re-proven red against the inversion of its own rule before it is changed —
  the standard story 019 set.

## Side Effects Assessment

| Potential Side Effect | Risk Level | Mitigation |
|---|---|---|
| A longer description dilutes triggering for phrasings that work today | **Medium** | This is the one real risk of frente B. Regression test 1 exists for it: full suite before, full suite after, compared per query. A query that regresses blocks the edit |
| `--fulfill` is used to close work that was not actually done | Medium | The evidence argument is mandatory and lands on the line; the refusal list keeps it away from terminal qualifiers. It cannot fabricate a census — the status stamp reads the boxes, not the claim |
| The preserved reason reintroduces a qualifier token and corrupts the census | Low | Refused with the token named. Measured clean on all five real reasons |
| The plugin-enabled refusal blocks a legitimate run (e.g. a different plugin also named `epic`) | Low | The refusal names the exact command to resolve it, and reads the name from the manifest rather than hardcoding it |
| Extracting the detector changes suite behaviour in an unnoticed way | Low | The detector is exercised against recorded fixtures, including a mutant that must be red. The harness change and the detector change are separate sub-tasks with separate validations |
| `claude plugin list` is slow or absent, so the new guard breaks the suite | Low | The CLI is already a hard dependency checked at startup; the guard reuses that precheck and treats an unparseable answer as "cannot verify", warning rather than refusing |
