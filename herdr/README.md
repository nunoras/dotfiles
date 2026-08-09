# Herdr

[Herdr](https://herdr.dev) is the terminal workspace manager the AI agents run
inside - tabs, splits, and per-pane agent state.

`config.toml` is symlinked to `%APPDATA%\herdr\config.toml` by `install.ps1`, so
keybindings and UI prefs are the same on every machine.

Installed by `bootstrap.ps1`:

```powershell
irm https://herdr.dev/install.ps1 | iex
```

The binary lands in `~\.herdr\packages\` with a shim at
`~\AppData\Local\Programs\Herdr\bin\herdr.exe`; `herdr update` keeps it current
on the channel `config.toml` pins (`preview`).

## Notes

- Herdr rewrites `config.toml` itself for a few things - finishing onboarding,
  `herdr config reset-keys`. If it ever replaces the file instead of writing
  through the symlink, the link is gone and the repo copy goes stale: re-run
  `install.ps1` to relink (it backs the live file up first, so nothing is lost).
- `install.ps1` calls `herdr server reload-config` after linking, so a running
  server picks up the config without a restart.
- The Claude Code side of the integration - the `SessionStart` hook that reports
  agent state to the pane - lives in [`../claude/hooks/`](../claude/hooks/).
