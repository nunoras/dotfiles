---
id: 05
title: Fallback watcher - relaunch dead session on fallback model
status: open
blocked_by: [03, 04]
---

## Task

Give builders and reviewers the fallback the roster promises, since pi has no mid-session auto-swap for these providers.

## Detail

Research: `allowedFallbackModels` is Anthropic-API-only; pi does not client-side swap on quota for zai/openrouter/openai-codex. So the script must do it.

- Extend `Wait-Agent` (or a sibling watcher) to distinguish a normal finish from a death on quota / rate-limit / auth.
  Detection can read the pane output and/or the pi session for the known error phrases.
- On such a death, relaunch the same ticket in the same worktree/pane on the ticket's `fallbackModels` entry, then keep watching.
- Relaunch at most once per fallback level; if the fallback also dies, surface `blocked` and notify, do not loop.
- Never claim the primary succeeded when it fell back - the report must state which model finished.

## Done when

- A builder whose primary provider is forced to fail (simulate an auth/quota error) is relaunched on its fallback and completes.
- The final report names the model that actually finished.
