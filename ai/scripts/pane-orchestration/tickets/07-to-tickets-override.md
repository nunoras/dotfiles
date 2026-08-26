---
id: 07
title: Local to-tickets override that stamps roster frontmatter
status: open
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
