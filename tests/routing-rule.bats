#!/usr/bin/env bats
# references/run-mode.md, Execution Threshold, and run-tech-review.md.
#
# A 2026-09-26 audit of five Fast runs applied the routing table literally and
# found three rule gaps, pinned here:
#   R1  closed spec read the files off the whole body — title, Objective or
#       ToDo. Real tasks name them in the title or Objective, and 3 of 20
#       sub-tasks had no file in the ToDo (one had no ToDo at all)
#   R2  tech review is an orchestrator step, so the inline route must say it
#       applies there too; "the same step sequence as the Executor" did not
#   R3  a single-tech sub-task skips review unless its Complexity is High —
#       the Complexity table says High reviews always
# A 2026-10-23 run handed a production implementation to an Executor through
# the "anything else" default; the owner ruled production code inline:
#   R7  production code is the main agent's, except in a parallel group

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUN="$ROOT/references/run-mode.md"
  TECH="$ROOT/references/run-tech-review.md"
}

@test "R1: the rule asks whether the work needs the context window, and doubt runs inline" {
  grep -q "^\*\*The question is whether the work needs what is in the context window.\*\*" "$RUN"
  grep -q "\*\*In doubt, inline\*\*" "$RUN"
  run grep -q "^| \*\*Closed spec\*\*" "$RUN"
  [ "$status" -eq 1 ]
}

@test "R2: the inline route runs the tech review too" {
  inline=$(awk '/^### Inline Route/{f=1; next} f && /^### /{exit} f' "$RUN")
  [[ "$inline" == *'**Tech review applies on this route too.**'* ]]
  grep -q 'whether an Executor or the main agent inline did the work' "$TECH"
}

@test "R3: High complexity reviews even a single-tech sub-task, in both files" {
  grep -q "| High | Always (even single-tech) |" "$RUN"
  grep -q 'A single-technology sub-task skips it, unless its Complexity is `High`' "$RUN"
  grep -q 'unless the sub-task.s Complexity is `High`, which reviews always' "$TECH"
}

@test "R4: the Fork Route is gone — the model never chose it and it never beat inline" {
  # 2026-09-27 fork battery: 0/3 chosen; forced, it tied (0.99x) or lost 16%.
  run grep -n -i 'fork' "$RUN" "$TECH" "$ROOT/references/personas.md"
  [ "$status" -eq 1 ]
}

@test "R5: a sub-task with no ToDo and no runnable Validation fails before routing, in both files" {
  # 2026-09-27 battery: a vague sub-task had its scope invented in 2 of 5 runs.
  grep -q '\*\*A sub-task too vague to act on takes no route.\*\*' "$RUN"
  grep -q '^### Before Step 1: a spec you can act on' "$ROOT/agents/executor.md"
  grep -q 'spec too vague' "$ROOT/agents/executor.md"
}

@test "R6: the Executor spawn template carries Context, Acceptance and the group's Commit" {
  tpl=$(awk '/^### Executor Prompt Template/{f=1; next} f && /^### /{exit} f' "$RUN")
  [[ "$tpl" == *'> **Context:**'* ]]
  [[ "$tpl" == *'> **Acceptance:**'* ]]
  [[ "$tpl" == *'> **Commit:**'* ]]
}

@test "R7: only context-free work goes to a sub-agent; a parallel group is the one exception" {
  table=$(awk '/^## Execution Threshold/{f=1; next} f && /^## /{exit} f' "$RUN")
  [[ "$table" == *'| **Parallel group member** |'*'| **Executor sub-agent, in a worktree when one is available** |'* ]]
  [[ "$table" == *'| **Context-free** |'*'| **Sub-agent** |'* ]]
  [[ "$table" == *'| anything else | production code, or any work that depends on'*'| **Main agent, inline** — or a new session'* ]]
  # Order matters: the first match wins, so the catch-all must stay last and inline.
  par=$(grep -n '^| \*\*Parallel group member\*\*' "$RUN" | cut -d: -f1)
  free=$(grep -n '^| \*\*Context-free\*\*' "$RUN" | cut -d: -f1)
  rest=$(grep -n '^| anything else |' "$RUN" | cut -d: -f1)
  [ "$par" -lt "$free" ] && [ "$free" -lt "$rest" ]
  delegated=$(awk '/^### Delegated Route/{f=1; next} f && /^### /{exit} f' "$RUN")
  [[ "$delegated" == *'**A serial sub-task that writes production code never lands here**'* ]]
}

@test "R8: a parallel group without a worktree runs in the main checkout, never serial" {
  par="$ROOT/references/run-parallel.md"
  grep -q 'run the groups \*\*without worktrees\*\* (below), never `--serial` on that account' "$par"
  grep -q '\*\*The worktree is preferred, not required\*\*' "$par"
}

# A 2026-10-24 replay of story 040 (zeo) found 8 of 13 sub-tasks still routed
# to Executors through parallel groups that wrote disjoint files but shared one
# crate graph and one target/, in code the session's repository ignores:
#   R9  a group sharing a build, or editing code outside the session's
#       repository, is refused
@test "R9: a parallel group that shares a build or edits code outside the repository is refused" {
  par="$ROOT/references/run-parallel.md"
  detection=$(awk '/^### Detection/{f=1; next} f && /^### /{exit} f' "$par")
  [[ "$detection" == *'4. **Verify the group does not share a build, and that its code is in the session'"'"'s repository.**'* ]]
  [[ "$detection" == *'**the same compile unit in the same output directory**'* ]]
  [[ "$detection" == *'**outside the repository the session runs in**'* ]]
  [[ "$detection" == *'A refused group runs its items one at a time, inline'* ]]
  [[ "$detection" == *'A group that passed steps 1–4 is proven independent'* ]]
}
