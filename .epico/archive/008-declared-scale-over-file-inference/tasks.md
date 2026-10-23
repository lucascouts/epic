---
story: declared-scale-over-file-inference
type: bugfix
scale: full
status: archived
version: 1
created: 2026-08-10
---

# Implementation Plan - A leftover artifact overrules the declared scale

## Overview

Resolution first, because everything else reads what it produces: once `tasks.md` owns `scale:`, the spike contract becomes reachable again and the divergence gets a name. Then the gating half — one predicate replacing two file-presence inferences. Then `archive-story.sh`, which is where the damage is irreversible, plus the retractions: this story falsifies three sentences that are currently written down, and each is corrected in the commit that falsifies it.

**Every case this story authors goes into one new suite, `tests/scale-resolution.bats`.** It is named for the contract rather than for a script — the house already splits that way (`scale-validation`, `spike-validation`, `checkbox-grammar`) — and it is a *new* file on purpose: Phase 3 stages authored tests under `.draft/authored-tests/` and Run mode materializes them by **copying, skipping any target that already exists**, so a case appended to an existing suite could never reach it. Every existing suite stays untouched and is re-run as pure regression.

## Task List

- [x] 1 - Resolution, divergence, and the spike contract restored
  - _Complexity: Moderate | Tests: Unit (scale-resolution.bats — this story owns a new suite) | Risks: a rewrite that returns early on the first match silently drops the enum error for an invalid value in the losing artifact — no current test would catch it; message ordering in `warning_details[]` moves if the new warning is placed after the R2.3 block | Dependencies: None_
  - Objective: `tasks.md` owns `scale:`, every declaring artifact is enum-checked, disagreement is named, and a spike stops losing its contract to an orphan file.

  - [x] 1.1 - `tasks.md` wins; every artifact enum-checked; `design.md` paired, never resolved
    - Context:
      - Files: `scripts/validate-story.sh` (`:126-153` the resolution loop and the rationale at `:131-137` that argues for the defect; `:169-180` where `DECLARED_SCALE_FILE` reaches a user-visible message; `:734-770` the `status:` collector whose array shape this mirrors)
    - Objective: resolution reads the authoritative artifact without losing the per-artifact enum error.
    - ToDo:
      - Iterate `story.md design.md tasks.md`; enum-check **every** declaring artifact and `continue` on an invalid value so it never occupies the slot — `story.md: medium` + `tasks.md: spike` must still resolve `spike` **and** still report the `medium` error (R1.3).
      - Collect `SCALE_FILES`/`SCALE_VALUES` in the same pass, appending only non-empty values — an artifact with no `scale:` carries no opinion. Guard every array expansion as `${arr[@]+"${arr[@]}"}` (bash 3.2 on macOS aborts otherwise, the reason `archive-story.sh:239` already does it).
      - Resolve the winner as the last valid declaration among `story.md` and `tasks.md`, `tasks.md` preferred (R1.1); a single declaring artifact still wins whichever it is (R1.2).
      - `design.md` is enum-checked (R2.3) and paired for divergence, but **never** resolves (R2.4).
      - Do not "simplify" `frontmatter_field` — its `sed -n '2,/^---$/p' | sed '$d'` avoids GNU-only `head -n -1`, which aborted validation on BSD/macOS under `set -e`.
      - **Ship the shared-rule comment with this copy, in this commit.** story.md's Constraints require *every* copy to carry it; deferring all of them to 3.2 would land two commits whose scale rule names no siblings, which is precisely the window in which a copy gets edited alone. 3.2 then reconciles the five and adds the two non-movers.
    - Tests: Unit · `tests/scale-resolution.bats` — tasks.md wins over story.md; single-artifact declaration unchanged whichever file carries it; invalid value in the losing artifact still errors and still does not win; invalid `scale` in design.md errors while resolution is unaffected; valid `scale` in design.md does not resolve
    - Validation: `bats tests/scale-resolution.bats` green; `tests/scale-validation.bats` still green with story 007's R2.2 legacy golden — the no-scale fixture — byte-identical; `shellcheck scripts/validate-story.sh` clean
    - Requirements: R1.1, R1.2, R1.3, R2.3, R2.4

  - [x] 1.2 - Divergence warning
    - Context:
      - Files: `scripts/validate-story.sh` (`:833-842` the `status:` divergence test, its `${VAR:+, }` pairs idiom and its warning wording — the sentence this one is a sibling of)
    - Objective: two artifacts disagreeing about scale stop being silent.
    - ToDo:
      - Compare-to-element-0 over `SCALE_VALUES`, the shape used at `:833-836` (R2.1).
      - Emit **immediately after the resolution loop and before the R2.3 mismatch block at `:155`**, so the warning's index in `warning_details[]` is fixed and stated. Existing tests `grep` rather than index — keep it that way.
      - Message names every pair **and the winner**, which the `status:` sibling has no need to do. Illustrative form — **the sentence is not frozen**: `Artifacts of this story declare different 'scale' values (story.md=standard, tasks.md=spike) — tasks.md is authoritative; the resolved scale is 'spike'`. The contract the tests pin is the weaker and deliberate one: every `file=value` pair appears, and the resolved value is named. Paraphrase freely inside that.
      - `design.md` participates in the comparison like any other declaring artifact, so `design.md: full` beside `tasks.md: spike` with no story.md present warns, naming `design.md=full`. This is the only shape in which R2.4's "compared but never resolved" is observable at all.
      - Agreement is silent (R2.2). The witness is a real story directory, not a documentation file: **this story's own** `.epic/stories/008-declared-scale-over-file-inference/` declares `scale: full` in all three artifacts and is validated on every run, so any "warn when two declare" variant would fire on it immediately. (`assets/examples/full-feature.md` shows the same shape but is one prose file that no validator ever runs on — a witness that cannot testify.)
      - An invalid value is **not** paired: it already has its own error, and reporting one defect twice in two vocabularies is what this story exists to stop.
    - Tests: Unit · `tests/scale-resolution.bats` — disagreement warns naming both pairs and the resolved value; a `design.md`/`tasks.md` disagreement with no story.md warns naming `design.md=…`; three artifacts agreeing warn nothing; an invalid value in one artifact produces its enum error and no divergence warning
    - Validation: `bats tests/` green; the warning appears before the R2.3 mismatch line in `warning_details[]`
    - Requirements: R2.1, R2.2

  - [x] 1.3 - The reproduction fixture reports the spike's real defects
    - Context:
      - Files: `.epic/stories/008-declared-scale-over-file-inference/story.md` (Reproduction Steps 3 and 4 — the measured before/after), `scripts/validate-story.sh` (`:674` the spike block, unchanged by this story)
    - Objective: prove the contract is reachable again, on the exact shape that lost it.
    - ToDo:
      - No production change. This sub-task exists because the spike block is fixed by *resolution*, not by editing the block — so the proof has to be an end-to-end case rather than an inference from 1.1 (R4.1).
      - Assert on message content, never on exit status: the fixture is malformed by construction and will keep collecting other diagnostics as the validator grows.
      - The case must show the movement in both directions — the Verdict error now present, the `Requirements:` demand now absent — because either one alone is satisfied by the wrong implementation.
    - Tests: Unit · `tests/scale-resolution.bats` — a spike `tasks.md` beside a `story.md` declaring `scale: standard` reports the missing-Verdict error and does not report the coverage demand
    - Validation: `bats tests/scale-resolution.bats` green; the same fixture with the `story.md` scale line deleted produces the same spike errors, proving the orphan line no longer decides
    - Requirements: R4.1

  - [x] 1.4 - Commit
    - Validation: full bats suite green; `shellcheck` clean; story 007's R2.2 legacy golden byte-identical
    - Commit: "fix(008): tasks.md owns the declared scale, and disagreement is named"

