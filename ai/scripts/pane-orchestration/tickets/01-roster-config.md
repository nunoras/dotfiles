---
id: 01
title: Roster config + harness-derivation helper
status: open
blocked_by: []
---

## Task

Create the single source of truth for role -> model, and a helper that derives the harness from a model's provider.

## Detail

- Add `roster.json` under `ai/` (symlinked to `~/.claude/roster.json`), keyed by role: `planner`, `builder-a`, `builder-b`, `reviewer`.
  Each role holds `{ primary: "provider:id", fallback: "provider:id" }`.
- Add a small PowerShell helper (dot-sourceable, e.g. `ai/scripts/roster.ps1`) exposing:
  - `Get-RosterEntry -Role <role>` -> primary + fallback.
  - `Get-Harness -Provider <p>` -> `claude` when `anthropic`, else `pi`.
  - `Split-ModelRef "provider:id"` -> `@{ Provider; Model }`.
- Keep it PowerShell 5.1 compatible (herdr spawns 5.1): no `??`, `?.`, ternary.

## Done when

- `Get-Harness -Provider anthropic` returns `claude`; `zai`/`openrouter`/`openai-codex` return `pi`.
- The roster matches the spec's table and is the only place model ids are written.
