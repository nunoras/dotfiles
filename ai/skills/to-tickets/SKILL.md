---
name: to-tickets
description: Split a plan or spec into tickets, each stamped with the model that will build it. Local override of the mattpocock-skills to-tickets - use this one, not the plugin copy.
disable-model-invocation: true
---

# To Tickets (roster-aware)

Run the `mattpocock-skills:to-tickets` skill for the whole breakdown: tracer-bullet vertical slices, blocking edges, the quiz, expand-contract for wide refactors.
None of that changes.

This override changes two things: where tickets land, and what their frontmatter says.

## Where tickets land

Not `.scratch/`.
Tickets live beside the spec they came from, in `<spec-dir>/<feature-slug>/tickets/`, one `.md` per ticket numbered from `01` in dependency order.
Add a `README.md` in that directory as the index, carrying the ticket table and a copy of the roster table.

## Frontmatter

`dispatch.ps1` reads a ticket's frontmatter to decide which model builds it and on which harness, so every ticket needs it:

```markdown
---
id: 04
title: Short descriptive name
status: open
blocked_by: [01, 03]
role: builder-a
model: zai:glm-5.3
fallbackModels: openrouter:z-ai/glm-5.2:free
base: main
---
```

`id`, `title`, `status` (`open` | `claimed` | `done`), and `blocked_by` are the tracker's.
`role`, `model`, `fallbackModels`, and `base` are the dispatcher's, and they come from the roster.

**Do not type model ids by hand.** Get them from the roster:

```powershell
. "$HOME\.claude\scripts\roster.ps1"
Get-RosterFrontmatter -Role builder-a          # -Base develop if the ticket branches off something else
```

That prints the four dispatcher lines ready to paste, omitting `fallbackModels` for a role that has none.
It is a command and not a lookup table on purpose: `pi --model <wrong-id>` does not error, it silently runs the default Anthropic model, so a typo here produces a builder that looks fine and is the wrong vendor.

## Choosing the role

You pick `builder-a` or `builder-b` per ticket; the roster maps that slot to a model.
Spread the work rather than defaulting every ticket to one slot - two builders on one subscription each is the point of having two.

Tickets that are mostly judgement rather than execution do not get a builder at all.
Say so in the ticket and leave it for the planner's own session.

Read the roster before you start, since the slots change:

```powershell
. "$HOME\.claude\scripts\roster.ps1"
Get-Roster | ConvertTo-Json
```

Use `Get-Roster`, not a path: the file lives in the dotfiles repo and is reached through a symlinked directory, so a hard-coded `~/.claude/roster.json` does not exist.

## Related overrides

`wayfinder` and `to-spec` stay roster-aware only.
They name the role a chunk of work needs, never a model id.
The model is bound here, at ticket time, because that is the last point before dispatch and the roster may have changed under a long-lived spec.
