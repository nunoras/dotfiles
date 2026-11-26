# dotfiles

How I work with coding agents, kept as the config they run on.
Claude Code, Codex and Pi read the same rules and skills from this repo, on Windows and Linux.

## How I work with agents

The rules live in [`ai/AGENTS.md`](ai/AGENTS.md); the skills in [`ai/skills`](ai/skills) carry them out.

- **What I hand over.** Agents write the code.
  A small change with a settled design goes to one agent as one PR.
  Bigger work becomes a spec, then tickets, then one agent thread per ticket.
- **What I keep.** Product calls, design decisions, and anything costly to undo: publishing, spending money, deleting.
  Agents make reversible calls themselves and list them so I can reverse them.
- **How the output gets checked.** An agent never claims a check it did not run, and a bug fix starts by reproducing the bug.
  [`full-send`](ai/skills/full-send/SKILL.md) takes a change to a merged PR only after proof for every change, a review by a model from a different vendor, and every review-bot finding fixed or answered.
- **How mistakes become rules.** When I correct an agent, the fix goes into a rule or skill in the same session.
  A correction that keeps coming back becomes a hook instead: [`prose-guard`](ai/scripts/prose-guard.mjs), [`poll-guard`](ai/scripts/poll-guard.mjs) and [`pkill-guard`](ai/scripts/pkill-guard.mjs) block the mistake before the command runs.

## Setup philosophy

- **Windows is home, Linux is supported.** Windows machines run native Windows
  tools (no WSL straddle). Linux boxes get the agent configs through `install.sh`.
- **One source of truth.** [`ai/AGENTS.md`](ai/AGENTS.md) is the canonical system
  prompt. Claude Code and Pi are both *pointed at it* rather than each holding
  their own copy.
- **Symlinks, not copies.** `install.ps1` (Windows) and `install.sh` (Linux) link
  the repo files into each tool's expected location, so editing the repo updates
  every tool live.

## Layout

```
dotfiles/
├── install.ps1                    # Windows: symlinks repo -> tool locations (idempotent)
├── install.sh                     # Linux: the same links, minus the Windows-only parts
├── ai/
│   ├── AGENTS.md                  # ⭐ single source of truth (system prompt)
│   ├── skills/                    # shared skills, every harness sees them
│   ├── scripts/skills-sync.mjs    # links skills into ~/.agents/skills
│   └── agents/                    # shared subagent definitions
├── claude/
│   ├── settings.json              # Claude Code settings (non-secret)
│   ├── statusline.mjs             # the two-line status line
│   └── hooks/                     # hooks referenced by settings.json
├── pi/                            # Pi global config, extensions and pi-only skills
└── shell/
    └── Microsoft.PowerShell_profile.ps1   # the "oh-my-zsh" experience, natively
```

## What maps where

| Repo file | Symlinked to | Read by |
|---|---|---|
| `ai/AGENTS.md` | `~/.claude/CLAUDE.md` | Claude Code |
| `ai/scripts/` | `~/.claude/scripts/` | PowerShell profiles, agent scripts |
| `ai/skills/` | `~/.claude/skills/` | Claude Code |
| `ai/agents/` | `~/.claude/agents/` | Claude Code |
| `claude/settings.json` | `~/.claude/settings.json` | Claude Code |
| `claude/statusline.mjs` | `~/.claude/statusline.mjs` | Claude Code |
| `claude/pstack-models.md` | `~/.claude/pstack-models.md` | Claude Code (pstack model sheet) |
| `shell/Microsoft.PowerShell_profile.ps1` | `~\Documents\PowerShell\…_profile.ps1` | PowerShell 7 (Windows only) |
| `pi/skills/` | `~/.pi/agent/skills/` | Pi |
| `pi/extensions/` | `~/.pi/agent/extensions/` | Pi |
| `ai/AGENTS.md` | `~/.pi/agent/AGENTS.md` | Pi |
| `ai/skills/*` + Claude plugin skills | `~/.agents/skills/*` (one link per skill) | Pi, Codex |

