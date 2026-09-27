#!/usr/bin/env bats
# references/run-mode.md, Execution Threshold, and run-tech-review.md.
#
# A 2026-09-26 audit of five Fast runs applied the routing table literally and
# found three rule gaps, pinned here:
#   R1  closed spec reads the files off the whole body — title, Objective or
#       ToDo. Real tasks name them in the title or Objective, and 3 of 20
#       sub-tasks had no file in the ToDo (one had no ToDo at all)
#   R2  tech review is an orchestrator step, so the inline route must say it
#       applies there too; "the same step sequence as the Executor" did not
#   R3  a single-tech sub-task skips review unless its Complexity is High —
#       the Complexity table says High reviews always

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUN="$ROOT/references/run-mode.md"
  TECH="$ROOT/references/run-tech-review.md"
}

@test "R1: closed spec names the files anywhere in the sub-task's body" {
  grep -q "^| \*\*Closed spec\*\* | the sub-task's body — its title, Objective or ToDo — names the files" "$RUN"
  run grep -q '| \*\*Closed spec\*\* | the ToDo names the files' "$RUN"
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
