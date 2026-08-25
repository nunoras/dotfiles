# herdr-automatic-rename config for this machine.
# Loaded via HERDR_AUTOMATIC_RENAME_CONFIG, set in win-launch.sh, so it travels
# with the plugin instead of living under ~/.config. See config.example.sh for
# every knob.

# Spaces (workspaces): keep herdr's own name, which follows the project folder.
# No "[N]" prefix on them.
AUTO_INDEX_WORKSPACES=0

# Tabs: numbered, and named after the foreground program or, for a coding-agent
# pane, after the task the agent reports in its terminal title. This is what
# turns a claude tab into "[1] Finalizar duas ofertas ..." and is the only place
# an agent's task can carry a "[N]" prefix (herdr forbids brackets/spaces in the
# agent-panel names themselves).
AUTO_INDEX_TABS=1
NAME_TABS=1
AGENT_TITLES=1

# On Windows a coding agent runs under the host shell (cmd.exe / pwsh), so that
# is the foreground program herdr reports. Treat those as wrappers, so a pane
# herdr has detected an agent in is named after the agent ("pi") instead of the
# shell ("cmd.exe") when the agent gives no usable task title. A plain shell tab
# has no detected agent and keeps its own name. This assignment replaces the
# upstream default list, so the Unix runtimes are carried over too.
WRAPPER_PROGRAMS=(cmd cmd.exe pwsh pwsh.exe powershell powershell.exe node bun deno npx bunx npm pnpm yarn python python3 uv uvx pipx ruby)
