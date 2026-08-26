---
id: 02
title: Authenticate openai-codex in pi
status: open
blocked_by: []
---

## Task

Make the reviewer's primary model reachable. It is the only reviewer model there is.

## Detail

Research found `pi auth check --provider openai-codex` returns `not_ready: credentials_not_configured`.
So `gpt-5.5` on the ChatGPT subscription cannot run on pi today.

The OpenRouter escape hatch is gone.
A live reviewer pane on `openrouter:openai/gpt-5.5` died with `402 ... requested up to 128000 tokens, but can only afford 1212`: the account is free-tier and every `openai/gpt-5.x` id on OpenRouter is paid.
The roster now carries `"fallback": null` for the reviewer and `review.ps1` fails loudly instead of picking a model nobody chose.

So there is one outcome: authenticate `openai-codex` in pi.
Find and run pi's login path for that provider, or point it at the Codex CLI credentials the way `pi-claude-auth` bridges Anthropic.
Expect interactive OAuth.

## Done when

- `pi auth check --provider openai-codex --json` reports ready.
- `review.ps1` selects `openai-codex:gpt-5.5` as `roster primary` and the reviewer pane actually produces a review.

## If it turns out to be impossible

Do not paper over it with a free model.
Record why in the spec and leave the reviewer on the documented manual fallback: the Opus `reviewer` agent, with the report stating it ran on the fallback.
