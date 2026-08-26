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
  Detection must read the pane output. Observed live: a reviewer pane that died on an OpenRouter 402 sat at `agent_status: idle` with the error printed in its output, so a status poll that waits for `working` before it accepts a settled state never returns and burns the full timeout.
  Read it with `herdr agent read <name> --source recent-unwrapped --lines <n>`; the default wrapped view truncates the error at the pane width, so match on a short prefix like `Error: 402` rather than the full message.
  There is also `herdr pane wait-output`, worth checking before hand-rolling a poll loop.
- Known death phrases so far: `Error: <http status>: {"message":...}` for openai-completions providers. Collect the zai and openai-codex shapes before fixing the pattern list.
- On such a death, relaunch the same ticket in the same worktree/pane on the ticket's `fallbackModels` entry, then keep watching.
- Relaunch at most once per fallback level; if the fallback also dies, surface `blocked` and notify, do not loop.
- Never claim the primary succeeded when it fell back - the report must state which model finished.

## Done when

- A builder whose primary provider is forced to fail (simulate an auth/quota error) is relaunched on its fallback and completes.
- A pane sitting `idle` after an error is detected as a death, not left to time out.
- The reviewer's `null` fallback is handled: nothing to relaunch on means notify and stop, not a crash.
- The final report names the model that actually finished.
