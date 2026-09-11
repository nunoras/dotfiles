---
name: to-tickets
description: Split a plan or spec into tickets, each stamped with the role that will build it. Local override of the mattpocock-skills to-tickets - use this one, not the plugin copy.
disable-model-invocation: true
---

# To Tickets (roster-aware, GitHub)

Run the `mattpocock-skills:to-tickets` skill for the whole breakdown: tracer-bullet vertical slices, blocking edges, the quiz, expand-contract for wide refactors.
None of that changes.

This override changes two things: where tickets land, and how they carry dispatcher info.

## Where tickets land

GitHub Issues in this repo, per `docs/agents/issue-tracker.md`. Use the `gh` CLI; infer the repo from `git remote -v`.

- One issue per ticket, created in dependency order so numbers roughly follow order.
- Blocking edges use GitHub's native issue dependencies (`gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`), where `<blocker-db-id>` is the blocker's numeric database id (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`).
- Label each ticket `ready-for-agent` once it is fully specified, or leave it unlabelled and let `/triage` handle it if it still needs decisions.
- Do not create a local `tickets/` folder or a README index. The issue list is the index.

## Dispatcher info in the issue body

Each ticket carries its dispatcher info in a fenced block at the top of the issue body:

```markdown
<!-- dispatch frontmatter -->
```
role: builder
model: zai:glm-5.3-flash:high
fallbackModels: xai:grok-4.6:high
base: main
```
```

The dispatch server does not read this block; it picks models from its own workflow roles.
The block records the roster at ticket time, so keep the roster in step with the server.

Omit the `fallbackModels` line entirely for a role that has none.
Do not include tracker fields (`id`, `status`, `blocked_by`) - the issue number, open/closed state, and native dependencies are those now.

**Do not type model ids by hand.** Get them from the roster:

```powershell
. "$HOME\.claude\scripts\roster.ps1"
Get-RosterFrontmatter -Role builder          # -Base develop if the ticket branches off something else
```

That prints the four dispatcher lines ready to paste.
It is a command and not a lookup table on purpose: `pi --model <wrong-id>` does not error, it silently runs the default Anthropic model, so a typo here produces a builder that looks fine and is the wrong vendor.

## Choosing the role

Every execution ticket gets `role: builder`; the roster maps that role to a model.

Tickets that are mostly judgement rather than execution do not get a dispatcher block at all.
Say so in the ticket body and leave it for the planner's own session.

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