- [x] 2 - Requirements-chain gating reads the scale, not the files
  - _Complexity: Simple | Tests: Unit (scale-resolution.bats — this story owns a new suite) | Risks: a positive predicate list makes the legacy empty case correct by accident; gating only the one warning arm of `--cross-ref` leaves the orphan/phantom loops emitting the same contradictory advice | Dependencies: Task 1_
  - Objective: one predicate answers "does this scale owe a requirements chain?", and all three consumers ask it instead of counting files.

  - [x] 2.1 - `scale_has_requirements_chain()` and the coverage gate
    - Context:
      - Files: `scripts/validate-story.sh` (`:550` the coverage gate carrying story 007's `!= "spike"`; `:531-541` the comment recording that trade, which must now cover `fast` too; `:169` `scale_mismatch()` as the placement and naming precedent)
    - Objective: the gate reads the scale, and `fast` stops being told to write what its contract omits.
    - ToDo:
      - Define the helper immediately after the resolution loop, above its first consumer, in the house shape (`name — one sentence`, then the paragraph saying why one skeleton).
      - Write it as the **false** set — `fast|spike) return 1 ;; *) return 0`. The direction is the point and it is easy to state backwards: a positive list `standard|full|"")` drops a future enum member through `*` and classifies it as having **no** chain, skipping the coverage gate in silence; the false set makes that newcomer fall to `*` as **having** a chain, so a tasks-only scale is told so loudly on its first run. Loud and wrong beats quiet and wrong. The positive list also makes the legacy empty case correct only by accident (R3.3).
      - Replace `!= "spike"` at `:550` with the predicate (R3.1).
      - Extend the `:531-541` comment: the same non-strict consequence story 007 recorded for `spike` now applies to `fast` — `hook-task-completed.sh` blocks on exit 1, reads `.error_details[]` only and has no warning branch, so that shape stops blocking it. Restate it rather than leave it to inference.
    - Tests: Unit · `tests/scale-resolution.bats` — a `fast` story with a leftover story.md and no `Requirements:` field reports no coverage error; a `standard` story omitting them still does; a story with no declared scale still does
    - Validation: `bats tests/` green; story 007's R2.2 legacy golden byte-identical; `shellcheck` clean
    - Requirements: R3.1, R3.3

  - [x] 2.2 - The whole `--cross-ref` block
    - Context:
      - Files: `scripts/validate-story.sh` (`:854` the block gate, file-presence only; `:881-893` the orphan and phantom loops; `:894-896` the warning arm — the one that was measured, and the smaller half of the defect)
    - Objective: a scale with no requirements chain is not compared against one.
    - ToDo:
      - Add the predicate as a conjunct to the block gate at `:854` — the **whole block**, not the `elif` arm alone (R3.2). The orphan and phantom loops carry the identical defect on a richer fixture: a spike whose tasks.md does contain R-tokens gets one warning per token, each advising exactly what the spike's no-requirements-chain rule makes an error.
      - A function defined at `:154` is callable here; the late parsing of `CROSS_REF`/`STRICT` at `:846` constrains variables, not functions.
    - Tests: Unit · `tests/scale-resolution.bats` — `--cross-ref` on a spike beside a story.md carrying R-numbers reports no R-reference finding; `--cross-ref` on a standard story still reports orphans and phantoms
    - Validation: `bats tests/` green; `bash scripts/validate-story.sh <spike fixture> --cross-ref` reports no requirements-chain finding
    - Requirements: R3.2

  - [x] 2.3 - `scripts/cross-reference.sh`, the fourth consumer
    - Context:
      - Files: `scripts/cross-reference.sh` (`:37-40`, which already exits 2 when `story.md` is absent — so a *conforming* spike never reaches the report; `:47-95` the extraction and the structural parse), `scripts/epic-gitpolicy.sh` (the non-git object — the precedent for reporting the fact that makes a measurement inapplicable instead of measuring zero)
    - Objective: the tool this story's own first Quality Gate runs stops giving the advice the story exists to remove.
    - ToDo:
      - Resolve the scale the same way `validate-story.sh` now does — tasks.md first — and when the resolved scale carries no requirements chain, emit `{story, scale, status: "no-requirements-chain"}` and **exit 0** (R3.4).
      - **This script has no frontmatter reader at all** — measured, zero occurrences — so one must be added, and the repo already has three mutually incompatible dialects (design.md's Known Divergence table). **Copy `archive-story.sh:307-326` verbatim**: it strips a trailing YAML comment and tolerates CRLF, and it is the dialect two of the three existing readers already share, so the new reader joins the majority row instead of adding a fourth. Do **not** copy `validate-story.sh`'s — under it a CRLF checkout reads as scale-less, which here would silently restore the very comparison this sub-task removes.
      - The script runs `set -euo pipefail`. A frontmatter pipeline over an **absent** key exits non-zero and aborts the whole run; `validate-story.sh:75-78` carries `|| true` for exactly that reason. Carry it too.
      - **Report the inapplicability, do not measure zero.** `traced: 0, coverage: "0/0"` claims a measurement was made and came back empty; that is a different statement from "there was nothing here to measure", and the distance between those two is the whole subject of this story. `orphan_requirements` and `phantom_references` are **absent as well, not `[]`** — the same argument rejects an empty array. Consumers branch on `status`, never on a measurement key being present.
      - Emit `scale` on **both** paths, not only this one. A key set that changes shape by scale is a second fact to know about the contract, and after this story the resolved scale is otherwise observable nowhere in the system. Measured safe: `tests/cross-reference.bats` asserts on neither the key set nor `.status`.
      - `no-requirements-chain` is a **fourth** `status` value beside `clean`, `issues` and `untraceable-format`. The consumer survey is done and recorded in design.md: nothing in the repository branches on this script's status string. Do not re-derive it — extend it if you add a caller.
      - **The exit code moves to 0 on a shape that is still malformed, and that is correct.** A spike carrying a `story.md` is reported by `validate-story.sh`'s R2.3 mismatch warning, which is the check that owns that defect; a traceability tool reporting a scale error would be this story's own category error, one script further along. State that in the comment beside the guard.
      - **Ship the shared-rule comment with this copy too**, same reasoning as 1.1 — 3.2 reconciles all five, it does not introduce them.
      - Reachable only on the leftover-artifact shape: `:37-40` already exits 2 for a tasks-only spike. **That guard is load-bearing after this change and must not be "fixed" to exit 0** — it encodes the decision that a spike is never routed through this script at all, which is a stronger and better statement than routing it and returning nothing. Say so in the comment, or the next reader will meet the guard beside R3.4 and read it as an oversight.
    - Tests: Unit · `tests/scale-resolution.bats` — a spike beside a story.md carrying R-numbers reports no orphan and exits 0; a `standard` story still reports its orphans and phantoms and still exits 1 when it has them; a tasks-only spike still exits 2 as before
    - Validation: `bash scripts/cross-reference.sh <spike fixture>` reports no orphan at exit 0; `bats tests/` green; `shellcheck scripts/cross-reference.sh` clean
    - Requirements: R3.4

  - [x] 2.4 - Commit
    - Validation: full bats suite green; `shellcheck` clean
    - Commit: "fix(008): requirements-chain gating reads the declared scale"

- [x] 3 - `archive-story.sh`, and the sentences this story falsifies
  - _Complexity: Moderate | Tests: Unit (scale-resolution.bats) | Risks: fixing only the gate call site leaves the manifest recording the wrong scale; flipping `story_field` itself would move `status` and `type`, which are out of scope | Dependencies: Task 1, Task 2 — 3.2's five-reader comment describes `cross-reference.sh` as changed, and sub-task 2.3 is what changes it_
  - Objective: the archive preflight sees the spike it is refusing, and no comment left in the tree still describes the old rule.

  - [x] 3.1 - `story_scale()` and **both** call sites
    - Context:
      - Files: `scripts/archive-story.sh` (`:330-337` `story_field`, story.md-first; `:536` `assess_completion`'s gate; `:573-589` the generic closed-boxes rule a mis-resolved spike falls through to; `:1731` `STORY_SCALE`, written into the manifest entry and the JSON)
    - Objective: a spike with a leftover `story.md` is refused, exactly as one without it already is.
    - ToDo:
      - Add `story_scale()` — tasks.md first, then story.md. Do **not** flip `story_field` itself: `status` (`:2691`) and `type` (`:1730`) keep story.md-first and are out of scope (R4.2).
      - Use it at **both** `:536` and `:1731`. Changing only the gate refuses correctly and then files a manifest entry naming the wrong scale — the likely error, and invisible to a test that only asserts the refusal.
    - Tests: Unit · `tests/scale-resolution.bats` — a spike `tasks.md` with every box `[x]` and no `## Verdict`, beside a `story.md` declaring `scale: full`, is refused and nothing is moved; an archivable spike in the same shape records `spike` in its manifest entry
    - Validation: `bats tests/scale-resolution.bats` green and `tests/archive-story.bats` unmoved; the measured reproduction (story.md Reproduction Step 5) now returns `status: "refused"` with the scale line present; `shellcheck scripts/archive-story.sh` clean
    - Requirements: R4.2

  - [x] 3.2 - The four-reader comment, the falsified comment, and the two retractions
    - Context:
      - Files: `scripts/archive-story.sh` (`:486-490` the `parse_verdict` "all four move together" comment — the shape to copy), `scripts/epic-index.sh` (`:751-754`, which states scale is read "story.md first, then tasks.md" and becomes false when 3.1 lands), `scripts/validate-story.sh` (`:131-137`, the prose arguing for the defect), `references/tasks.md` (`:265`)
    - Objective: no sentence left in the tree describes the rule this story replaced.
    - ToDo:
      - Give the scale rule the shared-rule comment in the house shape, naming all **five** readers and what each does: `validate-story.sh`, `archive-story.sh` and `cross-reference.sh` (changed here), `monitor-stale.sh:96` `declares_spike_scale` (already tasks.md-only — the precedent this rule agrees with), and `epic-index.sh:762-768` `status_cell` (knowingly left on story.md-first, out of scope). **Name the two that do not change, not only the movers** — an inventory of movers is the one that goes stale in silence, because the next person to touch `epic-index.sh` cannot tell a deliberate exception from an oversight.
      - Correct `epic-index.sh:751-754`. Its **code** is out of scope; its **comment** is falsified by 3.1 and ships in the same commit. A fix beside a comment it falsified is the defect class story 007's sub-task 5.6 spent itself removing (R1.1). **The precise falsehood is the attribution, not the precedence**: the comment explains `scale` by appealing to `archive-story.sh`'s `story_field`, and `story_field` stops resolving scale the moment 3.1 lands. The corrected comment may still record that `status_cell` keeps story.md-first — that is a true statement design.md deliberately preserves — but it must not reach `story_field` to justify it.
      - Rewrite `validate-story.sh:131-137`: it currently argues *for* story.md-first. Replace the rationale with why `tasks.md` owns `scale:`, naming the contract it now agrees with. **Phrase the retraction as what the rule IS, never by quoting the rule it replaces** — a retraction that repeats the old claim in order to deny it is indistinguishable from the claim to any reader that matches on content, human or grep, and the test for this sub-task matches on content.
      - Extend `references/tasks.md:265` to state the precedence explicitly instead of implying it: tasks.md is authoritative, and a disagreeing `story.md` is reported rather than honoured.
    - Tests: Unit · `tests/scale-resolution.bats` — a doc-contract case asserting `references/tasks.md` states the precedence, and that no reader's comment still claims story.md-first for `scale:`
    - Validation: `command grep` (not `grep`, a shim that skips `.epic/`) finds no comment explaining `scale:` through `archive-story.sh`'s `story_field`, and none in `validate-story.sh` asserting story.md-first for `scale:`. **Deliberately not "no surviving 'story.md first' claim"** — `epic-index.sh`'s `status_cell` genuinely stays on that precedence and design.md keeps it recorded, so a blanket phrase-ban would forbid the honest comment the fix requires; `bats tests/` green
    - Requirements: R1.1

  - [x] 3.3 - Commit
    - Validation: full bats suite green; `shellcheck` clean on all scripts; story validates 0 errors / 0 warnings
    - Commit: "fix(008): the archive preflight resolves scale from tasks.md, and the retractions"

## Quality Gates

Each gate names the command that settles it. None is ticked until that command has been run and its output pasted into the run report — a gate whose evidence is an inference is the defect story 007 spent its last task removing.

- [x] Every requirement traced — `bash scripts/cross-reference.sh .epic/stories/008-declared-scale-over-file-inference` reports `status: clean` with no orphans and no phantoms
- [x] The reproduction is closed — Reproduction Steps 3, 5, 6, 7, 8 and 9 of story.md re-run and produce the Expected Behavior, each output pasted. Step 5 is the one that matters most: it is the only irreversible consequence
- [x] Regression held — `bats tests/` green (386/386) with **no assertion semantics changed**; story 007's R2.2 legacy golden re-diffed and byte-identical — **007's R2.2, not this story's**, which is the unrelated "agreement is silent" rule. **One additive exception, escalated and approved before it landed**: `tests/checkbox-grammar.bats:356` gains the `scale` key sub-task 2.3 emits by design (`.draft/deviations.yaml`, task 2.3), every pre-existing key byte-unchanged. This gate originally read *no pre-authored assertion changed*, on the premise that the Architect's survey had found no case that has to move — falsified by measurement, and corrected here rather than left ticked over a false claim. A red that is **not** this one disclosed deviation is a defect in the change, never an expected update
- [x] No sentence left describing the old rule — `validate-story.sh:131-137`, `epic-index.sh:751-754` and `references/tasks.md:265` each re-read after the change, not merely re-pointed
- [x] `shellcheck` clean across all scripts, and the story validates 0 errors / 0 warnings
