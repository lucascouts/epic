#!/usr/bin/env bats
# The engineering level — the doc contract (0.7.0, implemented inline on the
# branch, no story). How long the thing must last decides how much the story
# pays for: the catalog tier, whether Phase 3 authors the tests or the run
# does, and the plan's box ceiling.
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor and asserts a keyword inside it, case-insensitively. No
# case requires a sentence verbatim: a correct rewrite must stay green. The
# validator's own behaviour (enum, per-level ceiling) is pinned in
# tests/authoring-ceiling.bats, not here.
#
#   E1  references/engineering-level.md is the single home: four levels with
#       their fishing questions and multiples, the 3× rule, how the level is
#       read (tool when unsettled, the price line, the orientation round),
#       where it is recorded, what each level pays for, what it never changes
#   E2  SKILL.md triage reads the level from the request, takes tool when
#       unsettled, and the proposal carries an Engineering line
#   E3  the Personas table gates the Test Advisor on project/product
#   E4  Phase Execution's ceiling paragraph makes the three offers
#   E5  the meta.yaml example and the frontmatter block carry engineering:
#   E6  tasks.md's Authoring Ceiling is per level, counts the Task List, keeps
#       60 for no level, and the old single-ceiling sentence is gone; the
#       Tests Field is authored only at project/product
#   E7  phase-gates.md spawns the Test Advisor only at project/product and
#       widens the Lite checklist to experiment/tool
#   E8  run-mode.md: materialization and its converse guard exempt the two
#       levels, the run-time ordering names them, the execution plan and the
#       Run Mode Rules carry the recorded line
#   E9  refine, validate-mode, auditor, test-advisor and batch-create read
#       Phase 3 through the level
#   E10 the catalog names the runtime, the justified dependencies, the atomic
#       write with its signal, the syntax-check-is-not-lint rule, and the level
#       bound
#   E11 README names the axis and the four levels
#   E12 requirements.md, plain-register.md and self-review-checklist.md know
#       the level
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() { # has <label> <block> <keyword>
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

hasF() { # hasF <label> <block> <fixed string>
  if ! printf '%s' "$2" | grep -qF -- "$3"; then
    echo "$1: expected the block to contain '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "E1: engineering-level.md is the single home — four levels, questions, multiples, 3×, how read, where recorded, what each pays for" {
  f="$ROOT/references/engineering-level.md"
  [ -f "$f" ]
  levels=$(section "$f" '^## The four levels' '^## ')
  [ -n "$levels" ]
  for w in '`experiment`' '`tool`' '`project`' '`product`' "open this again" "breaks" "besides you" "publish"; do
    has "E1 level" "$levels" "$w"
  done
  for m in "1×" "2–3×" "4–6×" "8×+"; do hasF "E1 multiple" "$levels" "$m"; done
  hasF "E1 3× rule" "$levels" "3×"
  has "E1 recalibrated" "$levels" "recalibrated"
  read_=$(section "$f" '^## How the level is read' '^## ')
  has "E1 tool when unsettled" "$read_" "does not settle it"
  has "E1 price line" "$read_" "one line"
  has "E1 orientation" "$read_" "orientation"
  has "E1 never a choice of level" "$read_" "which level is this"
  rec=$(section "$f" '^## Where it is recorded' '^## ')
  has "E1 frontmatter" "$rec" "engineering:"
  has "E1 meta" "$rec" "meta.yaml"
  has "E1 recorded line" "$rec" "recorded line"
  has "E1 boxes" "$rec" "boxes"
  pays=$(section "$f" '^## What each level pays for' '^## ')
  has "E1 advisor" "$pays" "Test Advisor"
  has "E1 run time" "$pays" "run time"
  has "E1 catalog" "$pays" "quality-catalog"
  for n in '| **5** Task List boxes |' '| **12** |' '| **24** |' '| **40** |'; do hasF "E1 ceiling" "$pays" "$n"; done
  has "E1 three offers" "$pays" "down a level"
  never=$(section "$f" '^## What the level never changes' '^## ')
  [ -n "$never" ]
  has "E1 never the scale" "$never" "scale"
}

@test "E2: triage reads the engineering level from the request, takes tool when unsettled, and the proposal carries an Engineering line" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Triage Protocol' '^### Complexity')
  [ -n "$block" ]
  has "E2 level" "$block" "engineering level"
  has "E2 reference" "$block" "engineering-level"
  for l in experiment tool project product; do has "E2 $l" "$block" "\`$l\`"; done
  has "E2 default" "$block" "when the request does not settle it"
  has "E2 price" "$block" "multiple"
  has "E2 never the scale" "$block" "never changes the scale and never changes the requester level"
  grep -q '^> - \*\*Engineering:\*\*' "$ROOT/skills/epic/SKILL.md"
  grep -q '^3a\. \*\*Read the engineering level\*\*' "$ROOT/skills/epic/SKILL.md"
}

