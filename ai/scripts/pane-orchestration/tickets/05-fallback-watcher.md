---
id: 05
title: Fallback watcher - relaunch dead session on fallback model
status: done
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

## Resolution

- `ai/scripts/herdr.ps1`: the shared plumbing both scripts had been duplicating (`Invoke-Herdr`, `Wait-Agent`, `Wait-PaneAgent`, `New-AgentPane`, `Get-AgentPane`), plus the watcher itself. `dispatch.ps1` and `review.ps1` now dot-source it and their local copies are gone.
- `Get-DeathLines` is pure text in, findings out, so it is testable without a live pane. It anchors on pi's own `Error:` rendering rather than a keyword search, because the ticket brief is echoed into the same buffer - a brief that says "handle the 429 rate limit" must not read as a rate-limit death. `herdr.tests.ps1` pins exactly that case.
- Failover triggers on 401/402/403/429 and on credential phrases. 5xx deliberately does not: those are transient, and spending a fallback on one hiccup is worse than waiting.
- `Wait-Agent` reads output every poll regardless of status, since a dead session never reaches `working`. `-BaselineDeaths` stops the previous failure in the scrollback from instantly killing the pane that just recovered from it.
- Failover closes the dead pane and re-splits from the worktree root rather than re-prompting the dead session, which is still alive at `idle` and would just hit the same provider again. One attempt per fallback level, then notify and stop.
- The final line always names the model that finished, and says loudly when that was a fallback rather than the ticket's model.
- Verified live end to end, not simulated: a ticket with `model: openrouter:openai/gpt-5.5` (guaranteed 402 on a free-tier account) and `fallbackModels: zai:glm-5.3` died on the 402, failed over, and GLM completed the work and committed it. `Outcome: done`, `FinishedOn: zai:glm-5.3`.
- `review.ps1` handles `died` by saying there is NO REVIEW and pointing at the manual route, rather than letting a dead reviewer pane pass for a quiet one.
- The final report names the model that actually finished.
