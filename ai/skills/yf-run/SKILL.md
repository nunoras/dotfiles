---
name: yf-run
description: Use when running, executing, or building an existing yf-plan implementation plan (specs/*.html) phase by phase, when each phase should run in a fresh agent checked by an independent reviewer, or when resuming a paused plan run. Triggers - "run the plan", "build the plan", "implement phase N", "kick off phase 1", phase relay, fresh context per phase.
---

# YF Run

Run a yf-plan (`specs/<name>.html`) as a phase relay.
One phase at a time, each phase implemented in a fresh agent and checked by an independent reviewer, with a copy-pasteable kick-off prompt (the baton) printed at every phase boundary.
State lives in the plan itself - its status markers and metadata header - not in a separate backlog.

## When to use

- You have a yf-plan and want to execute it.
- You want each phase to start with fresh context and be independently reviewed.
- You are resuming a plan that was paused mid-run.

Not this skill: authoring the plan (use `yf-plan`); heavyweight resumable multi-stream orchestration with a durable backlog (use `orchestrator`).

## Core rules

- **Thin coordinator.** Read only the plan's phase list plus the one phase you are running. Never read the whole repo. Sub-agent tool output must stay out of your context - that clean context per phase is the whole point.
- **One phase at a time.** Do not start phase N+1 until phase N passes review and its Testing Strategy is green.
- **Fresh implementer per phase.** Spawn a new `Agent` with `model: opus`, scoped to ONE phase. opus is always the implementer.
- **Independent reviewer.** Every phase is reviewed by Codex (`gpt-5.5`), never a Claude agent or fork - a Claude reviewing Claude output is not independent. See `references/agent-prompts.md` for the `codex exec` invocation.
- **Fresh `Agent` calls only, never `subagent_type: "fork"`.** A fork ignores `model:` and inherits your context, defeating both the model choice and the fresh-context goal.
- **The plan is the state store.** The implementer flips its phase's markers in the plan HTML: `[]` idle, `[wip]` in progress, `[x]` done, `[f]` failed. Do not track state anywhere else.
- **Feature branch, commit per phase.** Never commit to `main` - if you are on `main`, create a feature branch before the first phase. When a phase passes review, commit its changes locally (code + the plan's marker updates). Do not push; pushing and the PR are `yf-ship`'s job.

## Modes

- **Gated (default).** After each phase passes review, print the next phase's kick-off prompt and STOP for the user's OK.
- **All-phases.** If the user asks to run or implement all phases (or passes `--all`), auto-chain - skip the pause and start the next phase immediately. Still review every phase; only a review failure or an `[f]` task stops the chain.

## The Loop

1. **Locate the plan.** Resolve the `.html` path from the argument; if none is given, infer the most recent plan in `specs/` and confirm before running.
2. **Find the phase.** Read the plan's phase list and status markers. The active phase is the first one not `[x]`. Read only that phase's section: tasks, Relevant Files, Testing Strategy.
3. **Spawn the implementer** (fresh `Agent`, opus). Mission is the phase's kick-off prompt (the baton). It implements this phase only, flips markers, runs the Testing Strategy until green, and reports files changed, task statuses, and any `[f]`. It stops after the phase.
4. **Spawn the reviewer** (Codex `gpt-5.5`, `xhigh`) on the phase diff versus the phase section. Capture findings to `specs/<name>/run/phase-XX-review.md`.
5. **Triage.** Blocking findings - spawn a fix agent (fresh `Agent`, opus) and re-review. Non-blocking - record them in the report.
6. **Close the phase.** Mark it `[x]`, or `[f]` if it could not be made to pass.
7. **Commit the phase.** Stage everything (`git add -A`) and commit locally with a message like `<type>(<plan-slug>): Phase <N> - <phase name>`. The commit captures the code plus the plan's marker updates. No push, no auto-added co-author.
8. **Gate.** Gated mode: print the next phase's kick-off prompt plus a one-line status, then stop. All-phases mode: go to step 2 for the next phase.
9. **Finish.** When the last phase is `[x]`, the plan is built - hand off to `yf-ship` to run the global Validation Commands, open the PR, and append the ship Amendment + metadata. Do not push or open a PR from here.

## Model selection

| Role | Runner | Model | Effort |
|------|--------|-------|--------|
| Implementer | Agent | opus | high |
| Reviewer | Codex | gpt-5.5 | xhigh |
| Fix (blocking) | Agent | opus | high |
| Validation | Agent | haiku | low |

opus implements, Codex reviews - non-negotiable. Bump the implementer to `xhigh` only for an unusually gnarly phase.

## The baton

The kick-off prompt is the interface between phases - the same text whether you auto-spawn the next agent or paste it into a brand-new session yourself.
yf-plan pre-renders the Phase 1 baton in the plan's Run / Kick-off section; generate later phases' batons the same way from the plan.
Full templates (baton, implementer, reviewer, fix, validation) and the `codex exec` invocation live in `references/agent-prompts.md` - read it once at startup, do not re-read it during the loop.

## References

- `references/agent-prompts.md`: kick-off baton plus implementation, review (Codex), fix, and validation prompt templates.
