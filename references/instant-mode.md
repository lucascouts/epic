# Instant — the disposable-work shortcut

Loaded by `/epic:epic instant <description>`, together with [triage.md](triage.md), which it reads with the three pins below already set.

`/epic:epic instant <description>` is **Create with three pins, not a fourth scale.** It writes the same `tasks.md` every Fast story writes; what it removes is the deciding, not the artifact.

| Pin | Value | Why it is pinned rather than asked |
|---|---|---|
| `scale` | `fast` | the floor every story starts from ([engineering-level.md](engineering-level.md#how-the-level-is-read)) |
| `engineering` | `experiment` | typing `instant` **is** the answer to the first cascade question — asking it again would be asking someone to repeat themselves |
| Quality legend | the **security floor** only — supported and declared runtime, secrets, dependency CVEs, a README that says how to run it ([quality-catalog.md](quality-catalog.md#the-security-floor--four-items-no-level-drops)) | the floor is three commands, one file and no configuration file; anything dropped below it would be dropping the machine's safety, not the story's ceremony |

**No technical question round.** The intent cascade is already answered and does not run. A technical choice the request leaves open is taken as a recommended default and recorded on its line — never turned into a question. The requester asked for the short path; spending their turn on a menu is the one thing `instant` exists to avoid.

**The interface speaks the language the request was written in.** `instant` asks nothing, so it does not ask this either — and the artifacts' English is about artifacts, never about the menu the requester reads. Take their language, and say so on its line: *"menu in Portuguese, the language you wrote in — say the word and I'll switch it"*. Shipping an interface the requester cannot read, on a rule that was never about them, is the shortcut deciding something that was not its to decide ([Language](../skills/epic/SKILL.md#language)).

**What it does not remove.** The three pins are the whole difference. Triage still runs, the plan is still written, and every box still carries a `Validation:` that proves it alone.

**What it does cost, said plainly.** `instant` does not only drop ceremony — **it drops protections the person using the program would have had**, and it drops them without asking. Left alone, the shortcut can: leave out an operation the requester would have asked for; make an unreadable answer cost a point instead of re-asking the question for free; delete a record without confirming; pick an interface language the requester would have chosen differently; and ship **no README at all** — less documentation than the same request answered with no Epic in the session.

That is a fair bargain for something disposable, and it is not a bug. It stops being fair the moment it is silent. So:

**Every decision taken alone that reduces protection or documentation goes in the end-of-run report, not only in the plan.** One line each, naming what was dropped and what it would have cost to keep — the requester finds out by reading, never by being bitten. A decision that merely picks between equivalent means (a library, a file layout, an identifier scheme) stays in the plan where it belongs.

**When the request is plainly bigger than the shortcut** — several integrated surfaces, or a thing the description itself says others will depend on — **say so in one line and proceed anyway.** The requester chose the level; a shortcut that argues is a shortcut nobody uses. The line is a note, never a gate:

> Noted: this looks larger than `instant` usually covers. Proceeding at `experiment` as asked — say the word and I will re-run it at `tool`.

**Recorded like any other story.** `scale: fast` and `engineering: experiment` go in the frontmatter, so validation, the index and the telemetry read an `instant` story exactly as they read any other. There is no `instant` value anywhere in the artifacts — the shortcut is an entrance, not a state.

