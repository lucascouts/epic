---
story: root-anchored-secrets-scan
type: bugfix
scale: full
version: 1
created: 2026-08-13
status: archived
---

# Design - Bugfix: The secrets guard emits absolute fingerprints

## Root Cause Analysis

- **Symptom:** `archive-story.sh` reports 2 findings on story 005 and refuses to archive it, although both findings are already classified in the committed `.gitleaksignore`.
- **Root cause:** one argument. `run_secrets_scan()` at `archive-story.sh:1074` passes `"$STORY_ABS"` — an absolute path — as gitleaks' source. gitleaks composes `Fingerprint` as `<source-path-as-given>/<relative-file>:<rule>:<line>`, so an absolute source yields an absolute fingerprint. `.gitleaksignore` pins project-root-relative fingerprints, because that is the form gitleaks emits when the source is expressed relative to the repository root, and the form its own documentation assumes ("create a `.gitleaksignore` file at the root of your repo"). The two dialects are compared as opaque strings, so they never match.
- **Why it wasn't caught:** `tests/archive-story.bats` has 101 cases, 8 of them on the secrets guard, and **none exercises an allowlist**. Every existing case asserts on a finding being reported or the scan being skipped; not one asks whether a *classified* finding is suppressed. The guard was tested for its alarm and never for its silence.
- **A second, quieter cause, already known here:** `list-mode.md:358` documents that `gitleaks dir` defaults to `-i .`, so which allowlist applies is decided by the caller's working directory. That was recorded as a hazard and left in place. It is the same defect from the other side — the guard never states which allowlist governs it — and R2.1 closes both together.
- **Upstream context:** this is documented gitleaks behaviour, not a local anomaly — issues [#1059](https://github.com/gitleaks/gitleaks/issues/1059), [#1287](https://github.com/gitleaks/gitleaks/issues/1287), [#2107](https://github.com/gitleaks/gitleaks/issues/2107) and PR [#1354](https://github.com/gitleaks/gitleaks/pull/1354) all describe the source-path-to-fingerprint coupling. The fix adapts to it rather than waiting on it.

## Affected Components

| Component | Role in Bug | Change Needed |
|---|---|---|
| `scripts/archive-story.sh` — `run_secrets_scan()` | Passes the absolute source; relies on gitleaks' `"."` default for the allowlist | Anchor the source at the project root; pass `--gitleaks-ignore-path` explicitly |
| `scripts/archive-story.sh` — new `secrets_project_root()` | Does not exist | Resolve git top level, fall back to the `.epic/` ancestor, normalise physically |
| `scripts/archive-story.sh` — `set_secrets_json()` | Emits 7 keys; cannot express whether the allowlist applied | One additional **total** key, read from the global as `SECRETS_UNSCANNED` already is — its 5 call sites do not change |
| `references/list-mode.md` | Documents the `-i .` hazard and enumerates the `secrets{}` key set | Retract the mechanism, keep the warning, add the key |
| `.gitleaksignore` header | Instructs regeneration with `gitleaks detect` — the history dialect | Name the command that emits the dialect the guard compares against |
| `tests/archive-story.bats` | 101 cases, zero on the allowlist | Append cases; no existing assertion moves |

## Fix Approach

Surgical: one new helper, one changed command line, one additional JSON key. No control flow moves, and the guard keeps its position before the move and before the manifest write.

### 1. `secrets_project_root()` (R1.2, R1.3, R1.4)

```bash
# secrets_project_root <story-abs> — the directory the allowlist is anchored to.
#
# Resolved from the STORY, not from the caller's cwd: the allowlist that governs
# a story is the one in the story's own project, and a caller may stand anywhere.
# `.epic/` being gitignored is irrelevant here — ignore rules affect tracking,
# never repository discovery.
#
# Both candidates are normalised through `cd … && pwd -P` because STORY_ABS is
# physical (:2712) while `git rev-parse --show-toplevel` may return a LOGICAL
# path. Under a symlinked checkout the unnormalised pair disagrees, and the
# prefix strip below then silently fails to strip — producing the absolute
# fallback on a project that had a perfectly good root.
#
# Echoes the root, or nothing when there is none. Never fails the caller.
secrets_project_root() {
  local story_abs=$1 root dir
  root=$(cd "$story_abs" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) \
    && [ -n "$root" ] && (cd "$root" 2>/dev/null && pwd -P) && return 0
  # Not a git repository — Epic supports that (see epic-gitpolicy.sh), so walk up
  # for the directory that owns `.epic/`. The story itself lives INSIDE `.epic/`,
  # so the first ancestor CONTAINING one is the project root.
  dir=$story_abs
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    dir=$(dirname "$dir")
    [ -d "$dir/.epic" ] && { (cd "$dir" && pwd -P); return 0; }
  done
  return 0   # nothing found: caller takes the disclosed fallback (R3.1)
}
```

**Why git first and `.epic/` second.** gitleaks specifies the allowlist at the repository root, and in a monorepo with `.epic/` in a subproject the `.gitleaksignore` still sits at the git root — anchoring on `.epic/` there would recreate this very bug one level down. The `.epic/` walk exists only for the case git cannot answer.

### 2. The invocation (R1.1, R2.1, R3.1, R3.2, R3.3)

```bash
  # The source is expressed RELATIVE TO THE ROOT because gitleaks mirrors the
  # source path straight into every Fingerprint. Absolute source => absolute
  # fingerprint => no committed .gitleaksignore can ever match it. The `cd` is
  # inside the command substitution, so the caller's cwd never moves.
  #
  # -i is passed EXPLICITLY rather than left to its "." default: that default
  # made the effective allowlist a property of wherever the caller happened to
  # stand, which list-mode.md recorded as a way to disarm this guard.
  #
  # MEASURED, and the reason this is not a fail-open: `gitleaks dir` does NOT
  # honour .gitignore, so re-rooting does not make it skip `.epic/`. Both forms
  # read ~185801 bytes on story 005 — identical coverage, different fingerprints.
  if [ -n "$SECRETS_ROOT" ]; then
    out=$(cd "$SECRETS_ROOT" && gitleaks dir "$SECRETS_REL" --no-banner --no-color \
      --exit-code 1 --gitleaks-ignore-path "$SECRETS_ROOT" \
      --max-target-megabytes "$GITLEAKS_MAX_MB" \
      --report-format json --report-path "$report" 2>&1) && rc=0 || rc=$?
  else
    out=$(gitleaks dir "$STORY_ABS" … )   # unchanged, and disclosed
  fi
```

`SECRETS_REL` is a bash prefix strip, not a new dependency:

```bash
  SECRETS_REL=${STORY_ABS#"$SECRETS_ROOT"/}
  # Strip did nothing and the two are not the same directory => the story lies
  # OUTSIDE the root, so no relative expression exists. Disclose and fall back
  # (R3.1) rather than emitting `../../..`, which gitleaks would embed verbatim
  # into every fingerprint and no allowlist could match either.
  [ "$SECRETS_REL" = "$STORY_ABS" ] && [ "$STORY_ABS" != "$SECRETS_ROOT" ] && SECRETS_ROOT=""
  # The story IS the root — a story directory that is itself a git repository
  # resolves that way — so the strip leaves nothing. Measured on 8.30.1:
  # `gitleaks dir ""` and `gitleaks dir "."` produce identical findings and
  # identical fingerprints, so this is a fragility rather than a live defect.
  # It is pinned anyway: the equivalence is undocumented, and one character is
  # cheaper than depending on it.
  [ -z "$SECRETS_REL" ] && SECRETS_REL=.
```

`realpath --relative-to` would express this in one call and is deliberately **not** used: it appears nowhere in the tree, and a prefix strip on two identically-normalised absolute paths is exact.

### 3. The disclosure key (R3.1, R3.2)

`set_secrets_json()` emits `allowlist_root` — **always present**, `null` when no allowlist governed the scan — following the function's own established idiom for an optional scalar:

```bash
  local a_json="null"
  [[ -n "$SECRETS_ROOT" ]] && a_json=$(quote_scalar "$SECRETS_ROOT")
  SECRETS_JSON=$(printf '{ … , "error": %s, "allowlist_root": %s }' … "$e_json" "$a_json")
```

**Read from the global, not passed as a parameter — and no call site changes.** The function already mixes both: `report`, `skipped` and `error` arrive as parameters, while `SECRETS_UNSCANNED` is read straight from the global. `allowlist_root` belongs with `SECRETS_UNSCANNED`, because it is the same kind of value — a measurement the scan produced, not a decision the caller made. Two consequences, both good: the change touches **zero** of the five call sites, and the two paths that never scan — `--skip-secrets` (:2854) and gitleaks absent (:2863) — inherit the empty initial value and emit `null` without anyone having to remember to pass it. A sixth positional parameter would have made a missed site a loud arity error, which sounds safer until you notice it also makes five sites into five chances to be wrong about a value that has exactly one correct source.

**Never `printf '"%s"'` on the path.** It reaches a JSON document, and a directory name may legitimately contain a quote or a backslash; `quote_scalar` is the only correct route, exactly as it is for `report`.

**Total, not conditional.** Story 008 established the rule the hard way: a consumer must branch on a key's *value*, never on its *presence*, because an absent key and a null key are indistinguishable through `jq -r`. `list-mode.md:356` already commits to `secrets{}` keeping "one uniform shape on every path", so a key that appeared only on the fallback path would break a promise the shipped documentation has already made.

**`.secrets == {}` is unaffected**, and this was measured rather than assumed. That golden (`archive-story.bats:1495`) pins the *initial* `SECRETS_JSON='{}'` — the "blocked before the scanner was ever reached" shape — and is deliberately paired with the clean shape so the two can never be confused. `set_secrets_json` is not called on that path, so the new key cannot leak into it.

### 4. Documentation retractions (R4.1, and the honesty half of R2.1)

- **`.gitleaksignore` header (R4.1).** *Corrected during implementation:* the header already names **both** commands, `gitleaks detect` and `gitleaks dir .`, and always did — the earlier claim that it named only the first was wrong. What is genuinely missing is smaller and still worth fixing: it never says which of the two sections the archive guard can actually use (only the working-tree one — the guard scans one story's working tree), and it never says the commands must run from the project root, even though gitleaks mirrors the source path as given and the same command run elsewhere emits entries that match nothing. Both stated now, with story 009 named as the case where exactly that went wrong.
- **`list-mode.md:358`.** The paragraph's *mechanism* becomes false: the guard no longer inherits `-i .`. Its *warning* stays true and gets sharper — the project's `.gitleaksignore` is now unambiguously part of the guard's configuration, because the guard names it. Rewritten to say which allowlist applies and where, rather than warning that nobody knows.
- **`list-mode.md:356`.** The `secrets{}` key list gains `allowlist_root`, with one sentence on what `null` means.

## Regression Test Strategy

Every `SHALL CONTINUE TO` in story.md maps to a case here. Tests are appended to `tests/archive-story.bats`; **no existing assertion moves**.

- **Bug verification (R1.1, R5.1):** a fixture project with a `.gitleaksignore` classifying a fixture finding — asserts `findings: 0` and `status: archived`. Red today, because the absolute fingerprint cannot match.
- **Classification is not blanket suppression (the critical case):** the same project holding **one classified fixture and one unclassified secret** — asserts the archive is still blocked and `findings: 1`. This is the case the whole story exists for; without it, "the allowlist works" and "the guard was disabled" are indistinguishable.
- **Coverage is unchanged (Unchanged Behavior 2) — pinned twice, because one assertion cannot reach both sides.** The guard does not surface gitleaks' byte count, so at the **contract** level the pin is finding parity: a story holding three secrets at three depths, with no allowlist present, must still report three findings — a file gitleaks skipped contributes none. As a **premise**, gitleaks is invoked with a `.gitignore` covering the story to confirm `dir` still ignores it; a future release that changed that would report a clean story that is not clean, and this reddens instead.
- **Fallback discloses (R3.1, R3.2):** `allowlist_root` is `null` and the scan still runs. Only the *reachable* half is tested — a root that resolves without containing the story. The "no root at all" half cannot be produced from the command line, because the entry point refuses a story outside `.epic/` at exit 2 before the guard runs; it is defence in depth and is deliberately untested, which story.md states rather than leaves to be discovered.
- **Root resolution (R1.2, R1.3):** git project resolves the git top level; non-git project with `.epic/` resolves that directory.
- **Symlink normalisation (R1.4):** the project reached through a symlink still resolves and still suppresses. Without normalisation this silently takes the fallback.
- **Existing behaviour (Unchanged Behavior 1, 3, 4, 5, 7):** the 8 existing secrets cases are the regression suite and must pass untouched. They resolve the root through R1.3 — the harness builds its project under `mktemp -d` with `.epic/` and no git — find no allowlist there, and observe the same output as today.

**Existing test impact:** none expected. `.secrets == {}` is measured safe (§3); the other seven `.secrets.*` assertions all read individual keys. The claim will be verified by running the suite, not asserted.

## Side Effects Assessment

| Potential Side Effect | Risk | Mitigation |
|---|---|---|
| A re-rooted scan starts honouring `.gitignore` and silently skips `.epic/`, reporting 0 findings for the wrong reason | **High** — it is the failure mode that looks exactly like success | Measured false on 8.30.1 (identical 185801 bytes both ways) **and** pinned by a byte-count case, so a future gitleaks that changed this would redden a test rather than disarm the guard |
| An allowlist entry suppresses more than intended | Medium | Fingerprints pin `file:rule:line` — a moved or edited line stops matching. The one-classified-one-real case proves suppression is per-finding, not per-story |
| A story outside the project root loses its scan | Medium | R3.2: the fallback is today's behaviour plus a disclosure; it never scans less |
| The symlinked-checkout case degrades quietly to the fallback | Medium | R1.4 normalises both sides through `pwd -P`; a dedicated case covers it |
| `SECRETS_ROOT` is stale when `set_secrets_json` reads it | Low | It is initialised empty beside `SECRETS_REPORT` and assigned only inside `run_secrets_scan`, which runs at most once per invocation — there is no second archive to carry a value into. The `--skip-secrets` and gitleaks-absent cases assert `null` precisely here |
| Scope creep into the oversize enumeration, which also reads `$STORY_ABS` | Low | Named in story.md as the most likely over-reach; it asks the filesystem, not gitleaks, and does not move |

## Tooling Decisions

- **E2E tool: none.** This is a shell CLI with no browser surface, so no E2E sub-task exists and no favorite applies. Recorded per `preferred-tooling.md` rather than left implicit.
- **Test framework: `bats`**, the project's only one — 386 cases across `tests/`.
- **`frontend-design`: not applicable.**
- **Research MCPs used:** `context7` (`/gitleaks/gitleaks`) and `brave-search`, both health-checked. `brave-search` established that the fingerprint coupling is documented upstream behaviour. `perplexity` was not consulted — premium cost, and the policy forbids it as a default.

## Integration Points

- **The entry point bounds the resolver's input, and that bound is load-bearing.** `archive-story.sh` refuses any path that does not live in a `.epic/` directory — measured: `exit 2`, *"does not live in a .epic/ directory … expected `<project>/.epic/stories/<NNN>-<slug>`"* — and it refuses before the guard runs. Every story that reaches `run_secrets_scan` therefore has a `.epic/` ancestor, which is why the `.epic/` fallback always answers and why R3.1's first half is unreachable. A future change that relaxed this check would make that branch live for the first time, so it is noted here rather than in a comment nobody would connect to it.
- `run_secrets_scan()` keeps its three-value contract (0 clean / 1 findings / 2 untrustworthy) and its position before both the move and the manifest write.
- `set_secrets_json()` is the only emitter of `secrets{}`; `list-mode.md` and `validate-mode.md` are its documented consumers.
- `hook-task-completed.sh` reads `.error_details[]`, not `secrets{}` — unaffected.
- No other script invokes gitleaks: `run_secrets_scan` is the sole call site, measured across `scripts/` and `bin/`.

## Known Divergence — the allowlist outlives the path it pins

An entry pinned to `.epic/stories/NNN-…` is orphaned the moment the story moves to `.epic/archive/NNN-…`, and under story 007's `tracked-md` policy that archived copy is committed, so a repository-wide scan reports it again under the new path. This is registered, not fixed: its cause is the move, not the anchoring, and closing it would give a read-only script write access to `.gitleaksignore`. Named here so the next person meets it as a known boundary rather than as a surprise.
