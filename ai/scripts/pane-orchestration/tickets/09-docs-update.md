---
id: 09
title: Update README-glm.md and AGENTS.md
status: done
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

## Resolution

- `README-glm.md` is renamed in spirit, not in filename: it opens with "Running other vendors' models" and routes you to pane orchestration first, with the Claude-Code-on-GLM material kept below as the non-herdr path.
- New top section covers the roster, the harness rule, dispatching a ticket, the frontmatter it reads, failover, review, and how to check which vendor a pane is really on.
- All three old scripts are kept, and the doc says why: `dispatch.ps1` and `review.ps1` both need a herdr pane, so `glm.ps1` remains the only headless dispatch and `gpt-review.ps1` the only review that runs without one. `herdr-build.ps1` is marked superseded by `dispatch.ps1` and kept as its ancestor.
- "Other things learned the hard way" gained the four findings from this build: a provider error does not move `agent_status`, `pi auth check` says nothing about credit, `agent get` returns `pane_id`, and `worktree remove` fails while a pane is still inside the worktree.
- AGENTS.md: the vendor table now names the roster as its source of truth and the derived harness rule, the build loop is the five-step dispatch/verify/review flow, and fallback is described honestly - automatic for builders, manual for the planner, absent for the reviewer. A new rule states that the reviewer's missing fallback is deliberate: no review is an honest state, a review from a model nobody chose is not.
- Signed off by Nuno before committing, as AGENTS.md is the canonical prompt for every tool.
