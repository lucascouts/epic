---
story: close-011-audit-gaps
type: feature
scale: fast
version: 1
created: 2026-08-17
status: archived
---

# Implementation Plan - Close the 011 Audit Gaps

## Overview

Story 011's validate pass came back clean — no gaps, no unmet gates, no scope
creep — with warnings the auditor booked rather than fixed. Three of them are
measurable and are closed here: a test weaker than its own name, a carve-out
restated without the clause its own register demanded, and two agent
definitions naming a memory directory nothing writes to.

The failure mode is 016's, one turn worse. There, *a fact stated in prose
cannot fail, so it is never corrected*. Here, 1.1 is a test that **looks** like
it measures the declared risk and does not — which is worse than no test at
all, because it buys confidence it never delivers. Each sub-task therefore ends
with the check verified red against the mutation it is supposed to catch, not
merely green against the code as it stands.

Fast scale: three isolated fixes, two prose lines and one test body, no
architectural decision and no requirement traceability to carry. Two judgement
calls the executor should not have to make — which `md_section` span the
strengthened case reads, and which file the two new cases live in — are settled
in the ToDos below.

**Deliberately not closed here**, both from the same audit: the schema examples
in `agents/validator.md:41` and `agents/auditor.md:79` hardcode
`story: "011-reports-by-artifact"` where their templates use the house
`NNN-slug` placeholder (cosmetic; the inline comment mitigates it), and the
Auditor template's prose-summary bullets omit the code-review findings line
`agents/auditor.md:120` carries (pre-existing, and the schema block already
names `findings[]` as data). Named so the next reader knows they were seen and
judged, not missed.

A fourth warning needed no task: `.draft/deviations.yaml`'s discovery about the
memory path stated the inverse of what is on disk. It was corrected in place
during the validate pass, with the measurement recorded beside it — a register
read as Project State must show why a fact changed.

## Task List

