# Engineering Level

How long the thing must last decides how much the story pays for — in the quality catalog, in Phase 3, in the size of the plan. The scale ([SKILL.md](../skills/epic/SKILL.md#adaptive-modes)) says which artifacts are written; the engineering level says how much engineering the work carries. They are independent axes: a Fast story can be a product's one-line fix, a Full story can be an experiment with three tracks.

This file is the single home of the four levels, their multiples, their plan ceilings and what each activates. Every consumer cites it and restates nothing but the numbers `tasks.md` owns; recalibrating a multiple is one edit here.

## The four levels

| Level | What it means | The question that reveals it | Expected cost |
|---|---|---|---|
| `experiment` | Disposable. It answers a question and nobody comes back to it, even if others run it once | "A month from now, will you open this again?" — no | **1×** — the minimum that works |
| `tool` | Kept in use and fixed when it breaks, with no deadline and nobody else depending on it | "When it breaks, do you fix it or redo it?" — fix | **2–3×** |
| `project` | Maintained: updated with some regularity, and other people depend on it or contribute to it | "Will anyone besides you run it or change it?" — yes · "Do you want its history kept somewhere like GitHub?" — yes | **4–6×** |
| `product` | May become a product. Market standards from the first commit | "Could this become something you publish or charge for?" — yes | **8×+** |

The multiple is against the **control** — the same request answered by the model with no plan at all — in wall clock and in tokens, and it is what the level should cost, not what it is allowed to. **The owner's rule: a run above 3× the control is, in most cases, a wrong level or over-engineering.** `project` and `product` exceed 3× because they buy things the control never produces — a history, a CI, contract tests — and their multiples are read from measurements, never taken as a licence.

**First calibration (2026-09-17).** Controls: 2 min for a beginner's request and 4 min for a developer's, both a Pokédex CLI. A Fast run for the beginner took 12 min; two Standard runs for the developer planned 43 and 47 boxes and were stopped at 42 min with 28 and 2 of them closed. The multiples above are the target ranges those runs are measured against, **recalibrated at every release** from the harness's own numbers — a figure here that the next round contradicts is rewritten, not defended.

## How the level is read

**Proposed at triage, from the request, and confirmed by the triage gate.** Triage reads the level the way it reads the requester ([SKILL.md](../skills/epic/SKILL.md#triage-protocol)): from the words — "for a class", "to see if it works", "we ship this to customers", "my team" — and records it with the evidence. When the request does not settle it, **`tool`**: it is the level a careful person gives a small thing they intend to keep, and the two gates around it are cheap to cross in either direction. `experiment` and `product` are never assumed: the first drops every check, the second buys every one.

**The proposal line carries the price, in one line.** Whatever the level, the proposal states it with its multiple in words the requester chooses by:

> Engineering: tool — you will keep using this and fix it when it breaks, so I test each part as I build it. About 2–3× the time of a throwaway version. Say so if it is only for today, or if others will depend on it.

For a `layperson` the same line is one of the three lines of the plain-register proposal ([plain-register.md](plain-register.md)), and the level's name never reaches them — what they hear is how long it needs to last and what that costs. For a `developer` the term is used. Either way the triage gate confirms it, so the level costs no question of the budget.

**The orientation round fishes for it when triage was unsure.** Round 0 of Clarify ([SKILL.md](../skills/epic/SKILL.md#clarify-protocol)) already asks who uses it and what "done" looks like; when the level is unsettled, the questions in the table above join that round, **asked as consequences and never as "which level is this?"** — a requester cannot grade their own engineering, but they know whether they will open the thing again. The round counts one against the budget whatever its size, so fishing costs nothing extra. When the answers move the level, the proposal line is restated once, with the new price, before Phase 1.

**A spike is an experiment by definition** and carries `experiment` or nothing.

## Where it is recorded

- **The frontmatter** of every artifact, beside `scale:` — `engineering: experiment | tool | project | product`. `tasks.md` is authoritative, as it is for the scale; a value outside the four is a validation error naming the set; absence is legal and silent, and a story with no field keeps the pre-level plan ceiling ([tasks.md](tasks.md#authoring-ceiling)).
- **`meta.yaml`**, beside the `requester` block, from the moment the level is proposed.
- **The run** — the execution plan and the end-of-run report both open with **the recorded line**: scale, requester level, engineering level with its expected multiple, and the plan size in Task List boxes — `standard · developer · tool (2–3×) · 11 boxes`; the report adds the wall clock and the boxes closed. That line is what the persona harness reads to compare a run against its control; a run without it is a run nobody can measure ([run-mode.md](run-mode.md#run-mode-rules)).

## What each level pays for

The level ties three things together. Each row is the whole difference between levels; everything not named here is the same at every level.

| | `experiment` | `tool` | `project` | `product` |
|---|---|---|---|---|
| **Quality catalog** ([quality-catalog.md](quality-catalog.md)) | nothing — the legend reads `none`, the proof is that it runs | the **always** tier | always, plus every **context** item whose signal the tree or the request carries | always, every context item that applies, and the **CI-shaped** ones without waiting for a signal — pinned Actions, minimum dependency age, licence and SBOM — plus the **on-request** tier when a requirement names it |
| **Phase 3** ([phase-gates.md](phase-gates.md#test-advisor-sub-agent-standard--full-during-phase-3)) | tests optional, as in a spike: `Validation` is the proof | tests decided inline by the Lite checklist and **written at run time**, as Fast does — no Test Advisor, no `.draft/authored-tests/`, no `red-evidence.yaml` | the full Phase 3: the Test Advisor authors one failing test per Unit/Integration/E2E sub-task and records its Red | the same |
| **Plan ceiling** ([tasks.md](tasks.md#authoring-ceiling)) | **5** Task List boxes | **12** | **24** | **40** |

**Why Phase 3 is proportional.** Measured on 2026-09-17: the Test Advisor writing 22 tests before any code cost about 25 minutes in each of two developer runs for a tool-shaped request. Authoring the test at plan time buys an independent contract for the implementer, and that independence is worth its price when someone else will maintain the code; for a thing one person keeps for themselves, the test written at run time — Red before Green, the same cycle, no sub-agent — buys the same regression guard for a third of the clock. `experiment` and `tool` therefore land in the run-time test-first ordering that Fast and spike already use ([run-mode.md](run-mode.md#run-time-test-first-ordering)), whatever their scale; `project` and `product` pay the full Phase 3. Everything downstream that reads "Standard/Full" as "has a pre-authored test" reads it through this table: materialization, its converse guard, Refine's Red evidence for added sub-tasks and the Auditor's Red-precedence check all apply at `project` and `product` and are exempt below.

**Why the ceiling is per level.** The measured pace is about one box per minute, so the plan is where the multiple is decided and the plan is where the brake goes. The single 60-box ceiling let a 43-box and a 47-box plan for a Pokédex through without a word; at `tool` both would have stopped at 12. The ceiling is a warning with **three offers**, never a block: cut the scope, split the plan into waves, or **go down a level** — the offer to make when the plan is big because it was written for a longer life than the requester asked for, since a plan regenerated at a lower level carries fewer quality items and fewer boxes. Bytes keep their own arm at every level; the box arm counts the Task List only, since the Quality Gates section grows with the legend and not with the work.

## What the level never changes

- The scale, the artifacts and the gates — a `product` Fast story is still `tasks.md` alone, an `experiment` Full story still has its design doc
- The requester level and the register — the two levels are read independently and recorded side by side
- The Executor's six steps, the closing of a box, the commit — the level decides how much is planned, never how a planned box is done
