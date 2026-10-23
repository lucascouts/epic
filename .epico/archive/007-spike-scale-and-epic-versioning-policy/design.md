---
story: spike-scale-and-epic-versioning-policy
type: feature
scale: full
status: archived
version: 2
created: 2026-08-02
last-refined: 2026-08-09
history:
  - v1: Initial story
  - v2: Task 5 — close the validate-007 findings (spike exemption in Run, four unpinned branches, honest gates and complete registers). No component or interface changed.
---

# Design - Spike Scale & .epic Versioning Policy

## Overview

Two "legalize what users already do" capabilities. First, **`scale: spike`**: the corpus's heaviest canonical user ran 15+ tasks-only exploration dirs (probes, experiment harnesses) that the census misread as broken stories — spikes are a real work shape with no sanctioned home, and seeds died without a deadline (pmg 071 waited 35 days for a refine that never came). Second, an **official `.epic` versioning policy**: the absence of one destroyed history (54 stories wiped in a track→untrack transition; 9 zombie duplicates from a squash), while the three projects with the best auditable lifecycle all converged on the same model — **version the `.md` artifacts, ignore `.draft/`**. Per user decision this becomes the init wizard's recommended, explicit choice (not a silent default), because it deliberately supersedes the older "never commit .epic" doctrine.

## Components & Interfaces

### 1. `scale: spike`

- **Contract:** tasks-only (like Fast) + a MANDATORY `## Verdict` section; no story.md, no design.md, no `.draft/`, no R-chain (R-refs are an error, closing the dangling-pointer hole Fast has); single-author, no sub-agents.
- **Verdict section (the spike's reason to exist — a spike without a conclusion is a leak):**

```markdown
## Verdict
- status: open | promote | wont-do
- conclusion: <1-5 lines: what was learned>
- promoted-to: NNN   # required when status: promote
```

- **Lifecycle:** created `status: draft` → `in-progress` (004 engine) → terminal via Verdict: `promote` (orchestrator offers CREATE for the follow-up story, pre-filled with the conclusion; `promoted-to:` recorded; spike becomes archivable) or `wont-do` (terminal, archivable). Verdict `open` past **14 days** (mtime of tasks.md, reusing `monitor-stale.sh:36-61` logic inline) → LIST stale-warning: `spike open 14+ days — promote or close`.
- **Routing/triage:** SKILL.md scales table (:243-249) + complexity table (:285-291) gain the spike row — signals: "probe", "experiment", "spike", "harness", "descobrir se/whether", explicit user request. Triage proposes spike ONLY on exploratory intent; never auto-downgrades a feature to spike. `references/tasks.md` gains a spike adaptations block (mirroring the Fast block :195-203). `userConfig.defaultScale` (plugin.json:24-29) accepts `spike`.
- **Validation:** see component 3 — spike requires the scale-aware validator.

### 2. `.epic` versioning policy (init wizard)

- **The policy (recommended option):** git-track `story.md`, `design.md`, `tasks.md`, `archive/manifest.yaml`, `EPIC.md`; git-ignore `.draft/` (logs, authored-tests, snapshots, wip) — exactly the shidashi/wakeru/kpranois proven model.
- **Mechanism:** `references/init-mode.md` step 5 (:25-27, which today writes `.epic/.gitignore` excluding `.draft/`) becomes an **explicit question** with two options:
  1. *Versionado (recomendado):* ensure root `.gitignore` does NOT ignore `.epic/` (detect + offer to remove the line); write `.epic/.gitignore` containing `.draft/` and `*.wip`.
  2. *Local-only:* add `.epic/` to root `.gitignore` (current doctrine, kept as a first-class choice).
  The choice is recorded in `.epic/.gitpolicy` (one line: `tracked-md` | `local-only`) so tooling can lint against intent. Non-interactive init: default `local-only` (the conservative status quo — never silently start committing).
- **Contradiction lint — `scripts/epic-gitpolicy.sh` (new, tiny, read-only):** output JSON `{policy: tracked-md|local-only|undeclared, gitignore_ignores_epic: bool, tracked_md: N, tracked_draft: N, verdict: consistent|contradiction|partial}`. The corpus motivation: kpranois committed 47 `.epic` files THROUGH a `.gitignore` that said "never committed"; bentoolkit flip-flopped 5× and produced zombies. Consumers: LIST header shows one line when `verdict != consistent`; init runs it before asking (pre-fills the detected state).
- **Docs:** README + init-mode document the policy and its why (history destruction evidence); the user's own global-rule conflict is called out in README as "escolha por projeto — o init pergunta".

### 3. Scale-aware validation (`validate-story.sh`)

Today the validator infers scale from FILES PRESENT (:71-88) and never reads `scale:` — which is how `scale: medium` shipped unnoticed and how a spike would be mis-validated as Fast. Changes:

- Read `scale:` from frontmatter FIRST; file-inference becomes the fallback (legacy tolerance: absent field keeps today's behavior byte-for-byte).
- `scale:` present but not in `fast|standard|full|spike` → **error** (catches `medium`).
- `scale: spike` branch: require `## Verdict` with valid `status:` line; `promote` without `promoted-to:` → error; any `Requirements:` field or R-token in tasks.md → error ("spikes have no R-chain — promote to a story for traceability").
- `scale:` vs files mismatch (e.g. `spike` with story.md) → warning.

## Error Handling Strategy

- Spike promote flow interrupted after Verdict but before CREATE: `promoted-to:` may point to a not-yet-existing story — LIST renders `promote → (pending)`; next `stories` invocation re-offers the CREATE.
- gitpolicy in a non-git workspace: `{policy: …, verdict: consistent}` with `git: false` — silent.
- Init question skipped (user aborts): no `.gitpolicy` written; lint reports `undeclared` only in `stories full` (low noise).

## Testing Strategy

- **Unit (bats):** scale enum validation (each valid + `medium` error + absent = legacy fallback path asserted byte-identical on a legacy fixture); spike checks (missing Verdict, `open`/`promote`/`wont-do` matrix, `promote` without `promoted-to`, R-ref error); gitpolicy verdict matrix (tracked-md consistent, local-only consistent, kpranois-style contradiction, partial `.draft` tracking); stale threshold (13 vs 15 days fixtures via touch -d).
- **Integration (bats):** init wizard branch writes the right `.gitignore` + `.gitpolicy` in a temp repo (both options); LIST renders spike stale-warning and gitpolicy contradiction line.
- **E2E:** none (tool: none).

## Tooling Decisions

- E2E tool: none — no E2E tooling applicable (bats + shellcheck harness)
- Frontend aid: none
- Recommendation surfaced: no

## Integration Points

- **Depends on 004:** engine `status:` transitions apply to spikes; `[~]` grammar available in spike tasks.
- **Story 005:** spikes are archivable once Verdict is terminal (preflight accepts `wont-do`/promoted spikes); `epic-index.sh` renders spike verdicts.
- **SKILL.md:** scales/complexity tables, frontmatter spec (`scale: spike`), routing untouched otherwise.
- **references:** tasks.md (spike block), init-mode.md (step-5 question), list-mode.md (stale-warning + gitpolicy line).
- **monitor-stale.sh:** spike threshold (14d) added alongside the existing story threshold — same mtime helper, no duplication.
