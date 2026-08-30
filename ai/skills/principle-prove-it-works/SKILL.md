---
name: principle-prove-it-works
description: Apply when you are about to report something as done, working, passing, or fixed, or when you are accepting a result from a delegate.
disable-model-invocation: true
---

# Prove it works

## Rule

Run the real thing before you say it works.
Build it, execute the path a user would take, and read the output.
When someone else did the work, read their diff rather than their summary.

## Why

A claim you did not check is worth less than saying nothing, because the next person spends their budget on top of it.
"Tests pass" that nobody ran poisons every decision after it.
"Could not run the tests" costs one sentence and stays true.

A delegate's report is a claim about work that may exist nowhere.
A builder once returned a real diffstat, a real type-check exit 0 and a real green test run, and none of it was committed, so the merge said "Already up to date" and shipped nothing.
Every line of that report was true and the round was still empty.

## Pattern

- Run the command. Paste what it printed, not what it should have printed.
- Exercise the path end to end, not the unit you happened to touch.
- After a delegate reports done, check the commit exists before you check the code.
- If you changed the verify command itself, break something on purpose and watch it go red.
- Name what you could not check, and why.

## Test

Can you point at the exact command you ran and the exact output it gave?
If not, you have a belief rather than a verification, and the report has to say so.
