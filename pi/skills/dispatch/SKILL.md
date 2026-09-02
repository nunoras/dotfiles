---
name: dispatch
description: Submit a build-review workflow to the dispatch server. Use when the user asks to dispatch or hand off a task to the build loop, from an issue reference or from free text.
disable-model-invocation: true
---

# dispatch

Submit one build-review workflow and return immediately.
Never wait for the workflow to finish.

## Check the client

Run `command -v dispatch`.
If it is missing, stop and say that the dispatch client is not installed or not on PATH.
Hint: install it with install.sh or install.ps1, then check tailscale up and the token in ~/.dispatch/config.toml.

## Resolve the target repository

Run `git remote get-url origin`.
Normalize the URL to owner/repo by stripping https://, git@github.com: and any .git suffix.
If there is no origin remote, stop and say so.

## Build the prompt

If the request names an issue as #123 or as a full issue URL, run `gh issue view <number> --repo <owner/repo> --json title,body` and write the issue title and body to a temporary file as the prompt.
Otherwise write the request itself to a temporary file as the prompt.
Pass the prompt by file, never inline.

## Pick the workflow

A workflow says which roles run and in what order. `default` builds, reviews across
vendors, loops blocking findings back to the builder, and squashes the history when the
review comes back clean.

Use `default` unless the request names another one. `dispatch submit --workflow=<name>`
selects it, and the server refuses a name it does not have.

## Name the job

With an issue reference, use <issue>-<slug> where slug is the issue title lowercased with non-alphanumeric characters collapsed to single dashes, trimmed to 32 characters.
Without an issue reference, use job-<shortid> where shortid is a short random identifier.
This names the branch and the worktree, so it is not the workflow name.

## Submit

Run:

```sh
dispatch submit --repo=<owner/repo> --workflow=<workflow> --name=<name> --prompt-file=<file>
```

If the command fails, quote the error and stop.
When the error mentions the server, the dispatch server is unreachable.
Hint: check tailscale up and the token in ~/.dispatch/config.toml.

## Report

Print the workflow id and tell the user to follow it with `dispatch status <id>`.
Return now; never poll, never wait.
