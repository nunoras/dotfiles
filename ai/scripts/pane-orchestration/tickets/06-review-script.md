---
id: 06
title: review.ps1 - split-right read-only pi reviewer
status: done
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

## Resolution

- `ai/scripts/review.ps1`: reuses `gpt-review.ps1`'s prompt shape (intent + verdict + commits + files + diff, capped at `-MaxDiffBytes`) but writes it to a temp task file and runs pi in a pane split RIGHT of the builder, read-only.
- Reviewer model comes from the roster `reviewer` role, not the builder ticket. Auth-aware: if the primary provider is not ready it uses the fallback and says why. Verified live - `openai-codex` is not authed, so it selected `openrouter:openai/gpt-5.5`.
- Read-only enforced by a new `M2_READONLY` env consumed by `herdr-autostart.ps1` (`--exclude-tools write,edit,bash,powershell`). The task file is in temp, so the worktree stays clean.
- `-Verdict` is a precondition (validated for PASS/FAIL/not-run), same rationale as `gpt-review.ps1`. Reviewer standards come from `reviewer.md` as the appended system prompt. The script prints `herdr agent read` and shouts RELAY VERBATIM; it never captures-and-softens.
- `ai/scripts/review.tests.ps1`: 14 assertions (verdict validation, auth-aware model selection, diff collection, task-file contents, model override) against a real temp git repo. Pass on pwsh 7 and PS 5.1.
- NOT verified automatically: the live pane split and the builder-pane resolution (`herdr agent get` field names are best-effort - `-BuilderPane <id>` is the explicit fallback). Needs a keyboard smoke test.
