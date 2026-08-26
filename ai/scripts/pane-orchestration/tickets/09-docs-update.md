---
id: 09
title: Update README-glm.md and AGENTS.md
status: open
blocked_by: [03, 06, 08]
---

## Task

Document the new split so the setup docs match reality.

## Detail

- `README-glm.md`: the vendor split changed. GLM now runs on pi (not Claude Code via `glm.ps1`), GPT review runs on pi (not Codex via `gpt-review.ps1`). Describe `dispatch.ps1` / `review.ps1` and the harness rule. Keep or retire `glm.ps1` / `gpt-review.ps1` explicitly - say which.
- AGENTS.md: update the "which vendor does which job" table and the build-loop section to the pane-orchestration flow (planner fable5 on CC, builders glm-5.3/ox on pi, reviewer gpt-5.5 on pi, human dispatch per ticket, reviewer split-right).
- Note the manual planner fallback and the script-driven builder/reviewer fallback.
- Follow the unslop rules; one sentence per line in the Markdown.

## Done when

- A reader following the docs can dispatch a ticket and run a review without reading the scripts.
- No doc still claims GLM runs on Claude Code or that review runs on Codex.
