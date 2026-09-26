# Evals

The suite runs on Claude Code's native eval runner, `claude plugin eval` (Claude Code v2.1.269+). Each run gets an isolated home — no installed copy of the plugin, no user hooks, no personal `CLAUDE.md`, no other plugins — so a result describes this plugin, not the machine that ran it.

## Layout

```
evals/
├── triggers/should-trigger/<case>/       # 18 requests the skill should pick up
├── triggers/should-not-trigger/<case>/   # 12 requests it should leave alone
├── cases/<case>/                         # 6 end-to-end requests graded on the files written
└── results/                              # written by each run; gitignored
```

- **Trigger cases** have one grader: `tool_used` on `Skill` with the `epic` skill — at least once for should-trigger, never (`min: 0`, `max: 0`, `arm: both`) for should-not-trigger. They stop after 3 turns: the decision to load the skill is made in the first.
- **Artifact cases** grade what was written: `file_exists` for the story files, and `regex` over the trace scoped to the content of a `Write` to that file — never to the whole trace, which also carries the skill text and every reference the run read. The few judgements a regex cannot make use an `llm` grader. Three cases start from a small Express app (`scaffold.sh`), because their requests point at existing code; an empty workspace makes the right answer "there is nothing to change".

## Run

Always pass `--no-publish`: without it the HTML report is published to claude.ai. Export `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` first: each run is a single headless turn, and a sub-agent left in the background ends it before the story is written.

```bash
# Everything, both arms (with the plugin, and a no-plugin baseline)
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
claude plugin eval . --no-publish --scaffold --allow-tools Skill Bash Write Edit Agent

# Only the trigger cases, one run each, no baseline
claude plugin eval . --tag trigger --runs 1 --ablation none --no-publish --allow-tools Skill

# One artifact case while iterating on it
claude plugin eval . --case fast-feature --runs 1 --ablation none --no-publish --scaffold \
  --allow-tools Skill Bash Write Edit Agent --max-cost-usd 10
```

`--scaffold` runs the cases' `scaffold.sh` (author-supplied bash, off by default). `--trust-plugin` skips the first-run trust prompt in CI. Pin `--model` when comparing runs across days, so a change of default model does not read as a change in the plugin.

## What a trigger score is — and is not

A trigger rate is a property of the model's routing on that day, not of this repository: the same query can fire every time one day and never the next with identical code. So it informs and never gates. The deterministic gate for the skill description is `tests/skill-description-coverage.bats`, which checks offline that every routed mode is named in the description.
