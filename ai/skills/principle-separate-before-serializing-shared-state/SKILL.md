---
name: principle-separate-before-serializing-shared-state
description: Apply when two agents, processes, or jobs want the same file, branch, port, or record, and you are reaching for a lock, a queue, or a retry.
disable-model-invocation: true
---

# Separate before serializing shared state

## Rule

When two workers contend, give them separate state before you make them take turns.
A lock is the fallback, not the first move.

## Why

Serializing keeps the contention and adds waiting.
Separating removes the contention, and the waiting with it.

This is why every ticket gets its own git worktree and its own branch.
Two builders in one tree need a lock, a merge discipline, and a story for what happens when one dies mid-write.
Two builders in two worktrees need none of that, and a shared tree also breaks the per-ticket commit, because committing everything there sweeps up the other builder's work.

"We need a lock here" is a sentence to interrogate.
Ask what the two sides are actually sharing, and whether they have to.

## Pattern

- One worktree per ticket, one branch per worktree, one commit scoped by pathspec.
- A separate temp directory per job rather than one shared scratch path.
- A copy per reader beats a mutex around one buffer.
- When separation is genuinely impossible, say why in the commit message, then serialize.

## Test

Name the thing the two sides share.
If you can give each of them their own, the lock was solving a problem you invented.
