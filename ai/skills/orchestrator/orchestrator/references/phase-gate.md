# Phase Gate

Use this gate before moving from one phase to the next. A phase is not complete because an implementation agent says it is complete; it is complete when this gate passes.

## Close-Phase Checklist

- [ ] Active phase checklist items are done or explicitly deferred with reasons.
- [ ] Implementation agent handoff exists under `.agents/backlog/agents/`.
- [ ] Independent reviewer agent handoff exists under `.agents/backlog/agents/`.
- [ ] Blocking review findings are fixed.
- [ ] Non-blocking findings are either fixed or copied to `risks.md` / carryover.
- [ ] Relevant tests, builds, lint, type checks, or manual checks passed.
- [ ] Any blocked validation has a concrete reason and next step.
- [ ] `INDEX.md`, `CURRENT_STATE.md`, phase file, `decisions.md`, and `risks.md` are current.
- [ ] A handoff for the next phase exists under `.agents/backlog/handoffs/`.

## No-Mistakes-Style Gate

Use no-mistakes-style validation as a fixed quality sequence at phase boundaries, pre-commit, or pre-PR.

Recommended sequence:

1. Confirm intent: restate what changed and why.
2. Inspect repository state: `git status --short`.
3. Inspect diff: focus on files changed in the phase.
4. Review against the spec: confirm phase checklist coverage.
5. Run tests/build/lint/type checks.
6. Update docs/backlog.
7. Re-check status and unresolved risks.
8. Commit/push/PR only when explicitly requested or when the orchestration plan requires it.

Do not run the full gate after every tiny edit unless the work is high-risk or about to be handed off externally.

## Reviewer Pass Criteria

Reviewer result meanings:

- `PASS`: no blocking findings and no meaningful carryover.
- `PASS WITH RISKS`: no blocking findings, but carryover must be tracked.
- `FAIL`: blocking findings remain; do not close the phase.

Blocking finding examples:

- Spec-required behavior missing.
- Build, type check, migration, or core tests fail.
- Data model or API contract is incompatible with later phases.
- Auth or storage access can leak protected resources.
- UI flow is unusable for the target workflow.
- Design-system rules are materially violated.
- Audio/review/timestamp behavior cannot be verified for an audio-related phase.

Non-blocking finding examples:

- Minor polish that does not block the next phase.
- Additional test coverage that is valuable but not required to trust the current behavior.
- Small refactor opportunity with no current behavioral risk.

## Mix Notes Global Gate Notes

For `specs/mix-notes-feedback-platform.html`, preserve these constraints across phases:

- Backend: Python, FastAPI, SQLAlchemy 2.0, Alembic.
- Frontend: Next.js App Router, TypeScript, Tailwind v4, shadcn/ui.
- Auth: Clerk for engineers, share tokens for clients.
- Storage: Cloudflare R2 for version files, references, and attachments.
- Audio: wavesurfer.js for main waveform playback.
- Icons: Phosphor only; avoid Lucide in app UI.
- Motion: `motion/react` for component transitions, GSAP for isolated complex timeline work.
- Reduced motion: animated UI must respect `prefers-reduced-motion`.
- Design: permanent dark UI, amber accent, Geist typography.

When earlier spec sections conflict with later stack decisions or amendments, follow the later stack decisions and record the conflict in `decisions.md`.
