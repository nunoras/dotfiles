#!/usr/bin/env bash
#
# Windows launcher for herdr-automatic-rename.
#
# Upstream is a Unix-only plugin (bash + jq, POSIX paths). herdr on Windows
# runs plugin commands as native processes, so this shim runs the engine under
# Git Bash and makes the Windows environment herdr hands it look POSIX enough
# for automatic-rename.sh to run unchanged:
#
#   * Ship jq next to the plugin and put it first on PATH (Git Bash has none).
#   * Disable MSYS path mangling. The engine's jq programs are full of the
#     `//` alternative operator and pass herdr pane ids like "wN:p1F"; MSYS
#     would rewrite both as if they were paths.
#   * Normalize the paths herdr injects as native Windows strings
#     (HERDR_SOCKET_PATH, HOME) to mixed "C:/..." form, which both Git Bash
#     builtins and the native jq.exe/herdr.exe accept, so the engine's own
#     ${VAR%/*} slicing and file reads work without touching upstream code.
#   * Unset HERDR_PLUGIN_ROOT (a backslash path the engine would try to source
#     naming.sh from) so it self-resolves via BASH_SOURCE to a POSIX dir.
#
# herdr invokes:  bash.exe win-launch.sh <event-or-mode> [args...]
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
export PATH="$here/bin:$PATH"

# Keep the config in the repo, next to the plugin, instead of ~/.config.
export HERDR_AUTOMATIC_RENAME_CONFIG="${HERDR_AUTOMATIC_RENAME_CONFIG:-$here/config.sh}"

# herdr.exe is what the engine shells out to as "$HERDR"; pin it so a stripped
# PATH cannot lose it.
if command -v herdr >/dev/null 2>&1; then
  export HERDR_BIN_PATH="${HERDR_BIN_PATH:-herdr}"
fi

# Newer herdr can miss a pane's foreground process in some sandboxed setups;
# child-groups detection is what the README prescribes on >= 0.8.0.
export HERDR_PROCESS_DETECTION="${HERDR_PROCESS_DETECTION:-child-groups}"

# Native Windows paths herdr passes in -> mixed "C:/..." the engine can slice
# and hand to jq.exe/herdr.exe unchanged.
if [ -n "${HERDR_SOCKET_PATH:-}" ]; then
  export HERDR_SOCKET_PATH="$(cygpath -m "$HERDR_SOCKET_PATH" 2>/dev/null || printf '%s' "${HERDR_SOCKET_PATH//\\//}")"
fi
if [ -n "${HOME:-}" ]; then
  export HOME="$(cygpath -m "$HOME" 2>/dev/null || printf '%s' "${HOME//\\//}")"
fi

# Let the engine resolve its own root via BASH_SOURCE (a POSIX path) instead of
# herdr's backslash HERDR_PLUGIN_ROOT, which `source` cannot read.
unset HERDR_PLUGIN_ROOT

exec bash "$here/automatic-rename.sh" "$@"
