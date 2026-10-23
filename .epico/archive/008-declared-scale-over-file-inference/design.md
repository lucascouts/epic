---
story: declared-scale-over-file-inference
type: bugfix
scale: full
status: archived
version: 1
created: 2026-08-10
---

# Design - A leftover artifact overrules the declared scale

## Overview

**The root cause is a written rationale, not a slip.** `scripts/validate-story.sh:131-137` argues in prose that `story.md` should win — *"it is the story's own frontmatter and therefore wins when the two disagree"* — and the loop at `:138-153` implements exactly that. Meanwhile `references/tasks.md:265` states the opposite for the one scale where it decides everything: *"Declare `scale: spike` in the frontmatter [of tasks.md]. It is the only place a spike can declare it, and validation reads it from there."* Two contracts, both written down, pointing opposite ways. The fix must **retract one of them**, not reorder a `for` list quietly.

`scripts/archive-story.sh` resolves the same way through a different helper (`story_field`, `:330-337`), which is why the same leftover `story.md` lets a spike be archived with no `## Verdict` — measured, `status: "archived"`.

The second, independent half is a **category error in three gates**: "does this story owe a requirements chain?" is answered by asking which files exist, when it is a property of the scale. That is why `fast` still gets told to add `Requirements:` fields, and why `--cross-ref` still reports their absence as a finding.

Two more facts shape the design. `scripts/monitor-stale.sh:96` already reads `scale:` from **tasks.md alone** — so the rule chosen here is not new to the codebase, it is the one the newest consumer already follows. And `design.md` may declare `scale:` (`assets/examples/full-feature.md:15`) while no script reads it, so the enum check introduced by story 007 R2.1 covers two of the three artifacts that carry the field.

## Components & Interfaces

### 1. Scale resolution — `validate-story.sh:138-153`

**Contract:** iterate `story.md design.md tasks.md`; enum-check **every** declaring artifact; collect each into parallel arrays; resolve the winner as **the last valid declaration among `story.md` and `tasks.md`, with `tasks.md` preferred**.

```bash
SCALE_FILES=()      # basenames that declared a valid scale
SCALE_VALUES=()     # parallel values
DECLARED_SCALE=""   # resolved; "" when nothing declared validly
DECLARED_SCALE_FILE=""
```

Three properties a rewrite must preserve, each of which a naive reordering loses:

- **Every artifact is enum-checked before any winner exists.** An invalid value `continue`s (`:147`) and never occupies the slot, so `story.md: medium` + `tasks.md: spike` resolves to `spike` **and** reports the `medium` error. Preserved by keeping the enum check inside the loop and only the *selection* precedence-aware.
- **`design.md` is enum-checked and paired, never resolved (R2.4).** It describes the solution; it does not declare the work's shape.
- **An artifact with no `scale:` carries no opinion** — it is not appended, and cannot be divergent. This mirrors the `status:` collector's own comment at `validate-story.sh:762-763` — *"An artifact without the field carries no opinion, so it is never divergent"*.

**One divergence from the `status:` sibling, stated deliberately:** the `status:` collector appends a value even when it fails its enum (`:759-765`), so an invalid value can appear in its pairs. The scale collector does **not** — an invalid value is already reported by its own error, and repeating it inside a divergence warning would report one defect twice in two vocabularies.

`DECLARED_SCALE_FILE` is user-visible at `:170` (`"declared scale 'X' (in Y) contradicts the files present…"`). Inverting precedence changes that `(in Y)` for a story declaring in both files. No existing fixture declares in both, so no golden moves — but the sentence is part of the contract and belongs in the test surface.

### 2. Divergence warning (R2.1, R2.2) — sibling of the `status:` warning

Emitted **immediately after the resolution loop closes and before the R2.3 mismatch block at `:155`**, so its position in `warning_details[]` is fixed and stated.

```bash
# Compare-to-element-0, the shape used for `status:` at :833-836.
SCALE_DIVERGED=false
for sc_v in ${SCALE_VALUES[@]+"${SCALE_VALUES[@]}"}; do
  [[ "$sc_v" == "${SCALE_VALUES[0]}" ]] || SCALE_DIVERGED=true
done
```

Message, the `status:` sentence with its subject changed and the resolution named — because unlike `status:`, this warning has a winner to disclose. **The block below is illustrative and the sentence is not frozen**; the binding contract, and the one the tests pin, is that every `file=value` pair appears and the resolved value is named:

```
Artifacts of this story declare different 'scale' values (story.md=standard, tasks.md=spike) —
tasks.md is authoritative; the resolved scale is 'spike'
```

