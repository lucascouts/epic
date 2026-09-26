# CI/Headless Mode

Use these patterns when running Epic plugin operations programmatically with `claude -p` or the Agent SDK. Every recipe that invokes `/epic:epic` must load the plugin: pass `--plugin-dir "$EPIC_PLUGIN_ROOT"` (a checkout of this repo), or install the plugin first. Do not add `--bare`: it skips plugins, skills, subagents and hooks, and it ignores OAuth logins.

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

Run validation as a PR check or CI step. Inside a session with the plugin enabled, the scripts are on PATH as `epic-validate`, `epic-xref` and the other `epic-*` wrappers; for standalone CI pipelines clone the plugin repo and set `EPIC_PLUGIN_ROOT` to its path:

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
claude -p "/epic:epic Add retry logic to the payment gateway" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --allowedTools "Read,Write,Glob,Grep,Bash,Agent" \
  --output-format json
```

## Validate Implementation Against Story

```bash
claude -p "/epic:epic stories validate 001" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --allowedTools "Read,Glob,Grep,Bash,Agent" \
  --output-format json
```

## List Stories

```bash
claude -p "/epic:epic stories" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --allowedTools "Read,Glob,Grep,Bash" \
  --output-format text
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
claude -p "/epic:epic stories validate 001" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" --allowedTools "Read,Glob,Grep,Bash,Agent" \
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
  || { echo "Epic run failed or returned no structured output" >&2; exit 1; }
RESULT=$(echo "$OUT" | jq '.structured_output')
STATUS=$(echo "$RESULT" | jq -r '.status')
[ "$STATUS" = "fail" ] && { echo "$RESULT" | jq '.gaps'; exit 1; }
```

## Detecting plugin load failures (`system/init` event)

When you run `claude -p` with `--output-format stream-json --verbose`, the stream
carries one `system/init` event. It is not always the first line: SessionStart hook
events (`hook_started`, `hook_response`) come before it, and Epic ships a
SessionStart hook — so select it by type. It contains a `plugins` array (loaded
successfully), an optional `plugin_errors` array (load-time failures such as
unsatisfied dependency versions) and the `slash_commands` the session can run. Use this to **fail CI when Epic does not load**,
which can happen if the marketplace is unreachable or `plugin.json` becomes invalid:

```bash
claude -p "Validate epic stories in this repo" \
  --plugin-dir "$EPIC_PLUGIN_ROOT" \
  --output-format stream-json \
  --verbose \
  > stream.jsonl

# Select system/init by type; hook events may precede it.
INIT=$(jq -c 'select(.type == "system" and .subtype == "init")' stream.jsonl | head -1)

if echo "$INIT" | jq -e '.plugin_errors[]? | select(.plugin == "epic")' >/dev/null; then
  echo "Epic plugin failed to load:" >&2
  echo "$INIT" | jq '.plugin_errors[] | select(.plugin == "epic")' >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '.plugins[]? | select(.name == "epic")' >/dev/null; then
  echo "Epic plugin not found in loaded plugins. Check installation." >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '.slash_commands[]? | select(. == "epic:epic")' >/dev/null; then
  echo "Epic loaded but /epic:epic is not available in this session." >&2
  exit 1
fi

echo "Epic loaded successfully."
```

This is independent of any Epic-specific output — it is the platform reporting
what was actually loaded into the session. Combine with the validation example
above for an end-to-end CI pipeline.

## Notes

- Never use `--bare` with `/epic:epic`: it skips the plugin and every skill, subagent and hook it ships
- When the plugin comes from a marketplace instead of `--plugin-dir`, set `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1` so it is installed before the first turn
- Stories are always in English (no locale variation in artifacts)
- Scripts are standalone bash — no Claude Code dependency for validation
- For structured output from Claude operations, use `--output-format json`
- Combine with `--json-schema` for typed structured output (see example above)
- Inside a Claude session with the Epic plugin enabled, call the scripts through their `epic-*` wrappers on PATH (`epic-validate`, `epic-xref`, …)
