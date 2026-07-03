---
name: orchestrator
description: Coordinate long-running, phase-gated software implementation with multiple AI coding agents while keeping chat context low and publishing human-readable Lavish/lavis-axi updates when available. Use when Codex must execute a local implementation spec or plan through subagents, maintain `.agents/backlog` state, resume interrupted orchestrations, run independent reviewer agents, apply no-mistakes-style quality gates, surface progress for a human, ingest human notes, or hand work between Claude Code, Codex CLI, and other agent runners.
---

# Orchestrator

Use this skill to run a durable multi-agent implementation loop from a local spec. The orchestrator keeps only high-level state in chat, delegates scoped work to implementation and review agents, and stores durable context in `.agents/backlog/`.

## Core Rules

- The tasks-axi backlog (`.agents/backlog/backlog.md`, driven by `npx -y tasks-axi`) is the canonical store for phase/task state, gate progress, and dependencies. Mutate it only through tasks-axi; never hand-rewrite task or gate markdown. See `## Task Store (tasks-axi)`.
- Treat `.agents/backlog/CURRENT_STATE.md` as the narrative resume anchor and `INDEX.md` as the routing index. Keep both consistent with the tasks-axi backlog; they hold prose, not task state.
- Keep chat context low: read the spec selectively, send subagents narrow prompts, and write durable detail to backlog markdown.
- Run one implementation phase at a time. Do not start the next phase until the current phase passes review and validation.
- Use independent reviewers after implementation phases. Reviewers must not trust the implementer's handoff.
- **All reviews must use Codex (`gpt-5.5`), never a Claude fork or Claude agent.** Standard phases use `xhigh` effort; gate reviews use `xhigh`. See `references/agent-prompt-templates.md` for the exact invocation. This is non-negotiable — a Claude agent reviewing Claude agent output is not independent.
- Keep implementation agents and reviewer agents separate. Let a fix agent address reviewer findings when needed.
- Skip `[archived]` agent log entries in `INDEX.md` during the normal loop. Read them only when explicitly auditing a closed phase.
- Record decisions, risks, blocked tasks, validation results, and handoffs in `.agents/backlog`.
- Use Lavish (`lavis-axi`) as a human-facing progress and notes stream when an actual tool, app, or CLI surface is available. Keep `.agents/backlog` as the source of truth.
- When the spec conflicts with itself, prefer the latest amendment and explicit stack decisions. Record the conflict in `decisions.md`.
- Never ask subagents to read the whole repo unless the task genuinely requires it.

## Task Store (tasks-axi)

The canonical store for phase/task state, gate progress, and dependencies is the tasks-axi backlog at `.agents/backlog/backlog.md`, driven by `npx -y tasks-axi`. It replaces hand-rewritten task and gate markdown: mutations are one-line commands with compact confirmations, they are idempotent, and writes are lock-safe - which matters when implementation, review, fix, and validation agents (or a parallel `/orchestrator-fork`) touch the backlog.

Division of responsibility:
- tasks-axi owns the phase/task queue, each task's state (queued / in flight / done), gate progress (in the task body), and `blocked-by` dependencies.
- Prose files own narrative and audit: `CURRENT_STATE.md` (resume anchor), `decisions.md`, `risks.md`, `human-notes.md`, the phase `detail`/`spec-slice` files, agent logs, and handoffs.
- `INDEX.md` is a routing index only (pointers to logs/handoffs/detail with read-triggers). It no longer holds task or gate state.

Rules:
- The orchestrator is the only writer of task-state transitions. Subagents write their prose logs and `CURRENT_STATE.md`; they do not call tasks-axi.
- Never hand-edit task lines, sections, or `- [x]` markers in `backlog.md`. Use tasks-axi so the round-trip guarantee and locks hold.
- Model each phase as one task (`kind: ship`). Capture the gate checklist in the task body via `tasks-axi update <id> --append`. Encode phase ordering with `blocked-by` (phase N+1 blocked-by phase N).

Command vocabulary:
- `npx -y tasks-axi` - dashboard. `npx -y tasks-axi ready` - unblocked work the orchestrator may launch now.
- `npx -y tasks-axi show <id> --full` - one task with full body (gate checklist).
- `npx -y tasks-axi add <id> "title" --kind ship --priority N` / `start <id>` / `done <id>` / `reopen <id>`.
- `npx -y tasks-axi block <id> --by <other-id>` - record a dependency.
- `npx -y tasks-axi update <id> --append "note"` - append gate progress or notes without regenerating the file.

Config is `.tasks.toml` at the repo root (`path = ".agents/backlog/backlog.md"`). Run `npx -y tasks-axi setup hooks` once so each cold session and fork gets the backlog injected as ambient context.

