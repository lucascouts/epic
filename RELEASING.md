# Releasing

What a version cut actually involves, written from the 0.5.0 and 0.6.0 cuts. Every step below has been executed; where a step has a known trap, the trap is named rather than left to be rediscovered.

## 1. Verify locally, before anything is pushed

Local results are the evidence that the work is done — CI confirms them, it does not produce them.

```bash
bats tests/                              # as a normal user; see the trap below
shellcheck scripts/*.sh bin/*
for e in assets/examples/*.md; do bash scripts/validate-story.sh --help >/dev/null; done
gitleaks protect --staged=false          # and `gitleaks detect --log-opts main..HEAD`
jq -e . .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

**Trap — run `bats` as yourself, not as root.** Fourteen cases make a file unreadable and require the script to refuse. Root can read a `chmod 000` file, so the refusal never fires and the cases report false failures: 11 in `archive-story.bats`, 3 in `epic-index.bats`. This is why `act -j bats` (whose image runs as root) is **not** the faithful run.

## 2. Mirror CI locally

```bash
act -l                                   # list, no run
act -j shellcheck --pull=false           # faithful
act -j validate-examples --pull=false    # faithful
```

`act -j bats` is expected to report exactly the 14 failures above. Any *other* failure is real.

## 3. Take the triage-variance sample

The same request drew Fast once and Standard twice on v0.5.0 — scale instability was the defect that the 0.6.0 work set out to fix, and it is invisible in the test suite because it is a property of a model's judgement, not of a script.

From the persona harness (`Testes/epic-sim`, not part of this repository):

```bash
./triage-variance.sh 5
```

Each sample stops the moment `tasks.md` is written, which is the only place the chosen scale is legible — the plain register deliberately keeps the word out of the chat. Measured on one sample: **841k input tokens, 58 output, 313 seconds** — about a fifth of a full run, which reaches ~4M input tokens. The monitor reports tokens per sample from the stream, because a run that stops early never emits the `result` event that carries the cost.

**Record the distribution in the release's CHANGELOG entry.** It is a **monitor, never a gate**: a distribution is read by a human, and one run that disagrees is information, not a build failure. The reason is paid for — a trigger eval used as a gate read 0/30 and then 5/5 on a tree with no edit at all, measuring the calendar instead of the diff. Assertions belong in a deterministic lint; judgement belongs in monitoring.

## 4. Cut the version

Four sites, and they must agree:

| File | Where |
|---|---|
| `.claude-plugin/plugin.json` | `.version` |
| `.claude-plugin/marketplace.json` | `.plugins[0].version` |
| `README.md` | the version line near the end |
| `ARCHITECTURE.md` | "Last verified against" |

Then in `CHANGELOG.md`: promote `[Unreleased]` to `[N.N.N] — YYYY-MM-DD`, write the entry (what changed and the measurement that motivated it), state **Minimum Claude Code**, and repoint the link block so `[Unreleased]` compares from the new tag.

```bash
grep -rn '<previous version>' --include='*.md' --include='*.json' . | grep -v CHANGELOG
```

should return nothing: every remaining mention belongs to the changelog's own history.

## 5. Ship

The repository merges by pull request, and every merge on `main` is a **merge commit** — `git log --first-parent main` shows two parents on each. Recent feature PRs use a `feat: … (#N)` subject rather than the default text.

```bash
git push -u origin <branch>
gh pr create --base main --title '…' --body-file <body>
gh pr checks <N>                         # 5 checks: bats, shellcheck, validate-examples, Analyze, CodeQL
gh pr merge <N> --merge --delete-branch --subject 'feat: … (#N)'
```

`Analyze` / `CodeQL` have no local equivalent — CodeQL is the one check that genuinely cannot run here, and it is the only part of a release not verified before the push.

Then the tag, **annotated**, on the merge commit:

```bash
git checkout main && git pull --ff-only
git tag -a vN.N.N <merge-sha> -m 'Epic vN.N.N — <one line>'
git push origin vN.N.N
```

**The tag is not the release.** Every version since v0.1.0 has a GitHub Release object, and a pushed tag alone leaves the version invisible on the releases page even though the `releases/tag/…` link in the CHANGELOG still resolves — which is exactly how this step gets missed. Create it from the version's own CHANGELOG section, verbatim, titled `Epic vN.N.N`:

```bash
awk '/^## \[N\.N\.N\]/{f=1; next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/notes.md
gh release create vN.N.N --title 'Epic vN.N.N' --notes-file /tmp/notes.md --verify-tag
gh release list --limit 3        # the new one must read Latest
```

`--verify-tag` refuses rather than inventing a tag that was never pushed.
