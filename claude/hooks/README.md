# Claude Code hooks

Hooks are wired in [`../settings.json`](../settings.json). Hooks that other
tools drop into `~/.claude/hooks/` (herdr's `herdr-agent-state.ps1`, plugin
self-healers and the like) are left untouched by the installers.

Hook commands run through Git Bash on Windows and `sh` on Linux, so they are
written as `node "$HOME/..."`. One `settings.json` works on both platforms and on
machines with different usernames.

## skill sync (`ai/scripts/skills-sync.mjs --quiet`)

A `SessionStart` hook that relinks shared and plugin skills into
`~/.agents/skills` for pi and Codex, so a plugin update or a new skill reaches
them on the next Claude session. `--quiet` keeps stdout empty, so it adds nothing
to the session context. See the skills section of the top-level README.

## herdr

herdr installs `herdr-agent-state.ps1` itself. The `settings.json` entry is
guarded with `[ -f ... ]`, so it is a no-op on machines without herdr, including
Linux.
