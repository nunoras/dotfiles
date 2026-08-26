---
id: 06
title: review.ps1 - split-right read-only pi reviewer
status: open
blocked_by: [03, 04]
---

## Task

Replace the Codex `gpt-review.ps1` shell-out with a pi reviewer that runs in a pane split to the right of the builder.

## Detail

- Input: `-Ticket <id> -Verdict '<cmd> -> PASS'`. Verdict is required (human ran the build/tests; GPT cannot).
- Split the builder's pane right (`herdr pane split --direction right`), start pi + the reviewer model (roster `reviewer`, `openai-codex:gpt-5.5` or its OpenRouter fallback) read-only in the same worktree.
- Feed the reviewer: the committed diff vs `base`, the ticket brief, and the verdict. Reuse the review standards body from `ai/agents/reviewer.md` (strip frontmatter), as `gpt-review.ps1` does today.
- Read-only means no write/edit tools for the reviewer session.
- Relay the review verbatim. Do not paraphrase. Blocking findings are the human's call.

## Done when

- After a build, `review.ps1 -Ticket 42 -Verdict '...'` opens a reviewer pane to the right of the builder and prints the review verbatim.
- The reviewer cannot modify the worktree.
- Builder on the left, reviewer on the right.
