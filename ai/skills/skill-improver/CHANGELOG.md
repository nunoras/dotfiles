# skill-improver changelog

This is the skill's memory of every improvement it has applied to other skills.
Read it before proposing changes so the same suggestion is never made twice, and log rejected suggestions too (marked `(rejected)`) so they are not reopened.

Format per entry:

```
## <YYYY-MM-DD> - <target-skill> <new-version>
- **Change:** <what was patched, area>
- **Evidence:** <the friction that justified it>
- **Files:** <paths edited>
```

---

## 2026-06-27 - skill-improver 1.1.0 (self)
- **Change:** Adapted the imported v1.0.0 skill for Claude Code: locate skills via Glob across global/project/mirror roots, read the real SKILL.md, propose exact diffs, apply with Edit after approval, bump target version, and keep this changelog. Added a multi-copy guardrail.
- **Evidence:** Original was written for generic ChatGPT/Agent Skills and defaulted to "patch plan" hedging that is dead weight when files are directly readable.
- **Files:** SKILL.md, references/patch-template.md, examples/review-example.md, CHANGELOG.md (new)

## 2026-06-29 - orchestrator (unversioned)
- **Change:** Fixed the documented Codex reviewer invocation in `references/agent-prompt-templates.md`: `codex "<prompt>"` -> `codex exec ... -s read-only -o <file>`, plus a warning that the bare `codex` form launches the interactive TUI and hangs in an agent Bash context.
- **Evidence:** Running the owed Phase 09 review this session, the documented command would have hung; had to discover `codex exec` via `--help`. The command is core to the skill ("all reviews must use Codex"), so the gap recurs on every gate review.
- **Files:** `.agents/skills/orchestrator/references/agent-prompt-templates.md` (canonical; `.claude/skills` is a symlink to it)

## 2026-06-29 - orchestrator (unversioned)
- **Change:** Added a scratch-files note after the Codex invocation block in `references/agent-prompt-templates.md`: background gate reviews emit raw `<name>.stdout.log` / `<name>.stderr.log` dumps (can be megabytes); those, `_codex-prompt.md`, and dev-server logs under `.agents/backlog/` must be gitignored and kept out of phase commits/PRs - only the `-o` review `.md` is durable.
- **Evidence:** Closing the Phase 09 gate this session, a 1.9 MB Codex stderr dump plus dev-server logs sat untracked and a plain `git add -A` would have swept them into the PR; had to discover and gitignore them at commit time. The background-review pattern is documented in the same file, so the junk recurs on every gate review.
- **Files:** `.agents/skills/orchestrator/references/agent-prompt-templates.md` (canonical; `.claude/skills` is a symlink to it, confirmed this session)
