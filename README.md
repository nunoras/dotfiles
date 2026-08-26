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
│   ├── skills/                    # Claude Code skills (SKILL.md each)
│   └── agents/                    # shared subagent definitions
├── claude/
│   ├── settings.json              # Claude Code settings (non-secret)
│   ├── statusline-rich.ps1        # the two-line status line
│   └── hooks/                     # hooks referenced by settings.json
├── herdr/
│   └── config.toml                # Herdr keybindings + UI prefs
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
| `ai/system-prompt-append.md` | `~/.claude/system-prompt-append.md` | Claude Code (via the `claude` shim) |
| `ai/scripts/` | `~/.claude/scripts/` | PowerShell profiles, agent scripts |
| `ai/skills/` | `~/.claude/skills/` | Claude Code |
| `ai/agents/` | `~/.claude/agents/` | Claude Code |
| `claude/settings.json` | `~/.claude/settings.json` | Claude Code |
| `claude/statusline-rich.ps1` | `~/.claude/statusline-rich.ps1` | Claude Code |
| `claude/hooks/herdr-agent-state.ps1` | `~/.claude/hooks/herdr-agent-state.ps1` | Claude Code |
| `herdr/config.toml` | `%APPDATA%\herdr\config.toml` | Herdr |
| `zed/settings.json` | `%APPDATA%\Zed\settings.json` | Zed |
| `zed/keymap.json` | `%APPDATA%\Zed\keymap.json` | Zed |
| `shell/Microsoft.PowerShell_profile.ps1` | `~\Documents\PowerShell\…_profile.ps1` | PowerShell 7 |
| `shell/WindowsPowerShell_profile.ps1` | `~\Documents\WindowsPowerShell\…_profile.ps1` | Windows PowerShell 5.1 (herdr panes) |
| `pi/skills/` | `~/.pi/agent/skills/` | Pi |
| `pi/extensions/` | `~/.pi/agent/extensions/` | Pi |
| `ai/AGENTS.md` | `~/.pi/agent/AGENTS.md` | Pi |

### The two skill sets are separate on purpose

Claude Code reads `ai/skills`, pi reads `pi/skills`, and neither reads the other.
They are not two copies of one set: `orchestrator` exists in both with deliberately different content, because the two harnesses need different instructions.

Three skills are mirrored across both because both harnesses need them and they are harness-agnostic prose: `grilling`, `grill-with-docs`, `domain-modeling`.
Edit one, edit the other.
Dropping the copy from one side breaks whichever harness is documented to use it - AGENTS.md puts `grilling` at step 1 of the pipeline, and the planner runs on Claude Code.

## Setup on a new machine

```powershell
# 1. Clone
git clone https://github.com/nunoras/dotfiles "$HOME\Documents\GitHub\dotfiles"
cd "$HOME\Documents\GitHub\dotfiles"

# 2. Install the apps/tools AND link the configs in one go:
.\bootstrap.ps1          # winget + modules + font, then runs install.ps1
#    Accept the UAC prompt: install.ps1 enables Developer Mode once so the
#    config symlinks can be created without admin (now and on every re-run).
```

`bootstrap.ps1` installs the software stack (pwsh, Windows Terminal, Oh My Posh,
zoxide, fzf, git, gh, Node, Zed, the Nerd Font, PS modules, and the Claude Code
CLI via npm, plus Pi and Herdr via their official installers) and then calls
`install.ps1` to link configs and apply the look.
`install.ps1` enables Developer Mode the first time (one UAC prompt) so the
symlinks don't need admin, here or on any later re-run.
Re-runnable and tolerant of already-installed items. Use
`.\bootstrap.ps1 -SkipInstall` to install software only, or run `.\install.ps1`
on its own to (re)link configs without touching apps.

> **Order matters:** if a machine already has configs you care about, run the
> COLLECT runbook *before* linking — open Claude Code in the repo and say
> "follow COLLECT-FROM-THIS-MACHINE.md" — otherwise install backs them up and
> replaces them with the repo's versions.

> **Claude Code** (npm), **Pi** (`pi.dev/install.ps1`) and **Herdr**
> (`herdr.dev/install.ps1`) are all installed by bootstrap. Pi reads its global
> instructions from `~/.pi/agent/AGENTS.md`, which `install.ps1` symlinks to the
> canonical `ai/AGENTS.md` — same file as Claude.

## The system-prompt append

[`ai/system-prompt-append.md`](ai/system-prompt-append.md) is appended to the
system prompt of **every** Claude Code session. It is vendored verbatim from
[disler/fixing-smartass-opus-5](https://github.com/disler/fixing-smartass-opus-5);
re-fetch the raw file to update it.

Claude Code has no settings key and no env var for this - checked on 2.x, an
`appendSystemPrompt` key in `--settings` is silently ignored. The only mechanism
is the `--append-system-prompt-file` flag, so the flag has to be on every launch.
[`ai/scripts/claude-wrapper.ps1`](ai/scripts/claude-wrapper.ps1) defines a
PowerShell function named `claude` that injects it, and both profiles dot-source
that file - pwsh 7 for normal terminals, Windows PowerShell 5.1 because that is
what herdr spawns for its panes.

This is different from `ai/AGENTS.md`. AGENTS.md is *context* Claude reads and is
shared with Pi and Zed; the append goes into the actual system prompt and is
Claude Code only.

Three ways out:

| want | do |
|---|---|
| one session without it | `$env:M2_NO_PROMPT_APPEND = 1` |
| one command without it | `claude.cmd ...` (bypasses the function) |
| your own prompt instead | pass any `--system-prompt*` flag; the shim steps aside |

Subagents do not inherit it. The hidden `--append-subagent-system-prompt` flag
covers them if that is ever wanted.

## Herdr + the Claude status line

[Herdr](https://herdr.dev) is the terminal workspace the agents run in: tabs,
splits, and per-pane agent state. Its keybindings and UI prefs live in
[`herdr/config.toml`](herdr/README.md), and the `SessionStart` hook that reports
Claude's session to the current pane lives in
[`claude/hooks/`](claude/hooks/README.md).

The Claude Code status line is [`claude/statusline-rich.ps1`](claude/statusline-rich.ps1):

```
Opus 5 (1M context)  ████|██░░░░░░░░░░░░░░░░  31%  xhigh          main  (+21,-7)
5-hour: 12% (r: 3h 40m) | weekly: 40% (r: 1d 2h 46m)
```

The `|` on the context bar sits at 20%, the "time to start a new chat" tick. The
fill is green below it and amber above, and the tick turns red once the fill
passes it.

Hook and status-line commands in `claude/settings.json` are written as
`$HOME/...`, not `C:\Users\<me>\...`, because Claude Code runs them through Git
Bash. One settings file therefore works on machines with different usernames.

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