## Startup

1. Load task/phase/gate state with `npx -y tasks-axi` and `npx -y tasks-axi ready`. Read `.agents/backlog/CURRENT_STATE.md` for narrative status and `INDEX.md` for routing, if they exist.
2. If the tasks-axi backlog (`backlog.md`) or the narrative files do not exist or are stale, read `references/backlog-schema.md` and bootstrap or repair them. Seed `backlog.md` through tasks-axi, not by hand.
3. Inspect `git status --short`.
4. Read `references/agent-prompt-templates.md`, `references/human-update-stream.md`, and `references/phase-gate.md` now, at startup. Do not re-read them again during the loop.
5. Resolve the Lavish/lavis-axi update channel or initialize the `.agents/backlog/human-notes.md` fallback.
6. Identify the active phase, ready work, and blockers from `tasks-axi`; the active spec from `CURRENT_STATE.md`; and the last completed agent log, unresolved review findings, blocked validations, and unresolved human notes from the prose files.
7. Read only the current spec phase plus global constraints that affect it.
8. If a previous session ended mid-phase, resume from the smallest unfinished task (`npx -y tasks-axi ready`).

For `specs/mix-notes-feedback-platform.html`, treat the later "Stack Decisions" and "Amendments" sections as authoritative when earlier sections conflict.

## Orchestration Loop

For each phase:

1. Scope the phase into a short phase brief. Extract relevant spec sections into `phases/phase-XX-spec-slice.md` if not already present.
2. Publish or record a concise phase-start checkpoint, and mark the phase started with `npx -y tasks-axi start <phase-id>`.
3. Classify the implementation task (see Model Selection). Pick model and effort. Launch the implementation agent with a narrow mission, required handoff format, and the chosen model/effort. Pass the spec slice path and phase detail file path in the briefing.
4. Require the implementation agent to update its agent log and `CURRENT_STATE.md` before reporting done. The orchestrator, not the subagent, records task-state transitions in tasks-axi.
5. After the agent finishes, read only `CURRENT_STATE.md` to confirm it was updated correctly. Do not re-read the full handoff file unless CURRENT_STATE.md indicates an inconsistency.
6. Publish or record the implementation result for human review.
7. Launch an independent Codex reviewer (gpt-5.5 high for standard, xhigh for gate). Pass the same spec slice and phase detail file in the briefing. See `references/agent-prompt-templates.md` for Codex invocation.
8. Classify reviewer findings as blocking or non-blocking.
9. Classify each fix (see Model Selection). Launch fix agents with the appropriate model/effort.
10. Launch a validation agent to run build/typecheck/test commands. Read only the pass/fail summary it writes to CURRENT_STATE.md - do not run validation commands directly in the orchestrator context.
11. Update `CURRENT_STATE.md`, `decisions.md`, `risks.md`, and a phase handoff (prose). Record gate progress on the phase task with `npx -y tasks-axi update <phase-id> --append`.
12. Update `.lavish/progress.html` to reflect the newly closed phase. Mark it Complete, update stats (phases done, last gate result, open risks count), and remove any "In Progress" state for it.
13. Sync inbound human notes. When the gate in `references/phase-gate.md` passes, close the phase with `npx -y tasks-axi done <phase-id>`; `npx -y tasks-axi ready` then surfaces the next unblocked phase. Move on only then.

All three reference files are read once at startup (see Startup step 4). Do not re-read them during the loop.

## Session Close

Before ending a session (user signals done, context limit approaching, or natural stopping point):

1. Rewrite `CURRENT_STATE.md` from scratch to reflect actual current state. Remove stale notes, completed tasks from "Next Action", and any phase-specific context that no longer applies.
2. Verify `.lavish/progress.html` matches the true gate status of every phase.
3. Confirm `risks.md` marks resolved items as resolved and still-open items as open.
4. Record any user instructions given mid-session that should persist (model choices, workflow preferences, standing instructions) into `CURRENT_STATE.md` under "Orchestration Notes for Next Session".
5. Reconcile the tasks-axi backlog: confirm every closed phase is `done`, the active phase is `in flight`, and `npx -y tasks-axi ready` matches the "Next Action" in `CURRENT_STATE.md`.

The next session starts cold. CURRENT_STATE.md is the only context it has beyond the backlog files — make it accurate.

## Human Visibility