`SCALE_PAIRS` is built with the `${VAR:+, }` separator idiom already used at `:838-841`.

### 3. `scale_has_requirements_chain()` (R3.1, R3.2, R3.3)

Defined immediately after the resolution loop — a pure function of `DECLARED_SCALE`, placed like `scale_mismatch()` is placed above its consumer. Two consumers far apart (`:550`, `:854`), which is exactly the "one skeleton, spelled once" case this script already makes for `no_r_chain()`.

```bash
# scale_has_requirements_chain — does the resolved scale carry an R-chain?
# Written as the FALSE set on purpose, and the direction matters: a positive
# list `standard|full|"")` would drop every future enum member through `*` and
# classify it as having NO chain — opted OUT, skipping the coverage gate in
# silence. The false set does the opposite: a new scale falls to `*`, is
# treated as carrying a chain, and a tasks-only newcomer is told so loudly on
# its first run. Loud and wrong beats quiet and wrong; the positive list also
# makes the legacy empty case correct only by accident.
scale_has_requirements_chain() {
  case "$DECLARED_SCALE" in
    fast | spike) return 1 ;;
    *) return 0 ;;
  esac
}
```

Consumers:
- **`:550`** — the requirements-coverage gate becomes `HAS_STORY == true && scale_has_requirements_chain`, replacing story 007's `!= "spike"`.
- **`:854`** — the whole `--cross-ref` block gains the same conjunct. **The whole block, not the one warning arm**: its orphan and phantom loops (`:881-893`) carry the identical defect on a richer fixture — a spike whose tasks.md does contain R-tokens gets one warning per token, each advising what the spike's no-requirements-chain rule makes an error.

A function defined at `:154` is callable at `:854`; the late parsing of `CROSS_REF`/`STRICT` at `:846` constrains variables, not functions.

### 4. `story_scale()` in `archive-story.sh` (R4.2)

A dedicated helper — **`story_field` itself is not flipped**, because `status` (`:2691`) and `type` (`:1730`) must keep reading `story.md` first and are out of scope.

```bash
# story_scale — scale is the one field tasks.md owns (008 R1.1).
story_scale() {
  local v
  v=$(frontmatter_field "$STORY_PATH/tasks.md" scale)
  [[ -n "$v" ]] || v=$(frontmatter_field "$STORY_PATH/story.md" scale)
  printf '%s' "$v"
}
```

**Both call sites move**, and missing the second is the likely error: `:536` (`assess_completion`, the gate that decides refusal) and `:1731` (`STORY_SCALE`, written into the manifest entry and the JSON). A fix that changes only `:536` refuses correctly and then files a manifest entry calling the story `full`.

**`archive-story.sh` has no scale enum check, and this change makes that reachable.** Today an invalid `scale: medium` in `tasks.md` beside a valid `spike` in `story.md` resolves to `spike` and the preflight applies; after `story_scale`, `medium` wins and the spike preflight is skipped. No requirement asks for the enum here and adding one is out of scope — but the gap moves from unreachable to reachable, so it is registered rather than discovered. The validator still reports the invalid value on the same story.

### 5. `scripts/cross-reference.sh` — the fourth consumer (R3.4)

The standalone traceability script has **no scale awareness at all** and is the tool this story's own first Quality Gate runs. It already refuses a *conforming* spike — `:37-40` exits 2 when `story.md` is absent — so the contradictory report is reachable only on the leftover-artifact shape this story exists to fix: measured, a spike beside a `story.md` carrying R-numbers reports `orphan_requirements: ["R1.1"]`.

It resolves the scale the same way (tasks.md first) and, when the scale carries no requirements chain, **stops measuring rather than measuring zero**. The precedent is `epic-gitpolicy.sh`'s non-git object: report the fact that makes the measurement inapplicable, omit the measurements that were never made, and exit 0.

```json
{ "story": "…", "scale": "spike", "status": "no-requirements-chain" }
```

Deliberately **not** zeros: `traced: 0, coverage: "0/0"` reads as "measured and found empty", which is a different claim from "there is nothing here to measure" — and the whole story is about the cost of a check answering a question that was never asked of it.

Three consequences of that object, each decided rather than left to the implementer:

