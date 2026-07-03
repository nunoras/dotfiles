---
name: yf-review
description: Use when you want an independent Codex review of a code change - the current branch versus main, a specific PR, or the working tree - before merging or shipping. Triggers - "review this branch", "review the PR", "codex review", independent review, check my changes before merge.
---

# YF Review

Independent Codex review of a change.
This is the standalone reviewer - opus implements, Codex reviews - unbundled from `yf-run`'s per-phase gate.
Default scope is the current branch versus `main`.

## When to use

- Before opening or merging a PR, you want a second set of eyes from Codex.
- You want to review a specific PR's diff.

Not this skill: the per-phase review inside a plan run (built into `yf-run`); applying fixes (use `yf-fix`).

## Scope (from args)

- **Default** - current branch vs `main`: `git diff main...HEAD`.
- **PR number given** - fetch with `gh pr diff <n>` (context from `gh pr view <n>`).
- **`--wt` / "working tree"** - uncommitted changes: `git diff`.

## Core rules

- **Codex reviews, never a Claude agent or fork.** Independence is the entire point.
- **Review only.** Do not implement fixes here - hand blocking findings to `yf-fix`.
- **Bugs first.** Prioritize correctness, security, and spec/design drift. Note high-value simplification or reuse, but skip style nitpicks.

## The Loop

1. **Resolve scope + diff.** Pick the diff command from Scope. Confirm the diff is non-empty before spending a review.
2. **Review (Codex).** Write the reviewer prompt to a temp file and run `codex exec` (read-only, captured to a file). See Invocation below.
3. **Report.** Summarize findings in chat, grouped blocking / non-blocking, most severe first. Keep the full log at `specs/<name>/run/review-<branch>-<date>.md` when a plan is active, otherwise `.reviews/review-<branch>-<date>.md`.
4. **Hand off.** If there are blocking findings, suggest running `yf-fix` with the review file.

## Invocation (Codex)

```bash
mkdir -p .reviews
git diff main...HEAD > .reviews/_diff.patch   # or: gh pr diff <n> > .reviews/_diff.patch
cat > .reviews/_codex-prompt.md << 'PROMPT'
[reviewer prompt - see below]
PROMPT
codex exec -m gpt-5.5 -c 'model_reasoning_effort="xhigh"' -s read-only \
  -o .reviews/review-<branch>-<date>.md \
  "$(cat .reviews/_codex-prompt.md)"
rm -f .reviews/_codex-prompt.md .reviews/_diff.patch
```

## Reviewer prompt

```text
You are an independent reviewer. Review the change below as a critical engineer.

Scope: [current branch vs main | PR #N | working tree].
Diff: see .reviews/_diff.patch (or run: git diff main...HEAD).

Focus, in priority order:
1. Correctness bugs, edge cases, error handling.
2. Security, data-loss, and integration risks.
3. Spec / design-system drift and missing tests.
4. High-value simplification or reuse - only if clearly worth it, no style nitpicks.

For each finding:
- Severity: blocking | non-blocking
- File/line:
- Issue:
- Why it matters:
- Suggested fix:

Do not implement fixes. Finish with exactly one of: PASS | PASS WITH RISKS | FAIL.
```
