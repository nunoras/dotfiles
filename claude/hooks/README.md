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

## prose guard (`ai/scripts/prose-guard.mjs`)

A `PreToolUse` hook on the Bash and PowerShell tools.
It denies `gh pr|issue create|edit|comment|review`, `git commit`, `agni project propose|answer` and `agni worker submit|ask` when the command, or a file it passes with `--body-file`, `-F`, `--file` or `--description`, holds an emoji or an em dash.
The deny reason lists each line, so the agent rewrites it and runs the command again.
Any other command, or input it cannot parse, passes untouched.

## verify gate (`ai/scripts/verify-gate.mjs`)

A `Stop` hook that will not let a turn end while a repo's verify command fails.
It is off until you opt a repo in from inside it:

```
node ~/.claude/scripts/verify-gate.mjs --set "just check"
node ~/.claude/scripts/verify-gate.mjs --unset
node ~/.claude/scripts/verify-gate.mjs --list
```

Commands live in `~/.claude/verify-gate.json`, keyed by the repo's real top-level path, so a cloned repo cannot supply its own command and agni worktrees are not gated.
The command runs only when the working tree differs from the last tree that passed.
After three blocked stops in one session it lets the turn end and tells the agent to report `BLOCKED`.
