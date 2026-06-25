# Pi config

Pi reads a **global `AGENTS.md`** from `~/.pi/agent/AGENTS.md` at startup (then
walks up parent directories, then the current directory). So Pi consumes the
exact same canonical [`../ai/AGENTS.md`](../ai/AGENTS.md) that Claude does —
`install.ps1` symlinks `~/.pi/agent/AGENTS.md` to it.

Other global Pi paths (under `~/.pi/agent/`), for reference:
- `settings.json` — global settings
- `SYSTEM.md` — replace the default system prompt; `APPEND_SYSTEM.md` — add to it
- `extensions/`, `sessions/`, `trust.json`

Pi itself is installed by [`../bootstrap.ps1`](../bootstrap.ps1) via
`pi.dev/install.ps1` (npm `@earendil-works/pi-coding-agent`).
