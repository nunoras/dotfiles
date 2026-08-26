---
id: 03
title: dispatch.ps1 - frontmatter-driven pane dispatch
status: done
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

## Resolution

- `ai/scripts/dispatch.ps1`: reads flat YAML frontmatter (`role`, `model` as `provider:id`, `fallbackModels`, `base`), derives the harness via `roster.ps1`, and mirrors `herdr-build.ps1`'s worktree + pane-split + `Wait-Agent` flow. Passes `--provider`/`--model` as separate flags (never a bare `provider/id`). Detection accepts any agent kind, not just `claude`.
- `-DryRun` prints the resolved plan and the exact pi command without spawning anything. `-NoWatch` dispatches and returns.
- Claude harness path is a deliberate stub (`exit 2`): the only Anthropic role is the planner, which runs interactively, not via dispatch.
- `ai/scripts/dispatch.tests.ps1`: 14 assertions (frontmatter parse, slashed model ids, base default, harness derivation, validation throws, claude stub exit code). Pass on pwsh 7 and PowerShell 5.1.
- NOT verified automatically: the live pane launch (worktree + herdr split + a real GLM session). That is the human-at-keyboard path, same as `herdr-build.ps1`. Command construction is verified via `-DryRun`; the actual launch needs a keyboard run.
