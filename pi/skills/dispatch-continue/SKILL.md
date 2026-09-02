---
name: dispatch-continue
description: Answer a dispatch workflow that needs a human decision. Use when a workflow is in needs_human and the user gives the answer or an adjusted prompt.
disable-model-invocation: true
---

# dispatch-continue

Continue a workflow that is waiting for a human decision.

## Check the client

Run `command -v dispatch`.
If it is missing, stop and say that the dispatch client is not installed or not on PATH.
Hint: install it with install.sh or install.ps1, then check tailscale up and the token in ~/.dispatch/config.toml.

## Check the workflow

Run `dispatch status <id>`.
If the state is not needs_human, report the actual state and stop.
Read the reason and the detail, which hold the question the loop is waiting on.
Make sure the user's answer addresses that question before going on.

## Answer

Write the user's answer, or their adjusted prompt, to a temporary file.

Run:

```sh
dispatch continue <id> --answer-file=<file>
```

If the command fails, quote the error and stop.
When the error mentions the server, the dispatch server is unreachable.
Hint: check tailscale up and the token in ~/.dispatch/config.toml.

## Report

Print the workflow id and tell the user to follow it with `dispatch status <id>`.
Return now; never poll, never wait.
