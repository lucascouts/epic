# CI/Headless Mode

Use these patterns when running Epic plugin operations programmatically via the Claude Code Agent SDK.

## Validate Stories in CI

Run validation as a PR check or CI step. The plugin scripts are bundled at `${CLAUDE_PLUGIN_ROOT}/scripts/` when invoked inside a session; for standalone CI pipelines clone the plugin repo and set `EPIC_PLUGIN_ROOT` to its path:

```bash
# Validate structural correctness
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature-name/

# Validate with cross-reference checks (requirements traceability)
bash "$EPIC_PLUGIN_ROOT/scripts/validate-story.sh" .epic/stories/001-feature-name/ --cross-ref

# Dedicated cross-reference report
bash "$EPIC_PLUGIN_ROOT/scripts/cross-reference.sh" .epic/stories/001-feature-name/
```

Exit codes: 0 = pass, 1 = issues found, 2 = invalid input. Output is always JSON.

## Generate Stories Programmatically

```bash
claude -p "/epic:task Add retry logic to the payment gateway" \
  --allowedTools "Read,Write,Glob,Grep,Bash,Agent" \
  --bare \
  --output-format json
```

## Validate Implementation Against Story

```bash
claude -p "/epic:task stories validate 001" \
  --allowedTools "Read,Glob,Grep,Bash,Agent" \
  --bare \
  --output-format json
```

## List Stories

```bash
claude -p "/epic:task stories" \
  --allowedTools "Read,Glob,Grep" \
  --bare \
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
claude -p "/epic:task stories validate 001" \
  --bare --allowedTools "Read,Glob,Grep,Bash,Agent" \
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
RESULT=$(claude -p "..." --json-schema '{...}' | jq '.structured_output')
STATUS=$(echo "$RESULT" | jq -r '.status')
[ "$STATUS" = "fail" ] && { echo "$RESULT" | jq '.gaps'; exit 1; }
```

## Detecting plugin load failures (`system/init` event)

When you run `claude -p` with `--output-format stream-json --verbose`, the first
event of the stream is `system/init`. It contains a `plugins` array (loaded
successfully) and an optional `plugin_errors` array (load-time failures such as
unsatisfied dependency versions). Use this to **fail CI when Epic does not load**,
which can happen if the marketplace is unreachable or `plugin.json` becomes invalid:

```bash
claude -p "Validate epic stories in this repo" \
  --bare \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  > stream.jsonl

# First line is system/init. Confirm Epic is in `plugins` and not in `plugin_errors`.
INIT=$(head -1 stream.jsonl)

if echo "$INIT" | jq -e '.plugin_errors[]? | select(.plugin == "epic")' >/dev/null; then
  echo "Epic plugin failed to load:" >&2
  echo "$INIT" | jq '.plugin_errors[] | select(.plugin == "epic")' >&2
  exit 1
fi

if ! echo "$INIT" | jq -e '.plugins[]? | select(.name == "epic")' >/dev/null; then
  echo "Epic plugin not found in loaded plugins. Check installation." >&2
  exit 1
fi

echo "Epic loaded successfully."
```

This is independent of any Epic-specific output — it is the platform reporting
what was actually loaded into the session. Combine with the validation example
above for an end-to-end CI pipeline.

## Notes

- Use `--bare` for consistent results across machines (skips auto-discovery)
- Stories are always in English (no locale variation in artifacts)
- Scripts are standalone bash — no Claude Code dependency for validation
- For structured output from Claude operations, use `--output-format json`
- Combine with `--json-schema` for typed structured output (see example above)
- When invoked inside a Claude session with the Epic plugin enabled, scripts are reachable via `${CLAUDE_PLUGIN_ROOT}/scripts/`
