---
story: declared-scale-over-file-inference
type: bugfix
scale: full
status: archived
version: 1
created: 2026-08-10
---

# Bugfix - A leftover artifact overrules the declared scale, and three gates infer it from file presence

## Summary

`scripts/validate-story.sh` resolves a story's scale by taking the first valid `scale:` it finds, reading `story.md` before `tasks.md` — so a `scale:` left behind in an abandoned `story.md` overrules the one `tasks.md` declares. For a spike that is fatal: the whole spike contract (Verdict, `promoted-to:`, no-R-chain) stops being enforced, no warning names the disagreement, and `scripts/archive-story.sh` — which resolves the same way — **archives a spike that has no Verdict at all**. Separately, three gates decide whether a story owes a requirements chain by looking at which files exist rather than at the declared scale, which is how the same contradictory advice survives for `fast` and at the `--cross-ref` boundary.

## Reproduction Steps

Each step below was executed; the quoted output is measured, not predicted.

1. Create `.epic/stories/031-probe/tasks.md` with frontmatter `scale: spike`, one closed checkbox task, and **no `## Verdict` section**.
2. Beside it create `story.md` whose frontmatter declares `scale: standard`.
3. Run `bash scripts/validate-story.sh .epic/stories/031-probe` → `errors: 1` (`"tasks.md has 1 tasks but no 'Requirements:' fields"`), `warnings: 5`, **none of the five mentioning scale**. No Verdict error, no R-chain error: the spike contract was never evaluated.
4. Delete the single line `scale: standard` from `story.md` and re-run → `errors: 0, warnings: 6`, and the spike checks now run. **One line in an unrelated artifact decided whether the contract exists.**
5. Run `bash scripts/archive-story.sh .epic/stories/031-probe` with the `scale: standard` line present → `status: "archived"`, `moved: true`. With the line absent → `status: "refused"`, exit 1, `"spike '031-probe' has no '## Verdict' section with a status"`.
6. For the `fast` variant: `tasks.md` declaring `scale: fast` with no `Requirements:` field — which is exactly what [tasks.md](../../../references/tasks.md) instructs a fast story to write — beside any `story.md` → `errors: 1`, the same missing-`Requirements:` demand.
7. For the `--cross-ref` variant: a conforming spike plus a `story.md` carrying R-numbers, run with `--cross-ref` → warning `"story.md has requirements but tasks.md has no R-number references"`, advice that the spike's no-requirements-chain rule turns into an error the moment it is obeyed.
8. For the unread artifact: put `scale: medium` in `design.md` of any otherwise-valid story → `errors: 0`. The enum is not enforced there at all.
9. For the standalone traceability tool: run `bash scripts/cross-reference.sh` on the step-7 fixture → `orphan_requirements: ["R1.1"]`, `status: "untraceable-format"`, exit 1. A third script, never surveyed by this story until the test author found it, giving the same advice — and it is the tool this story's own first Quality Gate runs.

## Current Behavior (Defect)

WHEN two artifacts declare a valid `scale` THEN the system resolves the one from `story.md` and ignores `tasks.md`, although `references/tasks.md` states that `tasks.md` is the only place a spike may declare its scale.

WHEN artifacts declare different valid `scale` values THEN the system reports nothing, although the same script warns about artifacts that declare different `status` values.

WHEN a story declaring `scale: spike` in `tasks.md` carries a `story.md` that declares any other scale THEN the system evaluates none of the spike checks — a missing `## Verdict`, a `promote` with no `promoted-to:`, and every `Requirements:` field or R-token pass unreported.

WHEN `archive-story.sh` evaluates that same story THEN it archives it through the generic closed-boxes rule, so a spike is filed away without the conclusion that is its only deliverable.

WHEN a story declares `scale: fast` and a `story.md` is present THEN the system demands `Requirements:` fields that the fast contract tells the author to omit.

WHEN `--cross-ref` runs on a story whose declared scale has no requirements chain THEN the system compares story.md's R-numbers against tasks.md and reports the absence as a finding, which is advice the spike contract makes an error to follow.

WHEN `design.md` declares a `scale` outside the enum THEN the system reports nothing, so the invalid-value check that R2.1 of story 007 introduced does not cover a third of the artifacts that carry the field.

WHEN `scripts/cross-reference.sh` runs on a story whose declared scale has no requirements chain THEN it compares story.md's R-numbers against tasks.md anyway and reports the absence as orphans, exiting 1 — the same category error as the gates above, in a third script.

## Expected Behavior (Correct)

### R1. Resolution reads the authoritative artifact

- R1.1: WHEN `tasks.md` and `story.md` both declare a valid `scale` THE SYSTEM SHALL resolve the declared scale from `tasks.md`
- R1.2: WHERE exactly one of `story.md` and `tasks.md` declares a valid `scale` THE SYSTEM SHALL resolve that value whichever of the two carries it — `design.md` is deliberately excluded here, and R2.4 says why
- R1.3: WHEN an artifact declares a `scale` outside the enum THE SYSTEM SHALL report an error naming that artifact, the invalid value and the valid set, and SHALL resolve the scale from the remaining artifacts

### R2. Disagreement is named, and every declaring artifact is checked

