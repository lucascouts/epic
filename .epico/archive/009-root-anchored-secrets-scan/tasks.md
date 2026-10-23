---
story: root-anchored-secrets-scan
type: bugfix
scale: full
version: 1
created: 2026-08-13
status: archived
---

# Implementation Plan - Bugfix: The secrets guard emits absolute fingerprints

## Overview

One helper, one command line, one JSON key. Task 1 lands the whole behavioural fix in a single commit — including the `list-mode.md` paragraph that the change falsifies, because a retraction belongs in the commit that falsifies it, not in a tidy-up afterwards. Task 2 corrects the allowlist's own regeneration instruction, which is the same defect expressed as documentation. Task 3 closes the loop the story opened: classify the new suite's own fixtures and archive story 005 without an override.

**Every test here is Integration, and that is a finding, not a shortcut.** `archive-story.sh` executes on invocation and cannot be sourced, so `secrets_project_root()` is observable only through the guard's output. Labelling any of these Unit would describe a test that cannot exist.

## Task List

- [x] 1 - Anchor the scan at the project root and disclose the allowlist
  - _Complexity: Moderate | Tests: Integration | Risks: a re-root that makes gitleaks skip `.epic/` reports 0 findings for the wrong reason — pinned by a byte-count assertion | Dependencies: None_
  - Objective: The guard emits project-root-relative fingerprints, names the allowlist it used, and never scans less than it does today.

  - [x] 1.1 - Resolve the project root and express the story relative to it
    - _Complexity: Moderate_
    - Context:
      - Files: `scripts/archive-story.sh:2712` (`STORY_ABS` is physical — `cd … && pwd -P`), `scripts/run-evals.sh:16` (the only existing `--show-toplevel` use; reusable idiom, unusable failure mode — it aborts on non-git)
      - Docs: gitleaks fingerprint composition (context7 `/gitleaks/gitleaks`); upstream issues #1059, #1287, #2107
    - Objective: Add `secrets_project_root()` and compute the story's path relative to what it returns.
    - ToDo: Add `secrets_project_root <story-abs>` above `run_secrets_scan`. Try `cd "$story_abs" && git rev-parse --show-toplevel`; **on failure do not propagate — that is the expected non-git path**, so swallow it and walk ancestors for one containing `.epic/`. Normalise every returned candidate through `(cd … && pwd -P)`, matching how `STORY_ABS` is built at :2712 — an unnormalised git *logical* path silently fails the prefix strip under a symlinked checkout and degrades a perfectly good project to the fallback. Return empty when nothing is found; the function never fails its caller. Then set `SECRETS_REL=${STORY_ABS#"$SECRETS_ROOT"/}` and, when the strip changed nothing and the two are not the same directory, clear `SECRETS_ROOT` so the caller takes the disclosed fallback rather than emitting `../../..`. When the strip leaves the value **empty** — the story directory is itself the resolved root, which happens when it is its own git repository — set it to `.`; `gitleaks dir ""` and `gitleaks dir "."` were measured identical on 8.30.1, so this pins an undocumented equivalence rather than fixing a live defect. Do not use `realpath --relative-to`: it appears nowhere in the tree, and a prefix strip on two identically-normalised absolute paths is exact.
    - Tests: Integration · `tests/secrets-allowlist.bats` — git-rooted project resolves the git top level, non-git project with `.epic/` resolves that directory, symlinked checkout still resolves and still suppresses, a root that does not contain the story falls back
    - Validation: `bats tests/secrets-allowlist.bats` — the resolution cases pass
    - Requirements: R1.1, R1.2, R1.3, R1.4, R3.1

  - [x] 1.2 - Invoke gitleaks from the root, with the allowlist named
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/archive-story.sh:1074` (the invocation), `references/list-mode.md:358` (the `-i .` hazard this removes)
    - Objective: Pass a root-relative source and an explicit `--gitleaks-ignore-path`, keeping the caller's working directory untouched.
    - ToDo: When `SECRETS_ROOT` is non-empty, run the scan as `out=$(cd "$SECRETS_ROOT" && gitleaks dir "$SECRETS_REL" … --gitleaks-ignore-path "$SECRETS_ROOT" …)` — the `cd` lives inside the command substitution, so the main shell never moves. Keep `--report-path` absolute (it already is: a private `mktemp -d`). When `SECRETS_ROOT` is empty, leave today's absolute invocation byte-for-byte unchanged. **Do not touch the `case "$rc"` block**: gitleaks' exit-code ambiguity and its report-file discriminator are unrelated to this change, and every failure branch keeps returning through the existing paths rather than aborting.
    - Tests: Integration · `tests/secrets-allowlist.bats` — a classified fixture is suppressed and the story archives, one classified fixture beside one real secret still blocks with `findings: 1`, three secrets at three depths still yield three findings with no allowlist present, a `.gitignore` covering the story does not reduce what is read
    - Validation: `bash scripts/archive-story.sh .epic/stories/005-archive-in-the-flow` reports `secrets.findings: 0`
    - Requirements: R1.1, R2.1, R2.2, R3.2

  - [x] 1.3 - Make `allowlist_root` a total key on every emitted object
    - _Complexity: Simple_
    - Context:
      - Files: `scripts/archive-story.sh:967-978` (`set_secrets_json` — note it already reads `SECRETS_UNSCANNED` from the global while taking `report`, `skipped` and `error` as parameters), `:932` (where `SECRETS_REPORT` is initialised, and where `SECRETS_ROOT` joins it)
      - Files: `tests/archive-story.bats:1495` (`.secrets == {}` — the "never ran" shape, measured unaffected)
    - Objective: The output states which allowlist governed the scan, on every path.
    - ToDo: Emit `"allowlist_root": <path|null>` from `set_secrets_json`, reading `SECRETS_ROOT` from the global exactly as `SECRETS_UNSCANNED` is read — it is the same kind of value, a measurement the scan produced rather than a decision the caller made. Use the function's own idiom for an optional scalar: `local a_json="null"; [[ -n "$SECRETS_ROOT" ]] && a_json=$(quote_scalar "$SECRETS_ROOT")`. **Never `printf '"%s"'` on the path** — it reaches a JSON document and a directory name may legitimately contain a quote or a backslash; `quote_scalar` is the only correct route, as it already is for `report`. Initialise `SECRETS_ROOT=""` beside `SECRETS_REPORT` at :932 so the two paths that never scan — `--skip-secrets` (:2854) and gitleaks-absent (:2863) — inherit it and emit `null` with **no call site changing**. The key is total, never conditional: `list-mode.md:356` already promises `secrets{}` keeps one uniform shape on every path, and story 008 established that a consumer must branch on a key's value rather than its presence — `jq -r` cannot tell an absent key from a null one. Leave the initial `SECRETS_JSON='{}'` alone; it is a different shape with its own meaning.
    - Tests: Integration · `tests/secrets-allowlist.bats` — the key is *present* on every scanning path (asserted with `has()`, never with `== null`, which cannot tell an absent key from a null one), it names the root when one was used, it is `null` under `--skip-secrets`, and `.secrets == {}` still holds on the blocked-before-scan path
    - Validation: `bats tests/archive-story.bats` — 101/101, including the `.secrets == {}` golden
    - Requirements: R2.3, R3.1

  - [x] 1.4 - Retract the `-i .` paragraph the change falsifies
    - _Complexity: Trivial_
    - Context:
      - Files: `references/list-mode.md:356` (the `secrets{}` key list), `references/list-mode.md:358` (the hazard paragraph)
    - Objective: The shipped documentation describes the guard that now exists.
    - ToDo: Rewrite :358. Its **mechanism** is now false — the guard no longer inherits `-i .` from the caller. Its **warning** stays true and gets sharper: the project's `.gitleaksignore` is part of the guard's configuration, and the guard now names it in `allowlist_root` so a reader can check which one applied. Do not delete the warning; a reader who learns the allowlist can suppress findings is better served than one who learns nothing. Add `allowlist_root` to the key list at :356 with one sentence on what `null` means. This lands in Task 1's commit, not a later one — the sentence becomes false in this commit and is corrected in it.
    - Validation: `command grep -n 'allowlist_root' references/list-mode.md` returns both the key list and the paragraph; no occurrence of `-i .` survives as a live claim
    - Requirements: R2.1, R3.1

  - [x] 1.5 - Commit
    - Validation: `bats tests/` — 386 existing cases plus the new suite, zero failures; `shellcheck scripts/*.sh bin/*` clean
    - Commit: "fix(009): anchor the secrets scan at the project root so the allowlist applies"

- [x] 2 - Make the allowlist teach the dialect the guard compares against
  - _Complexity: Trivial | Tests: None — documentation; the dialect itself is proven by Task 1.2's suppression case | Risks: None | Dependencies: None_
  - Objective: A maintainer who follows `.gitleaksignore`'s own instructions produces entries that work.

  - [x] 2.1 - Correct the regeneration instruction
    - _Complexity: Trivial_
    - Context:
      - Files: `.gitleaksignore` (header comment, the `Regenerate after touching…` line)
    - Objective: Name the command that emits `file:rule:line`, not `commit:file:rule:line`.
    - ToDo: Replace the `gitleaks detect` instruction with the `dir`-mode equivalent, run from the project root, and state in one line why the dialect matters — `detect` walks history and emits `commit:file:rule:line`, while the guard scans the working tree and compares `file:rule:line`, so entries produced by the old instruction can never match. Leave every existing entry untouched: the history-dialect entries already present serve repository-wide scans and are not what this changes.
    - Validation: Following the corrected instruction on a known finding produces a fingerprint that suppresses it on re-run
    - Requirements: R4.1
    - Commit: "docs(009): the allowlist's regeneration instruction names the dialect the guard reads"

- [x] 3 - Close the loop the story opened
  - _Complexity: Simple | Tests: Covered by Task 1.2 | Risks: fingerprints pin line numbers, so entries regenerated before the suite is final are stale on arrival | Dependencies: Task 1, Task 2_
  - Objective: Story 005 archives without an override, and the new suite's own fixtures are classified rather than left to trip the next run.

  - [x] 3.1 - Classify the new suite's fixtures
    - _Complexity: Simple_
    - Context:
      - Files: `.gitleaksignore` (entries), `tests/secrets-allowlist.bats` (the new AWS-shaped literals)
    - Objective: The repository's own scans do not report the fixtures this story adds.
    - ToDo: The new suite must contain AWS-shaped literals gitleaks genuinely detects — a key the scanner ignores would make every suppression case a tautology, which is the reasoning `.gitleaksignore`'s own header already records. Generate the entries **after** the suite's contents are final, using the corrected Task 2.1 instruction, because a fingerprint pins `file:rule:line` and any later edit above a fixture invalidates it. Add them under the existing header, and extend the header's list of what is classified rather than leaving the new entries unexplained.
    - Validation: `gitleaks dir . --gitleaks-ignore-path .` from the project root reports no finding in `tests/secrets-allowlist.bats`
    - Requirements: R4.1

  - [x] 3.2 - Archive story 005 without an override
    - _Complexity: Trivial_
    - Context:
      - Files: `.epic/stories/005-archive-in-the-flow/` (the motivating story), `.gitleaksignore:16-17` (its two findings, already classified)
    - Objective: The live proof the fix works, on real fixtures and a real allowlist.
    - ToDo: Run `bash scripts/archive-story.sh .epic/stories/005-archive-in-the-flow` with **no** guard flags. **This moves a directory — confirm with the user before running it, and never re-run a blocked archive with an override on your own initiative**, which is what `validate-mode.md:197` requires. If it blocks, the fix is incomplete: report the verdict and stop rather than reaching for `--skip-secrets`.
    - Validation: exit 0, `status: archived`, `secrets.findings: 0`, `overrides_used: []`, and `allowlist_root` naming the project root
    - Requirements: R5.1

  - [x] 3.3 - Commit
    - Validation: `bats tests/` green; `bash scripts/validate-story.sh` on the remaining live stories reports no new error
    - Commit: "chore(009): classify the new secrets fixtures and archive story 005 unaided"

## Quality Gates

- [x] All acceptance criteria validated — R1.1 through R5.1 each traced to a passing case or a measured command
- [x] All task validations pass
- [x] All tests written and passing — the new suite plus the 386 existing cases
- [x] Code integrated (no orphaned implementations) — `secrets_project_root` is called by `run_secrets_scan`, and `allowlist_root` reaches every one of `set_secrets_json`'s five call sites without any of them changing, asserted with `has()` rather than by reading the source
- [x] Error handling implemented — `secrets_project_root` never fails its caller; the non-git path is expected, not exceptional; the fallback discloses instead of degrading silently
- [x] Coverage unchanged — the byte count gitleaks reports for a given story is identical before and after, pinned by an assertion and not merely observed
- [x] No new override — `--skip-secrets` remains the only guard flag; the corrected allowlist is the per-finding escape
- [x] Documentation matches the shipped guard — `list-mode.md`'s mechanism and key list, and `.gitleaksignore`'s regeneration instruction
