---
name: dispatch-status
description: Show dispatch workflow status. Use when the user asks about the state of a dispatched workflow, the build loop, or the latest review verdict.
---

# dispatch-status

Run `command -v dispatch` first and stop with a clear message if it is missing.
Hint: install the client with install.sh or install.ps1, then check tailscale up and the token in ~/.dispatch/config.toml.

Run `dispatch status` to list every workflow.
Run `dispatch status <id>` when an id is given or is already known from the conversation.

For a single workflow, report the state, the round, the reason and the detail of the latest terminal state.
For the list, report one line per workflow with its id, name, state, round and reason.

If the command fails, quote the error and stop.
When the error mentions the server, the dispatch server is unreachable.
Hint: check tailscale up and the token in ~/.dispatch/config.toml.
