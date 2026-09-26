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
