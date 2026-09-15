# Evals

Two suites, one runner.

| file | what it holds |
|---|---|
| `evals.json` | end-to-end cases — a prompt and the artifacts it must produce |
| `trigger-queries.json` | phrasings that must (or must not) make the skill fire |

```bash
bash scripts/run-evals.sh              # both
bash scripts/run-evals.sh --cases      # evals.json only
bash scripts/run-evals.sh --triggers   # trigger-queries.json only

EVAL_FILTER='migrate 007' EVAL_RUNS=5 bash scripts/run-evals.sh --triggers
```

`scripts/trigger-detect.sh` is the **only** scorer of a trigger run. It reads a
transcript and answers `triggered` / `not-triggered` / `error`. `run-evals.sh`
matches nothing inline — one scorer in the tree, pinned by
`tests/run-evals-contract.bats`.

---

## Before you run: disable the installed plugin

`--plugin-dir` does **not** outrank an installed plugin of the same name. With
`epic` enabled, the CLI resolves the cached copy and the suite grades code that
is not in your working tree.

```bash
claude plugin disable epic      # run-evals.sh refuses (exit 2, 0 model calls) without this
# … run …
claude plugin enable epic       # put it back
```

The runner checks once, at startup. **It cannot see a mid-run flip**, and a flip
is not hypothetical: on 2026-08-30 `~/.claude/settings.json` was rewritten 12
minutes into an 88-minute run, re-enabling the plugin and contaminating ~24 of
27 queries. That roster was discarded. For any run longer than a few minutes,
poll and re-disable:

```bash
( while :; do
    claude plugin list | grep -A3 'epic@' | grep -q 'enabled' \
      && claude plugin disable epic >/dev/null 2>&1
    sleep 10
  done ) &
```

---

## A trigger eval is not a gate

**This is the part that costs people a day if they learn it the hard way.**

A trigger eval measures a service that changes underneath you. Measured on this
repo, same commit, same `skills/epic/SKILL.md` md5, same plugin state:

| query | earlier | later | gap |
|---|---|---|---|
| `stories create --batch docs/audit-2026-07.md` | **0/30** (2026-08-29 → 2026-09-12 06h11) | **5/5** (2026-09-12 16h32) | 10 hours |
| `let's plan the Stripe webhook handler…` | **3/3** (2026-08-30) | **1/5** (2026-09-12 05h47) | 13 days |

One rose while the other fell, in the same window. That is a routing change on
the service side, not noise around a stable rate.

The consequence is structural, not a matter of tuning:

> **Never write a gate of the form "query X must fire."** It flaps without a
> line of code changing. A gate that says "no query that fired before may fail
> now" fails identically against a tree carrying **no edit at all** — it
> measures the calendar, not the diff. Story 021 marked exactly such a gate
> `waived` for this reason.

**Put the assertion in a deterministic instrument instead.**
`tests/skill-description-coverage.bats` compares the routing cascade against the
skill's `description` — offline, reproducible, no service in the loop. It would
have answered the same on both dates above. Trigger evals belong in
**monitoring**: run them to notice a change like the one in that table, never to
approve a commit.

### If you must compare anyway

1. **`EVAL_RUNS=5` minimum.** At n=1 a query whose true rate is 0.33 reads 0/1
   two times in three. The runner reports a rate for exactly this reason.
2. **Take the "before" on the same day.** Restore the previous file into the
   tree, measure, swap back — guard the restore with
   `trap … EXIT INT TERM HUP QUIT PIPE`. A roster from last week cannot separate
   your edit from the service's drift. It is the only comparison that isolates
   the change.
3. **Record the md5 of what you measured**, at the start and at the end of the
   run, plus the plugin state and any flips. A roster without its anchor is not
   evidence.
4. **Report the denominator.** `ran: N case(s), M trigger(s)` — a suite that
   measured nothing must not read as a suite that passed.

---

## Coverage: the suite only sees what someone wrote a query for

Adding a mode to the routing cascade does **not** add it here. `--batch` and
`migrate` sat in the cascade for eighteen months with no query and no
description entry, and nothing went red.

These four have a query but have **never been measured** — they were added to
close the coverage hole, not because a number exists for them:

- `set up epic in this project` (`init`)
- `archive story 014, …` (`archive`)
- `story 017 supersedes 012 — record that` (`supersede`)
- `enable team mode for stories` (`teams`)

Measuring them costs ~3 minutes per run per query. Until someone does, the
deterministic lint is the whole of the evidence that these modes are reachable —
and per the section above, that is the better half anyway.
