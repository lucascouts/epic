# Output Rules

Loaded before any story artifact is created or refined: where artifacts go, how they are numbered, and the frontmatter every artifact carries.

- Default path: `.epic/stories/NNN-<name>/`
- Naming: `NNN-kebab-case` where NNN is auto-incremented (zero-padded, 001-999)
- Auto-increment: `epic-next-number` detects the highest existing number across `.epic/stories/` AND `.epic/archive/` and adds 1. It is the single allocator — neither create flow re-implements the scan, and `--reserve N` claims numbers on disk (directory existence is the reservation)
- Numbers are NEVER recycled — archived stories retain their numbers permanently
- If 999 is reached: "Maximum story count reached. Archive old stories with `/epic:epic stories archive` to free space."
- Create directory before writing files
- User can override path; accept without further questions
- Add version frontmatter to each artifact on creation:
  ```yaml
  ---
  story: <story-name>
  type: feature | bugfix
  scale: fast | standard | full | spike
  engineering: experiment | tool | project | product
  version: 1
  created: <date>
  status: draft
  ---
  ```
- `status: draft` applies to **newly created stories only**. Never add the field
  to a story that already exists — an existing story's state is whatever the
  engine observed, and CREATE observed nothing about it. See
  [lifecycle-status.md](lifecycle-status.md) for the full field spec.
- Refine writes `status:` for exactly **one** transition: the reopen edge. A
  refinement that leaves an open `[ ]` on a story reading `done` or `validated`
  writes `in-progress` — see
  [Status Census](refine-mode.md#status-census). It writes no
  other value: a refinement that does not reopen the story leaves the field
  exactly as it was, including absent.
- On Refine, increment version and add history entry:
  ```yaml
  ---
  story: <story-name>
  type: feature
  scale: full
  version: 2
  created: <original-date>
  last-refined: <today>
  history:
    - v1: Initial story
    - v2: <one-line summary of refinement>
  ---
  ```
- Version is a simple integer, not semver
- Maximum 10 history entries; older entries: "see git history" — **unless the artifacts are not in git, in which case the cap does not apply.** The rule relegates old entries, and relegation needs somewhere to relegate them *to*. Where `.epic/` is gitignored — the default this plugin ships, and verifiable with `git ls-files .epic/` returning nothing — dropping the eleventh entry destroys it instead of moving it, and the escape hatch the rule names does not exist. Check before trimming; a story that has genuinely been refined eleven times keeps eleven entries, and that is not a violation. Where the artifacts *are* tracked, the cap holds as written
- All files in a story share the same version number

The `status:` field, its six values and who writes each: [lifecycle-status.md](lifecycle-status.md).
