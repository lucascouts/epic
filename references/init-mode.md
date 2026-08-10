# Init Mode

Triggered by `/epic:epic init`. Interactive wizard to set up project configuration files.

## Procedure

1. **Scan project** — detect language, framework, dependencies, existing config files
2. **Check existing files** — report which of `CLAUDE.md`, `.claude/agents/`, `.epic/constitution.md` already exist
3. **Interactive questionnaire** — ask questions in a single numbered block:

   **For `.epic/constitution.md`:**
   - Testing philosophy? [1] TDD [2] Test-after (default) [3] Minimal
   - Hard constraints? (e.g., "no ORMs", "integration tests hit real DB")
   - Commit style? (auto-detect from git log if available)

   **For `CLAUDE.md` (if not exists):**
   - Project description? (one line)
   - Key conventions to enforce?
   - Files/patterns Claude should never modify?

   **For `.claude/agents/` (if not exists):**
   - Create custom sub-agents? Common templates:
     [1] Code reviewer [2] Test writer [3] None (default)

4. **Generate files** — create all requested files with sensible defaults based on scan
5. **Ask the versioning-policy question** — measure first, offer exactly two options, then write the chosen state. Defined once, below: [Versioning Policy](#versioning-policy). A non-interactive run never asks and never starts tracking (R3.4)
6. **Report** — list all files created, and name the policy that was recorded

## Rules

- Never overwrite existing files without confirmation
- Auto-detect as much as possible from the project (language, framework, patterns)
- Defaults should be safe and conservative
- Each generated file includes comments explaining its purpose
- **Init writes files and nothing else.** It never runs `git add`, `git rm --cached`, `git commit` or `git checkout` — not in either policy branch, not in a headless run. Choosing to version artifacts is a declaration; committing them is the user's next action, and this is the wizard that must never make it for them

## Versioning Policy

**Why this is a question and not a default.** Across a 26-project corpus, the absence of a *declared* policy is what destroyed lifecycle history. A track→untrack transition **wiped 54 stories** in one project; a squash left **9 zombie duplicates** straddling `stories/` and `archive/` in another. One project (`kpranois`) had **47 `.epic` files committed THROUGH a `.gitignore` that said they were never committed**, and another (`bentoolkit`) **flip-flopped its policy five times**. Meanwhile the three projects with the most auditable lifecycle had all deliberately broken the older "never commit `.epic`" doctrine and converged on the same model: **version the `.md` artifacts, ignore `.draft/`**. That model is option 1 and it is *recommended* because it is the measured winner; it is still a *question* because every failure above came from a policy nobody ever said out loud.

**The recommended policy tracks exactly `story.md`, `design.md`, `tasks.md`, `EPIC.md` and `archive/manifest.yaml` — never `.draft/`.** `.draft/` is scratch space (run logs, authored tests, phase snapshots, `*.wip`) and is in no policy's tracked set.

**The per-project choice supersedes any global doctrine.** A global rule that says "never commit `.epic`" — in a user-level `CLAUDE.md` or a personal convention — is superseded by whatever this question records for this project. Init never reads, edits or reports on the user's global configuration; it asks, and the answer governs this repository.

### Step 5.1 — Measure before asking

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic-gitpolicy.sh"
```

Run it from the **workspace root** — it resolves `.epic/` against `$PWD` — and read the JSON it prints on stdout with `jq`. Every measurement path exits 0; exit 2 is a usage error only (an argument this script does not take), so a non-zero exit here is a bug in the call, never a finding about the workspace.

**The wizard acts on the script's fields; it never re-derives git state by hand.** No `grep` over `.gitignore` to decide whether `.epic` is ignored, no `git ls-files` to decide whether anything is tracked. The script already asks git — with `--no-index`, which is the only way the "tracked through an ignoring `.gitignore`" case answers truthfully — and a second reading of the same facts here would be a second thing to keep in step.

**Read order is a contract, and getting it wrong aborts the wizard.** `git`, `policy` and `verdict` are **total**: present on every path, safe to read unconditionally. The four measurement keys — `gitignore_ignores_epic`, `gitignore_source`, `tracked_md`, `tracked_draft` — are **absent when `git` is `false`**, and `jq -r` renders an absent key as the literal text `null`, not as `false`, `""` or `0`. Under `set -u` a `-gt` against that word aborts with `null: unbound variable`. **Read a measurement key only when `git == true`.** This is the script's own stated consumer requirement, in [`scripts/epic-gitpolicy.sh`](../scripts/epic-gitpolicy.sh)'s header.

| `policy` | `git` / measurements | What init presents before the question |
|---|---|---|
| `undeclared` | `git: false` | "Not a git repository — nothing about tracking was measured." The question is still asked: the declaration is valid before `git init` and takes effect the moment the directory becomes a repository |
| `undeclared` | `gitignore_ignores_epic: false` | "Nothing currently ignores `.epic/`." |
| `undeclared` | `gitignore_ignores_epic: true` | "`.epic/` is currently ignored by `<gitignore_source>`." Name the source file verbatim — which file it is decides what init may offer to do about it (step 5.3) |
| `tracked-md` | any | "This project already declares versioned artifacts (`tracked-md`)." |
| `local-only` | any | "This project already declares local-only." |

When `verdict` is not `consistent`, show it **before** asking, verbatim and with its numbers — e.g. `contradiction: 47 tracked files under an ignoring .gitignore` — so the choice is made against the real state rather than against the intention someone remembers having.

### Step 5.2 — The question (R3.1)

**Exactly two options, and option 1 always carries the recommendation.** Ask with `AskUserQuestion` when the function schema list exposes it; otherwise fall back to the numbered-list prose form, per the Runtime dependency precheck in [SKILL.md](../skills/epic/SKILL.md#runtime-dependency-precheck-mandatory-before-standardfull-triage).

```
How should this project version its .epic/ artifacts?

  [1] Versioned artifacts (recommended)
      Git-track story.md, design.md, tasks.md, EPIC.md and archive/manifest.yaml.
      Ignore .draft/ and *.wip through .epic/.gitignore.
      Your plan, your requirements and your task history become reviewable
      history that travels with the repository.
      Records: tracked-md

  [2] Local-only
      Add .epic/ to the root .gitignore. Nothing under .epic/ is ever committed.
      Records: local-only
```

**Which option is the default answer:**

- No policy declared yet (`policy: undeclared`) → **option 1**. That is R3.1's recommended default and the state a fresh init is in.
- A policy already declared → **the declared one**, still with option 1 labelled "(recommended)" and the declared one labelled "(current)". Re-running the wizard must never flip a recorded decision by the user pressing enter: `.epic/.gitpolicy` is an existing file, the Rules above already forbid overwriting one without confirmation, and a policy that flips on a re-run is exactly the five-times flip-flop this section exists to prevent.

**There is no third option, and aborting is not one.** If the user abandons the wizard at this question, write **nothing** — no `.epic/.gitpolicy`, no gitignore edit. The lint then reports `undeclared`, which is deliberately low-signal and surfaces only in `stories full`. A policy nobody chose must never be recorded as one somebody did.

### Step 5.3 — Versioned artifacts → `tracked-md` (R3.2)

Three writes, in this order. The gitignore step is second because it is the only one that can be declined, and neither of the other two depends on its outcome.

**a. Write `.epic/.gitignore`, verbatim:**

```gitignore
# Epic scratch space — never versioned under any policy.
.draft/
*.wip
```

The two patterns are the contract; the comment is the Rules' "each generated file includes comments explaining its purpose". If the file already exists with different content, confirm before overwriting — the Rules forbid overwriting an existing file silently — and keep any extra patterns the user added.

**b. The root-gitignore rule — gated on the source file AND on consent.**

`gitignore_ignores_epic: true` does **not** mean the root `.gitignore` has a line to delete. Git consults three exclude sources and the boolean fires for any of them; `gitignore_source` names the one that actually matched. Only the workspace-root `.gitignore` is a file this wizard may offer to edit.

| `gitignore_ignores_epic` | `gitignore_source` | What init does |
|---|---|---|
| `false` | `null` | Nothing. No rule is in the way |
| `true` | `.gitignore` | **Ask consent, quoting the exact line**; remove exactly that line on a yes |
| `true` | `.git/info/exclude` | **Do not offer a removal.** Report that the rule lives in `.git/info/exclude` — a file local to this clone, which init does not edit — and leave the edit to the user |
| `true` | any other path | The rule is in the user's global `core.excludesFile`. **Do not offer a removal**: that file governs every repository on the machine. Report its absolute path so the user knows where to look |
| — | absent (`git: false`) | Nothing was measured — skip this step and say so. After `git init`, re-run `/epic:epic init` to get the offer |

Locate the line before quoting it:

```
grep -nE '^[[:space:]]*/?\.epic/?[[:space:]]*$' .gitignore
```

That covers the four spellings the corpus shows (`.epic`, `.epic/`, `/.epic`, `/.epic/`). **If it matches nothing while the lint named `.gitignore`, the rule is spelled some other way** (`.ep*`, `**/.epic/`, a negation interplay) — do **not** guess and do **not** delete a line you inferred. Say the rule could not be pinned to one line, show the file, and let the user point at it or remove it themselves.

The consent prompt states the consequence of each answer:

```
Your root .gitignore ignores .epic:

  .gitignore:12: .epic/

Versioned artifacts cannot be committed while that rule stands. Remove this line?
  [y] remove the line — .epic/ becomes trackable
  [n] keep it — the policy is still recorded as tracked-md, and the policy lint
      will report `contradiction` until the rule is gone
```

Default is **no**. Removing a line from a file the user wrote is a destructive edit, and R3.2 says *offer*: **never remove it silently, and never remove more than the one line that was shown.**

**On `[n]`, record `tracked-md` anyway** and say plainly, in the step-6 report, that the lint will report `contradiction` and what closes it. The declaration is the user's intent; quietly downgrading it to match a rule they chose to keep would hide the disagreement, and surfacing exactly this disagreement is what the lint is for.

**c. Write `.epic/.gitpolicy`** — line 1 is the declaration, and it is the only line any tool reads:

```
tracked-md
# Epic versioning policy — line 1 is the declaration and the only line read.
# Written by /epic:epic init; re-run init to change it.
# Docs: references/init-mode.md#versioning-policy
```

### Step 5.4 — Local-only → `local-only` (R3.3)

**a. Ensure the *root* `.gitignore` ignores `.epic/`.**

| `gitignore_ignores_epic` | `gitignore_source` | What init does |
|---|---|---|
| `true` | `.gitignore` | Nothing. The root file already carries the rule |
| `true` | `.git/info/exclude` or any other path | **Append the rule to the root `.gitignore` anyway.** Neither `.git/info/exclude` nor a global `core.excludesFile` travels with the repository — a teammate who clones it has nothing ignoring `.epic/`. R3.3 asks for the root file specifically, and that is why |
| `false` | `null` | Append the rule |
| — | absent (`git: false`) | Append the rule. It costs nothing and takes effect the moment the directory becomes a repository |

**Before appending, disclose what the rule would strand (R3.3).** The append writes a rule; it untracks nothing, and git will not untrack anything either. So in a repository that already tracks artifacts the rule leaves those files committed under a line saying they never are — `verdict: contradiction`, the lint's first arm, kpranois's 47 files exactly, this time manufactured by the wizard that exists to prevent them. Read `tracked_md` from the step 5.1 measurement already in hand — only when `git` is `true`, per the read-order contract there — and add `tracked_draft` to it when that is non-zero, because the arm counts both. At `0`, append with no prompt: nothing can be stranded, and a question that always answers itself is one people learn to click through. Above `0`, ask first, quoting the count:

```
This repository already tracks 23 .epic artifacts.

Local-only adds .epic/ to the root .gitignore. Git will not untrack those 23
files, so they stay committed under a rule that says they never are — the
policy lint calls that `contradiction`. Add the rule anyway?
  [y] add it — the 23 files stay tracked, and the lint reports `contradiction`
      until you untrack them yourself with `git rm -r --cached .epic`;
      init never runs that command
  [n] skip the rule — local-only is still recorded, and the lint reports
      `partial`: declared local-only, artifacts tracked anyway
```

Default is **no**, and `[n]` still runs step b. The declaration is the user's answer to step 5.2 and is recorded either way; what `[n]` declines is the *rule*, leaving a `partial` that names the disagreement rather than a `contradiction` that adds one. Where the root file already carries the rule, init appends nothing and never reaches this prompt. Where `gitignore_source` is `.git/info/exclude` or a global file, the `contradiction` predates init — step 5.1 has already shown it and `[n]` cannot lower it — but the prompt still fires, because appending to the *root* file is what makes that state travel to every clone.

**This is step 5.5's reasoning on the other path.** A headless run must not reverse a declaration nobody watched it reverse; an interactive one must not strand the files a declaration is being made about. Both refuse to manufacture the same shape — one by declining to act, the other by asking first.

Appended block, when the file already exists:

```gitignore

# Epic artifacts stay local to this machine (policy: local-only, see .epic/.gitpolicy)
.epic/
```

**Ensure the file ends with a newline before appending**, or the comment splices onto whatever pattern was last in the file and silently changes what that pattern matches. When `.gitignore` does not exist, create it with the same two lines and no leading blank line.

**b. Write `.epic/.gitpolicy`** with the same footer as step 5.3c and `local-only` on line 1:

```
local-only
# Epic versioning policy — line 1 is the declaration and the only line read.
# Written by /epic:epic init; re-run init to change it.
# Docs: references/init-mode.md#versioning-policy
```

**c. Do not write `.epic/.gitignore` in this branch.** Under local-only the whole directory is excluded, so a nested ignore file inside it can never change what git does — it would be a generated file with no effect. An `.epic/.gitignore` left over from an earlier run is **kept, never deleted**: it is equally inert, and deleting a user's file to tidy up is not this wizard's business.

### Step 5.5 — Non-interactive init (R3.4)

**A headless run applies local-only, prompts for nothing, and never starts tracking.**

Detect the session kind with the signal the skill already defines — `TaskCreate` present in the function schema list means an interactive session, otherwise the run is headless or Agent SDK (see the Runtime dependency precheck in [SKILL.md](../skills/epic/SKILL.md#runtime-dependency-precheck-mandatory-before-standardfull-triage)). This is the same signal, read the same way, that [preferred-tooling.md](preferred-tooling.md) and [validate-mode.md](validate-mode.md#headless) use for their own pauses. Do not invent a second detection.

| `policy` reported by the lint | Headless init does |
|---|---|
| `undeclared` | Apply step 5.4 in full — root `.gitignore` rule, then `local-only` in `.epic/.gitpolicy` |
| `local-only` | Re-run step 5.4a only (idempotent: it appends nothing when the root file already carries the rule). Leave the policy file as it is |
| `tracked-md` | **Change nothing.** Log the detected policy and move on |

That last row is the one to get right. Overwriting a recorded `tracked-md` would reverse a decision the user made out loud, and adding `.epic/` to the root `.gitignore` of a repository that already tracks artifacts manufactures the exact kpranois contradiction — tracked files under an ignoring `.gitignore` — in a run nobody was watching. R3.4's conservative default is for a workspace that has said nothing; it is not a licence to overrule one that has.

Emit the outcome as a logged note, never a pause:

```
Epic versioning policy: local-only applied (non-interactive run — the conservative
default; nothing under .epic/ will be committed). Run `/epic:epic init` in an
interactive session to choose versioned artifacts instead.
```

### After init — making a `tracked-md` declaration real

Init records the intent; it does not stage or commit anything (the Rules above: init writes files and nothing else). So immediately after a versioned init the lint reports **`partial`** — "declared tracking that never happened", because `.epic/.gitpolicy` says `tracked-md` while every artifact is still untracked. That is correct, and one commit settles it. Close the step-6 report with the command that does:

```
git add .epic && git commit -m "chore: track .epic artifacts (policy: tracked-md)"
```

The verdict goes to `consistent` on the next run of the lint. Local-only reaches `consistent` with no follow-up: nothing is expected to be tracked, and nothing is.
