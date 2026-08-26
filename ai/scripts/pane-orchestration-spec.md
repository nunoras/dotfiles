# Pane orchestration - spec

Status: draft, ready for `/to-tickets`.
Supersedes: the workflow half of the setup (`@quintinshaw/pi-dynamic-workflows`, aka `/workflows`).
Sibling doc: `README-glm.md` (the vendor-split and glm/gpt scripts this builds on).

## Destination

A home-grown, herdr-based dispatch layer that replaces `/workflows`.

The planner assigns a model to each unit of work; a human dispatches that work into a herdr pane on the right harness; builders and reviewers run in their own panes, with a reviewer split to the right of the builder it reviews.
Quota exhaustion mid-work falls back to a paid model instead of dying.

Done means: `/workflows` is gone, a plan's tickets carry model assignments, and one command per ticket opens the correct pane.

## Why not `/workflows`

`pi-dynamic-workflows` fans work out to headless subagents inside one pi process.
It gives no panes, no per-model harness routing, and no human gate before spend.
The setup already has a better substrate for visible, steerable, multi-vendor work: herdr, driven today by `herdr-build.ps1`.
The plan generalizes that script rather than the workflow engine.

## Harness rule

One rule decides the harness from the model's `provider` in `models-store.json`:

- provider `anthropic` -> Claude Code harness.
- every other provider (`openai-codex`, `zai`, `openrouter`, `kimi-coding`) -> pi harness.

This inverts today's setup on purpose.
GLM runs on pi now, not on Claude Code via `glm.ps1`.
GPT review runs on pi now, not on the Codex CLI via `gpt-review.ps1`.
The dispatch script derives the harness; nothing hard-codes it per role.

## Model roster

Single source of truth, read by `to-tickets` (to stamp frontmatter) and available to a human reading a plan.
Subscription provider first, OpenRouter pay-per-token as the quota fallback.

| Role | Harness | Primary | Fallback |
|---|---|---|---|
| planner | Claude Code | `claude-fable-5` (Anthropic Max) | `claude-opus-5`, then manual restart on pi |
| builder A | pi | `glm-5.3` (zai coding plan) | `z-ai/glm-5.3` (OpenRouter) |
| builder B | pi | `stealth/ox-alpha` (OpenRouter) | `z-ai/glm-5.3` (OpenRouter) |
| reviewer | pi | `gpt-5.5` (openai-codex subscription) | `openai/gpt-5.5` (OpenRouter) |

The planner picks builder A or B per ticket.
The roster lives in one file (proposed: `~/.claude/roster.json`); the harness column is derived, not stored.

## Fallback mechanism

Research correction: pi has NO generic mid-session auto-fallback for a full pane session.
`allowedFallbackModels` in the model catalog is Anthropic-only - pi consumes it solely in the `anthropic-messages` handler, passing it as `params.fallbacks` to Anthropic's own server-side fallback.
For `openai-completions` and `openai-codex` providers (zai, openrouter, openai-codex) there is nothing equivalent.
The subagents extension's `fallbackModels` is a pre-flight retry (before any tool runs) and lives inside that tool, not in an interactive pane session.

So fallback is script-driven for every role:

- The watcher (generalized `Wait-Agent`) detects a session that died on a quota, rate-limit, or auth failure.
- It relaunches the same ticket on the ticket's `fallbackModels` entry, in the same worktree and pane.
- The planner is HITL, so its fallback is a manual relaunch on a non-Anthropic pi model; builders and reviewers get the automated relaunch.

This is more code than "pi does it for us," but it is the only mechanism that actually exists across the providers in the roster.

## Ticket format

Each ticket is a `.md` file: YAML frontmatter plus a brief body.

```markdown
---
role: builder            # builder | reviewer
model: glm-5.3           # from the roster
fallbackModels: z-ai/glm-5.3
base: main               # branch to worktree from
---

## Brief

<what to build, the seams, the verify command>
```

`role` and `model` are required.
The dispatch script reads frontmatter, derives the harness from the model's provider, and passes `model` + `fallbackModels` to the pi/Claude Code session.