- Treat Lavish as a fast human-facing status surface, not durable project memory.
- Post short updates at startup, before and after each implementation/review/fix agent, when blocked, and when a phase gate is ready.
- Check for new human notes at startup and before closing a phase gate. Do not re-read `human-notes.md` before every agent launch - the user will signal mid-phase notes explicitly.
- Paste relevant open human-note entries directly into subagent prompts rather than telling the agent to read the file.
- If Lavish/lavis-axi is unavailable or fails, continue with `.agents/backlog/human-notes.md` and record the fallback in `CURRENT_STATE.md`.

## Agent Boundaries

Implementation agents must:

- Work only on their assigned phase or task.
- Read the spec slice and phase detail file provided in the briefing. Do not read INDEX.md.
- Update or create an agent log under `.agents/backlog/agents/`.
- Update `CURRENT_STATE.md` and the phase detail file before reporting done. Do not edit the tasks-axi backlog (`backlog.md`); the orchestrator records task and gate state.
- Report files changed, checklist status, commands run, decisions, and risks.
- Include a "Suggested Next Agent Prompt" as a hint for the orchestrator, not a directive.
- Stop after the assigned mission.

Reviewer agents must:

- Read the spec slice, phase detail file, implementation log, changed files, and relevant tests. Do not read INDEX.md.
- Review as an independent engineer looking for bugs, missing tests, spec drift, UX regressions, design-system drift, and integration issues.
- Prefer findings with file and line references.
- Write a review log under `.agents/backlog/agents/`.
- Avoid implementing fixes unless explicitly asked.

## Model Selection

Classify each task before launching. Pick the lowest tier that can reliably handle it. Opus is the most expensive model by a wide margin and `xhigh` is a further multiplier on top - default to Sonnet and escalate deliberately, not the other way around.

| Tier | Runner | Model | Effort | When |
|------|--------|-------|--------|------|
| Trivial | Agent | haiku | low | Config, copy, rename, single-line fix |
| Simple | Agent | sonnet | medium | Single-file change, style fix, small tweak |
| Standard | Agent | sonnet | high | Multi-file feature, API endpoint, component with state |
| Complex | Agent | opus | high | Cross-cutting feature, data model, auth/storage work |
| Critical | Agent | opus | xhigh | Full phase implementation, complex integration |
| Validation | Agent | haiku | low | Always - just runs commands and writes a result |
| Fix - non-blocking | Agent | haiku | medium | Polish, copy, visual cleanup |
| Fix - blocking | Agent | opus | high | Correctness bug, spec drift, breaking test |
| Review - standard | Codex | gpt-5.5 | xhigh | Independent phase review |
| Review - gate | Codex | gpt-5.5 | xhigh | Close-phase gate or security audit |

Rules:
- Reserve `opus` for Complex, Critical, blocking fixes, and gate reviews. Everything else stays on haiku or sonnet.
- Reserve `xhigh` for Critical work and gate reviews. Most work does not need it.
- Never use haiku or sonnet for a gate review - an independent reviewer should always be stronger than the implementer.
- Classify in one sentence before launching. If uncertain between two tiers, start one tier *down* and escalate only if the agent fails or reports the task was underpowered. Do not pre-emptively round up to Opus.
- **Spawn every tiered agent as a fresh `Agent` call with an explicit `model:` set - never as `subagent_type: "fork"`. Forks ignore the `model` override and silently inherit the coordinator's (expensive) model, defeating this whole table.** Only the orchestrator coordinator itself may run as a fork (see `/orchestrator-fork`), and that coordinator should be launched on a cheap model.
- See `references/agent-prompt-templates.md` for Claude Agent and Codex CLI invocation patterns.

## Validation

Delegate all automated validation to a validation agent (see `references/agent-prompt-templates.md`).
Do not run build/typecheck/test commands directly in the orchestrator context - raw compiler output in the orchestrator's context window is pure waste.
Read only the pass/fail summary the validation agent writes to `CURRENT_STATE.md`.

For this project, the validation agent should run:

- `pnpm --filter web typecheck`
- `pnpm --filter web build`
- `pytest` from the API app (if tooling is available)
- formatting/linting where configured

Manual or browser verification (UI, audio, review-mode, reduced-motion) cannot be delegated and should be flagged as a human gate item.

Use no-mistakes-style review as a phase or pre-PR gate, not after every small task.

## References

Read all of these once at startup. Do not re-read them during the loop.

- `references/backlog-schema.md`: create and maintain `.agents/backlog`, including the tasks-axi backlog (`backlog.md`) and the prose files.
- `references/agent-prompt-templates.md`: implementation, review, fix, and resume prompts.
- `references/human-update-stream.md`: Lavish/lavis-axi progress updates and human-note ingestion.
- `references/phase-gate.md`: close-phase criteria and no-mistakes-style gate.