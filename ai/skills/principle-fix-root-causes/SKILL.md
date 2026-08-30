---
name: principle-fix-root-causes
description: Apply when a bug, flake, or failure appears and you are about to add a guard, a retry, a null check, or a special case.
disable-model-invocation: true
---

# Fix root causes

## Rule

Reproduce the failure the way a user hits it, find what actually causes it, and fix that.
A guard around a symptom is a note that you gave up.

## Why

Symptom patches accumulate.
Each one hides the next occurrence a little better, so the real cause surfaces later, further from its origin, in someone else's week.

A retry around a call that fails deterministically turns a fast error into a slow one.
A null check on a value that should never be null deletes the evidence of whatever produced it.

Scope pressure is what makes this tempting: the guard is small and the investigation is not.
The guard is small because it does nothing.

## Pattern

- Reproduce first. If you cannot reproduce it, you cannot know you fixed it.
- Ask why the bad value exists, not how to survive it.
- When the real fix is out of scope, say so and leave the bug, or escalate. Do not patch the symptom and call it fixed.
- A guard is legitimate when the bad input genuinely comes from outside your control. Then it belongs at the boundary, which is a different principle.

## Test

Can you state the causal chain from the code you changed to the failure you saw?
If the chain has a "somehow" in it, you patched a symptom.
