---
story: migrate-commit-field
type: feature
scale: full
status: archived
version: 1
created: 2026-08-16
---

# Story - Epic Migrate and the Commit Field

## Introduction

The corpus holds 17 tasks.md files no Epic parser can see, 15 files with
leaked wrapper tags, dangling `Requirements:` pointers in fast stories — and
12% of all checkboxes are ceremonial "Commit" sub-tasks, the single largest
factory of false-partial stories. This story ships the normalizer (`epic
migrate`, dry-run by default) and the template change it carries: `Commit`
becomes a group-level field, leaving the completion census to measure work,
not ritual. Derived from `design.md` (design-first).

## Requirements

### R1. The migrate contract

#### Acceptance Criteria

- R1.1: WHEN invoked without flags THE SYSTEM SHALL write nothing — dry-run is
  the default, emitting one JSON verdict on stdout and a unified diff on
  stderr
- R1.2: WHEN invoked with `--apply` THE SYSTEM SHALL rewrite atomically,
  preserve line endings, then run story validation and embed its verdict in
  the JSON
- R1.3: WHEN the target story lives under `.epic/archive/`, or a file is an
  unparseable mixture, THE SYSTEM SHALL refuse with exit 1 naming the reason
  and the offending lines — migrate never guesses
- R1.4: WHEN `--apply` runs a second time on the same story THE SYSTEM SHALL
  report zero rewrites and produce no diff — idempotency by grammar, never by
  marker file
- R1.5: WHEN any rewrite changes a file THE SYSTEM SHALL bump that artifact's
  frontmatter `version:`; an unchanged file keeps its version

### R2. The five variants, rewritten honestly

#### Acceptance Criteria

- R2.1: WHEN a tasks.md carries `## T1`-style headers or `Covers:` fields THE
  SYSTEM SHALL rewrite them to canonical checkbox tasks with `Requirements:`
  lines
- R2.2: WHEN a task list has no checkboxes THE SYSTEM SHALL add every box as
  `[ ]` — migrate records shape and never invents done-ness
- R2.3: WHEN leaked `</content>` or `</invoke>` wrapper tags appear outside
  fenced blocks THE SYSTEM SHALL strip them; inside a fence they are
  documentation and survive
- R2.4: WHEN the resolved scale (tasks.md authoritative) is fast or spike THE
  SYSTEM SHALL remove `Requirements:` fields and R-tokens — and SHALL leave
  any `satisfied-by:` suffix untouched
- R2.5: WHEN a Commit checkbox sub-task is found THE SYSTEM SHALL convert it
  to the group-level `Commit:` field, preserving the message verbatim and
  leaving the sub-task numbering gap in place — numbers are provenance and are
  never reassigned

### R3. Commit is a field, and every consumer knows

#### Acceptance Criteria

- R3.1: WHEN the template prescribes a group's commit point THE SYSTEM SHALL
  use the group-level `- Commit: "..."` field — the checkbox sub-task form
  leaves the template, the story-anchor recommendation moves with the field
  unchanged
- R3.2: WHEN validation counts commit coverage THE SYSTEM SHALL accept the
  field form as satisfying every-group-has-a-commit-point, and SHALL warn that
  a checkbox Commit sub-task is the legacy shape migrate converts
- R3.3: WHEN the template changes THE SYSTEM SHALL update every consumer copy
  in the same story: the tasks reference (template, field table, rules,
  gotchas, fast adaptations), run-mode (`--gate=commit`, Commit sections,
  parallel rule, and its prose copies of the sub-task form), phase-gates and
  test-advisor Commit exemptions, list-mode example lines, validate-mode and
  the validator's commit-verification arm, all four packaged examples, and the
  router entry (`stories migrate`) with its `bin/` wrapper
- R3.4: WHEN a batch or single create generates a new story THE SYSTEM SHALL
  emit the field form only

### R4. The census consequences are stated, not discovered

#### Acceptance Criteria

- R4.1: WHEN run-mode orders a group's tail THE SYSTEM SHALL close boxes →
  run the status census (which may write `done`) → execute the group's
  `Commit:` field → then offer archive — the commit executes after `done`
  exists, and the ordering text says so
- R4.2: WHEN a story with field-form commits is archived THE SYSTEM SHALL
  derive manifest counters from the boxes that exist; previously archived
  manifests are snapshots and SHALL NOT be re-derived
- R4.3: WHEN dependency satisfaction is evaluated THE SYSTEM SHALL be
  unaffected by the absence of Commit boxes — satisfaction reads the boxes
  that exist, and the reference states the semantic consequence

## Success Metrics

- The all-variants fixture migrates to a clean validate pass in one `--apply`,
  and the second run reports zero rewrites
- A bentoolkit-shaped tasks.md becomes visible to `cross-reference.sh` with
  non-empty mapping after migration
- New stories carry zero Commit checkboxes; the false-partial factory closes
  at the template

## Constraints

- House script contract (JSON stdout, diff on stderr, exit 0/1/2); majority
  frontmatter dialect (CRLF-tolerant, comment-stripping)
- Wave sequencing: story 010 lands first and reads both Commit shapes; this
  story rebases its run-mode ordering edit on 010's text
- No shared library — the detector regexes cite their sources and join the
  movers-comments

## Out of Scope

- Migrating stories under `.epic/archive/` (read-only by invariant)
- A cross-project sweep (`--all` over many repos) — per-story, this repo's
  mode prose may loop
- Re-deriving existing archive manifests
- Normalizing story.md/design.md prose beyond wrapper-tag stripping
