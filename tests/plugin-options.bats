#!/usr/bin/env bats
# Plugin options reach the model, and the options that promise nothing are gone.
#
# Claude Code substitutes ${user_config.KEY} in skill content only; files
# under references/ are not substituted, and CLAUDE_PLUGIN_OPTION_<KEY> reaches
# hook processes only. So every option the model must honour is named in
# SKILL.md, and the references point there.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$ROOT/skills/epic/SKILL.md"
}

@test "SKILL.md carries aiMemory and defaultScale through user_config" {
  grep -qF '${user_config.aiMemory}' "$SKILL"
  grep -qF '${user_config.defaultScale}' "$SKILL"
}

@test "SKILL.md states each option's default, because an unsaved value is not substituted" {
  # Claude Code substitutes only a SAVED value; with none saved the literal
  # placeholder reaches the model, so the default must be written beside it.
  for key in aiMemory defaultScale staleThresholdDays spikeStaleThresholdDays; do
    default=$(jq -r --arg k "$key" '.userConfig[$k].default' "$ROOT/.claude-plugin/plugin.json")
    grep -qF "\${user_config.$key}\` [\`$default\`]" "$SKILL"
  done
}

@test "artifact language is not an option: no artifactLanguage key anywhere" {
  run jq -e '.userConfig.artifactLanguage' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -ne 0 ]
  run git -C "$ROOT" grep -n 'artifactLanguage' -- skills agents references README.md
  [ "$status" -eq 1 ]
}

@test "SKILL.md states that .epic documentation is always English and not configurable" {
  grep -q 'Everything the Epic writes under `.epic/` is written in English' "$SKILL"
  grep -q 'This is not an option and no setting changes it' "$SKILL"
}

@test "no hook defers git commit" {
  run grep -n 'defer' "$ROOT/hooks/hooks.json"
  [ "$status" -eq 1 ]
  [ ! -e "$ROOT/scripts/hook-defer-commit.sh" ]
}

@test "ci-mode recipes never pass --bare with /epic:epic" {
  run bash -c "grep -nE -- '--bare( |\$)' '$ROOT/references/ci-mode.md' | grep -v 'Never use'"
  [ -z "$output" ]
}

@test "SKILL.md fits the post-compaction budget, standing rules first" {
  # After compaction Claude Code re-attaches only the first 5,000 tokens of a
  # skill (about 20,000 characters, before the injected project state). The
  # rules that must survive sit above the routing, and the file stays well
  # under the cap so the injected state does not push them out.
  [ "$(wc -c < "$SKILL")" -lt 17000 ]
  lang=$(grep -n '^## Language' "$SKILL" | cut -d: -f1)
  gotchas=$(grep -n '^## Gotchas' "$SKILL" | cut -d: -f1)
  routing=$(grep -n '^## Command Routing' "$SKILL" | cut -d: -f1)
  [ "$lang" -lt "$routing" ]
  [ "$gotchas" -lt "$routing" ]
}

@test "SKILL.md carries no thinking keyword and no paths gate" {
  # `ultrathink` anywhere in the body raises effort on every invocation;
  # `paths:` would keep the skill from triggering in a repo with no .epic yet.
  run grep -niw 'ultrathink' "$SKILL"
  [ "$status" -eq 1 ]
  run grep -n '^paths:' "$SKILL"
  [ "$status" -eq 1 ]
}
