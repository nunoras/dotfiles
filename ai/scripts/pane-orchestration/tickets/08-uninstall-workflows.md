---
id: 08
title: Uninstall /workflows and scrub references
status: open
blocked_by: []
---

## Task

Remove the `pi-dynamic-workflows` engine and everything that only exists for it.

## Detail

- Remove `npm:@quintinshaw/pi-dynamic-workflows` from `~/.pi/agent/settings.json` packages (and the dotfiles `pi/settings.json` copy). Run `pi uninstall`.
- Remove the `workflow-liveness.ts` extension (it polls the workflow run store; useless once the engine is gone).
- Scrub workflow references from the orchestrator skill and AGENTS.md.
- The `workflow-authoring` / `workflow-patterns` skills disappear with the package - confirm they are gone from `pi config`.
- Research note: the workflow `[workflow-delivery]` shim fail-closed headless pi (`-p`) runs; removing it also fixes that.

## Done when

- `pi list` no longer shows the workflow package, and `--list-models`/headless `-p` run clean without `--no-extensions`.
- No dangling references to `/workflows` or `workflow-*` skills in AGENTS.md or the orchestrator skill.