@test "E3: the Personas table gates the Test Advisor on project or product, and names the run-time alternative" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Personas' '^## Command Routing')
  row=$(printf '%s' "$block" | grep -E '^\| \*\*Test Advisor\*\*')
  [ -n "$row" ]
  has "E3 project" "$row" "project"
  has "E3 product" "$row" "product"
  has "E3 run time" "$row" "run time"
  has "E3 reference" "$row" "engineering-level"
}

@test "E4: the Phase 3 ceiling paragraph is per level and makes the three offers" {
  block=$(section "$ROOT/skills/epic/SKILL.md" '^## Phase Execution' '^## Persistence')
  [ -n "$block" ]
  has "E4 level" "$block" "engineering level"
  has "E4 cut" "$block" "cut"
  has "E4 split" "$block" "split"
  has "E4 down" "$block" "down a level"
  has "E4 warning" "$block" "never a block"
}

@test "E5: the meta.yaml example and the frontmatter block carry engineering:" {
  draft=$(section "$ROOT/skills/epic/SKILL.md" '^### Draft Saving' '^### Resume')
  [ -n "$draft" ]
  has "E5 meta" "$draft" "engineering:"
  out=$(section "$ROOT/skills/epic/SKILL.md" '^## Output Rules' '^### Lifecycle')
  [ -n "$out" ]
  hasF "E5 frontmatter" "$out" "engineering: experiment | tool | project | product"
  am=$(section "$ROOT/skills/epic/SKILL.md" '^## Adaptive Modes' '^## Workflow Variants')
  has "E5 two axes" "$am" "engineering level"
}

@test "E6: tasks.md's Authoring Ceiling is per level, counts the Task List, keeps 60 for no level; the Tests Field is authored only at project/product" {
  f="$ROOT/references/tasks.md"
  ceil=$(section "$f" '^### Authoring Ceiling' '^### ')
  [ -n "$ceil" ]
  for l in experiment tool project product; do has "E6 $l" "$ceil" "\`$l\`"; done
  has "E6 sixty" "$ceil" "60"
  has "E6 task list" "$ceil" "Task List"
  has "E6 gates not counted" "$ceil" "Quality Gates"
  has "E6 fence" "$ceil" "fence"
  has "E6 cut" "$ceil" "cut"
  has "E6 split" "$ceil" "split"
  has "E6 down" "$ceil" "down a level"
  has "E6 warning" "$ceil" "never a block"
  if grep -q '32KB or 60 checkboxes, whichever comes first' "$f"; then
    echo "E6: the single 60-box ceiling sentence is back" >&2
    return 1
  fi
  tf=$(section "$f" '^### Tests Field' '^### ')
  has "E6 project" "$tf" "project"
  has "E6 product" "$tf" "product"
  has "E6 run time" "$tf" "run time"
  has "E6 reference" "$tf" "engineering-level"
}

@test "E7: phase-gates.md spawns the Test Advisor only at project/product and widens the Lite checklist" {
  f="$ROOT/references/phase-gates.md"
  ta=$(section "$f" '^## Test Advisor Sub-agent' '^### ')
  [ -n "$ta" ]
  has "E7 project" "$ta" "project"
  has "E7 product" "$ta" "product"
  has "E7 reference" "$ta" "engineering-level"
  has "E7 measured" "$ta" "25 minutes"
  has "E7 foreground kept" "$ta" "run_in_background: false"
  lite=$(section "$f" '^### Test Advisor Lite' '^## ')
  [ -n "$lite" ]
  has "E7 lite experiment" "$lite" "experiment"
  has "E7 lite tool" "$lite" "tool"
  refs=$(section "$f" '^## Reference Files Loaded Per Phase' '^## ')
  has "E7 loaded" "$refs" "engineering-level.md"
}