### Every harness gets every skill

Shared skills live in `ai/skills`.
Claude Code reads them through `~/.claude/skills` and gets pstack and mattpocock-skills as plugins.
[`ai/scripts/skills-sync.mjs`](ai/scripts/skills-sync.mjs) links the shared skills and every enabled Claude plugin's skills into `~/.agents/skills`, which both pi and Codex scan.

- It runs from both installers and from a Claude `SessionStart` hook, so plugin updates and new skills show up on the next Claude session.
- It only touches links it made, tracked in `~/.agents/skills/.dotfiles-skills-sync.json`. Skills other tools install there (like `npx skills add`) are left alone.
- When two skills share a name, the first one wins: personal skills, then plugins in `enabledPlugins` order. That is why `pstack` comes before `mattpocock-skills` in `claude/settings.json`.
- Plugin skills get the plugin as a folder prefix, for example `pstack-poteto-mode`.

### Private skills

Skills that are personal or someone else's work live in a separate private repo, `dotfiles-private`, cloned next to this one.
The installers link each folder in its `skills/` into `ai/skills/` and add it to `.git/info/exclude`, so it never shows up here.
Set `DOTFILES_PRIVATE` to use another path.

`pi/skills` holds the few skills that only work inside pi (they read pi's sessions or use pi's browser tools), linked to `~/.pi/agent/skills`.
`ai/skills/synced/` is where Claude Code drops skills synced from claude.ai, and it is gitignored.

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
CLI via npm, plus Pi via its official installer) and then calls
`install.ps1` to link configs and apply the look.
`install.ps1` enables Developer Mode the first time (one UAC prompt) so the
symlinks don't need admin, here or on any later re-run.
Re-runnable and tolerant of already-installed items. Use
`.\bootstrap.ps1 -SkipInstall` to install software only, or run `.\install.ps1`
on its own to (re)link configs without touching apps.

> Existing configs are moved aside as `<name>.bak-<timestamp>` before linking,
> so nothing on the machine is lost.

> **Claude Code** (npm) and **Pi** (`pi.dev/install.ps1`) are both installed by
> bootstrap. Pi reads its global instructions from `~/.pi/agent/AGENTS.md`, which
> `install.ps1` symlinks to the canonical `ai/AGENTS.md` — same file as Claude.

### Linux

```bash
git clone https://github.com/nunoras/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run   # preview
./install.sh
```

`install.sh` links the Claude Code and pi configs, removes links into the repo whose target is gone, and runs the skill sync.
It does not install software. It warns about missing `git`, `node`, `claude`, `pi` or `codex`, and `node` is required for the status line, hooks and skill sync.
Existing files are moved aside as `<name>.bak-<timestamp>` before linking, same as on Windows.

## Voice and formatting

How agents talk to me lives in the Voice section of [`ai/AGENTS.md`](ai/AGENTS.md): plain terms, few words, no mannered prose, and when to use lists, tables and headers.
Claude Code injects CLAUDE.md into the user turn, which is where Anthropic's Fable 5.1 guide says the mannered-prose instruction works best.
Longer prose (docs, READMEs, PR descriptions) follows the `unslop` skill.

## The Claude status line


The Claude Code status line is [`claude/statusline.mjs`](claude/statusline.mjs):

```
Opus 5 (1M context)  ████|██░░░░░░░░░░░░░░░░  31%  xhigh          main  (+21,-7)
5-hour: 12% (r: 3h 40m) | weekly: 40% (r: 1d 2h 46m)
```

The `|` on the context bar sits at 20%, the "time to start a new chat" tick. The
fill is green below it and amber above, and the tick turns red once the fill
passes it.

Hook and status-line commands in `claude/settings.json` are `node "$HOME/..."`.
Claude Code runs them through Git Bash on Windows and `sh` on Linux, and Node is
already there for Claude Code and pi, so one settings file works on both
platforms and on machines with different usernames. Right-alignment reads
`COLUMNS`, which Claude Code sets for the status line command.

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
