# Running Claude Code on GLM

`glm.ps1` points Claude Code at Z.AI's GLM models instead of Anthropic's.
Nothing leaks between the two: the env is set on that process only, so an
Anthropic session in another terminal is untouched.

## One-time setup

Subscribe to the GLM Coding Plan, create a key at
<https://z.ai/manage-apikey/apikey-list>, then:

```powershell
[Environment]::SetEnvironmentVariable('ZAI_API_KEY','<key>','User')
```

Restart the terminal. The script falls back to reading user scope, so a shell
that predates the set still works.

The key never goes in a file. Do not put it in `settings.json`.

## Use

```powershell
.\glm.ps1                                  # interactive GLM session
.\glm.ps1 -Prompt "implement ticket #42"   # headless, for shell-outs
.\glm.ps1 -WhatIfEnv                       # show what would be set, run nothing
```

Useful switches: `-Model` (default `glm-5.2`), `-PermissionMode` (default
`acceptEdits`, since a headless session cannot prompt you), `-OutputFormat
stream-json` when you want a transcript to debug rather than just a verdict.

### `-Agent`

```powershell
.\glm.ps1 -Agent builder -AllowedTools Bash -Prompt "<brief>"
```

`-Agent <name>` makes `~/.claude/agents/<name>.md` the system prompt of the GLM
session itself. So `builder.md` governs the run without being restated in the
prompt, and the same file works whether the builder runs on Anthropic or GLM.

`--model` still wins over the agent file's own `model:` field, which is why the
script always passes it.

### `-AllowedTools`

`acceptEdits` covers writing files but **not** running a test suite. Without
`-AllowedTools Bash` a headless builder edits code it cannot verify. It will say
so rather than lie about it, but you pay an extra round trip.

Granting `Bash` means the session can run any shell command unattended. That is
only acceptable inside a throwaway worktree, which is why the `glm-builder`
dispatcher carries `isolation: worktree`. Do not grant it from your real tree.

## How the models map

Z.AI maps Anthropic's aliases, so the agent definitions in `~/.claude/agents/`
work unchanged on either vendor and keep their cheap/expensive tiering:

| alias in an agent file | on Anthropic | on GLM  |
|---|---|---|
| `model: haiku`  | Haiku  | GLM-4.7 |
| `model: sonnet` | Sonnet | GLM-5.2 |
| `model: opus`   | Opus   | GLM-5.2 |

## The review leg: `gpt-review.ps1`

```powershell
.\gpt-review.ps1 -Base main -Context "<the ticket or brief>"
```

Runs the change past GPT through the Codex CLI, read-only, and prints the review
on stdout. Switches: `-Cwd`, `-Model` (default `gpt-5.5`), `-Effort` (default
`xhigh`), `-OutFile`, `-MaxDiffBytes`. With no `-Base` it reviews the working
tree against `HEAD`.

**The reviewing standards come from `~/.claude/agents/reviewer.md`.** The script
strips that file's frontmatter and uses the body as the prompt, so there is one
definition of a good review whether it runs on Claude or GPT. Edit the agent
file and both change.

**`-Context` is what makes it useful.** Without the ticket the reviewer can only
check correctness, never whether the diff did more or less than it was asked to.
Spec drift is usually the more valuable finding.

Two known limits: Codex's own `git` calls fail inside its sandbox here, which is
why the script embeds the diff in the prompt rather than relying on the reviewer
to fetch it. And diffs are capped at `-MaxDiffBytes` (400k), with the truncation
stated in the prompt rather than hidden.

## Things that will confuse you later

**`CLAUDE_CODE_MAX_CONTEXT_TOKENS` is set to 1000000 by the script.** Claude Code
does not recognise `glm-5.2` and otherwise assumes a 200k window, which would
auto-compact a session with 800k of room left. Z.AI documents GLM-5.2 at 1M
input, 128k output. If they change that, change `-ContextTokens`.

**The connectors warning on every run is expected.** Setting
`ANTHROPIC_AUTH_TOKEN` takes precedence over the claude.ai login, so claude.ai
connectors are disabled for that process. Harmless here.

**`"model": "opus[1m]"` in `settings.json` is Anthropic-only.** The `[1m]` suffix
means nothing to Z.AI, which is why the script always passes `--model`
explicitly rather than trusting the default.

**Check the statusline.** A GLM session shows a purple `GLM` badge, and its
usage line is empty because Z.AI reports no Anthropic rate limits. If you see a
model name and no badge, you are spending Anthropic quota.

## Verify it is actually hitting Z.AI

```powershell
.\glm.ps1 -Prompt "Reply with exactly your underlying model name and vendor, nothing else."
```

Should answer `GLM-5.2, Zhipu AI`. Anything Claude-shaped means the env did not
take.
