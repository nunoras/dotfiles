# Claude Code hooks

## skill-improver auto-loop (`skill-improver-stop.mjs`)

A `Stop` hook (wired in `../settings.json`) that powers the [skill-improver](../../ai/skills/skill-improver/) improvement loop.

After a turn, it scans the session transcript for `Skill` invocations. When a **new** skill on the allowlist has been used since its last check, it blocks the stop once and makes the agent run a silent skill-improver self-review against the conversation. Plain turns, and turns that only used non-allowlisted skills, stop instantly.

### Tuning the allowlist

Edit `skill-improver-skills.json` - the `skills` array lists the skills worth reviewing (the ones you actively iterate on). This keeps the loop from burning a turn on third-party utilities.

- **Empty array** -> review nothing (pauses the loop without removing it).
- **Delete the file** -> review every skill.
- **`SKILL_IMPROVER_SKILLS="a,b,c"`** env var overrides the file.
- **`SKILL_IMPROVER_LOOP=0`** env var disables the hook entirely.

`skill-improver` itself is always excluded (no self-review recursion).

### Cost

The script is free (a shell command, no model call). The cost is one extra agent turn each time an allowlisted skill is used - mostly prompt-cache hits, output usually a single line. Negligible unless you lean hard on the allowlisted skills in one session.

### Safety

Honors `stop_hook_active` (no recursion), advances its per-session marker before blocking, and fails open on any error - a hook fault can never wedge a session.