- R2.1: IF two or more artifacts declare different valid `scale` values THEN THE SYSTEM SHALL report a warning naming each artifact and the value it declares
- R2.2: WHERE every artifact that declares a `scale` declares the same value THE SYSTEM SHALL report no divergence warning
- R2.3: WHEN `design.md` declares a `scale` outside the enum THE SYSTEM SHALL report the same enum error it reports for `story.md` and `tasks.md`
- R2.4: WHERE `design.md` declares a valid `scale` THE SYSTEM SHALL use it for the divergence comparison only and SHALL NOT resolve the declared scale from it

### R3. Requirements-chain gating reads the scale, not the files

- R3.1: WHERE the resolved scale is one that carries no requirements chain THE SYSTEM SHALL NOT report the missing-`Requirements:`-fields error
- R3.2: WHERE the resolved scale is one that carries no requirements chain THE SYSTEM SHALL skip the entire `--cross-ref` comparison, including its orphan and phantom reports
- R3.3: WHERE no artifact declares a `scale` THE SYSTEM SHALL treat the story as carrying a requirements chain
- R3.4: WHERE the resolved scale carries no requirements chain THE SYSTEM SHALL make `scripts/cross-reference.sh` report no orphan and no phantom, and exit 0

### R4. The spike contract survives a leftover artifact

- R4.1: WHEN `tasks.md` declares `scale: spike` THE SYSTEM SHALL enforce the Verdict contract whatever any other artifact declares
- R4.2: WHEN `archive-story.sh` evaluates a story whose `tasks.md` declares `scale: spike` THE SYSTEM SHALL apply the spike archive preflight whatever any other artifact declares

## Unchanged Behavior (Regression Prevention)

- WHEN a story declares no `scale` in any artifact THE SYSTEM SHALL CONTINUE TO produce output byte-identical to the pre-change behavior, as pinned by the legacy golden in `tests/scale-validation.bats`
- WHEN the existing suites run THE SYSTEM SHALL CONTINUE TO pass with **no assertion semantics changed** — stated as an invariant rather than as a count, because this story adds a suite of its own and any number written here would be falsified by its own commit. **One additive exception, escalated and approved before it landed** (`.draft/deviations.yaml`, task 2.3): `tests/checkbox-grammar.bats:356` gains the `scale` key that sub-task 2.3 deliberately emits, with every pre-existing key keeping its position, its value and its bytes. This bullet originally read *no pre-authored assertion changed*, on a survey that measured `tests/cross-reference.bats` and missed a fifth full-object pin living in a differently-named suite; it is corrected here rather than left standing, because a sentence that asserts something measurably false is the defect class this story exists to remove. `tests/epic-index.bats` also moved — comments only, no assertion touched
- WHERE a story declares its `scale` only in `story.md` THE SYSTEM SHALL CONTINUE TO resolve that value and to warn when it contradicts the files present
- WHEN an artifact declares `scale: medium` THE SYSTEM SHALL CONTINUE TO report an error naming the value and the full valid set, including when another artifact declares a valid scale
- WHEN a declared scale contradicts the files present THE SYSTEM SHALL CONTINUE TO report the R2.3 mismatch warning of story 007, naming both sides
- WHEN a story carries a requirements chain and omits its `Requirements:` fields THE SYSTEM SHALL CONTINUE TO report that as an error
- WHEN `archive-story.sh` resolves `status` or `type` THE SYSTEM SHALL CONTINUE TO read `story.md` first — only `scale` moves, and flipping the shared `story_field` helper instead of adding a dedicated one is the single most likely wrong fix
- WHEN `epic-index.sh` renders a row THE SYSTEM SHALL CONTINUE TO resolve `scale` story.md-first — that divergence is deliberate, recorded, and out of scope; a fix that "helpfully" aligns it is a scope breach, not a cleanup

**One consequence is deliberately not listed as unchanged, because it will move.** Making the spike contract reachable on the leftover-artifact shape means that shape stops reporting one coverage error and starts reporting the spike errors it always owed — a missing Verdict, a `promote` with no target, an R-token. The error *count* and the error *messages* both change, and `scripts/hook-task-completed.sh` prints different `.error_details[]` as a result. That is the fix working, not a regression, and it is stated here so it is not discovered later.

## Success Metrics

- The step-3 fixture reports the spike's real defects — a missing Verdict — instead of a demand for `Requirements:` fields
- The step-5 fixture is **refused** by `archive-story.sh` with the `scale: standard` line present, exactly as it is without it
- A `scale: medium` in `design.md` is reported
- The step-9 fixture reports no orphan and exits 0
- Story 007's R2.2 legacy golden — the no-scale fixture in `tests/scale-validation.bats` — is byte-identical after the change

## Constraints

- No shared library file: `scripts/` has no lib and every script is invoked standalone by path. Where the resolution rule must exist in two scripts, follow the house convention already used for `parse_verdict` — duplicate it and give every copy a comment naming the number of consumers that move together
- `CROSS_REF` and `STRICT` are parsed after the checks run; only `DECLARED_SCALE` is safe to read earlier
- The enum check must evaluate **every** declaring artifact before a winner is chosen — a rewrite that returns early on the first match silently drops the error for an invalid value in the losing artifact
- The fix introduces no new error class: disagreement is a warning, because which artifact is wrong is the author's call

## Out of Scope

- `scripts/epic-index.sh`'s identical lookup — render-only, no decision gated on it; registered as a discovery instead
- `ARCHITECTURE.md`'s remaining stale scale statements and its silence about `epic-gitpolicy.sh`
- A shared resolution library for `scripts/`
- The shipped bugfix example's own inability to validate without warnings (it carries no `### Rn.` headings)
