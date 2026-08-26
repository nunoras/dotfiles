---
id: 03
title: dispatch.ps1 - frontmatter-driven pane dispatch
status: open
blocked_by: [01]
---

## Task

Generalize `herdr-build.ps1` into `dispatch.ps1`: read a ticket's frontmatter, derive the harness, and open the right pane on the right model.

## Detail

- Input: `-Ticket <path-or-id>`. Read YAML frontmatter: `role`, `model` (`provider:id`), `fallbackModels`, `base`.
- Derive harness via the ticket 01 helper. `anthropic` -> Claude Code (existing `glm.ps1`-style path but real Anthropic), else -> pi.
- Reuse the worktree + pane flow from `herdr-build.ps1` (worktree create, pane split, autostart via env, `Wait-Agent` detection).
- Pass the model as `--provider <p> --model <id>`, never a bare `provider/id` (research: pi silently falls back to default Anthropic on a bad pattern).
- Keep the human gate: dispatch is run by a person per ticket, watches, and surfaces `blocked` as actionable.

## Done when

- `dispatch.ps1 -Ticket 42` opens a pane running the ticket's model on the derived harness, in a fresh worktree off `base`, and submits the brief.
- A builder ticket for `zai:glm-5.3` lands a GLM session on pi (verified by the pane's status/badge), not Anthropic.
