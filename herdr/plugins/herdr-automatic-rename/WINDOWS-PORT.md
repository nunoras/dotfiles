# Windows port notes

Upstream ([qu8n/herdr-automatic-rename](https://github.com/qu8n/herdr-automatic-rename)) is Linux/macOS only.
This is a local fork that runs it under native Windows herdr via Git Bash.
Keep the diff from upstream small so a future upstream bump is easy to re-apply.

## Requirements on this machine

- Git Bash at `C:\Program Files\Git\bin\bash.exe` (the launcher hardcodes this path).
- herdr for Windows (the CLI is on PATH as `herdr.exe`).
- jq is bundled under `bin/`, so nothing extra to install.

## Files added by the fork (not upstream)

- `win-launch.sh` - the shim herdr actually runs. It puts the bundled jq on PATH, disables MSYS path mangling, normalizes the native Windows paths herdr injects (`HERDR_SOCKET_PATH`, `HOME`) to mixed `C:/...` form, unsets `HERDR_PLUGIN_ROOT` so the engine self-resolves via `BASH_SOURCE`, then execs `automatic-rename.sh`.
- `bin/jq` - wrapper that runs `jq-bin.exe` and strips `\r`. The native jq.exe opens stdout in text mode and emits CRLF, and the trailing `\r` poisons every value the engine reads back through `read`/`$(...)`. `PIPESTATUS[0]` preserves jq's real exit code, which the engine branches on.
- `bin/jq-bin.exe` - jq 1.7.1 win64.
- `config.sh` - machine config, loaded via `HERDR_AUTOMATIC_RENAME_CONFIG` (set in the launcher). Spaces unnumbered, tabs numbered + agent task titles, `cmd`/`pwsh` treated as agent wrappers.
- `herdr-plugin.toml` - `platforms = ["windows"]`, and every command runs `C:/Program Files/Git/bin/bash.exe win-launch.sh <event>` instead of `bash automatic-rename.sh <event>`.

## Edits inside upstream engine files (re-apply on upstream bump)

Four edits, all because herdr on Windows reports backslash paths and pi appends its folder to the title.

- `automatic-rename.sh`, three spots that took a basename with `split("/")`. Windows cwds are backslash paths like `N:\GitHub\drop\`, so `split("/")` returned the whole string and the "this title is just the folder" guard never matched. Each now strips a trailing separator and splits on `[\\/]`:
  `| gsub("[\\\\/]+$"; "") | split("[\\\\/]"; "") | last`
  (search for `split("[\\\\/]"` to find all three).
- `naming.sh`, end of `ar_title_clean`. Strips a trailing ` - <folder>` from an agent title, so a named pi session (`π - <session> - <cwd>`) reads as the session alone. Matches the folder case-insensitively against `$dirlc`, cuts the kept part from the original title so its case survives. Search for `kept_lc`.

## Not ported

- The real-time shell hooks under `shell/` are zsh/bash/fish. This machine uses PowerShell, so tab names update on herdr events (focus, tab/pane create/close), not on every command. A PowerShell precmd hook could be added later.

## Test

```sh
export PATH="$PWD/bin:$PATH"
bash tests/test_naming.sh   # 173/173 with the fork edits
```