- **`orphan_requirements` and `phantom_references` are absent too, not `[]`.** The rationale that rejects `traced: 0` rejects `[]` with identical force — an empty array claims a look was taken. The rule this makes explicit for every consumer: **branch on `status`, never on the presence of a measurement key.**
- **`scale` is emitted on *both* paths**, not only this one. A key set that changes shape by scale is a second thing to know about the contract, and there is a positive reason to add it: after this story the resolved scale is otherwise **observable nowhere** in the system, which is why every test of resolution has to infer it from a downstream error. Measured safe: `tests/cross-reference.bats` (15 cases) asserts on neither the key set nor `.status`, so no existing case moves.
- **`no-requirements-chain` is a fourth `status` value**, joining `clean`, `issues` and `untraceable-format`. Consumer survey, measured rather than assumed: **nothing in the repository branches on this script's `status` string** — the only occurrences are inside the script itself, and `references/ci-mode.md:59` consumes `validate-story.sh --cross-ref` by exit code, not this script. The new value therefore reaches no existing reader.

**The exit code moves to 0 on a shape that is still malformed**, and that is the same trade this story already makes twice: a spike carrying a `story.md` is reported by `validate-story.sh`'s R2.3 mismatch warning, which is the check that owns that defect. A traceability tool reporting a scale error would be the category error this story exists to remove, one script further along.

### 6. The shared-rule comment (house convention)

The rule now lives in more than one standalone script, so it takes the shape `parse_verdict` already uses (`archive-story.sh:486-490`, `validate-story.sh:615-625`, `epic-index.sh:430-441`, `monitor-stale.sh:130-137`). Every copy names the whole set, so amending one means moving all:

- `validate-story.sh` — the resolution loop (changes here)
- `archive-story.sh` — `story_scale` (changes here)
- `cross-reference.sh` — the R3.4 gate (changes here)
- `monitor-stale.sh:96` — `declares_spike_scale`, already **tasks.md only**; the precedent this rule agrees with, unchanged
- `epic-index.sh:762-768` — `status_cell`, knowingly left on story.md-first (out of scope)

**Five readers, and the comment must name all five including the two that do not change** — an inventory that lists only the movers is the one that goes stale silently, because the next person to touch `epic-index.sh` has no way to learn it was a deliberate exception rather than an oversight.

**`epic-index.sh:751-754` must be corrected in this same commit even though its code is out of scope.** It states in prose that scale *"is looked up the way archive-story.sh's `story_field` looks it up — story.md first, then tasks.md"*. That sentence becomes false the moment `story_scale` lands, and shipping a fix beside a comment it falsified is the defect class story 007 spent its last task removing.

### 7. Documentation retraction

- `validate-story.sh:131-137` — the rationale arguing for story.md-first is replaced by one that states why `tasks.md` owns `scale:`, and names the contract (`references/tasks.md:265`) it now agrees with.
- `references/tasks.md:265` — extended to state the precedence explicitly rather than implying it: tasks.md is authoritative, and a disagreeing `story.md` is reported, not honoured.

## Error Handling Strategy

- **Disagreement is a warning, never an error.** Which artifact is wrong is the author's call — the same reasoning that makes story 007's R2.3 scale-vs-files check a warning.
- **An invalid value stays an error** and is reported per artifact, including `design.md` (R2.3), naming the artifact, the value and the full enum.
- **The gating change moves exit codes in one direction only.** For `fast` and `spike` shapes, the coverage error disappears: `errors: 1, exit 1` becomes `errors: 0, exit 0` non-strict. `scripts/hook-task-completed.sh` blocks on exit 1 and reads `.error_details[]` with no warning branch, so those shapes stop blocking it — the trade story 007 documented at `validate-story.sh:531-541` for `spike`, now extended to `fast`, and it must be restated there rather than left to inference.
- **The opposite movement is expected on the spike shape and is the fix working.** With resolution corrected, a leftover-artifact spike stops reporting one coverage error and starts reporting the spike errors it always owed. Count and messages both change.

## Testing Strategy

**Every case this story authors lives in one new suite, `tests/scale-resolution.bats`.** Not appended to the three existing suites the subject matter would suggest: Run mode materializes staged tests by *copying, skipping any target that already exists*, so a case appended to a suite that is already in the tree could never reach it. Named for the contract rather than for a script, which is how the house already splits (`scale-validation`, `spike-validation`, `checkbox-grammar`).

