---
name: yf-ship
description: Use when finishing or shipping a yf-plan whose phases are all built (all [x]), when you want to validate then commit/push and open a PR for a completed plan, or when closing out a yf-run relay. Triggers - "ship the plan", "open the PR", "finalize", "wrap up the plan", ship, PR.
---

# YF Ship

Finalize a built yf-plan: validate, push, open the PR, and record the ship back into the plan.
Assumes `yf-run` already implemented every phase and made per-phase commits on a feature branch.

## When to use

- Every phase of a yf-plan is `[x]` and you want to open a PR.
- You are closing out a `yf-run` relay.

Not this skill: building phases (use `yf-run`); creating the plan (use `yf-plan`).

## Core rules

- **Never ship from `main`.** If the plan's commits landed on `main`, stop and tell the user - `yf-run` should have branched.
- **Validation is a hard gate.** No push and no PR until the plan's global Validation Commands pass.
- **Push and PR only after the user confirms.** Show the commit range and validation result, then wait for the OK (per commit/push-only-when-asked).
- **Plan writes are append-only.** Only ever append to the metadata header and Amendments section (per yf-plan) - never overwrite existing entries.
- **No auto-added co-author** in any commit you create.

## The Loop

1. **Locate the plan + branch.** Resolve the `.html` path (infer the most recent in `specs/` and confirm if none given). Confirm every phase is `[x]`; warn on any `[f]` and ask before continuing. Confirm you are on a feature branch, not `main`.
2. **Validate (hard gate).** Spawn a validation agent (haiku) to run the plan's global Validation Commands. Read only its pass/fail summary. If anything fails: spawn an opus fix agent, re-validate, and do not proceed until green.
3. **Confirm + push.** Show the user the commit range (`git log main..HEAD --oneline`) and the validation result. On their OK, push the branch (`git push -u origin HEAD`).
4. **Open the PR.** `gh pr create` with a title from the plan and a body: purpose, phases shipped (with commit SHAs), validation result, and a link back to the plan file.
5. **Record the ship.** Append to the plan's metadata header (modified ISO, agent name, session id, commit SHAs) and add an Amendments entry noting what shipped and the PR link. Append-only.
6. **Report.** Print the PR URL and final status.

## Model selection

| Role | Runner | Model | Effort |
|------|--------|-------|--------|
| Validation | Agent | haiku | low |
| Fix (validation failure) | Agent | opus | high |

The coordinator runs the `git` and `gh` commands directly - they are light. Delegate only the build/test validation to the agent so its output stays out of your context.

## PR body shape

```text
## Purpose
[from the plan's Purpose section]

## Phases shipped
- Phase 1: <name> (<sha>)
- Phase 2: <name> (<sha>)
...

## Validation
- <command> - pass
...

Plan: specs/<name>.html
```