- [x] 1 - Close the three measurable warnings from story 011's audit
  - _Complexity: Simple | Tests: Unit | Risks: 1.1 must be proven by mutation — a strengthened assertion that was never red proves nothing | Dependencies: None_
  - Objective: Every warning closed here fails the suite when it drifts back.

  - [x] 1.1 - The recovery case measures what its name promises
    - Context:
      - Files: the `2.1: an absent or unparseable report is re-requested once via SendMessage, then the run is failed` case of `tests/reports-by-artifact-policy.bats` (the weak assertions), the `### Absent or unparseable` subsection of `references/validate-mode.md` (the prose it should measure), the neighbouring `2.1:` cases in the same file (which scope with `md_section` — copy that shape)
    - Objective: Deleting any one of the three recovery sentences turns the suite red.
    - ToDo: the case asserts only that the strings `SendMessage` and `unparseable` occur somewhere in the whole document — it pins neither "one" request, nor "never respawn silently", nor "the run is failed", which is task group 2's declared Risk verbatim. Scope it to the recovery subsection and assert those three facts. Settle the helper subtlety rather than discovering it: `md_section`'s end pattern `'^## '` carries a trailing space and therefore does **not** stop at a `###` subsection, so a naive call swallows the rest of the mode file and any sentence anywhere in it satisfies the grep — start on `'^### Absent or unparseable'` and end on `'^#'`. Assert against the **flattened** section text, so a line wrap cannot hide a phrase — and note that the file's `flat` helper reads a *file* (`tr '\n' ' ' < "$1"`) and cannot take a captured section on a pipe, so flatten the section inline (`printf '%s\n' "$sec" | tr '\n' ' '`) rather than reaching for `flat`. Keep the case name and the `# R2.3:` comment; they were already right, only the body was not.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — the strengthened `2.1:` recovery case, same name and same count
    - Validation: each of the three assertions verified red against a copy of `references/validate-mode.md` with its sentence deleted, then restored — three separate mutations, three separate reds; `bats tests/` green afterwards with the case count unchanged

  - [x] 1.2 - The Auditor template keeps the memory clause
    - Context:
      - Files: the Auditor prompt template's closing carve-out in `references/validate-mode.md` (restated without the clause), the `## Rules` carve-out in `agents/auditor.md` ("Your memory directory is not a second path in the code under audit — it is your own store, governed by the Memory section above"), the `the Write carve-out vs the auditor's own memory` discovery in `.epic/stories/011-reports-by-artifact/.draft/deviations.yaml` (which required any restatement to keep it)
    - Objective: A template-spawned Auditor is not told to violate the memory append its own system prompt mandates.
    - ToDo: append the clause to the Auditor template's carve-out in the words the agent definition uses, so the two copies say the same thing rather than merely both mentioning writes. Scope it to the **Auditor's** template only — the Validator's identically-worded sentence stays exactly as it is, because `memory: project` is carried by `analyst` and `auditor` alone, and a memory clause in the Validator's prompt would name a store it does not have. This is not hypothetical: story 011's own audit withheld its mandated memory append rather than risk the violation, which is why that run left no note behind. Not introduced by 011 either — the line it replaced ("Do NOT modify any files") forbade the append just as absolutely; 011 narrowed an inherited contradiction without resolving it, and this resolves it.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — a case asserting the Auditor template's carve-out names the memory directory as the agent's own store, and that the Validator's carve-out does **not** (the negative half is what keeps a well-meaning sweep from copying the clause into a prompt with no memory behind it)
    - Validation: the new case verified red before the prose edit; `bats tests/` green with one case more than before

  - [x] 1.3 - The declared memory directory is the one the runtime writes to
    - Context:
      - Files: the `## Memory` heading of `agents/auditor.md`, the `## Memory` heading of `agents/analyst.md`, `.claude/agent-memory/` (what exists on disk)
    - Objective: An agent reading its own definition is told where its notes actually live.
    - ToDo: change both headings to the `epic-`-prefixed directory — `.claude/agent-memory/epic-auditor/` and `.claude/agent-memory/epic-analyst/`. Measured, not assumed: those two directories exist and are populated by prior runs (the auditor's holds six notes), while the unprefixed pair the headings name does not exist at all — the prefix is the runtime convention for a plugin-namespaced agent. Body text in both files refers to the location obliquely ("your memory directory", "the Memory section above") and needs no edit. These two headings are the only `agent-memory` mentions across `agents/`, `references/`, `skills/`, `ARCHITECTURE.md` and `README.md`, so the both-copies sweep R3.4 demands elsewhere has no second copy to reach here — verify that with the grep below rather than trusting the claim.
    - Tests: Unit · `tests/reports-by-artifact-policy.bats` — a case asserting that every agent definition carrying `memory: project` heads its Memory section with the `epic-`-prefixed directory, derived from the frontmatter rather than from a hardcoded pair, so a third memory-carrying agent joins the pin by existing. Keep it in this file rather than opening a new one for a single case, and comment it as a general agent-definition convention so a later story can move it out when a second such case appears
    - Validation: the new case verified red before the edits; `bats tests/` green with one case more than before; `command grep -rn 'agent-memory' agents/ references/ skills/ ARCHITECTURE.md README.md` shows only the two corrected headings

  - [x] 1.4 - Commit
    - Validation: `bats tests/` fully green (482 cases: 480 + 2 — 1.1 strengthens an existing case without adding one, 1.2 and 1.3 add one each); the 19 existing wave-011 cases still green
    - Commit: "test(018): close the three measurable warnings from story 011's audit"

## Quality Gates

- [x] All acceptance criteria validated (each warning closed by a passing test, not a prose claim)
- [x] All task validations pass
- [x] All tests written and passing (full bats suite green; the wave-011 cases still green, one of them strengthened)
- [x] Code integrated (the Auditor's template and its agent definition state the same carve-out; the declared memory paths match the directories on disk)
- [~] Error handling implemented (n/a at creation — no new runtime code; 1.1's three mutation reds are what cover the arm that decides a run is failed) (n-a: no new runtime code — the story edits prose and one test body; the arm that decides a run is failed is covered by 1.1's three mutation reds)
