---
name: setup-dispatch
description: Install or repair the dispatch client on this machine. Use when the user asks to set up dispatch, when the dispatch binary or its skills are missing or stale, or when another dispatch skill fails on the client, the server or the token.
disable-model-invocation: true
---

# setup-dispatch

Bring this machine to a working dispatch client: the binary on PATH, the config pointing at the server, the skills installed.
Stop at the first failure, quote the error and say what the user has to do.
Never print the token.

## Check Go

Run `go version`.
If it is missing, stop: install Go from https://go.dev/dl/ and run this skill again.

## Install or refresh the binary

Run:

```sh
go install github.com/nunoras/dispatch/cmd/dispatch@latest
```

This is what install.sh and install.ps1 do, and it refreshes a stale binary too.
If it fails, quote the error and stop.

Run `command -v dispatch`.
If it is missing, run `go env GOPATH`, tell the user to add `<GOPATH>/bin` to PATH and open a new shell, and stop.

## Check the network

Run `tailscale status`.
If it reports stopped, logged out or needs login, stop and tell the user to run `tailscale up`.
If the tailscale command itself is missing, skip this check; the next step reports reachability.

## Get the token

The server is https://inspire.example.ts.net.
If ~/.dispatch/config.toml exists and has a token, reuse it.
Otherwise ask the user for it.
It is the bearer token in the server config on inspire, reached with `ssh nunoras@inspire`.

## Configure and install the skills

Run:

```sh
dispatch init --server=https://inspire.example.ts.net --token=<token>
```

It writes ~/.dispatch/config.toml, checks the server answers, and writes every embedded skill to ~/.claude/skills and ~/.pi/agent/skills, overwriting.

Read a failure by its text:

- connection refused, no such host, or a timeout: the tailnet does not reach inspire, or the server is down. Run `tailscale ping inspire` and report what it says.
- 401 or unauthorized: the token is wrong. Ask for it again and rerun init.
- anything else: quote it and stop.

## Skills that live in a dotfiles repo

Run `ls -ld ~/.claude/skills ~/.pi/agent/skills`.
If either is a symlink into a git repository, run `git status --short` there and tell the user the dispatch skills it lists need committing.

## Report

Run `dispatch version` and `dispatch status`.
Report three lines: the binary version, the server URL and that it answered, and where the skills were written.
