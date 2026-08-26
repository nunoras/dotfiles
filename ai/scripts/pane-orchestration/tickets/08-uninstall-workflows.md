---
id: 08
title: Uninstall /workflows and scrub references
status: done
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

## Resolution

- `pi remove npm:@quintinshaw/pi-dynamic-workflows` removed the package; `@quintinshaw` node_modules is now empty, so `workflow-authoring` / `workflow-patterns` are gone with it.
- `pi/extensions/workflow-liveness.ts` deleted. It was untracked in git (only on disk), so its removal is not in the repo history - it is simply gone from the live env.
- Verified: headless `pi -p` returns clean output WITHOUT `--no-extensions`; the `[workflow-delivery]` shim no longer fires.
- No scrub needed: the two "workflow" hits in AGENTS.md and the orchestrator skill refer to Matt Pocock's dev lifecycle and to "workflow preferences," not the package. Left untouched.
- `pi/settings.json` also picked up pre-existing live-config drift (version, theme, thinking, defaultProjectTrust, defaultTools) that had never been committed, since pi writes through the symlink. Synced in the same commit.
