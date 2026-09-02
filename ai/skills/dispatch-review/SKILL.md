---
name: dispatch-review
description: Submit a review-only dispatch workflow against the current branch. Use when the user asks for an independent dispatch review of the branch they are on.
disable-model-invocation: true
---

# dispatch-review

Submit a review-only workflow for the current branch and return.

## Check the client

Run `command -v dispatch`.
If it is missing, stop and say that the dispatch client is not installed or not on PATH.
Hint: install it with install.sh or install.ps1, then check tailscale up and the token in ~/.dispatch/config.toml.

## Check the branch is pushed

Run `git status -sb`.
If the first line does not show an upstream in the form `## <branch>...<upstream>`, stop and tell the user to push the branch first.
A review needs a pushed branch.

Run `git branch --show-current` for the branch name.

## Resolve the target repository

Run `git remote get-url origin`.
Normalize the URL to owner/repo by stripping https://, git@github.com: and any .git suffix.
If there is no origin remote, stop and say so.

## Build the prompt and name

Write the review focus from the request, or a single line asking for a plain review, to a temporary file.
Name the workflow <issue>-<slug> when an issue reference is in play, else job-<shortid> with a short random identifier.

## Submit

Run:

```sh
dispatch review --repo=<owner/repo> --branch=<branch> --prompt-file=<file> --name=<name>
```

If the command fails, quote the error and stop.
When the error mentions the server, the dispatch server is unreachable.
Hint: check tailscale up and the token in ~/.dispatch/config.toml.

## Report

Print the workflow id and tell the user to follow it with `dispatch status <id>`.
Return now; never poll, never wait.
