---
story: root-anchored-secrets-scan
type: bugfix
scale: full
version: 1
created: 2026-08-13
status: archived
---

# Bugfix - The secrets guard emits absolute fingerprints, so the project's allowlist can never suppress a classified fixture

## Summary

`scripts/archive-story.sh` runs `gitleaks dir "$STORY_ABS"` with an absolute path. gitleaks builds every `Fingerprint` by mirroring the source path **as it was given**, so the guard emits machine-absolute fingerprints while `.gitleaksignore` — which gitleaks itself specifies as living at the root of the repository — pins project-root-relative ones. The two dialects can never match, so a finding a maintainer has already classified is reported again on every run. Story 005 cannot be archived for exactly this reason: its two findings are AWS-shaped literals in test fixtures, already pinned in the committed allowlist, and the guard cannot see that classification. The only escape is `--skip-secrets`, which disables the scan for the **whole story** — so a real secret sitting beside a classified fixture would be archived in silence. A guard whose only override is the master switch is a guard that gets switched off by habit.

## Reproduction Steps

Each step below was executed on gitleaks 8.30.1; the quoted output is measured, not predicted.

1. Confirm the classification already exists. The committed `.gitleaksignore`'s **working-tree** section already holds exactly story 005's two findings, written project-root-relative (cited by content rather than by line number, per story 008's lesson that only the name survives an edit — and these two were later repointed to `.epic/archive/…` when 005 was archived):
   `.epic/stories/005-archive-in-the-flow/.draft/authored-tests/tests/archive-story.bats:aws-access-token:276` and `:289`.
2. Run the guard's own command line with the absolute path it passes today —
   `gitleaks dir "$PWD/.epic/stories/005-archive-in-the-flow" --report-format json --report-path A.json` →
   **2 findings**, each fingerprint prefixed with the machine path: `/home/otaku/Projetos/Pessoais/claude-code/epic/.epic/stories/005-.../archive-story.bats:aws-access-token:276`.
3. Run the identical scan with the source expressed **relative to the project root**, from the project root —
   `gitleaks dir ".epic/stories/005-archive-in-the-flow" …` → **0 findings**. Both runs report `scanned ~185801 bytes`, so step 3 is not an empty scan wearing a green mask; it is the same scan whose fingerprints finally match lines 16-17.
4. Rule out allowlist *discovery* as the cause: repeat step 2 adding `--gitleaks-ignore-path "$PWD/.gitleaksignore"` → still **2 findings**. Handing gitleaks the file directly changes nothing, because the fingerprints on both sides are written in different dialects.
5. Rule *matching* in: repeat step 2 with an allowlist containing the two **absolute** fingerprints from step 2 → **0 findings**. The suppression mechanism works; only the anchoring is wrong.
6. Run the guard end to end — `bash scripts/archive-story.sh .epic/stories/005-archive-in-the-flow` → exit **1**, `{"status":"blocked","moved":false,"secrets_findings":2}`, and a reason offering `--skip-secrets` as the only alternative.
7. Read the flag's own default — `gitleaks dir --help` → `-i, --gitleaks-ignore-path string   path to .gitleaksignore file or folder containing one (default ".")`. The allowlist is sought in the **current working directory**, never in the scan target, which is why step 4 could rule discovery out and why the guard's behaviour silently depends on where its caller happened to stand.

## Current Behavior (Defect)

WHEN the guard scans a story THEN the system passes an absolute source path, so every fingerprint it emits carries a machine-specific prefix that no committed allowlist can match.

WHEN a maintainer classifies a finding in `.gitleaksignore` using the project-root-relative form that gitleaks documents THEN the system reports that finding again on the next run, as though it had never been classified.

WHEN a maintainer instead copies a fingerprint out of the guard's own report THEN the system accepts an entry that is bound to one machine's directory layout, so the allowlist stops being portable across checkouts and CI.

WHEN a story contains a classified fixture and nothing else THEN the system blocks the archive and offers `--skip-secrets`, which disables the scan for the entire story — so the only available response to two known-benign findings also silences every unknown one beside them.

WHEN the guard runs THEN the system relies on gitleaks' `"."` default to locate the allowlist, so which allowlist applies — or whether any applies — is decided by the caller's working directory rather than by the project.

WHERE `.gitleaksignore` documents how to regenerate its own entries THEN the system names both `gitleaks detect` and `gitleaks dir .` without saying **which of the two dialects the archive guard compares against**, or that both must be run from the project root — so a maintainer has two sections, no rule for choosing between them, and a command whose output silently depends on the directory it was run from.

*This bullet originally claimed the header names only `gitleaks detect`. It names both, and has since it was written. The claim was corrected here rather than left standing, and R4.1 was rewritten around what is actually missing — which is smaller than what was first asserted.*

## Expected Behavior (Correct)

### R1. The scan is anchored at the project root

- R1.1: WHEN the guard scans a story directory THE SYSTEM SHALL express the scan source relative to a resolved project root, so that every emitted fingerprint is project-root-relative
- R1.2: WHERE the project is a git repository THE SYSTEM SHALL resolve the project root as git's top level, because that is where gitleaks specifies `.gitleaksignore` lives
- R1.3: WHERE the project is not a git repository THE SYSTEM SHALL resolve the project root as the nearest ancestor directory containing `.epic/`
- R1.4: WHEN the project root and the story path are compared THE SYSTEM SHALL normalise both through the same physical-path resolution, because `pwd -P` returns the physical path while `git rev-parse --show-toplevel` may return a logical one, and a symlinked checkout makes the two disagree

### R2. The allowlist is located by the project, not by the caller

- R2.1: WHEN the guard invokes gitleaks THE SYSTEM SHALL pass `--gitleaks-ignore-path` resolved from the project root, rather than relying on the `"."` default
- R2.2: WHERE the resolved project root holds no `.gitleaksignore` THE SYSTEM SHALL scan and report exactly as it does today, with no error and no additional output
- R2.3: WHEN the guard reports a finding THE SYSTEM SHALL emit a fingerprint that a maintainer can paste into the project's `.gitleaksignore` unedited

### R3. An unusable root degrades loudly, never silently

- R3.1: WHERE the project root cannot be resolved, **or resolves to a directory that does not contain the story**, THE SYSTEM SHALL scan the story by absolute path and SHALL state, in the machine-readable output, that no project allowlist was applied
- R3.2: WHEN that fallback is taken THE SYSTEM SHALL NOT reduce what is scanned and SHALL NOT mark the story unscanned — the fallback is today's behaviour with a disclosure added, so it reports at least as many findings as before and never fewer

**One half of R3.1 is unreachable through the current entry point, and that is stated rather than hidden.** `archive-story.sh` refuses any story that does not live in a `.epic/` directory — measured: `exit 2`, *"does not live in a .epic/ directory … expected `<project>/.epic/stories/<NNN>-<slug>`"* — and it refuses **before** the guard runs. So a story that reaches the scan always has a `.epic/` ancestor, and the `.epic/` fallback always finds a root: the "no root at all" branch cannot be produced from the command line. It is retained as defence in depth, because the resolver must never fail its caller, and it is deliberately left without a test — a test for it would have to manufacture a state the entry point exists to forbid. The **reachable** half is a root that resolves but does not contain the story, which a symlinked checkout produces when the two sides are not normalised (R1.4), and which an inherited `GIT_WORK_TREE` — the kind a git hook exports — produces directly.

### R4. The allowlist says which of its two dialects the guard reads

- R4.1: WHERE `.gitleaksignore` documents how to regenerate its entries THE SYSTEM SHALL state that the working-tree section (`file:rule:line`) is the only one the archive guard can use, and SHALL state that both regeneration commands are run from the project root — because gitleaks mirrors the source path as given, so the same command run elsewhere produces entries that match nothing

### R5. The motivating story archives without an override

- R5.1: WHEN `bash scripts/archive-story.sh .epic/stories/005-archive-in-the-flow` runs **without** `--skip-secrets` THE SYSTEM SHALL report `findings: 0` and archive the story

## Unchanged Behavior (Regression Prevention)

- WHEN a story holds a secret that no allowlist classifies THE SYSTEM SHALL CONTINUE TO block the archive, move nothing and write no manifest entry — the guard still runs before both, as story 005's R1.3 requires
- WHEN the scan runs THE SYSTEM SHALL CONTINUE TO cover exactly the story directory and nothing else. Only how the path is *expressed* changes; how much is *read* does not. This is the fail-open trap the fix could otherwise introduce — a scan re-rooted so that gitleaks skipped the story would report 0 findings for the wrong reason, and would look exactly like success. It is pinned in **two** places, because the guard does not surface gitleaks' byte count in its output and no single assertion covers both sides: at the contract level, a story holding three secrets at three depths with no allowlist present must still report three findings; and as a premise, gitleaks is invoked directly to confirm that `dir` still ignores `.gitignore`, so a future release that changed that reddens a test instead of disarming the guard
- WHEN gitleaks is absent from `PATH` THE SYSTEM SHALL CONTINUE TO archive the story UNSCANNED and emit the same `gitleaks-not-installed` notice
- WHEN `--skip-secrets` is passed THE SYSTEM SHALL CONTINUE TO bypass the scan and record the override in the manifest entry — this story adds no second master switch, because a working allowlist *is* the per-finding escape that was missing
- WHEN a finding is reported THE SYSTEM SHALL CONTINUE TO keep every matched value out of stdout, stderr and the permanent record, with the report written mode 600 inside a private `mktemp -d` outside the story directory
- WHEN the oversize-file enumeration runs THE SYSTEM SHALL CONTINUE TO ask the filesystem through `$STORY_ABS` — that lookup is deliberately not gitleaks' and is not what moves; changing it too is the most likely over-reach in this fix
- WHEN gitleaks exits in any of its ambiguous ways THE SYSTEM SHALL CONTINUE TO discriminate on the report file exactly as it does today: exit 1 is both the findings code and the fatal code, and the report is what tells them apart
- WHEN the 101 existing cases of `tests/archive-story.bats` run THE SYSTEM SHALL CONTINUE TO pass with **no assertion semantics changed**. This is load-bearing and was measured, not assumed: the harness builds its fixture project under `mktemp -d`, containing `.epic/` and **no** git repository, so R1.3 resolves that directory as the root, the story lies under it, and no `.gitleaksignore` exists there — the guard's observable output is therefore unchanged for all 8 existing secrets cases

## Success Metrics

- Story 005 archives with `findings: 0` and no `--skip-secrets`, where today it reports `{"status":"blocked","moved":false,"secrets_findings":2}` at exit 1
- A fingerprint taken from the guard's report can be pasted into `.gitleaksignore` unedited and suppresses that finding on the next run
- A story holding an **unclassified** AWS-shaped literal still blocks — the existing `2.2: gitleaks finding blocks the archive with a findings count` case passes untouched
- The byte count gitleaks reports for a given story directory is identical before and after the change — measured by invoking gitleaks directly, since the guard does not surface it

## Constraints

- `scripts/` has no shared library and every script is invoked standalone by path. Where a rule must exist in more than one script, follow the house convention already used for `parse_verdict` and the scale readers — duplicate it and give every copy a comment naming how many consumers move together
- The fix must not widen the scan. Re-rooting is a change of expression, not of scope
- No new master switch and no new opt-out flag: the corrected allowlist is the per-finding escape
- The repository is already GNU-assuming (`sed -i` without an argument, `readlink -f`) and its CI runs only `ubuntu-latest`, so no portability *regression* is possible here — but the relative path SHALL still be computed with a bash prefix strip rather than by adding `realpath --relative-to`, which appears nowhere in the tree today
- The guard's position in the archive sequence — before the move and before the manifest write — must not change

## Out of Scope

- **Allowlist entries going stale after a story archives.** The move to `.epic/archive/NNN-…` changes the path, so any entry pinned to `.epic/stories/NNN-…` is orphaned. Under story 007's `tracked-md` policy that archived copy is committed, and a repository-wide scan will report it again under its new path. Named here because it is a real consequence with a real user, not a hypothetical — but it has a different root cause and a different fix (rewriting entries during the move), and folding it in would add write access to `.gitleaksignore` from a script that only reads today
- A `--secrets-allowlist <path>` flag. Considered and declined: it adds a second surface to test and a second way to disable the guard
- gitleaks' own inconsistency between `git` and `dir` fingerprint paths (upstream issues #1059, #1287, #2107 and PR #1354). This story adapts to the documented behaviour rather than waiting on it
- `--baseline-path` as an alternative suppression mechanism
- Any change to how `epic-gitpolicy.sh` or the `.gitignore` posture treat `.epic/`
