---
name: principle-make-operations-idempotent
description: Apply when writing anything that a retry, a fallback, a hook, or a resumed session could run twice.
disable-model-invocation: true
---

# Make operations idempotent

## Rule

Write it so that running it twice leaves the same result as running it once.

## Why

Retries are not hypothetical here.
A builder that dies on a quota error is reopened on the next model in its chain, on the same worktree, against the same half-finished state.
A message delivery replays until it is acknowledged.
A dispatch that failed its readiness check may still have launched a live process.

Anything that appends, increments, or creates without checking will be wrong the second time, and the second time is normal operation rather than an edge case.

## Pattern

- Create if absent rather than create.
- Key writes by an id the caller supplies, so a replay overwrites instead of duplicating.
- Make cleanup safe to run when there is nothing to clean.
- Before an operation, ask what the world looks like if the previous attempt got halfway.

## Test

Run it twice.
If the second run errors, duplicates, or double-counts, it is not done.
