---
id: 02
title: Authenticate openai-codex in pi (or default reviewer to OpenRouter)
status: open
blocked_by: []
---

## Task

Make the reviewer's primary model reachable, or make its fallback the honest default.

## Detail

Research found `pi auth check --provider openai-codex` returns `not_ready: credentials_not_configured`.
So `gpt-5.5` on the ChatGPT subscription cannot run on pi today; only the OpenRouter fallback `openai/gpt-5.5` works.

Two acceptable outcomes:

- Authenticate `openai-codex` in pi (find and run pi's login path for that provider, or point it at the Codex CLI credentials the way `pi-claude-auth` bridges Anthropic). Then `gpt-5.5` is the reviewer primary as specced.
- If that is not cleanly possible, flip the roster so the reviewer primary is `openrouter:openai/gpt-5.5` and drop the subscription tier from the spec, stating why.

## Done when

- `pi auth check --provider openai-codex --json` reports ready, OR
- the roster and spec are updated so the reviewer runs on a provider that is actually authenticated, with a one-line note on the tradeoff.
