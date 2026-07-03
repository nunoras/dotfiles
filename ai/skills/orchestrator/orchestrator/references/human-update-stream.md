# Human Update Stream

Use Lavish (`lavis-axi`) as a human-facing progress and notes channel when an actual tool, app connector, MCP surface, or CLI exists in the current environment. Do not invent Lavish commands. If no real surface is available, write the same updates to `.agents/backlog/human-notes.md` and keep working.

Backlog files remain the durable source of truth. Lavish is for fast scanning, review prompts, and human notes.

## Resolve the Channel

1. Prefer explicit user-provided Lavish/lavis-axi instructions.
2. If a Lavish/lavis/lavis-axi tool or app connector is available, use that surface.
3. If only a CLI appears available, inspect its help before using it.
4. If the channel is unavailable, unknown, or failing, use `.agents/backlog/human-notes.md` as the fallback and mention the fallback in `CURRENT_STATE.md`.
5. Never block implementation solely because Lavish is unavailable.

## Outbound Updates

Post or record concise updates at these moments:

- Startup or resume: active spec, active phase, current gate, next action, blockers.
- Before launching an implementation/review/fix agent: role, mission, expected handoff file, main files in scope.
- After an agent finishes: result, changed files, validations, blockers, next decision.
- Before a phase gate: validation status, review result, open risks, what a human should inspect.
- When blocked: the decision needed, options if obvious, impact, and the file/log to read.

Use this shape:

```md
[Phase XX / role] Short status
- Now:
- Evidence:
- Needs human:
- Next:
```

Keep each update short enough to scan quickly. Prefer paths to full pasted diffs. Do not post private chain-of-thought, secrets, environment variables, or long logs.

## Inbound Notes

Check for human notes:

- at startup or resume
- before closing a phase gate

Do not re-read `human-notes.md` before every agent launch.
If the user adds a note mid-phase, they will say so explicitly - pick it up at the next gate check.

Copy or summarize each actionable note into `.agents/backlog/human-notes.md`:

```md
## YYYY-MM-DD HH:MM Source/Author
- Source id/link:
- Note:
- Interpretation:
- Action:
- Status: open | applied | declined | needs-clarification
```

Treat human notes as high-priority instructions, but reconcile them with the active spec and backlog. If a note conflicts with the spec, record the decision in `decisions.md`. If a note is ambiguous or would broaden scope materially, ask the user or mark it `needs-clarification` before launching broad changes.

Include relevant open or newly applied note entries in subagent prompts by citing `.agents/backlog/human-notes.md`.

## Noise Control

- Batch tiny updates instead of posting every small command.
- Prefer one clear question over a broad status dump when human input is needed.
- Do not duplicate the full backlog into Lavish.
- Keep unresolved human notes visible in `CURRENT_STATE.md` until applied, declined, or clarified.