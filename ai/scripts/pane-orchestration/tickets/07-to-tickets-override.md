---
id: 07
title: Local to-tickets override that stamps roster frontmatter
status: done
blocked_by: [01]
---

## Task

Make `to-tickets` emit tickets that already carry their model assignment.

## Detail

- Add a local override of the Matt Pocock `to-tickets` skill under `ai/skills/` (higher precedence than the plugin copy).
- On splitting a spec into tickets, it stamps each ticket's frontmatter from `roster.json`:
  `role`, `model` (`provider:id`), `fallbackModels`, `base`.
- The planner chooses `builder-a` vs `builder-b` per ticket; `to-tickets` maps the chosen role to its roster entry.
- `wayfinder` and `to-spec` stay roster-aware only: they note which role a chunk needs, not the exact model. Add a short note to their local overrides if needed.

## Done when

- Running `to-tickets` against a spec produces ticket files whose frontmatter matches the roster, with no hand-editing of model ids.

## Resolution

- `ai/skills/to-tickets/SKILL.md`: a thin override, in the house style of `grill-with-docs`. It defers the whole breakdown to `mattpocock-skills:to-tickets` and changes only two things - tickets land beside their spec rather than in `.scratch/`, and they carry dispatch frontmatter.
- `Get-RosterFrontmatter -Role <slot> [-Base <branch>]` in `roster.ps1` prints the four dispatcher lines ready to paste, omitting `fallbackModels` for a role that has none. The skill tells the planner to run it rather than copy ids, because `pi --model <wrong-id>` does not error - it silently runs the default Anthropic model, so a typo produces a builder that looks fine and is the wrong vendor.
- It validates the refs it emits, so a malformed roster fails at ticket time instead of inside a pane an hour later.
- Note lives in `ai/skills/`, which is the Claude Code skill set (`~/.claude/skills` -> `ai/skills`). pi reads `pi/skills` instead. The planner is a Claude Code session, so that is the right side.
- Verified: 8 new assertions in `roster.tests.ps1` on both shells, plus a round trip - frontmatter produced by `Get-RosterFrontmatter` pasted into a ticket, then read back by `dispatch.ps1 -DryRun`, resolving to the right provider, model, harness, agent prompt, and fallback.
- Corrected while writing it: the first draft told the planner to `Get-Content ~/.claude/roster.json`, which does not exist. The roster is reached through a symlinked directory, so the skill says `Get-Roster`.
