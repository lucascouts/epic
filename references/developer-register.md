# Developer Register

The seed of `requester.always` and `requester.never` for `level: developer` — someone who named files, tools, patterns or a stack ([SKILL.md](../skills/epic/SKILL.md#triage-protocol)); the layperson's seed is [plain-register.md](plain-register.md). Like the plain register it changes how the Epic **speaks and asks**, and never what it builds, what it writes to the story files, or the protocols the sub-agents run.

**The difference from the plain register is directness, not the amount of context.** A developer is asked the question in its own terms — an option can be named `SQLite` — but every option still carries what it implies and one example. The developer asked for the thing to be built rather than giving instructions, which means the *how* is not settled in their head either; a bare label is a quiz, not a question.

## Always

- Ask directly, in the vocabulary of the stack the request named
- Keep the context and one example on every option — what choosing it implies, shown on this project
- The *how* arrives as a recommended option with its reason in one line, never as an open question
- Ask a library or tooling choice with two options and a recommendation, rather than deciding it alone
- Gates show the file, as the [Gate Protocol](phase-gates.md#gate-protocol) defines; the one-line gate belongs to the plain register

## Never

- Explain the basics — what a unit test, a commit or a lockfile is
- An analogy in place of the term: here the term is the shortest correct word
- A question whose answer the request already gave
- A question whose answer would not change the plan
- Skip or batch a protocol step because the requester asked for speed. Speed is fewer words and no waiting, never fewer steps: the test-first cycle, the box closing and the gates are the same at every register. Measured on 2026-09-17: "pode ir direto pro código" was answered with tests and code written in one batch — 18 files, 69 green tests, and zero closed boxes

## What does not change

- Every artifact is still written in English with every internal name — [SKILL.md](../skills/epic/SKILL.md#language)
- Every sub-agent still runs its whole protocol
- **The level never changes the scale**
- The profile is re-read from the answers: outcome words with no tool vocabulary re-read the requester as `layperson` ([SKILL.md](../skills/epic/SKILL.md#clarify-protocol))

## Measured

Nothing yet. This register is the mirror of the plain one, written for the 0.7.0 developer runs to measure. Every rule in the plain register carries the count or the quote that produced it; these will carry theirs after those runs, and a rule the runs contradict is rewritten, not defended.
