# COLLECT FROM THIS MACHINE

> **This file is a runbook for Claude Code.** Open Claude Code inside this repo on
> any machine and say: **"follow COLLECT-FROM-THIS-MACHINE.md"**. It will detect
> what's installed here, ask you what to pull into the repo, copy it in, and
> (with your OK) commit + push.

---

## Instructions to the agent

You are running on one of the user's machines. Your job is to **collect this
machine's AI/editor configuration INTO this repo** so it can be reproduced
elsewhere. Follow these steps in order. **Do not copy anything until the user has
chosen it.**

### Step 1 — Detect the environment

Figure out what this machine is and what's present. Check each source path below
(it may be a native Windows machine, or WSL/Linux, so check both styles). Only
things that **actually exist** become options.

| # | Item | Native Windows path | WSL / Linux path |
|---|------|---------------------|------------------|
| 1 | Claude — system prompt | `~\.claude\CLAUDE.md` | `~/.claude/CLAUDE.md` |
| 2 | Claude — settings | `~\.claude\settings.json` | `~/.claude/settings.json` |
| 3 | Claude — skills | `~\.claude\skills\` | `~/.claude/skills/` |
| 4 | Claude — subagents | `~\.claude\agents\` | `~/.claude/agents/` |
| 5 | Claude — slash commands | `~\.claude\commands\` | `~/.claude/commands/` |
| 6 | Zed — settings | `%APPDATA%\Zed\settings.json` | `~/.config/zed/settings.json` |
| 7 | Zed — keymap | `%APPDATA%\Zed\keymap.json` | `~/.config/zed/keymap.json` |
| 8 | Pi — global config | _locate it_ (`~\.pi\`, `~\.config\pi\`, or app config) | `~/.pi/`, `~/.config/pi/` |
| 9 | Shell — PowerShell profile | `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` | — |
| 10 | Shell — zsh / oh-my-zsh | — | `~/.zshrc`, `~/.oh-my-zsh/custom/` |
| 11 | Oh My Posh theme | `$env:POSH_THEMES_PATH` / custom `.omp.json` | `~/.config/ohmyposh/` |

For Pi (#8), if you can't find the config, run the Pi CLI's help/version or check
its docs to locate where it stores global config, then report what you found.

### Step 2 — Present a menu and ask

Build a list of **only the items found in Step 1**. Show the user a short summary
of each (path + size / file count + a one-line preview where useful). Then **ask
the user which items to copy** using a multi-select question. Phrase it like:

> "Found these configs on this machine — which do you want to pull into the
> dotfiles repo?"

Also ask, when relevant:
- **Merge vs replace** for folders that already exist in the repo (e.g. `skills/`):
  add only new files, or overwrite the repo copy?
- For `settings.json` files: confirm before copying — they may contain secrets
  (see Step 4).

Never copy an item the user didn't pick.

### Step 3 — Copy into the repo

For each chosen item, copy it to its destination below. Create folders as needed.
Preserve subfolder structure for directories.

| Item | Repo destination |
|---|---|
| Claude system prompt (`CLAUDE.md`) | `ai/AGENTS.md` — **but** if the repo's `ai/AGENTS.md` already has real content, do NOT blindly overwrite. Show a diff and ask whether to replace, merge, or skip. |
| Claude settings | `claude/settings.json` |
| Claude skills | `ai/skills/` |
| Claude subagents | `ai/agents/` |
| Claude commands | `claude/commands/` |
| Zed settings | `zed/settings.json` |
| Zed keymap | `zed/keymap.json` |
| Pi config | `pi/` |
| PowerShell profile | `shell/Microsoft.PowerShell_profile.ps1` |
| zsh / oh-my-zsh custom | `shell/zsh/` (reference only — Windows is home) |
| Oh My Posh theme | `shell/<name>.omp.json` |

> The canonical system prompt is **`ai/AGENTS.md`**. A machine's `CLAUDE.md` is
> usually just a pointer to it — if the machine's `CLAUDE.md` is only an `@import`
> line, you don't need to copy it; the repo already owns the real content.

### Step 4 — Scrub secrets (mandatory)

Before staging anything, **scan copied files for secrets**: API keys, tokens
(`sk-…`, `gho_…`, `ghp_…`), passwords, absolute paths with usernames, anything
that looks private. In particular:

- `settings.json` files can contain API keys or per-machine secrets. Move any
  secret value out into a `*.local.json` (which `.gitignore` already excludes) and
  leave a placeholder, **or** ask the user how to handle it. Do **not** commit raw
  secrets.
- If you find a secret you can't cleanly separate, stop and ask the user.

### Step 5 — Review, commit, push

1. Show `git status` and a concise summary of what changed (files added/updated).
2. Ask the user to confirm.
3. On confirmation:
   ```
   git add -A
   git commit -m "Collect configs from <machine name> (<what was added>)"
   git push
   ```
4. Report the commit and remind the user they can now run `install.ps1` on other
   machines to receive these configs.

### Guardrails

- Ask before each destructive overwrite; default to **merge/keep** when unsure.
- Never push secrets. When in doubt, ask.
- If `git push` fails (auth, no remote), report the error and stop — don't retry blindly.
- Keep the user in control: this runbook **collects**, it does not install. Use
  `install.ps1` to push configs back out to a machine.
