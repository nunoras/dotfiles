# Running other vendors' models

Two routes, and they answer different questions.

**Pane orchestration** is the current one.
A ticket carries the model that should build it, `dispatch.ps1` opens it in a herdr pane on the right harness, and `review.ps1` opens a reviewer beside it.
Builders and reviewers run on **pi**, on their own provider and model.
Jump to [Pane orchestration](#pane-orchestration-dispatchps1--reviewps1).

**The scripts below it** are the older, non-herdr route: `glm.ps1` runs Claude Code against GLM, `gpt-review.ps1` reviews through the Codex CLI.
They are kept, not retired, because both work with no herdr pane at all - `glm.ps1` is the only headless GLM dispatch, and `gpt-review.ps1` is the only review that runs outside a pane.
`herdr-build.ps1` is superseded by `dispatch.ps1` and stays only as the thing `dispatch.ps1` was generalized from.

## Pane orchestration: `dispatch.ps1` + `review.ps1`

Spec and tickets: `pane-orchestration-spec.md`, `pane-orchestration/tickets/`.

### The roster

`ai/roster.json` maps a role to its model, written `provider:id`.

| role | primary | fallback |
|---|---|---|
| planner | `anthropic:claude-fable-5` | `anthropic:claude-opus-5`, then a manual restart on pi |
| builder-a | `zai:glm-5.3` | `openrouter:z-ai/glm-5.2:free` |
| builder-b | `openrouter:stealth/ox-alpha` | `openrouter:z-ai/glm-5.2:free` |
| reviewer | `openai-codex:gpt-5.5` | none |

The harness is derived, never stored: `anthropic` means Claude Code, everything else means pi.

The OpenRouter account is free-tier with no credits, so fallbacks name `:free` ids only.
A paid id passes `pi auth check` and then dies on the first request with a 402.

The reviewer has no fallback on purpose, because every `openai/gpt-5.x` id on OpenRouter is paid.
If `openai-codex` is unreachable, `review.ps1` refuses to run and you fall back by hand to the Opus `reviewer` agent, saying in the report that it ran on the fallback.

### Dispatch a ticket

```powershell
.\dispatch.ps1 -Ticket path\to\ticket.md            # open the pane and watch it
.\dispatch.ps1 -Ticket t.md -DryRun                 # print the plan, spawn nothing
.\dispatch.ps1 -Ticket t.md -NoWatch                # dispatch and return
```

The ticket's frontmatter decides everything:

```markdown
---
role: builder-a
model: zai:glm-5.3
fallbackModels: openrouter:z-ai/glm-5.2:free
base: main
---
```

The `to-tickets` override stamps those lines, so you should never type a model id.
If you do write one by hand, get it from `Get-RosterFrontmatter -Role builder-a` in `roster.ps1`.

Dispatch creates a worktree off `base`, splits a pane running pi on that provider and model with `~/.claude/agents/<role>.md` as the system prompt, submits the ticket body as the brief, and watches.
Role `builder-a` resolves to `builder.md`: the exact name first, then the part before the last dash.

Anthropic-role tickets exit 2 rather than launching.
The only Anthropic role is the planner, and that is an interactive session, not something you dispatch.

### Fallback

pi has no mid-session fallback for these providers, and a session that hits a provider error does not exit - it prints the error and sits at `idle` forever.
So while `dispatch.ps1` is watching, it reads pane output, and on a 401/402/403/429 or a credentials error it closes the pane and reopens the ticket on the next `fallbackModels` entry.
One attempt per level, then it notifies and stops.
5xx is not a trigger, because a transient blip should not spend a fallback.

The final line always names the model that actually finished, and says so loudly when that was a fallback.
`-NoWatch` means no watcher, so no fallback.

### Review

```powershell
.\review.ps1 -Ticket path\to\ticket.md -Verdict "pwsh -File build.ps1 -> PASS"
.\review.ps1 -Ticket t.md -Verdict "..." -BuilderPane <id>   # if the builder is not named disp-<slug>
```

Splits the builder's pane to the right and runs pi read-only on the roster's reviewer model, in the builder's worktree.
Read-only is enforced by the pane, not by asking nicely: `M2_READONLY=1` starts pi with `--exclude-tools write,edit,bash,powershell`.

`-Verdict` is a precondition, not an option.
The reviewer cannot run anything, so without your build results it reviews around the hole.
One line per command, and `not run: <why>` when you could not run one.
Never write PASS for something you did not watch pass.

Then read the review and **relay it verbatim**.
Paraphrasing a reviewer replaces its judgement with yours, which is the single thing it exists to prevent.

### Verify the vendor

`pi --model zai/glm-5.3` matches no id and **silently runs the default Anthropic model**.
Provider and model are always separate flags: `pi --provider zai --model glm-5.3`.
The pane statusline names the model, so check it before believing a dispatch.

---

# Running Claude Code on GLM

The non-herdr route, kept for headless dispatch.

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

Useful switches: `-Model` (default `sonnet`, an **alias** that the table below
maps to GLM-5.2; pass an alias, never a raw GLM name, because Claude Code
validates `--model` against its own aliases and hard-fails an unknown string
with `unrecognized_model` and exit 1), `-PermissionMode` (default
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

The non-herdr review path.
Inside herdr, use `review.ps1` instead - same prompt shape, same `reviewer.md` standards, but in a pane beside the builder.
This one runs anywhere and prints to stdout, which is why it is kept.

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

## Watched builds: `herdr-build.ps1`

**Superseded by `dispatch.ps1`.**
It only ever built GLM-on-Claude-Code tickets; `dispatch.ps1` does the same thing for any role in the roster.
It is kept because it is what `dispatch.ps1` was generalized from, and the notes below still explain why both work the way they do.

```powershell
.\herdr-build.ps1 -Ticket 42 -Brief (Get-Content brief.md -Raw) -Watch
```

Creates a git worktree workspace, opens a pane in it that starts GLM under
`builder.md`, submits the brief, and waits. Use it when you are at the keyboard.
The headless `glm.ps1 -Prompt` path is still correct for unattended dispatch
from inside a Claude session.

What the watched path buys, and headless cannot:

- **`blocked` is recoverable.** A headless run that stops for a permission
  prompt, or because `builder.md` told it to ask rather than guess, is a wasted
  dispatch. In a pane you answer it and it continues.
- You see it going wrong early instead of reading about it at the end.
- Several builds run side by side, which is the only way a cheap execution
  subscription earns its keep.

### Two Windows landmines behind this

**`herdr agent start --kind claude` does not work here.** It runs
`Start-Process -FilePath claude`, and on a Windows npm install that resolves to
the extensionless `claude`, which is a `#!/bin/sh` script. It fails with "%1 is
not a valid Win32 application". `claude.cmd` works, but there is no config
surface to choose it. So the pane starts the agent itself, via `M2_AUTOSTART`
and `herdr-autostart.ps1`.

**herdr spawns Windows PowerShell 5.1**, not pwsh 7. Different profile path, so
`herdr-autostart.ps1` is dot-sourced from *both*
`Documents\PowerShell\Microsoft.PowerShell_profile.ps1` and
`Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`. Keep that file
5.1 compatible: no `??`, no `?.`, no ternary.

### Other things learned the hard way

- `agent prompt --wait` hangs. It matches the first state observed *after*
  submission, so it misses an agent that has not started working yet. Poll
  `agent get` instead and accept a settled state only once `working` has been
  seen. That is what `Wait-Agent` does (now in `herdr.ps1`, shared by
  `dispatch.ps1` and `review.ps1`).
- **A provider error does not move `agent_status`.** A pi session that hits a
  quota, auth, or rate-limit error prints the error and stays `idle`, alive and
  useless. Watching status alone means waiting out the full timeout on a
  session that will never do anything again, so `Wait-Agent` reads pane output
  every poll. Read it with `--source recent-unwrapped`: the default wrapped
  view truncates the error at the pane width.
- `pi auth check` reporting `ready` does not mean a request will succeed. It
  checks credentials, not credit. A paid OpenRouter id on a free-tier account
  authenticates fine and then dies with a 402 on the first request.
- `herdr agent get <name>` returns `pane_id`, so you can find an agent's pane
  to split beside it.
- `worktree remove` fails with "Permission denied" while any pane still has its
  cwd inside the worktree. Close the panes first, then remove.
- `agent send-keys` will not target a pane id, only a detected agent. A bare
  pane cannot be typed into, which is why the env must be set at split time.
- `worktree remove` deletes the checkout but **leaves the branch**. Delete it
  yourself.
- `glm-settings.local.json` is currently unused by this flow, since `glm.ps1`
  sets the environment directly. It is kept because `claude --settings <file>`
  is a working way to run GLM with no env manipulation at all, and is the
  fallback if herdr ever launches claude itself.

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

## Claude on the Max plan inside pi: `pi-claude-auth`

Set up 2026-08-25, Nuno's call after the risk was stated.

pi's own `/login` for Claude Pro/Max bills per token as extra usage. The
`pi-claude-auth` extension instead reads the Claude Code OAuth token from
`~/.claude/.credentials.json` and forges Claude Code's billing header, so
Anthropic routes the request to the plan. Its README says this is against
Anthropic's ToS for subscription tokens, and it will break silently when
Anthropic changes the header or the OAuth flow. The account at risk is the one
every Claude session here runs on.

Installed from GitHub, because the npm name in its README was never published:

```powershell
pi install git:github.com/pankajudhas81/pi-claude-auth   # lands in ~/.pi/agent/git/
pi update git:github.com/pankajudhas81/pi-claude-auth
```

No `/login` needed. `pi --list-models claude` lists the catalog, and a headless
`pi -p "Reply with the single word OK and nothing else."` proves the auth.

Two things to know:

- pi and Claude Code now share one token. The extension writes refreshed
  tokens back into `~/.claude/.credentials.json` every 5 minutes. If pi says
  the credentials are expired, run `claude` once and retry.
- Whether a given pi session landed on the plan or on extra usage is only
  visible at <https://claude.ai/settings/usage>, not from pi.

Every herdr tab starts `pi -a --bash-guard-disabled` (see `herdr-autostart.ps1`):
no project-trust prompt, no Run/Abort dialogs. Inside a running pi, `/bash-guard`
toggles the dialogs for that session, with a `BG OFF` badge in the status line
while they are off. Even off, bash-guard still hard-blocks `rm -rf`, `sudo`,
`curl | sh`, `git push --force`, `git reset --hard`, `git clean -f` and disk
tooling. To run with no floor at all, move `pi/extensions/bash-guard` out of
the extensions folder.

pi discovers skills from `~/.pi/agent/skills` and `.pi/skills`, not from
`.claude/skills`. To reuse a repo's Claude Code skills add
`"skills": ["../.claude/skills"]` to that repo's `.pi/settings.json`.
