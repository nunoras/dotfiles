# dotfiles

Reproducible AI + editor environment across all my machines. One canonical source
of truth, symlinked into the locations each tool actually reads.

## Philosophy

- **Windows is home.** Every machine runs native Windows tools (no WSL straddle).
  One home directory (`C:\Users\<me>`), one of every config.
- **One source of truth.** [`ai/AGENTS.md`](ai/AGENTS.md) is the canonical system
  prompt. Claude Code, Pi, and Zed are all *pointed at it* rather than each holding
  their own copy.
- **Symlinks, not copies.** `install.ps1` links the repo files into each tool's
  expected location, so editing the repo updates every tool live.

## Layout

```
dotfiles/
├── install.ps1                    # symlinks repo -> tool locations (idempotent)
├── COLLECT-FROM-THIS-MACHINE.md   # runbook: pull a machine's configs INTO this repo
├── ai/
│   ├── AGENTS.md                  # ⭐ single source of truth (system prompt)
│   ├── skills/                    # shared Claude skills (SKILL.md each)
│   └── agents/                    # shared subagent definitions
├── claude/
│   └── settings.json              # Claude Code settings (non-secret)
├── zed/
│   ├── settings.json
│   └── keymap.json
├── pi/                            # Pi global config (path TBC)
└── shell/
    └── Microsoft.PowerShell_profile.ps1   # the "oh-my-zsh" experience, natively
```

## What maps where

| Repo file | Symlinked to | Read by |
|---|---|---|
| `ai/AGENTS.md` | `~/.claude/CLAUDE.md` | Claude Code |
| `ai/skills/` | `~/.claude/skills/` | Claude Code |
| `ai/agents/` | `~/.claude/agents/` | Claude Code |
| `claude/settings.json` | `~/.claude/settings.json` | Claude Code |
| `zed/settings.json` | `%APPDATA%\Zed\settings.json` | Zed |
| `zed/keymap.json` | `%APPDATA%\Zed\keymap.json` | Zed |
| `shell/Microsoft.PowerShell_profile.ps1` | `~\Documents\PowerShell\…_profile.ps1` | PowerShell 7 |
| `ai/AGENTS.md` | Pi global config | Pi (path TBC) |

## Setup on a new machine

```powershell
# 1. Clone
git clone https://github.com/nunoras/dotfiles "$HOME\Documents\GitHub\dotfiles"
cd "$HOME\Documents\GitHub\dotfiles"

# 2. Turn on Developer Mode once so symlinks don't need admin:
#    Settings > Privacy & security > For developers > Developer Mode = On

# 3. Install the apps/tools AND link the configs in one go:
.\bootstrap.ps1          # winget + modules + font, then runs install.ps1
```

`bootstrap.ps1` installs the software stack (pwsh, Windows Terminal, Oh My Posh,
zoxide, fzf, git, gh, Node, Zed, the Nerd Font, PS modules, and the Claude Code
CLI via npm) and then calls `install.ps1` to link configs and apply the look.
Re-runnable and tolerant of already-installed items. Use
`.\bootstrap.ps1 -SkipInstall` to install software only, or run `.\install.ps1`
on its own to (re)link configs without touching apps.

> **Order matters:** if a machine already has configs you care about, run the
> COLLECT runbook *before* linking — open Claude Code in the repo and say
> "follow COLLECT-FROM-THIS-MACHINE.md" — otherwise install backs them up and
> replaces them with the repo's versions.

> **Claude Code** is installed via npm (Node is installed alongside it). **Pi**
> is still manual — add its install command in `bootstrap.ps1` once confirmed.

## The native-Windows terminal stack (replaces WSL + oh-my-zsh)

| WSL + oh-my-zsh | Native Windows |
|---|---|
| Ubuntu terminal | Windows Terminal |
| zsh | PowerShell 7 (`pwsh`) |
| oh-my-zsh + Powerlevel10k | Oh My Posh |
| zsh-autosuggestions | PSReadLine predictive IntelliSense |
| fzf Ctrl-R | PSFzf + fzf |
| `z` / autojump | zoxide |
| `apt` | Scoop / winget |

Install:

```powershell
winget install Microsoft.PowerShell Microsoft.WindowsTerminal JanDeDobbeleer.OhMyPosh ajeetdsouza.zoxide junegunn.fzf
Install-Module PSFzf, Terminal-Icons -Scope CurrentUser
oh-my-posh font install        # pick a Nerd Font (e.g. CaskaydiaCove)
```

The wiring lives in [`shell/Microsoft.PowerShell_profile.ps1`](shell/Microsoft.PowerShell_profile.ps1).