- **Unit — resolution:** tasks.md wins over story.md; a single declaring artifact still resolves whichever of the two carries it; an invalid value in the losing artifact still errors and still does not occupy the slot; an invalid `scale` in `design.md` errors while resolution is unaffected; a valid one there does not resolve.
- **Unit — divergence:** disagreement names every pair and the resolved value; a `design.md`/`tasks.md` disagreement with no story.md warns too (the only shape in which R2.4's "compared but never resolved" is observable); agreement is silent; an invalid value is not paired.
- **Unit — the reproduction:** spike tasks.md + story.md declaring `standard` reports the Verdict error and **not** the coverage demand, asserted on message content rather than exit status.
- **Unit — gating:** `fast` with a leftover story.md is not asked for `Requirements:` fields; `standard` still is; an undeclared legacy story still is; `--cross-ref` on a spike reports neither the missing-references warning nor an orphan or phantom, while a standard story still reports all three.
- **Unit — `cross-reference.sh` (R3.4):** the spike fixture reports no orphan and exits 0 with the inapplicability object; a standard story still reports its orphan and exits 1; a conforming tasks-only spike still exits 2 — that last pin protects the `:37-40` guard, which after this change *encodes* the decision that a spike is never routed through the script at all.
- **Unit — `archive-story.sh`:** the leftover-artifact spike with every box `[x]` and no `## Verdict` is **refused** and nothing moves; an archivable one records `spike` in its manifest entry, which is the only case that discriminates the `:1731` call site from the `:536` one.
- **Unit — doc contract:** `references/tasks.md` states the precedence; no reader's comment still explains `scale:` through `archive-story.sh`'s `story_field`.
- **Regression:** every existing suite re-runs green, and **no assertion semantics change**. Story 007's R2.2 legacy golden must be byte-identical. Stated as an invariant rather than a case count, because this story's own commit adds a suite and would falsify any number written here. **One additive exception, measured rather than predicted:** `tests/checkbox-grammar.bats:356` — story 004's R5.1 full-object golden for `cross-reference.sh` — gains one line for the `scale` key §5 above deliberately emits. The Executor escalated instead of editing the assertion, and the decision is recorded in `.draft/deviations.yaml`. Every pre-existing key keeps its position, its value and its bytes, and no consumer of that object moves. This bullet originally claimed the Architect's survey had found no case that has to change: the survey measured the suite named after the script and missed a pin living in a differently-named one. **The sweep is now exhaustive and closed** — exactly two full-object goldens exist in `tests/`, both in `checkbox-grammar.bats`, and only one pins this script, so the gap cannot recur for this object.
- **Integration:** none — every surface is a script with a JSON contract, already covered at the unit level.
- **E2E:** none.

## Tooling Decisions

- E2E tool: none — no browser or UI surface; the harness is bats + shellcheck. `playwright` and `chrome-devtools` are installed but inapplicable
- Frontend aid: none
- Recommendation surfaced: no

## Integration Points

- **Story 007** — this defends R1.2/R1.3/R1.4 (the spike contract) and R2.1 (the scale enum), and completes the gating half of its sub-task 5.4. It closes three discoveries 007 registered as unowned.
- **`scripts/hook-task-completed.sh`** — a non-strict consumer that blocks on exit 1 and never reads warnings; affected by the gating change, unchanged by the resolution change.
- **`references/ci-mode.md:59`** — runs `validate-story.sh --cross-ref` without `--strict`; a `fast`/`spike` story stops failing it. **`references/ci-mode.md:17`** runs `cross-reference.sh` standalone, so it is the one documented consumer whose output *shape* changes.
- **`references/phase-gates.md:259-278`** — builds the traceability table from `mapping`, `traced` and `coverage`, all three absent from the inapplicability object. Safe by its own gate rather than by luck: `:259` restricts the table to standard and full scales, which is exactly the set that keeps a requirements chain. Cited here so the safety is a reading, not an inference.
- **`scripts/monitor-stale.sh`** — already tasks.md-only; after this change validate, archive and the staleness monitor agree on what a spike is. `epic-index.sh` deliberately does not, and that is recorded.

## Known Divergence — the three frontmatter readers

Not fixed here, and named so it is a decision rather than an oversight. Three implementations disagree on tolerance:

| Reader | YAML comment | CRLF |
|---|---|---|
| `validate-story.sh:61-79` | not stripped (`scale: spike # probe` → `spike#probe` → enum error) | not tolerated |
| `archive-story.sh:307-326` | stripped | `^---\r?$` tolerated |
| `monitor-stale.sh:96-125` | stripped | tolerated |
| `cross-reference.sh` (new, sub-task 2.3) | stripped | tolerated — **copies `archive-story.sh`'s verbatim**, joining the majority row rather than adding a fourth dialect |

A CRLF story therefore looks **scale-less** to the validator and **spike** to archive. Unifying them changes what several existing fixtures parse as, which is a bugfix of its own — out of scope, registered.
