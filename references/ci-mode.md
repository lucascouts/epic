# CI/Headless Mode

Use these patterns when running Epico plugin operations programmatically with `claude -p` or the Agent SDK. Every recipe that invokes `/epico:epico` must load the plugin: pass `--plugin-dir "$EPIC_PLUGIN_ROOT"` (a checkout of this repo), or install the plugin first. Do not add `--bare`: it skips every hook — the archive, executor and identity guards included — loads none of the plugin's sub-agents, and authenticates only through `ANTHROPIC_API_KEY`, never an OAuth login. Every recipe below also states its permissions instead of inheriting them:

- `--permission-mode acceptEdits` — set it explicitly; a `-p` run with no mode picks one that depends on the provider.
- `--permission-prompts none` — nobody is there to answer, so anything that would prompt is denied at once instead of hanging the run.
- `--allowedTools` names everything the mode calls: `Edit` wherever a story file is updated (validate writes `status: validated`), and `mcp__ai-memory__*` so the first turn waits for the memory server to connect — without the name, triage's one memory check reads memory as absent.

Export `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` as a precaution: it keeps every sub-agent in the foreground, so the end of the run never depends on how Claude Code waits for background work.

## Contents

- [Validate Stories in CI](#validate-stories-in-ci)
- [Generate Stories Programmatically](#generate-stories-programmatically)
- [Validate Implementation Against Story](#validate-implementation-against-story)
- [List Stories](#list-stories)
- [GitHub Actions Example](#github-actions-example)
- [Typed structured output with `--json-schema`](#typed-structured-output-with---json-schema)
- [Detecting plugin load failures (`system/init` event)](#detecting-plugin-load-failures-systeminit-event)
- [Notes](#notes)

## Validate Stories in CI

Run validation as a PR check or CI step. Inside a session with the plugin enabled, the scripts are on PATH as `epico-validate`, `epico-xref` and the other `epic-*` wrappers; for standalone CI pipelines clone the plugin repo and set `EPIC_PLUGIN_ROOT` to its path:

```bash
# Validate structural correctness
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature-name/

# Validate with cross-reference checks (requirements traceability)
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature-name/ --cross-ref

# Dedicated cross-reference report
bash "$EPIC_PLUGIN_ROOT/scripts/cross-reference.sh" .epic/stories/001-feature-name/
```

Exit codes: 0 = pass, 1 = issues found, 2 = invalid input. Output is always JSON.

`cross-reference.sh` has a fourth `status`, `no-requirements-chain`, reported at **exit 0**: the story's declared scale (`fast` or `spike`) carries no requirements chain, so there was never anything to compare. Exit 0 there means *nothing to measure*, not *measured and clean* — a distinction `0 = pass` alone does not draw.

That object carries `story`, `scale` and `status` and **omits every measurement key**: no `traced`, no `coverage`, no `mapping`, and `orphan_requirements` / `phantom_references` are absent rather than `[]`, because an empty array claims a look was taken. So:

- **Branch on `status`, never on a measurement key being present.** A pipeline reading `.coverage` unconditionally gets `null` on this shape, silently.
- **`scale` is emitted on every path**, so a consumer can always tell which shape it is holding before it reads further.

## Generate Stories Programmatically

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "/epico:epico Add retry logic to the payment gateway" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Agent,mcp__ai-memory__*" \
  --output-format json \
  --max-budget-usd 5 --no-session-persistence
```

## Validate Implementation Against Story

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "/epico:epico stories validate 001" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Agent,mcp__ai-memory__*" \
  --output-format json \
  --max-budget-usd 5 --no-session-persistence
```

## List Stories

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "/epico:epico stories" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Read,Glob,Grep,Bash" \
  --output-format text \
  --max-budget-usd 1 --no-session-persistence
```

## GitHub Actions Example

```yaml
- name: Validate epic stories
  env:
    EPIC_PLUGIN_ROOT: ${{ github.workspace }}/.epic-plugin
  run: |
    git clone https://github.com/lucascouts/epic.git "$EPIC_PLUGIN_ROOT"
    for dir in .epic/stories/*/; do
      echo "Validating $dir..."
      bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" "$dir" --cross-ref || exit 1
    done
```

## Typed structured output with `--json-schema`

When you need machine-consumable output (CI gating, dashboards, downstream agents),
combine `--output-format json` with `--json-schema`. Claude returns the result in
the `structured_output` field, sibling to the usual `result` and metadata.

Example: extract a validation summary for a story:

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "/epico:epico stories validate 001" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Agent,mcp__ai-memory__*" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "required": ["story", "status", "requirements_total", "requirements_covered", "tasks_total", "tasks_passed", "tasks_failed", "scope_creep", "gaps"],
    "properties": {
      "story": {"type": "string", "description": "Story directory name (e.g. 001-email-verification)"},
      "status": {"type": "string", "enum": ["pass", "warn", "fail"]},
      "requirements_total": {"type": "integer"},
      "requirements_covered": {"type": "integer"},
      "tasks_total": {"type": "integer"},
      "tasks_passed": {"type": "integer"},
      "tasks_failed": {"type": "integer"},
      "scope_creep": {"type": "array", "items": {"type": "string"}, "description": "Files implemented outside the story"},
      "gaps": {"type": "array", "items": {"type": "object", "properties": {"requirement": {"type": "string"}, "reason": {"type": "string"}}, "required": ["requirement", "reason"]}}
    }
  }'
```

Pipe to `jq` for CI gating:

```bash
OUT=$(claude -p "..." --plugin-dir "$EPIC_PLUGIN_ROOT" --output-format json --json-schema '{...}')
# A run that errored, or ended without a structured result, is a failure — not a pass.
echo "$OUT" | jq -e '(.is_error | not) and (.structured_output != null)' >/dev/null \
  || { echo "Epico run failed or returned no structured output" >&2; exit 1; }
RESULT=$(echo "$OUT" | jq '.structured_output')
STATUS=$(echo "$RESULT" | jq -r '.status')
[ "$STATUS" = "fail" ] && { echo "$RESULT" | jq '.gaps'; exit 1; }
```

## Detecting plugin load failures (`system/init` event)

When you run `claude -p` with `--output-format stream-json --verbose`, the stream
carries one `system/init` event. It is not always the first line: SessionStart hook
events (`hook_started`, `hook_response`) come before it, and Epico ships a
SessionStart hook — so select it by type. It contains a `plugins` array (loaded
successfully), an optional `plugin_errors` array (load-time failures such as
unsatisfied dependency versions) and the `slash_commands` the session can run. Use this to **fail CI when Epico does not load**,
which can happen if the marketplace is unreachable or `plugin.json` becomes invalid:

```bash
claude -p "Validate epic stories in this repo" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --permission-mode acceptEdits --permission-prompts none \
  --output-format stream-json \
  --verbose \
  > stream.jsonl

# Select system/init by type; hook events may precede it.
INIT=$(jq -c 'select(.type == "system" and .subtype == "init")' stream.jsonl | head -1)

if echo "$INIT" | jq -e '.plugin_errors[]? | select(.plugin == "epico")' >/dev/null; then
  echo "Epico plugin failed to load:" >&2
  echo "$INIT" | jq '.plugin_errors[] | select(.plugin == "epico")' >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '.plugins[]? | select(.name == "epico")' >/dev/null; then
  echo "Epico plugin not found in loaded plugins. Check installation." >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '[.agents[]? | select(startswith("epico:"))] | length == 6' >/dev/null; then
  echo "Epico loaded without its six sub-agents (is `--bare` set?)." >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '.slash_commands[]? | select(. == "epico:epico")' >/dev/null; then
  echo "Epico loaded but /epico:epico is not available in this session." >&2
  exit 1
fi

echo "Epico loaded successfully."
```

This is independent of any Epico-specific output — it is the platform reporting
what was actually loaded into the session. Combine with the validation example
above for an end-to-end CI pipeline.

## Notes

- Bound every unattended run: `--max-budget-usd` stops it at a cost ceiling, and `--no-session-persistence` leaves no session file behind on the runner
- Never use `--bare` with `/epico:epico`: it skips the hooks and the sub-agents the plugin ships, and accepts only an API key
- When the plugin comes from a marketplace instead of `--plugin-dir`, set `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1` so it is installed before the first turn
- Stories are always in English (no locale variation in artifacts)
- Scripts are standalone bash — no Claude Code dependency for validation
- For structured output from Claude operations, use `--output-format json`
- Combine with `--json-schema` for typed structured output (see example above)
- Inside a Claude session with the Epico plugin enabled, call the scripts through their `epic-*` wrappers on PATH (`epico-validate`, `epico-xref`, …)