@test "E8: run-mode.md exempts the two levels from materialization and its guard, names them in the run-time ordering, and carries the recorded line" {
  f="$ROOT/references/run-mode.md"
  step7=$(awk '!inb && $0 ~ /^[0-9]+[.] .*Materialize pre-authored tests/ {inb=1; print; next} inb && $0 ~ /checks the converse/ {exit} inb {print}' "$f")
  [ -n "$step7" ]
  has "E8 step 7 experiment" "$step7" "experiment"
  has "E8 step 7 tool" "$step7" "tool"
  has "E8 step 7 reference" "$step7" "engineering-level"
  if grep -q 'Materialize pre-authored tests (Standard/Full only)' "$f"; then
    echo "E8: step 7 still reads Standard/Full only" >&2
    return 1
  fi
  guard=$(awk '!inb && $0 ~ /checks the converse/ {inb=1; print; next} inb && $0 ~ /^[0-9]+[.] / {exit} inb {print}' "$f")
  [ -n "$guard" ]
  has "E8 guard experiment" "$guard" "experiment"
  ord=$(section "$f" '^### Run-time test-first ordering' '^### Inline Route')
  [ -n "$ord" ]
  has "E8 ordering experiment" "$ord" "experiment"
  has "E8 ordering tool" "$ord" "tool"
  has "E8 ordering spike kept" "$ord" "spike"
  has "E8 ordering reference" "$ord" "engineering-level"
  plan=$(grep -E '^8\. \*\*Present execution plan' "$f")
  [ -n "$plan" ]
  has "E8 recorded line at plan" "$plan" "recorded line"
  rules=$(section "$f" '^## Run Mode Rules' '^### ')
  has "E8 recorded line at end" "$rules" "recorded line"
  has "E8 multiple" "$rules" "multiple"
  has "E8 boxes" "$rules" "boxes"
}

@test "E9: refine, validate-mode, auditor, test-advisor and batch-create read Phase 3 through the level" {
  refine=$(section "$ROOT/references/refine-mode.md" '^## Red Evidence for Added Sub-tasks' '^## ')
  [ -n "$refine" ]
  has "E9 refine project" "$refine" "project"
  has "E9 refine product" "$refine" "product"
  has "E9 refine run time" "$refine" "run time"
  v10=$(grep -E '^> 10\. Red precedence' "$ROOT/references/validate-mode.md")
  [ -n "$v10" ]
  has "E9 validate level" "$v10" "engineering level"
  a10=$(grep -E '^10\. \*\*Red precedence' "$ROOT/agents/auditor.md")
  [ -n "$a10" ]
  has "E9 auditor level" "$a10" "engineering level"
  role=$(section "$ROOT/agents/test-advisor.md" '^## Your Role' '^## ')
  has "E9 advisor project" "$role" "project"
  has "E9 advisor product" "$role" "product"
  has "E9 advisor reference" "$role" "engineering-level"
  batch=$(grep -E 'Phase 3 runs the Test Advisor' "$ROOT/references/batch-create.md")
  [ -n "$batch" ]
  has "E9 batch product" "$batch" "product"
}

@test "E10: the catalog names the runtime, justified dependencies, the atomic write with its signal, the syntax-check rule and the level bound" {
  f="$ROOT/references/quality-catalog.md"
  always=$(section "$f" '^## Always' '^## ')
  has "E10 runtime" "$always" "Supported and declared runtime"
  has "E10 deps" "$always" "Dependencies justified"
  has "E10 syntax" "$always" "syntax check"
  has "E10 omitted" "$always" "omitted"
  has "E10 node check" "$always" "node --check"
  context=$(section "$f" '^## By context' '^## ')
  has "E10 atomic" "$context" "Atomic write"
  has "E10 signal" "$context" "reads back"
  chosen=$(section "$f" '^## How the set is chosen' '^## ')
  has "E10 bound" "$chosen" "engineering level"
  has "E10 never installs kept" "$chosen" "never installs"
}

@test "E11: README names the axis and the four levels" {
  f="$ROOT/README.md"
  has "E11 axis" "$(cat "$f")" "engineering level"
  for l in experiment tool project product; do has "E11 $l" "$(cat "$f")" "\`$l\`"; done
  grep -q 'references/engineering-level.md' "$f"
}

@test "E12: requirements.md, plain-register.md and self-review-checklist.md know the level" {
  hasF "E12 template" "$(cat "$ROOT/references/requirements.md")" "engineering: experiment | tool | project | product"
  guide=$(section "$ROOT/references/requirements.md" '^## Writing Guidelines' '^## ')
  has "E12 guideline" "$guide" "engineering-level"
  words=$(section "$ROOT/references/plain-register.md" '^## Words that stay' '^## ')
  has "E12 plain level" "$words" "engineering level"
  has "E12 plain rendering" "$words" "how long"
  has "E12 self-review" "$(cat "$ROOT/references/self-review-checklist.md")" "Sized to the level"
}