## Planning skills

Local overrides of the Matt Pocock plugin skills, so the roster travels with the pipeline.

- `to-tickets` owns mechanical assignment: it stamps each ticket's frontmatter from the roster.
- `wayfinder` and `to-spec` are roster-aware: they note which role a chunk of work needs, not the exact model.
- `implement` and `code-review` are unchanged except where they reference dispatch.

## Flows

### Build

1. Planner produces tickets with model frontmatter.
2. Human runs `dispatch.ps1 -Ticket N`.
3. Script reads the frontmatter, derives the harness, creates a worktree + pane (generalized `herdr-build.ps1`), and starts the session on the assigned model with fallbacks armed.
4. Human watches; `blocked` is recoverable in the pane.

### Review

1. Builder finishes.
2. Human runs the build/tests and records a verdict.
3. Human runs `review.ps1 -Ticket N -Verdict '<cmd> -> PASS'`.
4. Script splits the builder's pane to the right, starts pi + `gpt-5.5` read-only in the same worktree, and feeds it the committed diff, the ticket brief, and the verdict.
5. The review is relayed verbatim. Blocking findings are the human's call.

Builder on the left, reviewer on the right.
Three vendors, none reviewing its own code: planner is Anthropic, builders are GLM/ox, reviewer is GPT.

## Uninstall scope

- Remove `npm:@quintinshaw/pi-dynamic-workflows` from `~/.pi/agent/settings.json` packages.
- Remove the `workflow-liveness.ts` extension (it polls the workflow run store and has no purpose once the engine is gone).
- Remove workflow references from the orchestrator skill and AGENTS.md.
- The `workflow-authoring` / `workflow-patterns` skills vanish with the package.

## Research findings (resolved before build)

1. Model selection: `pi --provider zai --model glm-5.3` routes correctly to GLM. WARNING: `--model zai/glm-5.3` matches no id and pi SILENTLY falls back to the default Anthropic model instead of erroring. The dispatch script must pass `--provider <p> --model <id>` from the roster and must not trust a bare `provider/id` string. Confirmed live: the wrong form answered "Claude, Anthropic"; the right form answered "GLM, Z.ai."
2. Provider auth from this machine: `anthropic` (oauth), `zai` (api_key), `openrouter` (api_key) all report ready. `openai-codex` reports `not_ready: credentials_not_configured`. So the reviewer's subscription primary `gpt-5.5` (openai-codex) cannot run on pi until that provider is authenticated. Its OpenRouter fallback `openai/gpt-5.5` works today. A setup task must authenticate openai-codex in pi, or the reviewer defaults to the OpenRouter model.
3. Panes: `herdr pane split --direction right --env KEY=VALUE --ratio <f> --no-focus` all exist. Reviewer-right and env passthrough are supported. Autostart must be extended past `pi`/`claude`/`glm` to carry an arbitrary provider+model+fallback set.
4. The workflow package actively harms headless pi: a `[workflow-delivery]` shim fail-closed the `-p` send until `--no-extensions` was passed. Extra reason to uninstall it.
5. Windows landmines from `README-glm.md` still apply: PowerShell 5.1 profile compatibility, `claude` vs `claude.cmd`, `pi` vs the extensionless shim.

## Proposed tickets

See `pane-orchestration/tickets/` for the specified set. Summary:

- Roster config file + harness-derivation helper (harness from provider).
- Authenticate `openai-codex` in pi, or fix the reviewer default to the OpenRouter model.
- Generalize `herdr-build.ps1` into `dispatch.ps1` (frontmatter-driven, `--provider`+`--model`, any harness).
- Extend `herdr-autostart.ps1` to carry an arbitrary provider+model+fallback set.
- Script-driven fallback watcher: relaunch a dead session on its `fallbackModels` entry.
- `review.ps1`: split-right, read-only pi reviewer, verbatim relay.
- Local `to-tickets` override that stamps roster frontmatter.
- Uninstall `/workflows` (package + `workflow-liveness.ts`) and scrub references.
- Update `README-glm.md` / AGENTS.md to describe the new split.
