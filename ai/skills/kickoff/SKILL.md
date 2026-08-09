---
name: kickoff
description: Write a self-contained kick-off prompt that hands the current session's work to a fresh chat. Use when context is getting bloated, when the user wants to continue elsewhere, or on any of "kick off prompt", "handoff", "hand this off", "continue in a new chat", "start a fresh chat on this".
---

# Kickoff

Turn everything live in this session into one prompt that a fresh chat can start from cold.

The new chat has zero context.
It reads `CLAUDE.md` and the repo on its own, so the handoff carries only what the repo does not already say: the goal, the state, the decisions, and the things this session discovered.

## When to use

- Context is filling up and the work is not done.
- The user wants to park this and pick it up in another chat or on another machine.
- A long investigation reached a conclusion and the build should happen somewhere clean.

Not this skill: summarising a finished task, writing a commit message, or saving a durable fact (that goes to memory).

## The loop

1. **Scope it.** No argument means the whole session's active thread. An argument narrows it ("just the extrato gate work") - carry only that thread and say so in the prompt.
2. **Check state for real, do not recall it.** After a long session your memory of the working tree is stale. Run `git status --short`, `git log --oneline -5`, and the current branch. If something was running or half-applied, verify it rather than asserting it.
3. **Separate durable from disposable.** Anything true beyond this task belongs in memory or in the repo docs, not in a handoff prompt. Say so in one line if you write one, then leave it out of the prompt.
4. **Draft against the template below**, then cut. A handoff longer than the work it describes is a failed handoff. Aim under 60 lines.
5. **Save and print.** Write to `~/.claude/handoffs/<YYYY-MM-DD>-<slug>.md` (use the real date from `date +%F`, slug from the goal). Then print the whole thing in the chat as a single fenced code block so it copies clean.

## What goes in

- **The goal**, in one sentence, with the reason behind it if the reason is not obvious.
- **State**: branch, uncommitted files that matter, what currently works and what does not.
- **Decisions already made**, each with the alternative that was rejected and why. This is the single highest-value section - without it the new chat cheerfully re-proposes the thing you already threw out.
- **What this session learned that is written down nowhere else.** Measured numbers, a query that works, a failure mode you hit. This is what would cost another hour to rediscover.
- **The next concrete action.** Not "continue the work" - the actual first move.
- **Open questions**, marked as needing the user's call.
- **Corrections the user made**, phrased as rules, if they would otherwise be repeated.

## What stays out

- File contents, diffs, and tool output. Point at `path:line` instead.
- Anything already in `CLAUDE.md`, the repo docs, or git history. The new chat reads those.
- The story of how you got there. Only the conclusions.
- Praise, preamble, and options you are not pursuing.

## Template

```
Continuing work from another chat. Read CLAUDE.md first, then this.

GOAL
<one sentence, plus why if not obvious>

STATE
Branch: <branch>. <clean | uncommitted: files that matter>
Working: <what is done and verified>
Not working: <what is broken or unverified>

DECIDED
- <decision>. Rejected <alternative> because <reason>.
- ...

LEARNED (not written down anywhere else)
- <fact, with the number or the query that proves it>
- ...

NEXT
1. <first concrete action, with the file or command>
2. <then>

OPEN - needs Nuno's call
- <question>

DO NOT REDO
- <thing already tried that failed, one line each>
```

Drop any section that is empty rather than writing "N/A".

## Output rules

- The prompt goes in one plain fenced code block, nothing else inside it, ready to paste verbatim.
- Every line starts at column 0. No blockquotes, no indentation, no nested fences.
- No em dashes.
- Put the saved file path and any notes to the user outside the block, after it.
