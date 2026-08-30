---
name: principle-sequence-verifiable-units
description: Apply when planning a change big enough to need steps, or when you have written several files without running anything.
disable-model-invocation: true
---

# Sequence verifiable units

## Rule

Split the work into steps that each end in something you can run.
Write the failing test first, make it pass, then move on.

## Why

Four files written before the first run means four suspects when it breaks.
One file per green check means the last thing you touched is the culprit.

Debugging cost does not grow with the size of the change, it grows faster than that.
The step that ends in a passing test is the cheapest unit of progress available.

Test first is our rule at pre-agreed seams: the ticket names where the tests go, and that is where they go.
It is not a licence to test every private function.

## Pattern

- Failing test, fix, verify, commit. Then the next one.
- If a step has no observable result, it is not a step, it is half of one.
- Do not batch four changes and then run the suite once.
- Never weaken a test to make it pass. A red test means the code is wrong or you misread the requirement, and both mean stop.

## Test

What would you run right now to prove the step you just finished?
If the answer is "the whole thing, at the end", the units are too big.
