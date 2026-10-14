---
name: kickoff
description: Write a self-contained kick-off prompt that hands the current session's work to a fresh chat, and resume from a saved one. Use when context is getting bloated, when the user wants to continue elsewhere, or on any of "kick off prompt", "handoff", "hand this off", "continue in a new chat", "start a fresh chat on this", "give me a prompt to keep going", "a prompt for my desktop", "a prompt for my windows machine", "do this in a new chat", "resume", "pick up where I left off".
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
3. **Name the target machine.** If the work continues on another machine, find out which one, and write that machine's paths, shell and tools into the prompt. Check where the files and keys it needs live there before you ask the user to find them.
4. **Separate durable from disposable.** Anything true beyond this task belongs in memory or in the repo docs, not in a handoff prompt. Say so in one line if you write one, then leave it out of the prompt.
5. **Draft against the template below**, then cut. A handoff longer than the work it describes is a failed handoff.
6. **Pick the model for the receiving session.** See the rubric below. This session knows what the next chunk of work actually is, so it is the one that should make the call.
7. **Save and print.** Write to `~/.claude/handoffs/<YYYY-MM-DD>-<slug>.md` (today's real date, slug from the goal), starting with the frontmatter below so a later session can find it by repo. Then print the prompt, without the frontmatter, in the chat as a single fenced code block so it copies clean.

```
---
repo: <absolute path of the git toplevel, or none>
branch: <branch>
head: <short commit>
agni: <task ids still open for this work, or none>
status: open
---
```

## What goes in

- **The goal**, in one sentence, with the reason behind it if the reason is not obvious.
- **State**: branch, uncommitted files that matter, what currently works and what does not.
- **Decisions already made**, each with the alternative that was rejected and why. This is the single highest-value section - without it the new chat cheerfully re-proposes the thing you already threw out.
- **What this session learned that is written down nowhere else.** Measured numbers, a query that works, a failure mode you hit. This is what would cost another hour to rediscover.
- **The skill that owns the job**, when one does. Name it and tell the new chat to run it, instead of restating its steps. A restated procedure drops the skill's safety checks and goes stale when the skill changes.
- **Facts the new chat must re-check live**, such as branch heads, merge state and how far one branch is ahead of another. Write the command that checks each one, not the value you saw.
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
Machine: <this one | the other machine, with its repo path and shell>
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
1. <first concrete action, with the file, command or skill to run>
2. <then>

OPEN - needs Nuno's call
- <question>

DO NOT REDO
- <thing already tried that failed, one line each>
```

Drop any section that is empty rather than writing "N/A".

## Choosing the model for the next session

The handoff is the moment the model gets picked, because the session boundary is the task boundary.
Recommend one, in a single line after the code block, phrased as an instruction Nuno can act on before pasting.

Pick **Opus** when the next session still has to decide something: architecture, a spec, a plan, a bug with no known cause, or anything where a wrong turn burns several sessions.

Pick **Sonnet** when the decisions are already in the DECIDED section and what remains is execution: a scoped ticket, a refactor that follows an existing pattern, mechanical edits with a test that says when they are right.
Add "and drop effort to low" when the work is genuinely mechanical.

If it is a real toss-up, say Opus. The downside of under-powering a deciding session is larger than the token saving.

State the reason in the same line, in a few words. "Sonnet, the design is settled and this is three files of the same edit" is useful. A bare "Sonnet" is not, because the next session cannot tell whether you thought about it.

## Resume

On "resume" or "pick up where I left off" in a fresh session:

1. List `~/.claude/handoffs/*.md` whose frontmatter `repo` matches the current git toplevel and `status` is `open`, newest first.
   Show at most five, one line each: date, slug, branch.
2. If exactly one matches, load it without asking. Otherwise ask which one.
3. Compare the frontmatter with the live state: current branch and head, and `agni status` for the listed tasks.
   Report each difference in one line before acting, because the handoff describes the past.
4. Continue from its NEXT section.
5. When the handed-off work is done, set `status: done` in the file.

## Output rules

- The prompt goes in one plain fenced code block, nothing else inside it, ready to paste verbatim.
- Every line starts at column 0. No blockquotes, no indentation, no nested fences.
- No em dashes.
- Put the saved file path and any notes to the user outside the block, after it.
- The model recommendation goes outside the block too, on its own line, starting with `Run this on`. It stays out of the block because Nuno acts on it before the new session exists, and a session cannot change its own model.
