# Running other vendors' models

Two headless scripts, plus the credentials both routes need.

`glm.ps1` runs Claude Code against Z.AI's GLM models.
`gpt-review.ps1` runs a review through the Codex CLI and prints it to stdout.
Neither needs a terminal, a pane, or a worktree, which is why they survived the move to Orca.

Dispatch into an Orca worktree is `orca-dispatch`, not these scripts.
The roster, the harness rule, and the review loop live in `AGENTS.md`.

# Running Claude Code on GLM

The headless route, kept for unattended dispatch.

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

Runs anywhere and prints to stdout, which is why it is kept.
Same prompt shape and the same `ai/agents/reviewer.md` standards as any other review path.

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


## Other things learned the hard way

- **A provider error does not change an agent's status.** A pi session that
  hits a quota, auth, or rate-limit error prints the error and stays idle,
  alive and useless. Watching status alone means waiting out the full timeout
  on a session that will never do anything again, so anything that supervises
  a dispatch has to read the terminal output, not just the state.
- `pi auth check` reporting `ready` does not mean a request will succeed. It
  checks credentials, not credit. A paid OpenRouter id on a free-tier account
  authenticates fine and then dies with a 402 on the first request.
- `glm-settings.local.json` is currently unused by this flow, since `glm.ps1`
  sets the environment directly. It is kept because `claude --settings <file>`
  is a working way to run GLM with no env manipulation at all, and is the
  fallback if a harness ever launches claude itself.

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

Launching pi as `pi -a --bash-guard-disabled` gives you:
no project-trust prompt, no Run/Abort dialogs. Inside a running pi, `/bash-guard`
toggles the dialogs for that session, with a `BG OFF` badge in the status line
while they are off. Even off, bash-guard still hard-blocks `rm -rf`, `sudo`,
`curl | sh`, `git push --force`, `git reset --hard`, `git clean -f` and disk
tooling. To run with no floor at all, move `pi/extensions/bash-guard` out of
the extensions folder.

pi discovers skills from `~/.pi/agent/skills` and `.pi/skills`, not from
`.claude/skills`. To reuse a repo's Claude Code skills add
`"skills": ["../.claude/skills"]` to that repo's `.pi/settings.json`.
