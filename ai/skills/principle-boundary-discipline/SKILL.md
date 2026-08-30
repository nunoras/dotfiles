---
name: principle-boundary-discipline
description: Apply when data arrives from a CLI, an API, a file, an environment variable, or another process, and when you are adding a defensive check deep inside your own code.
disable-model-invocation: true
---

# Boundary discipline

## Rule

Parse and validate once, at the edge where the data arrives.
Past that point, trust your own types.

## Why

Validation scattered through the call stack is validation nobody can find and nobody can remove.
Every inner check implies the outer one might have failed, so the checks breed.

The edge is also where the failure is legible.
"The terminal read returned no tail" names the seam and the command.
The same failure caught six frames in reads as an undefined property on an object with no story attached.

This is the fix that closed a real one here.
A CLI started wrapping every response in an envelope, every accessor read from the wrong level at once, and the repair was one parse at the seam rather than a check at each reader.

## Pattern

- One parse function per external surface, returning your own type.
- Fail loud at the boundary with the raw input in the message.
- Inside the boundary, no defensive null checks on values your own types say exist.
- A response shape you have not captured live is a guess. Capture it, then encode it.

## Test

Point at the single place this data is validated.
If there is more than one, the boundary is not where you think it is.
