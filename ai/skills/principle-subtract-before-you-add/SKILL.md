---
name: principle-subtract-before-you-add
description: Apply when you are about to add a file, a flag, an abstraction, or a fix the ticket did not ask for.
disable-model-invocation: true
---

# Subtract before you add

## Rule

Look for the thing that already does this before you build a new one.
Follow the ticket, and stop where it stops.

## Why

Most tickets are already half built somewhere in the repo, and the half that exists is the half that has been used.
A second implementation of the same idea is not progress, it is a fork you now have to keep in step.

An unrequested fix in a diff is the most expensive thing you can hand a reviewer.
They now have to review two changes, they can only accept or reject both, and the good one goes back with the bad one.

Deleting is allowed to be the whole change.
A flag with one caller, a helper wrapping one line, a config key nothing reads: removing those is work, and it is the cheapest work available.

## Pattern

- Grep for the behaviour before you write it.
- Prefer an existing helper over a better abstraction that is not there yet.
- Note the unrelated problem in the report. Do not fix it.
- When the ticket is done, stop, even if you can see the next thing.

## Test

Does the diff contain anything the ticket did not ask for?
Say why it is there, or take it out.
