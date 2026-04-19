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

## Notes

- Use `--bare` for consistent results across machines (skips auto-discovery)
- Stories are always in English (no locale variation in artifacts)
- Scripts are standalone bash — no Claude Code dependency for validation
- For structured output from Claude operations, use `--output-format json`
- Combine with `--json-schema` for typed structured output
- When invoked inside a Claude session with the Epic plugin enabled, scripts are reachable via `${CLAUDE_PLUGIN_ROOT}/scripts/`
