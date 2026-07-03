---
name: yf-fix
description: Use when applying the blocking findings from a yf-review or yf-run review log, when fixing issues raised by an independent reviewer, or when a plan phase failed review. Triggers - "fix the review", "apply the findings", "address the blockers", fix review comments.
---

# YF Fix

Apply reviewer findings.
opus fixes the blocking findings from a review log, re-runs the relevant tests, and reports.
This is the apply counterpart to `yf-review`, and also works on a `yf-run` per-phase review log.

## When to use

- A `yf-review` or `yf-run` review produced blocking findings you want fixed.
- A plan phase failed review and needs a fix pass.

Not this skill: producing the review (use `yf-review`); the per-phase fix loop inside a run (built into `yf-run`).

## Input

- Default: the review file passed as an argument, otherwise the most recent under `.reviews/` or `specs/<name>/run/`.
- The file lists findings with severity, file/line, issue, and a suggested fix.

## Core rules

- **Blocking findings only.** Leave non-blocking findings as noted follow-ups - do not gold-plate.
- **Stay scoped.** Read the review file and the directly affected source files only. Do not read the whole repo.
- **Verify before reporting.** Re-run the relevant tests after fixing - a fix that breaks a test is not done.
- **Do not commit unless asked.** Leave the fixes in the working tree; `yf-run` and `yf-ship` own commits.

## The Loop

1. **Load findings.** Read the review file and extract the blocking findings (severity blocking, or a FAIL verdict).
2. **Fix (opus).** Spawn a fresh `Agent` (opus) scoped to those findings and the files they touch. It applies each fix and updates or adds tests where a finding calls for it.
3. **Re-run tests.** Run the tests relevant to the changed files - the plan's phase Testing Strategy, or the affected package's tests.
4. **Report.** List each blocking finding and how it was resolved, files changed, commands run, and anything left unresolved (with why). Note the non-blocking findings intentionally deferred.

## Model selection

| Role | Runner | Model | Effort |
|------|--------|-------|--------|
| Fix | Agent | opus | high |

Escalate to `xhigh` only for a subtle correctness fix.

## Fix agent prompt

```text
You are a fix agent. Apply ONLY the blocking findings below.

Review file: [path]
Blocking findings:
[paste the blocking findings - severity, file/line, issue, suggested fix]

Rules:
- Read the review file and the affected source files only. Do not read the whole repo.
- Fix only the listed blocking findings unless a nearby issue blocks the fix.
- Update or add tests where a finding calls for it.
- Re-run the relevant tests; loop until green.

Report:
## Fixed Findings (finding -> how resolved)
## Files Changed
## Commands Run
## Unresolved / Deferred (with why)
```
