# Clarify — the question rounds

Loaded when a Create run asks questions (Standard and Full always; Fast when the request is ambiguous). Instant never loads it: it asks nothing. Moved out of [SKILL.md](../skills/epic/SKILL.md) so a run that does not need it does not carry it.

## Clarify Protocol

**Mandatory for standard and full modes.** After triage confirmation, gather
clarifications using the `AskUserQuestion` tool. Multiple-choice prompts are
faster for the user than free-text confirmations and yield structured answers
the orchestrator can route on without re-parsing prose.

**The Epic asks the way an architect asks a client.** The requester came to
have something built, not to give instructions; whatever their level, they
know what it is and what it must do, and the how — the stack, the storage,
the pattern, the tooling — is not settled in their head. So every question
is about **what and what for**, and the **how is proposed, never asked**: it
arrives between the questions as a recommended option with its reason, in
words the requester can choose by. The level sets directness, not the amount
of context: a `developer` is asked in the stack's own terms, a `layperson` in
the plain register, and both get the context and the example.

- **Round 0 is orientation.** At most three context questions — who uses
  it, what exists today, what "done" looks like — or one open question in
  the requester's own words: "describe it as you would to a friend".
  Skipped when the request already answers them; a question the request
  answered is a defect in either register. When triage could not settle
  the engineering level, this round carries its indirect questions — will
  you open this again, when it breaks do you fix it or redo it, will anyone
  besides you run it, could it be published or sold
  ([engineering-level.md](engineering-level.md)) — asked as
  consequences, inside the same count.
- **Ask the consequence, never the mechanism.** "What happens to the data
  when the program closes?" decides persistence; "JSON or SQLite?" asks the
  requester to be the architect. The consequence is what they can observe
  and choose by; the mechanism is what their answer decides for them.
- **Every option carries its context and one example** — what choosing it
  implies, shown on this project. A bare label is a quiz. When the choice is
  technical and `requester.level` is `layperson`, add the analogy that lets
  them choose by logic ([plain-register.md](plain-register.md#explain-by-example));
  a `developer` gets the term instead, with the same context and example
  ([developer-register.md](developer-register.md)).
- **The how is a recommendation, never a question.** When a technical
  decision is due — stack, storage, pattern, tooling — offer it as options
  with the recommended one first and labelled `(Recommended)`, its reason
  in one line, and each alternative's trade-off in one line. Never an open
  "how do you want this built?".
- **Rounds are free in size, and built from what the last one left open.**
  Bundle only questions whose answers cannot change each other; a question
  whose answer can prune another goes alone, and first. Before composing
  round N+1, apply round N's answers: an `out-of-scope` answer removes its
  whole branch; a default taken removes the follow-ups that default implies;
  an answer given in tool vocabulary re-reads `requester.level` as
  `developer` for the rest of the story, and one given in outcome words
  keeps `layperson`; an answer that reveals how to work with this person —
  "I don't know how to run a command" — is appended to `requester.never`
  or `requester.always` and applied from then on. A question whose answer
  no longer changes the plan is not asked. When triage was unsure of the
  requester, round 0 opens with **one calibration question** — "How do you want me to work with you?" with two
  options in plain words: *explain in plain words and decide the technical
  details for me* / *ask me the technical questions* — and every round after
  it follows that answer.
- **One question budget per story, counted in questions from triage to the
  last box.** Every question in an `AskUserQuestion` call (or its
  numbered-list fallback) counts one; the orientation round counts one
  whatever its size; every phase gate and every question asked during Run
  counts one, against the same budget: **`layperson` — Fast 3, Standard 9,
  Full 12; `developer` — Fast 4, Standard 10, Full 14.** Measured on the
  format's own trial (September 2026, a Standard-shaped request):
  orientation, four, four with the gate — nine. Before any budget existed:
  1 out-of-reach question in Fast and 5–8 in Standard, for one beginner and
  one request. When the budget is spent, decide by the constitution's
  `## Defaults` and the
  [plain register](plain-register.md#decisions-the-requester-is-not-asked)
  table, write each decision as an assumption in story.md (Fast: in the run
  report) and proceed. Infinite clarification defeats the purpose — and so
  does a question the requester cannot answer.
- **The interface language is a question, never an inheritance.** When the
  request is not in English and the story ships something a person reads on
  screen, ask which language its menu, prompts, messages and README are in —
  in the requester's own language, one question, three options: English, the
  language they wrote in, another. Not asked when the request is
  already in English. The artifacts stay English either way
  ([Language](../skills/epic/SKILL.md#language)).
- For each ambiguity, build a question with **2–4 mutually-exclusive options**.
  When the answer is binary, prefer `[yes / no / out-of-scope]` over open
  phrasings.
- Focus on: ambiguities, scope boundaries, edge cases, dependencies.
- **Stack recommendation must consider story complexity.**
- **Implicit capability detection:** For each requirement, identify whether
  it implicitly depends on an architectural capability not yet established in
  the design. Add it as a multi-choice question (`include now / defer to
  follow-up story / explicitly out of scope`).
- For Fast mode: skip clarify only if request is unambiguous.
- **Never skip clarify for Standard/Full.**

### Question shape

```
question:    "What happens to the other signed-in devices when a user changes their password?"
             ← the consequence; "invalidate the other tokens?" would ask the mechanism
options:
  - "They are all signed out (Recommended)" — "the password change is the moment they wanted the others out; one extra query"
  - "They keep working until they expire" — "nothing to build; a stolen session survives the change"
  - "Out of scope for this story"
context:     "Affects R2.3 (token TTL) and downstream session handling"
```

### Fallback (headless or AskUserQuestion unavailable)

When the tool is not callable (some `-p` modes, restricted permission scopes),
revert to the legacy assertion style — present a single message with a numbered
list of `"I understand X will work as Y. Confirm?"` items.
